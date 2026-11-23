import Foundation

/// sales/sl910.cbl: Invoicing Data Entry (請求書入力)
enum SLB910 {
    static let progName = "SL910 (3.01.13)"
    static let esc = 2005, f1 = 1001, f2 = 1002, f3 = 1003, f5 = 1005, f6 = 1006, f8 = 1008

    /// copybooks/fdanal.cob analysis-record
    static let analysisLayout = Layout("analysis-record", [
        ("pa-code", .x(3)), ("pa-gl", .n9(digits: 6, scale: 0, signed: false)), ("pa-desc", .x(24)), ("pa-print", .x(3)),
    ])
    /// copybooks/fdstock.cob Stock-Record (400 バイト)
    static let stockLayout: Layout = {
        let c6 = FieldType.comp(digits: 6, scale: 0, signed: true)
        return Layout("stock-record", [
            ("stock-key", .x(13)), ("stock-abrev-key", .x(7)), ("stock-suppliers", .x(21)), ("stock-desc", .x(32)),
            ("stock-construct-item", .x(13)), ("stock-location", .x(10)), ("stock-pa-code", .x(3)),
            ("stock-sa-system", .x(1)), ("stock-sa-group", .x(2)), ("stock-services-flag", .x(1)),
            ("stock-last-actual-cost", .comp3(digits: 9, scale: 2, signed: false)), ("", .filler(8)),
            ("stock-construct-bundle", c6), ("stock-under-construction", c6), ("stock-work-in-progress", c6),
            ("stock-reorder-pnt", c6), ("stock-std-reorder", c6), ("stock-back-ordered", c6), ("stock-on-order", c6),
            ("stock-held", c6), ("stock-pre-sales", c6),
            ("stock-retail", .comp3(digits: 9, scale: 2, signed: false)),
            ("stock-cost", .comp3(digits: 11, scale: 4, signed: false)),
            ("stock-value", .comp3(digits: 11, scale: 2, signed: false)),
            ("", .filler(231)),
        ])
    }()

    /// 索引ファイル stockctl.dat (主キー + 副キー Stock-Abrev-Key / Stock-Desc) の参照
    final class StockFile {
        let s: Session
        let path: String
        var status = "00"
        /// 参照キー順の並びと現在位置 (READ NEXT 用)
        private var order: [[UInt8]] = []
        private var pos = 0
        init(_ s: Session) { self.s = s; path = s.ledgers + "stockctl.dat" }
        private func pad(_ b: [UInt8]) -> [UInt8] { b + [UInt8](repeating: 0x20, count: max(0, 400 - b.count)) }
        private func sorted(_ r: Range<Int>) -> [[UInt8]] {
            let all = s.store.all(path).map { pad($0.data) }
            if r.lowerBound == 0 { return all }
            return all.enumerated().sorted { a, b in
                let x = Array(a.element[r]), y = Array(b.element[r])
                return x == y ? a.offset < b.offset : x.lexicographicallyPrecedes(y)
            }.map { $0.element }
        }
        /// READ ... KEY IS (r = キーのバイト範囲)
        func read(_ r: Range<Int>, _ key: [UInt8]) -> Record? {
            order = sorted(r)
            guard let i = order.firstIndex(where: { Array($0[r]) == key }) else { status = "23"; return nil }
            pos = i + 1; status = "00"
            return Record(SLB910.stockLayout, bytes: order[i])
        }
        /// START ... KEY NOT < key
        func start(_ r: Range<Int>, _ key: [UInt8]) -> Bool {
            order = sorted(r)
            guard let i = order.firstIndex(where: { !Array($0[r]).lexicographicallyPrecedes(key) }) else { status = "23"; return false }
            pos = i; status = "00"; return true
        }
        func readNext() -> Record? {
            if pos >= order.count { status = "10"; return nil }
            pos += 1; status = "00"
            return Record(SLB910.stockLayout, bytes: order[pos - 1])
        }
        func rewrite(_ rec: Record) -> Bool {
            let ok = s.store.rewrite(path, key: Array(rec.bytes[0..<13]), data: rec.bytes)
            status = ok ? "00" : "23"; return ok
        }
    }

    private enum L2 { case getData2, getProduct, getProdTest, getCode, getDesc, getQty, getUnit, recompNet, getDisc, jumpTotals }

    static func run(_ s: Session) throws { try Prog(s).run() }

    final class Prog {
        let s: Session
        let c: Console
        var analysis: IndexedFile, salesFile: IndexedFile, inv: IndexedFile, delivery: IndexedFile, oi3: IndexedFile
        let stockFile: StockFile
        let dnos: String, auditPath: String

        var sih = Record(SLB.sihLayout)
        var lines = [Record](repeating: Record(SLB.silLayout), count: 41)
        var sales = Record(SLB.salesLayout)
        var deliv = Record(SLB.deliveryLayout)
        var oi = Record(SLB.oiLayout)
        var pa = Record(SLB910.analysisLayout)
        var stock = Record(SLB910.stockLayout)
        var i = 0, j = 0, lin = 0, z = 0
        var crt = 0, newScreen = 0
        var escapeCode = " ", wsReply = " ", wsNamed = " "
        var wsDate = "", wsPa = "  ", wsProduct = Cobol.x("", 13), testProduct = Cobol.x("", 13)
        var wsDescription = Cobol.x("", 32), addressLine = Cobol.x("", 36)
        var wsQty: Int64 = 0, wsNet: Int64 = 0, wsVat: Int64 = 0, wsUnit: Int64 = 0, vatCode: Int64 = 0
        var wsDiscount: Int64 = 0
        var showDelivery = "N"
        var delinv = 0, dnosPos = 0, dnosOpen = false
        var exitProgram = false

        init(_ s: Session) {
            self.s = s; c = s.console
            analysis = IndexedFile(s.store, path: s.ledgers + "analysis.dat", layout: SLB910.analysisLayout, keyOffset: 0, keyLength: 3)
            salesFile = SLB.salesFile(s); inv = SLB.invoiceFile(s); delivery = SLB.deliveryFile(s); oi3 = SLB.oi3File(s)
            stockFile = StockFile(s)
            dnos = s.ledgers + "delinvno.dat"; auditPath = s.ledgers + "staudit.dat"
        }

        var stockLink: String { s.sys.str("sl-stock-link") }
        var level1: Bool { s.sys.int("invoicer") == 1 }
        var silComment: Bool { testProduct.hasPrefix("/") }
        func t(_ k: String) -> String { s.t(k) }
        func d9(_ v: Int64) -> String { SLB.z99(v, 7) }
        func d8(_ v: Int64) -> String { SLB.z99(v, 6) }

        func acc(_ llcc: Int, _ size: Int, _ initial: String? = nil, color: UInt8 = 0) throws -> String {
            let r = try c.accept(at: llcc, size: size, initial: initial ?? "", options: initial == nil ? [] : [.update], color: color)
            crt = c.crtStatus
            return r
        }
        func accNum(_ llcc: Int, _ digits: Int, _ initial: Int64, color: UInt8 = 0) throws -> Int64 {
            let r = try SLB.acceptNum(s, at: llcc, digits: digits, initial: initial, color: color)
            crt = c.crtStatus
            return r
        }
        private func digits(_ a: ArraySlice<Character>) -> Int64 {
            a.reduce(Int64(0)) { $0 * 10 + Int64($1.wholeNumberValue ?? 0) }
        }
        /// accept-money6/7 (b = 表示して入力、戻り値は amt-ok)
        func acceptMoney(_ llcc: Int, intDigits n: Int, _ amt: Int64) throws -> Int64 {
            let v = abs(amt) % Cobol.pow10(n + 2)
            let shown = Cobol.z(v / 100, n) + "." + Cobol.z(v % 100, 2)
            c.display(shown, at: llcc, color: 3)
            let r = Array(Cobol.x(try acc(llcc, n + 3, shown, color: 3), n + 3))
            return digits(r[0..<n]) * 100 + digits(r[(n + 1)...])
        }
        func moneyText(_ amt: Int64, _ n: Int) -> String {
            let v = abs(amt) % Cobol.pow10(n + 2)
            return Cobol.z(v / 100, n) + "." + Cobol.z(v % 100, 2)
        }
        func vatRate(_ n: Int64) -> Int64 { s.sys.int("vat-rate-\(n)") }

        // MARK: init / main

        func run() throws {
            wsDate = SLB.wsDate(s)
            try programStart()
            if s.sys.str("sl-own-nos") == "Y" { delinv = 0 }
            mainLoop: while true {
                sih = Record(SLB.sihLayout)
                try invoiceDetails()
                if z != 0 || escapeCode == "Q" { break }
                c.display(" ", at: 1601, eraseEOS: true)
                // data-input
                lines = [Record](repeating: Record(SLB.silLayout), count: 41)
                i = 0
                if level1 { try invLevel1() } else { try invLevel2() }
                if crt == SLB910.esc { continue }
                if i != 1 {
                    try endTotals()
                    if exitProgram { return }
                }
                while true {   // more-data
                    c.display(t("sl910.further"), at: 2429, color: 3)
                    crt = 0
                    wsReply = try acc(2460, 1, "Y", color: 6).uppercased()
                    c.display(" ", at: 2401, eraseEOL: true)
                    if wsReply == "Y" { continue mainLoop }
                    if wsReply != "N" { continue }
                    break mainLoop
                }
            }
            // menu-exit
            s.sys.setInt("pass-value", 0)
            closeAll()
        }

        func closeAll() {
            dnosOpen = false
            salesFile.close(); delivery.close(); analysis.close(); inv.close(); oi3.close()
        }

        // MARK: Program-Start

        func programStart() throws {
            c.display(" ", at: 101, eraseEOS: true)
            if SLB.fileStatus(s, 15) != 1 {
                s.processFunc = 1; s.subFunction = 1
                _ = try s.call("sl070")
                if SLB.fileStatus(s, 15) != 1 {
                    try SLB.maps99(s, 29)
                    try SLB.maps99(s, 15)
                }
            }
            salesFile.open(); delivery.open(); analysis.open()
            if SLB.fileStatus(s, 16) != 1 {
                inv.openOutput(); inv.close()
                SLB.setFileStatus(s, 16, 1)
            }
            if SLB.fileStatus(s, 19) != 1 {
                oi3.openOutput(); oi3.close()
                SLB.setFileStatus(s, 19, 1)
            }
            inv.open(); oi3.open()
            if !s.store.exists(dnos) { delinv = 0; dnosOpen = false }
            else { delinv = 1; dnosOpen = true; dnosPos = 0 }
            if stockLink == "Y" {
                if SLB.fileStatus(s, 11) != 1 {
                    s.store.deleteFile(stockFile.path); s.store.createIndexed(stockFile.path)
                    SLB.setFileStatus(s, 11, 1)
                }
                if s.sys.int("stk-audit-used") == 1 {
                    if SLB.fileStatus(s, 10) != 1 {
                        s.store.writeRaw(auditPath, [])
                        SLB.setFileStatus(s, 10, 1)
                    } else if !s.store.exists(auditPath) {
                        s.store.writeRaw(auditPath, [])
                    }
                }
            }
        }

        // MARK: running-totals / write-details

        func runningTotals() {
            var net: Int64 = 0, vat: Int64 = 0
            if i >= 1 { for k in 1...min(i, 40) { net += lines[k].int("sil-net"); vat += lines[k].int("sil-vat") } }
            sih.setInt("sih-net", net); sih.setInt("sih-vat", vat)
            if level1 { c.display(d9(net), at: 1237, color: 3) }
            if level1 { c.display(d9(vat), at: 1255, color: 3) }
            c.display(d9(net + vat), at: level1 ? 1268 : 1270, color: 3)
        }

        func invoiceWriteError(_ status: String, _ key: [UInt8]) throws {
            c.display(t("sl910.sl180"), at: 2301, color: 4, eraseEOL: true)
            c.display(status, at: 2336, color: 3)
            c.display(SLB.fsMsg(s, status), at: 2339, color: 3)
            c.display(SJIS.decode(key[...]), at: 2364, color: 3)
            c.display(t("sl910.sl006"), at: 2401, color: 3)
            wsReply = try acc(2430, 1)
            c.display(" ", at: 2301, eraseEOS: true)
        }

        func writeDetails() throws {
            j += 1
            lines[j].setInt("sil-invoice", sih.int("sih-invoice"))
            lines[j].setInt("sil-line", Int64(j))
            lines[j]["sil-letter"] = sih.str("sih-letter")
            lines[j]["sil-type"] = String(sih.int("sih-type"))
            let rec = SLB.invoiceRecord(from: lines[j])
            let st = inv.write(rec)
            if st != "00" { try invoiceWriteError(st, inv.key(of: rec)) }
            try updateStockAndAudit()
        }

        static func signTrailing(_ v: Int64, digits: Int) -> [UInt8] {
            var b = Array(Cobol.z(abs(v) % Cobol.pow10(digits), digits).utf8)
            if v < 0 { b[digits - 1] += 0x40 }
            return b
        }

        func updateStockAndAudit() throws {
            if stockLink != "Y" { return }
            let silType = lines[j].str("sil-type")
            let product = lines[j].raw("sil-product")
            let qty = lines[j].int("sil-qty")
            var auditType = 3, reverse = 0
            var crForInvoice: Int64 = 0
            if silType == "3" { auditType = 5; reverse = 1; crForInvoice = sih.int("sih-cr") }
            var valueChange: Int64 = 0
            var found: Record?
            if product[7..<13].allSatisfy({ $0 == 0x20 }) { found = stockFile.read(13..<20, Array(product[0..<7])) }
            else { found = stockFile.read(0..<13, product) }
            if let f = found { stock = f }
            else {
                stock.setInt("stock-cost", 0); stock["stock-key"] = ""
            }
            if stockFile.status != "00" {
                c.display(t("sl910.stock_read"), at: 2301, color: 4, eraseEOL: true)
                c.display(stockFile.status, at: 2316, color: 3)
                c.display(SLB.fsMsg(s, stockFile.status), at: 2319, color: 3)
                c.display(stock.str("stock-key"), at: 2064, color: 3)
                c.display(t("sl910.sl006"), at: 2401, color: 3)
                wsReply = try acc(2430, 1)
                c.display(" ", at: 2301, eraseEOS: true)
            }
            if stock.str("stock-key") != Cobol.x("", 13) {
                var held = stock.int("stock-held")
                let cost = stock.int("stock-cost")
                if silType == "1" || silType == "2" {
                    valueChange = Cobol.truncate(Cobol.rescale(qty * cost * -1, from: 4, to: 2), digits: 10)
                    held = Cobol.truncate(held - qty, digits: 6)
                } else if silType == "3" {
                    valueChange = Cobol.truncate(Cobol.rescale(qty * cost, from: 4, to: 2), digits: 10)
                    held = Cobol.truncate(held + qty, digits: 6)
                }
                if held < 0 {
                    held *= -1
                    stock.setInt("stock-pre-sales", Cobol.truncate(stock.int("stock-pre-sales") + held, digits: 6))
                    held = 0
                }
                stock.setInt("stock-held", held)
                if held > 0 { stock.setInt("stock-value", Cobol.rescale(held * cost, from: 4, to: 2) % Cobol.pow10(11)) }
                else { stock.setInt("stock-value", 0) }
                if !stockFile.rewrite(stock) {
                    c.display(t("sl910.sl191"), at: 2301, color: 4, highlight: true, eraseEOL: true)
                    c.display(stockFile.status, at: 2338, color: 2, highlight: true)
                    c.display(t("sl910.sl006"), at: 2401)
                    wsReply = try acc(2445, 1)
                }
                if stockFile.status != "00" {
                    c.display(t("sl910.stock_rewrite"), at: 2301, color: 4, eraseEOL: true)
                    c.display(stockFile.status, at: 2316, color: 3)
                    c.display(SLB.fsMsg(s, stockFile.status), at: 2319, color: 3)
                    c.display(stock.str("stock-key"), at: 2064, color: 3)
                    c.display(t("sl910.sl006"), at: 2401, color: 3)
                    wsReply = try acc(2430, 1)
                    c.display(" ", at: 2301, eraseEOS: true)
                }
            }
            if s.sys.int("stk-audit-used") == 1 {
                s.sys.setInt("stk-activity-rep-run", 0)
                var b: [UInt8] = Array(String(auditType).utf8)
                b += Array(Cobol.z(sih.int("sih-invoice"), 8).utf8)
                b += Array(Cobol.z(crForInvoice, 8).utf8)
                b += product
                b += lines[j].raw("sil-description")
                b += SJIS.encode(wsDate, size: 10)
                b += Array(String(reverse).utf8)
                b += Prog.signTrailing(qty, digits: 6)
                b += Prog.signTrailing(0, digits: 10)
                b += Prog.signTrailing(valueChange, digits: 10)
                b += Array(Cobol.z(s.sys.int("stk-audit-no"), 5).utf8)
                s.store.appendRaw(auditPath, b)
            }
        }

        // MARK: inv-level-1

        func invLevel1() throws {
            c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
            c.display(t("sl910.level1"), at: 1201, color: 2)
            c.display(t("sl910.line"), at: 1216, color: 2)
            for p in [1236, 1254, 1267] { c.display("[          ]", at: p, color: 2) }
            c.display(t("sl910.l1_code"), at: 1405, color: 2)
            c.display(t("sl910.l1_heads"), at: 1436, color: 2)
            while true {
                lin = 16
                while lin < 23 {
                    i += 1
                    c.display("(", at: lin * 100 + 1, color: 2, eraseEOL: true)
                    c.display(Cobol.z(i, 2), at: lin * 100 + 2, color: 2)
                    c.display(") [  ]", at: lin * 100 + 4, color: 2)
                    c.display("[          ] [ ]   {         } (", at: lin * 100 + 36, color: 2)
                    c.display(")", at: lin * 100 + 78, color: 2)
                    lin += 1
                }
                i = abs(i - 8) % 100
                j = 1
                c.display(Cobol.z(i, 2), at: 1223, color: 3)
                crt = 0
                try getData1()
                if crt == SLB910.esc { return }
                if newScreen == 1 { continue }
                if line(i).str("sil-description") != Cobol.x("", 32) && i != 40 { continue }
                return
            }
        }

        /// 添字 0 や 40 超の参照 (レガシーは範囲検査なし) は作業用の空行で受ける
        func line(_ n: Int) -> Record { (1...40).contains(n) ? lines[n] : Record(SLB.silLayout) }
        func setLine(_ n: Int, _ body: (inout Record) -> Void) { if (1...40).contains(n) { body(&lines[n]) } }

        func getData1() throws {
            outer: while true {
                lin = j + 15
                if lin > 23 { i = abs(i - 1) % 100; newScreen = 1; return }
                newScreen = 0
                getCode: while true {
                    if i > 1 && line(i).str("sil-pa") == "  " { let p = line(i - 1).str("sil-pa"); setLine(i) { $0["sil-pa"] = p } }
                    wsPa = line(i).str("sil-pa")
                    c.display(wsPa, at: lin * 100 + 7, color: 3)
                    wsPa = Cobol.x(try acc(lin * 100 + 7, 2, wsPa, color: 3), 2)
                    setLine(i) { $0["sil-pa"] = self.wsPa; $0["sil-description"] = "" }
                    if wsPa == "  " { return }
                    if crt == SLB910.esc { return }
                    if wsPa == "<<" && i == 1 { continue getCode }
                    if wsPa == "<<" {
                        lin -= 1
                        if lin > 15 { i -= 1; j -= 1; continue getCode }
                        i = abs(i - 8) % 100
                        continue outer
                    }
                    guard let r = analysis.read(key: "S" + wsPa) else {
                        c.display(t("sl910.sl186"), at: 2301, color: 4, highlight: true)
                        continue getCode
                    }
                    pa = r
                    c.display(" ", at: 2301, eraseEOL: true)
                    c.display(pa.str("pa-desc"), at: lin * 100 + 11, color: 3)
                    setLine(i) { $0["sil-description"] = self.pa.str("pa-desc") }
                    // get-net
                    let amt7 = try acceptMoney(lin * 100 + 37, intDigits: 7, 0)
                    if amt7 == 0 { continue getCode }
                    setLine(i) { $0.setInt("sil-net", amt7) }
                    wsNet = amt7
                    // get-vat-code
                    repeat { vatCode = try accNum(lin * 100 + 50, 1, vatCode, color: 3) } while vatCode > 3
                    setLine(i) { $0.setInt("sil-vat-code", self.vatCode) }
                    var amt6: Int64 = 0
                    if vatCode != 0 { amt6 = Cobol.rescaleRounded(wsNet * vatRate(vatCode), from: 6, to: 2) % Cobol.pow10(8) }
                    // get-vat-rate
                    amt6 = try acceptMoney(lin * 100 + 56, intDigits: 6, amt6)
                    setLine(i) { $0.setInt("sil-vat", amt6) }
                    wsVat = amt6
                    c.display(d9(wsVat + wsNet), at: lin * 100 + 68, color: 3)
                    runningTotals()
                    j += 1; i += 1
                    continue outer
                }
            }
        }

        // MARK: inv-level-2

        func invLevel2() throws {
            c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
            c.display(t(stockLink != "Y" ? "sl910.level2" : "sl910.stock_linked"), at: 1201, color: 2)
            c.display(t("sl910.line"), at: 1216, color: 2)
            c.display(t("sl910.net_box"), at: 1227, color: 2)
            c.display(t("sl910.vat_box"), at: 1244, color: 2)
            c.display(t("sl910.invoice_box"), at: 1261, color: 2)
            c.display(t(stockLink == "N" ? "sl910.l2_heads_pa" : "sl910.l2_heads_stock"), at: 1405, color: 2)
            while true {
                lin = 16
                while lin < 23 {
                    i += 1
                    if stockLink == "N" {
                        c.display("[             ][  ][", at: lin * 100 + 1, color: 2, eraseEOL: true)
                        c.display("][     ][          ][     ][ ]", at: lin * 100 + 51, color: 2)
                    } else {
                        c.display("[             ][", at: lin * 100 + 1, color: 2, eraseEOL: true)
                        c.display("]  [     ][          ][     ][ ]", at: lin * 100 + 49, color: 2)
                    }
                    lin += 1
                }
                i = abs(i - 8) % 100
                j = 1
                c.display(Cobol.z(i, 2), at: 1223, color: 2)
                try getData2()
                if crt == SLB910.esc { return }
                if newScreen == 1 { continue }
                if wsProduct != Cobol.x("", 13) && i != 40 { continue }
                return
            }
        }

        private func stockMsg(_ key: String, _ color: UInt8) {
            stock["stock-desc"] = t(key)
            c.display(stock.str("stock-desc"), at: lin * 100 + 17, color: color)
        }
        private func showStockBrowse() {
            setLine(i) { $0["sil-product"] = self.stock.str("stock-abrev-key") }
            wsProduct = Cobol.x(stock.str("stock-abrev-key"), 13)
            c.display(stock.str("stock-desc"), at: lin * 100 + 17, color: 3, highlight: true)
            wsQty = abs(stock.int("stock-held")) % 100000
            c.display(Cobol.z(wsQty, 5), at: lin * 100 + 53, color: 3, highlight: true)
        }

        func getData2() throws {
            var label = L2.getData2
            let blank13 = Cobol.x("", 13), blank32 = Cobol.x("", 32)
            while true {
                switch label {
                case .getData2:
                    lin = j + 15
                    if lin > 22 { i = abs(i - 1) % 100; newScreen = 1; return }
                    newScreen = 0
                    label = .getProduct

                case .getProduct:
                    if i > 1 && line(i).str("sil-product") == blank13 {
                        let p = line(i - 1).str("sil-product"); setLine(i) { $0["sil-product"] = p }
                    }
                    c.display(Cobol.z(i, 2), at: 1223, color: 2)
                    wsProduct = line(i).str("sil-product")
                    c.display(wsProduct, at: lin * 100 + 2, color: 3)
                    wsProduct = Cobol.x(try acc(lin * 100 + 2, 13, wsProduct, color: 3), 13)
                    setLine(i) { $0["sil-description"] = "" }
                    if crt != SLB910.f6 {
                        if wsProduct == blank13 { return }
                        if crt == SLB910.esc { return }
                    }
                    // Bypass-Product-Space-Tests
                    wsProduct = wsProduct.uppercased()
                    setLine(i) { $0["sil-product"] = self.wsProduct }
                    testProduct = wsProduct
                    if silComment {
                        wsNet = 0; wsUnit = 0; wsQty = 0
                        label = .getDesc; continue
                    }
                    if wsProduct == Cobol.x("<<", 13) { lin -= 1; label = .getProdTest; continue }
                    if stockLink != "Y" { label = .getCode; continue }
                    let cur = lin * 100 + 17
                    let stockKey = SJIS.encode(wsProduct, size: 13)
                    if crt == SLB910.f3 {
                        if !stockFile.start(13..<20, Array(stockKey[0..<7])) { stockMsg("sl910.not_found", 4); continue }
                        guard let r = stockFile.readNext() else { stockMsg("sl910.end_of_file", 4); continue }
                        stock = r
                        setLine(i) { $0["sil-product"] = self.stock.str("stock-abrev-key") }
                        c.display(stock.str("stock-desc"), at: cur, color: 3)
                        continue
                    }
                    if crt == SLB910.f2 {
                        guard let r = stockFile.readNext() else { stockMsg("sl910.end_of_file", 4); continue }
                        stock = r
                        setLine(i) { $0["sil-product"] = self.stock.str("stock-abrev-key") }
                        c.display(stock.str("stock-desc"), at: cur, color: 3)
                        continue
                    }
                    if crt == SLB910.f6 {
                        wsDescription = line(i).str("sil-description")
                        wsDescription = Cobol.x(try acc(cur, 32, wsDescription, color: 3), 32)
                        stock["stock-desc"] = wsDescription
                        if !stockFile.start(41..<73, SJIS.encode(wsDescription, size: 32)) { stockMsg("sl910.not_found", 4); continue }
                        guard let r = stockFile.readNext() else { stockMsg("sl910.end_of_file", 4); continue }
                        stock = r
                        showStockBrowse()
                        wsReply = try acc(2410, 1)
                        c.display(moneyText(stock.int("stock-retail"), 7), at: lin * 100 + 60, color: 3, highlight: true)
                        continue
                    }
                    if crt == SLB910.f5 {
                        guard let r = stockFile.readNext() else { stockMsg("sl910.end_of_file", 4); continue }
                        stock = r
                        showStockBrowse()
                        c.display(moneyText(stock.int("stock-retail"), 7), at: lin * 100 + 60, color: 3, highlight: true)
                        continue
                    }
                    let r: Record?
                    if stockKey[7..<13].allSatisfy({ $0 == 0x20 }) { r = stockFile.read(13..<20, Array(stockKey[0..<7])) }
                    else { r = stockFile.read(0..<13, stockKey) }
                    guard let rec = r else { stockMsg("sl910.not_on_file", 4); continue }
                    stock = rec
                    // Test-For-Read-Stock
                    if stockFile.status != "00" {
                        c.display(t("sl910.read_stock_error"), at: 2301, color: 4, highlight: true, eraseEOL: true)
                        c.display(stockFile.status, at: 2320, color: 2, highlight: true)
                        c.display(SLB.fsMsg(s, stockFile.status), at: 2324, color: 3)
                        c.display(t("sl910.sl006"), at: 2401)
                        wsReply = try acc(2445, 1)
                    }
                    // Process-Stock-Record
                    wsPa = stock.str("stock-sa-group")
                    pa["pa-code"] = String(pa.str("pa-code").prefix(1)) + wsPa
                    setLine(i) { $0["sil-pa"] = self.wsPa }
                    c.display(stock.str("stock-desc"), at: cur, color: 3)
                    wsDescription = stock.str("stock-desc")
                    setLine(i) { $0["sil-description"] = self.wsDescription }
                    wsUnit = stock.int("stock-retail")
                    c.display(moneyText(wsUnit, 7), at: lin * 100 + 60, color: 3)
                    wsQty = abs(stock.int("stock-held")) % 100000
                    label = .getQty

                case .getProdTest:
                    if i == 1 { lin += 1; label = .getProduct; continue }
                    if lin > 15 { i -= 1; j -= 1; label = .getProduct }
                    else { i = abs(i - 8) % 100; label = .getData2 }

                case .getCode:
                    if i > 1 && line(i).str("sil-pa") == "  " { let p = line(i - 1).str("sil-pa"); setLine(i) { $0["sil-pa"] = p } }
                    wsPa = line(i).str("sil-pa")
                    c.display(wsPa, at: lin * 100 + 17, color: 3)
                    wsPa = Cobol.x(try acc(lin * 100 + 17, 2, wsPa, color: 3), 2)
                    setLine(i) { $0["sil-description"] = "" }
                    if wsPa == "  " { label = .getProduct; continue }
                    setLine(i) { $0["sil-pa"] = self.wsPa }
                    guard let r = analysis.read(key: "S" + wsPa) else {
                        c.display(t("sl910.sl186"), at: lin * 100 + 21, color: 4)
                        continue
                    }
                    pa = r
                    label = .getDesc

                case .getDesc:
                    if i > 1 && line(i).str("sil-description") == blank32 && !silComment {
                        let d = line(i - 1).str("sil-description"); setLine(i) { $0["sil-description"] = d }
                    }
                    let cur = lin * 100 + (stockLink == "Y" ? 17 : 21)
                    wsDescription = line(i).str("sil-description")
                    c.display(wsDescription, at: cur, color: 3)
                    wsDescription = Cobol.x(try acc(cur, 32, wsDescription, color: 3), 32)
                    setLine(i) { $0["sil-description"] = self.wsDescription }
                    escapeCode = wsDescription == blank32 ? "B" : " "
                    if escapeCode == "B" && silComment { label = .getProduct; continue }
                    if escapeCode == "B" { label = .getCode; continue }
                    if silComment { label = .jumpTotals; continue }
                    label = .getQty

                case .getQty:
                    if stockLink == "N" { wsQty = 0 }
                    c.display(Cobol.z(wsQty, 5), at: lin * 100 + 53, color: 3)
                    wsQty = try accNum(lin * 100 + 53, 5, wsQty, color: 3)
                    if wsQty == 0 { label = .getDesc; continue }
                    if stockLink == "Y" && wsQty > stock.int("stock-held") {
                        wsQty = abs(stock.int("stock-held")) % 100000
                        continue
                    }
                    label = stockLink == "Y" ? .recompNet : .getUnit

                case .getUnit:
                    let amt7 = try acceptMoney(lin * 100 + 60, intDigits: 7, 0)
                    if amt7 == 0 { label = .getQty; continue }
                    wsUnit = amt7
                    label = .recompNet

                case .recompNet:
                    let n = wsQty * wsUnit
                    if n >= Cobol.pow10(9) {
                        c.display("SizEr", at: lin * 100 + (stockLink == "Y" ? 53 : 60), color: 4)
                        label = .getQty; continue
                    }
                    wsNet = n
                    setLine(i) { $0.setInt("sil-net", self.wsNet); $0.setInt("sil-qty", self.wsQty); $0.setInt("sil-unit", self.wsUnit) }
                    c.display(d9(wsNet), at: 1232, color: 3)
                    label = .getDisc

                case .getDisc:
                    wsDiscount = sales.int("sales-discount")
                    let shown = Cobol.z(wsDiscount / 100, 2) + "." + Cobol.z(wsDiscount % 100, 2)
                    c.display(shown, at: lin * 100 + 72, color: 3)
                    let r = Array(Cobol.x(try acc(lin * 100 + 72, 5, shown, color: 3), 5))
                    wsDiscount = digits(r[0..<2]) * 100 + digits(r[3...])
                    setLine(i) { $0.setInt("sil-discount", self.wsDiscount) }
                    var work1 = Cobol.rescale(wsNet * wsDiscount, from: 4, to: 2) % Cobol.pow10(9)
                    work1 = work1 / 100
                    wsNet = abs(wsNet - work1)
                    setLine(i) { $0.setInt("sil-net", self.wsNet) }
                    c.display(d9(wsNet), at: 1232, color: 3)
                    // Get-Vat-Code
                    repeat {
                        c.display(String(vatCode), at: lin * 100 + 79, color: 3)
                        vatCode = try accNum(lin * 100 + 79, 1, vatCode, color: 3)
                    } while vatCode > 3
                    setLine(i) { $0.setInt("sil-vat-code", self.vatCode) }
                    if vatCode == 0 { wsVat = 0 }
                    else { wsVat = Cobol.rescaleRounded(wsNet * vatRate(vatCode), from: 6, to: 2) % Cobol.pow10(9) }
                    setLine(i) { $0.setInt("sil-vat", self.wsVat) }
                    c.display(d9(wsVat), at: 1249, color: 3)
                    runningTotals()
                    label = .jumpTotals

                case .jumpTotals:
                    j += 1; i += 1
                    label = .getData2
                }
            }
        }

        // MARK: end-totals / total-screen

        func endTotals() throws {
            while true {
                crt = 0
                try totalScreen()
                if crt == SLB910.esc { return }
                c.display(" ", at: 1501, eraseEOS: true)
                let stars = String(repeating: "*", count: 21)
                c.display(stars, at: 1660, color: 2)
                for p in [1760, 1780, 1860, 1880, 1960, 1980] { c.display("*", at: p, color: 2) }
                c.display(stars, at: 2060, color: 2)
                c.display(t("sl910.ok_to"), at: 1761, color: 2)
                c.display(t(s.sys.int("pass-value") == 2 ? "sl910.store" : "sl910.print"), at: 1775, color: 2)
                c.display(t("sl910.yn_y"), at: 1968, color: 2)
                var again = false
                while true {   // confirmation
                    wsReply = try acc(1977, 1, "Y", color: 6).uppercased()
                    if crt == SLB910.esc { return }
                    if wsReply == "N" { again = true; break }
                    if wsReply == "Y" { break }
                }
                if !again { break }
            }
            sih["sih-status"] = "P"
            sih["sih-status-p"] = " "
            i = abs(i - 1) % 100
            sih.setInt("sih-lines", Int64(i))
            let rec = SLB.invoiceRecord(from: sih)
            let st = inv.write(rec)
            if st != "00" { try invoiceWriteError(st, inv.key(of: rec)) }
            j = 0
            for _ in 0..<i { try writeDetails() }
            let pass = s.sys.int("pass-value")
            if s.sys.int("first-sl-inv") == 0 && pass != 3 { s.sys.setInt("first-sl-inv", sih.int("sih-invoice")) }
            if delinv != 1 { s.sys.setInt("next-invoice", s.sys.int("next-invoice") + 1) }
            // else: delete del-inv-nos-file record (順編成ファイルへの DELETE は無効: 何も起きない)
            if pass == 3 {
                // et-print
                closeAll()
                _ = try s.call("sl930")
                exitProgram = true
                return
            }
            s.sys.setInt("s-flag-i", 1)
            c.display(" ", at: 1101, eraseEOS: true)
        }

        func totalScreen() throws {
            c.display(" ", at: 1101, eraseEOS: true)
            c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
            c.display(t("sl910.level"), at: 1201, color: 2)
            c.display(level1 ? "1" : "2", at: 1207, color: 2)
            c.display(t("sl910.tot_heads1"), at: 1225, color: 2)
            c.display(t("sl910.tot_heads2"), at: 1254, color: 2)
            c.display(t("sl910.sub_totals"), at: 1404, color: 2)
            c.display("{          }   {         }", at: 1425, color: 2)
            c.display("{          }     [  ]", at: 1454, color: 2)
            c.display(s.sys.str("extra-desc"), at: 1504, color: 2)
            c.display("[          ]   [         ]", at: 1525, color: 2)
            c.display("{          }", at: 1554, color: 2)
            c.display(t("sl910.shipping"), at: 1604, color: 2)
            c.display("[          ]   [         ]", at: 1625, color: 2)
            c.display("{          }", at: 1654, color: 2)
            c.display(t("sl910.late_charge"), at: 1704, color: 2)
            c.display("[          ]              ", at: 1725, color: 2)
            c.display("{          }     [  ]", at: 1754, color: 2)
            c.display("------------   -----------", at: 1825, color: 2)
            c.display("------------", at: 1854, color: 2)
            c.display(t("sl910.itemised"), at: 1904, color: 2)
            c.display("{          }   {         }", at: 1925, color: 2)
            c.display("{          }", at: 1954, color: 2)
            let net = sih.int("sih-net"), vat = sih.int("sih-vat")
            c.display(d9(net), at: 1426, color: 3)
            c.display(d8(vat), at: 1441, color: 3)
            c.display(d9(net + vat), at: 1455, color: 3)
            // get-days
            let type = sih.int("sih-type")
            sih.setInt("sih-days", 0); sih.setInt("sih-carriage", 0)
            if type == 2 { sih.setInt("sih-days", sales.int("sales-credit")) }
            else if type == 4 { sih.setInt("sih-days", Int64(Int8(truncatingIfNeeded: s.sys.int("pf-retention")))) }
            var dayes = abs(sih.int("sih-days")) % 100
            c.display(Cobol.z(dayes, 2), at: 1472, color: 3)
            if type == 2 {
                dayes = try accNum(1472, 2, dayes, color: 3)
                sih.setInt("sih-days", dayes)
            }
            // get-extra
            let m9 = Cobol.pow10(9)
            if s.sys.str("extra-type") == " " {
                sih.setInt("sih-extra", 0); sih.setInt("sih-e-vat", 0)
            } else {
                var extra: Int64 = 0
                if s.sys.int("extra-rate") != 0 { extra = Cobol.rescale(net * s.sys.int("extra-rate"), from: 6, to: 2) % m9 }
                extra = try acceptMoney(1526, intDigits: 7, extra)
                sih.setInt("sih-extra", extra)
                // get-extra-vat
                if extra == 0 { sih.setInt("sih-e-vat", 0) }
                else {
                    var amt6 = abs(Cobol.rescale(extra * vatRate(1), from: 6, to: 2)) % Cobol.pow10(8)
                    amt6 = try acceptMoney(1541, intDigits: 6, amt6)
                    sih.setInt("sih-e-vat", amt6)
                    c.display(d9(extra + amt6), at: 1555, color: 3)
                    if s.sys.str("extra-type") == "D" {
                        sih.setInt("sih-extra", -extra); sih.setInt("sih-e-vat", -amt6)
                    }
                }
            }
            // get-carriage
            let carriage = try acceptMoney(1626, intDigits: 7, 0)
            sih.setInt("sih-carriage", carriage)
            var amt6 = Cobol.rescaleRounded(carriage * vatRate(1), from: 6, to: 2) % Cobol.pow10(8)
            amt6 = try acceptMoney(1641, intDigits: 6, amt6)
            sih.setInt("sih-c-vat", amt6)
            c.display(d9(carriage + amt6), at: 1655, color: 3)
            // get-deduct-amt
            if wsNamed == "A" && oi.int("oi-net") == net && oi.int("oi-vat") == vat && oi.int("oi-carriage") == carriage {
                wsNamed = "Z"
            }
            if (type != 2 && type != 3) || sales.int("sales-late") != 1 || wsNamed == "Z" {
                sih.setInt("sih-deduct-amt", 0); sih.setInt("sih-deduct-vat", 0); sih.setInt("sih-deduct-days", 0)
                return
            }
            var amt7 = abs(net / 10) % m9
            if amt7 < 400 { amt7 = 400 }
            amt7 = try acceptMoney(1726, intDigits: 7, amt7)
            sih.setInt("sih-deduct-amt", amt7 % 100000)
            sih.setInt("sih-deduct-vat", 0)
            let dAmt = sih.int("sih-deduct-amt"), dVat = sih.int("sih-deduct-vat")
            let n = net + sih.int("sih-extra") + carriage + dAmt
            let v = vat + sih.int("sih-e-vat") + sih.int("sih-c-vat") + dVat
            c.display(d9(n), at: 1926, color: 3)
            c.display(d8(v), at: 1941, color: 3)
            c.display(d9(n + v), at: 1955, color: 3)
            // get-deduct-days
            dayes = abs(sih.int("sih-days")) % 100
            c.display(Cobol.z(dayes, 2), at: 1772, color: 3)
            dayes = try accNum(1772, 2, dayes, color: 3)
            sih.setInt("sih-deduct-days", dayes)
        }

        // MARK: invoice-details

        func invoiceDetails() throws {
            let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))
            details: while true {
                c.display(SLB910.progName, at: 101, color: 2, eraseEOS: true)
                c.display(t("sl910.title"), at: 132, color: 2)
                wsDate = SLB.wsDate(s)
                c.display(wsDate, at: 171, color: 2)
                let stars = String(repeating: "*", count: 40)
                c.display(stars, at: 441, color: 2)
                c.display(t("sl910.box_date"), at: 541, color: 2)
                c.display(t("sl910.box_ac"), at: 641, color: 2)
                c.display(t("sl910.box_invoice"), at: 741, color: 2)
                c.display(stars, at: 841, color: 2)
                c.display(t("sl910.fkeys"), at: 911, color: 2)
                c.display(t("sl910.type_line"), at: 1001, color: 2)
                // date-input
                while true {
                    c.display(wsDate, at: 549, color: 3)
                    wsDate = Cobol.x(try acc(549, 10, wsDate, color: 3), 10)
                    if crt == SLB910.esc || wsDate == Cobol.x("", 10) { z = 1; return }
                    let v = SLB.validateDate(s, wsDate)
                    if v.bin == 0 { wsDate = v.uDate; continue }
                    sih.setInt("sih-date", v.bin)
                    break
                }
                customerInput: while true {
                    sih["sih-customer"] = ""
                    crt = 0
                    sih["sih-customer"] = try acc(652, 7, Cobol.x("", 7), color: 3).uppercased()
                    showDelivery = crt == SLB910.f8 ? "Y" : "N"
                    let cust = sih.str("sih-customer")
                    if cust == "CREATE9" {
                        c.display(t("sl910.creating"), at: 2301, color: 2)
                        inv.close(); inv.openOutput(); inv.close()
                        SLB.setFileStatus(s, 16, 1)
                        inv.open()
                    }
                    // customer-test
                    if cust == Cobol.x("NEW", 7) || crt == SLB910.f1 {
                        // new-customer
                        closeAll()
                        _ = try s.call("sl960")
                        try programStart()
                        continue details
                    }
                    if cust == Cobol.x("", 7) { escapeCode = "Q"; return }
                    guard let r = salesFile.read(key: sih.raw("sih-customer")) else {
                        sales.setRaw("sales-key", sih.raw("sih-customer"))
                        c.display(t("sl910.no_customer"), at: 401, color: 3)
                        continue
                    }
                    sales = r
                    c.display(String(repeating: " ", count: 23), at: 911)
                    if s.sys.str("sl-own-nos") != "Y" {
                        if delinv == 1 { getADeletedInvoice() }
                        else { sih.setInt("sih-invoice", s.sys.int("next-invoice")) }
                        c.display(Cobol.z(sih.int("sih-invoice"), 8), at: 751, color: 3)
                        sih["sih-letter"] = " "
                        break
                    }
                    // get-inv
                    var back = false
                    getInv: while true {
                        sih.setInt("sih-invoice", try accNum(751, 8, sih.int("sih-invoice"), color: 3))
                        if crt == SLB910.esc { back = true; break }
                        sih["sih-letter"] = " "
                        while true {   // try-again
                            sih.setInt("sih-test", 0)
                            var key = Record(SLB.invoiceLayout)
                            key.setInt("invoice-nos", sih.int("sih-invoice"))
                            key["invoice-let"] = sih.str("sih-letter")
                            key.setInt("item-nos", 0)
                            if inv.read(key: inv.key(of: key)) == nil { break getInv }
                            c.display(t("sl910.confirm_dup"), at: 701, color: 2)
                            wsReply = try acc(722, 1, wsReply, color: 6).uppercased()
                            if wsReply != "Y" { continue getInv }
                            switch sih.str("sih-letter") {
                            case " ": sih["sih-letter"] = "A"
                            case "A": sih["sih-letter"] = "B"
                            case "B": sih["sih-letter"] = "C"
                            default: break
                            }
                        }
                    }
                    if back { continue customerInput }
                    break
                }
                // jump-1
                var addressA: String
                if sales.int("delivery-tag") == 0 || showDelivery == "N" {
                    addressA = sales.str("sales-addr1") + sales.str("sales-addr2")
                } else {
                    deliv["deliv-key"] = "D" + sales.str("sales-key")
                    if let d = delivery.read(key: deliv.raw("deliv-key")) {
                        deliv = d
                        addressA = deliv.str("deliv-address")
                    } else {
                        sales.setInt("delivery-tag", 0)
                        addressA = sales.str("sales-addr1") + sales.str("sales-addr2")
                    }
                }
                // customer-display
                if sales.int("delivery-tag") == 0 { c.display(sales.str("sales-name"), at: 301, color: 3) }
                else { c.display(deliv.str("deliv-name"), at: 301, color: 3) }
                let src = Array(Cobol.x(addressA, 96))
                z = 1
                for (n, pos) in [401, 501, 601, 701, 801].enumerated() {
                    if n > 0 { addressLine = Cobol.x("", 36) }
                    if let a = SLB940.unstring(src, n < 4 ? delim : nil, size: 36, pointer: &z) { addressLine = a }
                    c.display(addressLine, at: pos, color: 3)
                }
                z %= 100
                addressLine = Cobol.x("", 36)
                // ref-input / order-input
                sih["sih-ref"] = ""; sih["sih-order"] = ""
                sih["sih-ref"] = try acc(669, 10, Cobol.x("", 10), color: 3)
                sih["sih-order"] = try acc(769, 10, sih.str("sih-order"), color: 3)
                // type-input
                var type: Int64
                repeat {
                    sih.setInt("sih-type", 0)
                    type = try accNum(1007, 1, 0, color: 3)
                    sih.setInt("sih-type", type)
                    wsNamed = " "
                    if type == 0 { continue details }
                } while type > 4
                let dTypes = ["sl910.type_receipt", "sl910.type_account", "sl910.type_credit", "sl910.type_proforma"]
                c.display(" ", at: 1001, eraseEOL: true)
                c.display(">>> ", at: 1031, color: 2)
                c.display(Cobol.x(t(dTypes[Int(type) - 1]), 15), at: 1035, color: 2)
                sih.setInt("sih-cr", 0)
                if type == 3 {
                    try crNote()
                    if escapeCode == "Q" { continue details }
                }
                z = 0
                if type == 1 || type > 2 { return }
                var weError = 0
                let current = sales.int("sales-current") - sales.int("sales-unapplied")
                sales.setInt("sales-current", current)
                if current > 0 {
                    let work1 = abs(s.sys.int("run-date") - sales.int("sales-last-inv")) * 100
                    if work1 > sales.int("sales-credit") * 100 {
                        c.display(t("sl910.overdue"), at: 1648, color: 2, highlight: true)
                        weError = 999
                    }
                }
                if current > sales.int("sales-limit") * 100 {
                    c.display(t("sl910.exceeds"), at: 1725, color: 2, highlight: true)
                    weError = 998
                }
                if sales.int("sales-credit") <= 0 || sales.int("sales-limit") <= 0 {
                    c.display(t("sl910.no_longer"), at: 1825, color: 2, highlight: true)
                    weError = 997
                }
                if weError == 0 { return }
                c.display(t("sl910.warning"), at: 1635, color: 2, highlight: true)
                let s22 = String(repeating: "*", count: 22)
                c.display(s22, at: 1958, color: 2)
                for p in [2058, 2158, 2079, 2179] { c.display("*", at: p, color: 2) }
                c.display(s22, at: 2258, color: 2)
                c.display(t("sl910.abort"), at: 2060, color: 2)
                c.display(t("sl910.continue"), at: 2160, color: 2)
                z = 0
                z = Int(try accNum(2280, 2, 0, color: 6))
                if crt == SLB910.esc { z = 1; crt = 1 }
                return
            }
        }

        // MARK: get-a-deleted-invoice

        func getADeletedInvoice() {
            if delinv == 1 {
                let raw = s.store.readRaw(dnos) ?? []
                while dnosPos + 19 <= raw.count {
                    let rec = Array(raw[dnosPos..<(dnosPos + 19)])
                    dnosPos += 19
                    let n = Cobol.moveNumeric(SJIS.decode(rec[0..<8]), digits: 8, scale: 0)
                    if n == 0 { continue }
                    sih.setInt("sih-invoice", n)
                    c.display(t("sl910.using_deleted"), at: 345, color: 2)
                    return
                }
                // l70ac-close
                s.store.writeRaw(dnos, [])
                dnosPos = 0
                c.display(String(repeating: " ", count: 29), at: 345)
            }
            sih.setInt("sih-invoice", s.sys.int("next-invoice"))
            delinv = 0
        }

        // MARK: cr-note

        func crNote() throws {
            func clear() { for p in [1201, 1301, 1401, 1501, 1601] { c.display(" ", at: p, eraseEOL: true) } }
            clear()
            mainInput: while true {
                c.display(t("sl910.inv_to_credit"), at: 1201, color: 2)
                c.display("] ", at: 1230, color: 2)
                let cr = try accNum(1222, 8, 0, color: 3)
                if crt == SLB910.esc { escapeCode = "Q"; return }
                sih.setInt("sih-cr", cr)
                if cr == 0 { wsNamed = "Z"; clear(); return }
                wsNamed = " "
                if cr == 99999999 { escapeCode = "Q"; return }
                escapeCode = " "
                var key = Record(SLB.oiLayout)
                key["oi-customer"] = sih.str("sih-customer")
                key.setInt("oi-invoice", cr)
                guard let r = oi3.read(key: oi3.key(of: key)) else {
                    oi.setRaw("oi-customer", key.raw("oi-customer")); oi.setInt("oi-invoice", cr)
                    c.display(t("sl910.sl181"), at: 2301, color: 2, highlight: true)
                    while true {   // check-inv-no-ok
                        c.display(t("sl910.use_inv_no"), at: 1401, color: 2)
                        c.display(t("sl910.use_inv_no2"), at: 1501, color: 2)
                        c.display(t("sl910.use_inv_no3"), at: 1601, color: 2)
                        wsReply = try acc(1439, 1, "N", color: 6).uppercased()
                        if wsReply == "Y" { clear(); return }
                        if wsReply == "N" { clear(); continue mainInput }
                    }
                }
                oi = r
                c.display(" ", at: 2301, eraseEOL: true)
                if oi.int("oi-type") != 2 {
                    c.display(t("sl910.sl184"), at: 2301, color: 2, highlight: true)
                    continue
                }
                if oi.int("oi-status") == 1 {
                    c.display(t("sl910.sl182"), at: 1301, color: 2, highlight: true)
                    continue
                }
                c.display(" ", at: 2301, eraseEOL: true)
                if oi.str("oi-hold-flag") == "Q" { c.display(t("sl910.sl183"), at: 2301, color: 2, highlight: true) }
                if oi.int("oi-date") + 1 + oi.int("oi-deduct-days") > sih.int("sih-date") { wsNamed = "A" }
                oi.setInt("oi-deduct-amt", (oi.int("oi-deduct-amt") + oi.int("oi-deduct-vat")) % 100000)
                var disc = oi.int("oi-discount") + oi.int("oi-extra") + oi.int("oi-carriage") + oi.int("oi-deduct-amt")
                    + oi.int("oi-net") + oi.int("oi-vat") + oi.int("oi-c-vat") + oi.int("oi-e-vat")
                disc -= oi.int("oi-paid")
                oi.setInt("oi-discount", Cobol.truncate(disc, digits: 9))
                c.display(t("sl910.amount_os"), at: 1401, color: 2)
                c.display(d9(oi.int("oi-discount")), at: 1426, color: 3)
                c.display(t("sl910.of_which"), at: 1437, color: 2)
                c.display(d8(oi.int("oi-deduct-amt")), at: 1446, color: 3)
                c.display(t("sl910.is_late"), at: 1456, color: 2)
                if wsNamed == "A" { c.display(t("sl910.sl185"), at: 1510, color: 2) }
                c.display(t("sl910.sl006"), at: 1626)
                wsReply = try acc(1661, 1)
                clear()
                return
            }
        }
    }
}
