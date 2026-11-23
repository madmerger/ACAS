import Foundation

/// sales/sl920.cbl: Invoicing Data Amend (請求書修正)
enum SLB920 {
    static let progName = "SL920 (3.01.08)"
    static let esc = 2005, f2 = 1002, f3 = 1003, f5 = 1005, f6 = 1006, f8 = 1008

    private enum L2 { case getData2, getProduct, getProdTest, getCode, getDesc, getQty, getUnit, recompNet, getDisc, jumpTotals }

    /// Change-Item-Tables の 1 要素
    struct CIT {
        var key = Cobol.x("", 13), desc = Cobol.x("", 32)
        var qty: Int64 = 0
    }

    static func run(_ s: Session) throws { try Prog(s).run() }

    final class Prog {
        let s: Session
        let c: Console
        var analysis: IndexedFile, salesFile: IndexedFile, inv: IndexedFile, delivery: IndexedFile
        let stockFile: SLB910.StockFile
        let auditPath: String

        var sih = Record(SLB.sihLayout)
        var lines = [Record](repeating: Record(SLB.silLayout), count: 41)
        var sales = Record(SLB.salesLayout)
        var deliv = Record(SLB.deliveryLayout)
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
        // Change-Item-Tables (添字 0 は範囲外参照の受け皿)
        var citNewProduct = 0, citA = 0, citD = 0
        var additions = [CIT](repeating: CIT(), count: 41)
        var deletions = [CIT](repeating: CIT(), count: 41)
        // Stock-Audit-Record
        var aType = 0, aReverse = 0
        var aInvoice: Int64 = 0, aCr: Int64 = 0, aQty: Int64 = 0, aValueChange: Int64 = 0, aNo: Int64 = 0
        var aKey = [UInt8](repeating: 0x20, count: 13), aDesc = Cobol.x("", 32), aDate = Cobol.x("", 10)

        init(_ s: Session) {
            self.s = s; c = s.console
            analysis = IndexedFile(s.store, path: s.ledgers + "analysis.dat", layout: SLB910.analysisLayout, keyOffset: 0, keyLength: 3)
            salesFile = SLB.salesFile(s); inv = SLB.invoiceFile(s); delivery = SLB.deliveryFile(s)
            stockFile = SLB910.StockFile(s)
            auditPath = s.ledgers + "staudit.dat"
        }

        var stockLink: String { s.sys.str("sl-stock-link") }
        var level1: Bool { s.sys.int("invoicer") == 1 }
        var silComment: Bool { testProduct.hasPrefix("/") }
        func t(_ k: String) -> String { s.t(k) }
        func d9(_ v: Int64) -> String { SLB.z99(v, 7) }
        func d8(_ v: Int64) -> String { SLB.z99(v, 6) }
        func line(_ n: Int) -> Record { (1...40).contains(n) ? lines[n] : Record(SLB.silLayout) }
        func setLine(_ n: Int, _ body: (inout Record) -> Void) { if (1...40).contains(n) { body(&lines[n]) } }
        func setA(_ body: (inout CIT) -> Void) { if (0...40).contains(citA) { body(&additions[citA]) } }
        func setD(_ body: (inout CIT) -> Void) { if (0...40).contains(citD) { body(&deletions[citD]) } }

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
        func moneyText(_ amt: Int64, _ n: Int) -> String {
            let v = abs(amt) % Cobol.pow10(n + 2)
            return Cobol.z(v / 100, n) + "." + Cobol.z(v % 100, 2)
        }
        /// accept-money6c / accept-money7c
        func acceptMoney(_ llcc: Int, intDigits n: Int, _ amt: Int64) throws -> Int64 {
            let shown = moneyText(amt, n)
            c.display(shown, at: llcc, color: 3)
            let r = Array(Cobol.x(try acc(llcc, n + 3, shown, color: 3), n + 3))
            return digits(r[0..<n]) * 100 + digits(r[(n + 1)...])
        }
        func vatRate(_ n: Int64) -> Int64 { s.sys.int("vat-rate-\(n)") }
        func invKey(_ nos: Int64, _ letter: String, _ item: Int64) -> [UInt8] {
            var k = Record(SLB.invoiceLayout)
            k.setInt("invoice-nos", nos); k["invoice-let"] = letter; k.setInt("item-nos", item)
            return inv.key(of: k)
        }

        // MARK: init01 / main

        func run() throws {
            wsDate = SLB.wsDate(s)
            try programStart()
            mainLoop: while true {
                lines = [Record](repeating: Record(SLB.silLayout), count: 41)
                citNewProduct = 0; citA = 0; citD = 0
                additions = [CIT](repeating: CIT(), count: 41)
                deletions = [CIT](repeating: CIT(), count: 41)
                try invoiceDetails()
                if crt == SLB920.esc || z != 0 || escapeCode == "Q" { break }
                c.display(" ", at: 1601, eraseEOS: true)
                // data-input
                sih.setInt("sih-p-c", 0); sih.setInt("sih-net", 0); sih.setInt("sih-vat", 0)
                i = 0
                if level1 { try invLevel1() } else { try invLevel2() }
                if crt == SLB920.esc { continue }
                if i != 1 { try endTotals() }
                while true {   // more-data
                    c.display(t("sl920.further"), at: 1629, color: 2)
                    wsReply = try acc(1661, 1, "Y", color: 6).uppercased()
                    c.display(" ", at: 1601, eraseEOL: true)
                    if wsReply == "Y" { continue mainLoop }
                    if wsReply != "N" { continue }
                    break mainLoop
                }
            }
            // menu-exit
            s.sys.setInt("pass-value", 0)
            salesFile.close(); delivery.close(); analysis.close(); inv.close()
        }

        // MARK: program-start

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
            inv.open()
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
            if i >= 1 {
                for k in 1...min(i, 40) where lines[k].str("sil-type") != "D" {
                    net += lines[k].int("sil-net"); vat += lines[k].int("sil-vat")
                }
            }
            sih.setInt("sih-net", net); sih.setInt("sih-vat", vat)
            if level1 { c.display(d9(net), at: 1237, color: 3) }
            if level1 { c.display(d9(vat), at: 1255, color: 3) }
            c.display(d9(net + vat), at: level1 ? 1268 : 1270, color: 3)
        }

        func invoiceError(_ msgKey: String, _ status: String, _ key: [UInt8]) throws {
            c.display(t(msgKey), at: 2301, color: 4, eraseEOL: true)
            c.display(status, at: 2336, color: 3)
            c.display(SLB.fsMsg(s, status), at: 2339, color: 3)
            c.display(SJIS.decode(key[...]), at: 2364, color: 3)
            c.display(t("sl910.sl006"), at: 2401, color: 3)
            wsReply = try acc(2430, 1)
            c.display(" ", at: 2301, eraseEOS: true)
        }

        func writeDetails() throws {
            j += 1
            guard (1...40).contains(j) else { return }
            lines[j].setInt("sil-invoice", sih.int("sih-invoice"))
            lines[j].setInt("sil-line", Int64(j))
            lines[j]["sil-letter"] = sih.str("sih-letter")
            lines[j]["sil-type"] = String(sih.int("sih-type"))
            let rec = SLB.invoiceRecord(from: lines[j])
            var st = inv.rewrite(rec)
            if st != "00" { st = inv.write(rec) }
            if st != "00" { try invoiceError("sl910.sl180", st, inv.key(of: rec)) }
        }

        // MARK: Update-Stock-and-Audit

        private func readStockForAudit() throws {
            var found: Record?
            if aKey[7..<13].allSatisfy({ $0 == 0x20 }) { found = stockFile.read(13..<20, Array(aKey[0..<7])) }
            else { found = stockFile.read(0..<13, aKey) }
            if let f = found { stock = f }
            else { stock.setInt("stock-cost", 0); stock["stock-key"] = "" }
            if stockFile.status != "00" {
                c.display(t("sl910.stock_read"), at: 2301, color: 4, eraseEOL: true)
                c.display(stockFile.status, at: 2316, color: 3)
                c.display(SLB.fsMsg(s, stockFile.status), at: 2319, color: 3)
                c.display(stock.str("stock-key"), at: 2064, color: 3)
                c.display(t("sl910.sl006"), at: 2401, color: 3)
                wsReply = try acc(2430, 1)
                c.display(" ", at: 2301, eraseEOS: true)
            }
        }
        private func rewriteStockAndAudit(_ heldIn: Int64) throws {
            if stock.str("stock-key") != Cobol.x("", 13) {
                var held = heldIn
                let cost = stock.int("stock-cost")
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
                var b: [UInt8] = Array(String(aType).utf8)
                b += Array(Cobol.z(aInvoice, 8).utf8)
                b += Array(Cobol.z(aCr, 8).utf8)
                b += aKey
                b += SJIS.encode(aDesc, size: 32)
                b += SJIS.encode(aDate, size: 10)
                b += Array(String(aReverse).utf8)
                b += SLB910.Prog.signTrailing(aQty, digits: 6)
                b += SLB910.Prog.signTrailing(0, digits: 10)
                b += SLB910.Prog.signTrailing(aValueChange, digits: 10)
                b += Array(Cobol.z(aNo, 5).utf8)
                s.store.appendRaw(auditPath, b)
            }
        }
        private func valueChange(_ sign: Int64) -> Int64 {
            Cobol.truncate(Cobol.rescale(aQty * stock.int("stock-cost") * sign, from: 4, to: 2), digits: 10)
        }

        func updateStockAndAudit() throws {
            if stockLink != "Y" { return }
            if citA == 0 && citD == 0 { return }
            // initialize Stock-Audit-Record
            aType = 0; aReverse = 0; aInvoice = 0; aCr = 0; aQty = 0; aValueChange = 0; aNo = 0
            aKey = [UInt8](repeating: 0x20, count: 13); aDesc = Cobol.x("", 32); aDate = Cobol.x("", 10)
            let isCr = line(j).str("sil-type") == "3"
            func common(_ e: CIT) {
                aType = 3
                aInvoice = sih.int("sih-invoice")
                aDate = wsDate
                aKey = SJIS.encode(e.key, size: 13)
                aDesc = e.desc
            }
            func crSwitch() {
                if isCr {
                    if aReverse == 0 { aReverse = 1; aType = 5; aCr = sih.int("sih-cr") }
                    else { aReverse = 0 }
                }
            }
            if citA >= 1 {
                for tabA in 1...min(citA, 40) {
                    let e = additions[tabA]
                    common(e)
                    if e.qty > 0 { aQty = e.qty; aReverse = 1 }
                    else if e.qty < 0 { aQty = -e.qty }
                    crSwitch()
                    aNo = s.sys.int("stk-audit-no")
                    try readStockForAudit()
                    var held = stock.int("stock-held")
                    if stock.str("stock-key") != Cobol.x("", 13) {
                        if !isCr {
                            if e.qty > 0 { held += e.qty; aValueChange = valueChange(1) }
                            else if e.qty < 0 { held -= e.qty; aValueChange = valueChange(-1) }
                        } else {
                            if e.qty < 0 { held += e.qty; aValueChange = valueChange(1) }
                            else if e.qty > 0 { held -= e.qty; aValueChange = valueChange(-1) }
                        }
                        held = Cobol.truncate(held, digits: 6)
                    }
                    try rewriteStockAndAudit(held)
                }
            }
            if citD >= 1 {
                for tabD in 1...min(citD, 40) {
                    let e = deletions[tabD]
                    common(e)
                    if e.qty > 0 { aQty = e.qty }
                    crSwitch()
                    aNo = s.sys.int("stk-audit-no")
                    try readStockForAudit()
                    var held = stock.int("stock-held")
                    if stock.str("stock-key") != Cobol.x("", 13) {
                        if !isCr { held += e.qty; aValueChange = valueChange(1) }
                        else { held -= e.qty; aValueChange = valueChange(-1) }
                        held = Cobol.truncate(held, digits: 6)
                    }
                    try rewriteStockAndAudit(held)
                }
            }
        }

        // MARK: read-details

        func readDetails() {
            j = 0
            var last = Record(SLB.invoiceLayout, bytes: SLB.invoiceRecord(from: sih).bytes)
            let n = Int(sih.int("sih-lines"))
            if n < 1 { return }
            for _ in 0..<n {
                j += 1
                if let r = inv.read(key: invKey(sih.int("sih-invoice"), sih.str("sih-letter"), Int64(j))) { last = r }
                if (1...40).contains(j) { lines[j] = SLB.sil(from: last) }
            }
        }

        // MARK: inv-level-1

        func displayOutline1() {
            i += 1
            c.display("(", at: lin * 100 + 1, color: 2, eraseEOL: true)
            c.display(Cobol.z(Int64(i % 100), 2), at: lin * 100 + 2, color: 2)
            c.display(") [  ]", at: lin * 100 + 4, color: 2)
            c.display("[          ] [ ]   {         } (", at: lin * 100 + 36, color: 2)
            c.display(")", at: lin * 100 + 78, color: 2)
        }
        func displayOutline2() {
            i += 1
            if stockLink == "N" {
                c.display("[             ][  ][", at: lin * 100 + 1, color: 2, eraseEOL: true)
                c.display("][     ][          ][     ][ ]", at: lin * 100 + 51, color: 2)
            } else {
                c.display("[             ][", at: lin * 100 + 1, color: 2, eraseEOL: true)
                c.display("]  [     ][          ][     ][ ]", at: lin * 100 + 49, color: 2)
            }
        }

        func invLevel1() throws {
            c.display(String(repeating: "-", count: 80), at: 1101, color: 2)
            c.display(t("sl910.level1"), at: 1201, color: 2)
            c.display(t("sl910.line"), at: 1216, color: 2)
            for p in [1236, 1254, 1267] { c.display("<          >", at: p, color: 2) }
            c.display(t("sl910.l1_code"), at: 1405, color: 2)
            c.display(t("sl910.l1_heads"), at: 1436, color: 2)
            while true {
                lin = 16
                while lin < 23 { displayOutline1(); lin += 1 }
                i = abs(i - 8) % 100
                j = 1
                c.display(Cobol.z(Int64(i), 2), at: 1223, color: 2)
                crt = 0
                try getData1()
                if crt == SLB920.esc { return }
                if newScreen == 1 { continue }
                if line(i).str("sil-description") != Cobol.x("", 32) && i != 40 { continue }
                return
            }
        }

        /// clear-down-line
        func clearDownLine() {
            if i >= 1 && i <= 39 {
                for k in i...39 {
                    lines[k] = lines[k + 1]
                    lines[k].setInt("sil-line", Int64(k))
                }
            }
            z = 0
            let n = sih.int("sih-lines")
            if Int64(i) <= n {
                _ = inv.delete(key: invKey(sih.int("sih-invoice"), sih.str("sih-letter"), n))
                sih.setInt("sih-lines", n - 1)
            }
        }

        func getData1() throws {
            outer: while true {
                lin = j + 15
                if lin > 23 { i = abs(i - 1) % 100; newScreen = 1; return }
                newScreen = 0
                getCode: while true {
                    wsPa = line(i).str("sil-pa")
                    c.display(wsPa, at: lin * 100 + 7, color: 3)
                    wsPa = Cobol.x(try acc(lin * 100 + 7, 2, wsPa, color: 3), 2)
                    if wsPa == "  " { return }
                    if crt == SLB920.esc { return }
                    if wsPa == "<<" && i == 1 { continue getCode }
                    if wsPa == "<<" {
                        lin -= 1
                        if lin > 15 { i -= 1; j -= 1; continue getCode }
                        i = abs(i - 8) % 100
                        continue outer
                    }
                    if wsPa == "**" {
                        clearDownLine()
                        i = abs(i - 1) % 100
                        displayOutline1()
                        continue getCode
                    }
                    setLine(i) { $0["sil-pa"] = self.wsPa }
                    guard let r = analysis.read(key: "S" + wsPa) else {
                        c.display(t("sl910.sl186"), at: 2301, color: 4, highlight: true)
                        continue getCode
                    }
                    pa = r
                    c.display(" ", at: 2301, eraseEOL: true)
                    c.display(pa.str("pa-desc"), at: lin * 100 + 11, color: 3)
                    setLine(i) { $0["sil-description"] = self.pa.str("pa-desc") }
                    // get-net
                    let amt7 = try acceptMoney(lin * 100 + 37, intDigits: 7, line(i).int("sil-net"))
                    if amt7 == 0 { continue getCode }
                    setLine(i) { $0.setInt("sil-net", amt7) }
                    wsNet = amt7
                    // get-vat-code
                    repeat {
                        vatCode = line(i).int("sil-vat-code")
                        c.display(String(vatCode), at: lin * 100 + 50, color: 3)
                        vatCode = try accNum(lin * 100 + 50, 1, vatCode, color: 3)
                    } while vatCode > 3
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
            c.display(t("sl920.net_box"), at: 1227, color: 2)
            c.display(t("sl920.vat_box"), at: 1244, color: 2)
            c.display(t("sl920.invoice_box"), at: 1261, color: 2)
            c.display(t(stockLink == "N" ? "sl920.l2_heads_pa" : "sl920.l2_heads_stock"), at: 1405, color: 2)
            while true {
                lin = 16
                while lin < 23 { displayOutline2(); lin += 1 }
                i = abs(i - 8) % 100
                j = 1
                c.display(Cobol.z(Int64(i), 2), at: 1223, color: 2)
                try getData2()
                if crt == SLB920.esc { return }
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
                    wsProduct = line(i).str("sil-product")
                    c.display(wsProduct, at: lin * 100 + 2, color: 3)
                    wsProduct = Cobol.x(try acc(lin * 100 + 2, 13, wsProduct, color: 3), 13)
                    if wsProduct == blank13 { return }
                    if crt == SLB920.esc { return }
                    wsProduct = wsProduct.uppercased()
                    testProduct = wsProduct
                    citA = (citA + 1) % 100
                    if wsProduct == line(i).str("sil-product") {
                        if stockLink == "N" {
                            citA = abs(citA - 1) % 100
                            label = .getCode; continue
                        }
                        citNewProduct = 0
                        let d = line(i).str("sil-description"), q = line(i).int("sil-qty")
                        setA { $0.key = self.wsProduct; $0.desc = d; $0.qty = q }
                        label = .getQty; continue
                    }
                    if silComment {
                        setLine(i) {
                            $0["sil-product"] = self.wsProduct
                            $0.setInt("sil-net", 0); $0.setInt("sil-qty", 0); $0.setInt("sil-vat", 0)
                        }
                        label = .getDesc; continue
                    }
                    if wsProduct == Cobol.x("<<", 13) { lin -= 1; label = .getProdTest; continue }
                    if stockLink == "Y" {
                        let p = line(i).str("sil-product"), d = line(i).str("sil-description"), q = line(i).int("sil-qty")
                        setA { $0.key = p; $0.desc = d; $0.qty = q }
                        citD = (citD + 1) % 100
                        citNewProduct = 1
                        setD { $0.key = self.wsProduct }
                    }
                    setLine(i) { $0["sil-product"] = self.wsProduct }
                    if wsProduct.hasPrefix("**") {
                        citD = abs(citD - 1) % 100
                        citNewProduct = 0
                        label = .getCode; continue
                    }
                    if stockLink == "N" { label = .getCode; continue }
                    let cur = lin * 100 + 17
                    let stockKey = SJIS.encode(wsProduct, size: 13)
                    if crt == SLB920.f3 {
                        if !stockFile.start(13..<20, Array(stockKey[0..<7])) { stockMsg("sl910.not_found", 4); continue }
                        guard let r = stockFile.readNext() else { stockMsg("sl910.end_of_file", 4); continue }
                        stock = r
                        setLine(i) { $0["sil-product"] = self.stock.str("stock-abrev-key") }
                        c.display(stock.str("stock-desc"), at: cur, color: 3)
                        continue
                    }
                    if crt == SLB920.f2 {
                        guard let r = stockFile.readNext() else { stockMsg("sl910.end_of_file", 4); continue }
                        stock = r
                        setLine(i) { $0["sil-product"] = self.stock.str("stock-abrev-key") }
                        c.display(stock.str("stock-desc"), at: cur, color: 3)
                        continue
                    }
                    if crt == SLB920.f6 {
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
                    if crt == SLB920.f5 {
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
                    setD { $0.desc = self.wsDescription }
                    wsUnit = stock.int("stock-retail")
                    c.display(moneyText(wsUnit, 7), at: lin * 100 + 60, color: 3)
                    wsQty = abs(stock.int("stock-held")) % 100000
                    label = .getQty

                case .getProdTest:
                    if i == 1 { lin += 1; label = .getProduct; continue }
                    if lin > 15 { i -= 1; j -= 1; label = .getProduct }
                    else { i = abs(i - 8) % 100; label = .getData2 }

                case .getCode:
                    if line(i).str("sil-product").hasPrefix("**") {
                        clearDownLine()
                        i = abs(i - 1) % 100
                        displayOutline2()
                        label = .getProduct; continue
                    }
                    wsPa = line(i).str("sil-pa")
                    c.display(wsPa, at: lin * 100 + 17, color: 3)
                    wsPa = Cobol.x(try acc(lin * 100 + 17, 2, wsPa, color: 3), 2)
                    if wsPa == "  " { label = .getProduct; continue }
                    setLine(i) { $0["sil-pa"] = self.wsPa }
                    guard let r = analysis.read(key: "S" + wsPa) else {
                        c.display(t("sl910.sl186"), at: lin * 100 + 21, color: 4)
                        continue
                    }
                    pa = r
                    label = .getDesc

                case .getDesc:
                    let cur = lin * 100 + (stockLink == "Y" ? 17 : 21)
                    wsDescription = line(i).str("sil-description")
                    c.display(wsDescription, at: cur, color: 3)
                    wsDescription = Cobol.x(try acc(cur, 32, wsDescription, color: 3), 32)
                    escapeCode = wsDescription == blank32 ? "B" : " "
                    if escapeCode == "B" && silComment { label = .getProduct; continue }
                    if escapeCode == "B" { label = .getCode; continue }
                    setLine(i) { $0["sil-description"] = self.wsDescription }
                    if silComment { label = .jumpTotals; continue }
                    label = .getQty

                case .getQty:
                    wsQty = abs(line(i).int("sil-qty")) % 100000
                    c.display(Cobol.z(wsQty, 5), at: lin * 100 + 53, color: 3)
                    wsQty = try accNum(lin * 100 + 53, 5, wsQty, color: 3)
                    if wsQty == 0 && stockLink == "Y" { label = .recompNet; continue }
                    if wsQty == 0 { label = .getDesc; continue }
                    if stockLink == "Y" && wsQty > stock.int("stock-held") {
                        wsQty = abs(stock.int("stock-held")) % 100000
                        continue
                    }
                    if stockLink == "Y" && citNewProduct == 1 {
                        setD { $0.qty = self.wsQty }
                        label = .recompNet; continue
                    }
                    if stockLink == "Y" && citNewProduct == 0 && wsQty == line(i).int("sil-qty") {
                        setA { $0 = CIT() }
                        citA = abs(citA - 1) % 100
                        label = .recompNet; continue
                    }
                    if stockLink == "Y" && citNewProduct == 0 && wsQty != line(i).int("sil-qty") {
                        let q = line(i).int("sil-qty") - wsQty
                        setA { $0.qty = q }
                    }
                    label = .getUnit

                case .getUnit:
                    let amt6 = try acceptMoney(lin * 100 + 60, intDigits: 6, line(i).int("sil-unit"))
                    if amt6 == 0 { label = .getQty; continue }
                    wsUnit = amt6
                    label = .recompNet

                case .recompNet:
                    // レガシーは "on size error display ... ." で文が終わり、続く go to get-qty が無条件に実行される
                    let n = wsQty * wsUnit
                    if n >= Cobol.pow10(9) {
                        c.display("SizEr", at: lin * 100 + 60, color: 4)
                    } else {
                        wsNet = n
                    }
                    label = .getQty

                case .getDisc:
                    // 到達不能 (recomp-net の無条件 go to のため)。ソースどおり残す
                    setLine(i) { $0.setInt("sil-net", self.wsNet); $0.setInt("sil-qty", self.wsQty); $0.setInt("sil-unit", self.wsUnit) }
                    c.display(d9(wsNet), at: 1232, color: 3)
                    wsDiscount = line(i).int("sil-discount")
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
                    // get-vat-code
                    repeat {
                        vatCode = line(i).int("sil-vat-code")
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
                try totalScreen()
                c.display(" ", at: 1501, eraseEOS: true)
                let stars = String(repeating: "*", count: 21)
                c.display(stars, at: 1660, color: 2)
                for p in [1760, 1760, 1860, 1880, 1960, 1980] { c.display("*", at: p, color: 2) }
                c.display(stars, at: 2060, color: 2)
                c.display(t("sl920.ok_to_store"), at: 1761, color: 2)
                c.display(t("sl920.yn_y"), at: 1967, color: 2)
                var again = false
                while true {   // confirmation
                    wsReply = try acc(1975, 1, "Y", color: 6).uppercased()
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
            let st = inv.rewrite(rec)
            if st != "00" { try invoiceError("sl920.sl192", st, inv.key(of: rec)) }
            j = 0
            for _ in 0..<i { try writeDetails() }
            try updateStockAndAudit()
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
                sih.setInt("sih-extra", extra)
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
            let carriage = try acceptMoney(1626, intDigits: 7, sih.int("sih-carriage"))
            sih.setInt("sih-carriage", carriage)
            var amt6 = Cobol.rescaleRounded(carriage * vatRate(1), from: 6, to: 2) % Cobol.pow10(8)
            amt6 = try acceptMoney(1641, intDigits: 6, amt6)
            sih.setInt("sih-c-vat", amt6)
            c.display(d9(carriage + amt6), at: 1655, color: 3)
            // get-deduct-amt
            if (type != 2 && type != 3) || sales.int("sales-late") != 1 || wsNamed == "Z" {
                sih.setInt("sih-deduct-amt", 0); sih.setInt("sih-deduct-vat", 0); sih.setInt("sih-deduct-days", 0)
                return
            }
            var amt7 = abs(net / 10) % m9
            if amt7 < 400 { amt7 = 400 }
            amt7 = try acceptMoney(1726, intDigits: 7, amt7)
            sih.setInt("sih-deduct-amt", amt7 % 100000)
            // get-deduct-vat
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
            let ownNos = s.sys.str("sl-own-nos") == "Y"
            c.display(SLB920.progName, at: 101, color: 2, eraseEOS: true)
            c.display(t("sl920.title"), at: 132, color: 2)
            wsDate = SLB.wsDate(s)
            c.display(wsDate, at: 171, color: 2)
            let stars = String(repeating: "*", count: 40)
            c.display(stars, at: 441, color: 2)
            c.display(t("sl920.box_date"), at: 541, color: 2)
            c.display(t("sl920.box_ac"), at: 641, color: 2)
            c.display(t("sl920.box_invoice"), at: 741, color: 2)
            c.display(stars, at: 841, color: 2)
            c.display(t("sl920.fkeys"), at: 911, color: 2)
            c.display(t("sl910.type_line"), at: 1001, color: 2)
            // invoice-enter
            while true {
                sih.setInt("sih-invoice", 0)
                c.display(Cobol.z(0, 8), at: 751, color: 3)
                if !ownNos { c.display("] ", at: 759, color: 2) }
                sih.setInt("sih-invoice", try accNum(751, 8, 0, color: 3))
                if sih.int("sih-invoice") == 0 || crt == SLB920.esc { z = 1; return }
                sih["sih-letter"] = " "
                if ownNos { sih["sih-letter"] = try acc(759, 1, " ", color: 6) }
                guard let r = inv.read(key: invKey(sih.int("sih-invoice"), sih.str("sih-letter"), 0)) else {
                    c.display(t("sl920.sl194"), at: 1640, color: 4)
                    continue
                }
                sih = SLB.sih(from: r)
                c.display(" ", at: 1640, eraseEOL: true)
                if sih.str("sih-status") == "z" {
                    c.display(t("sl920.sl195"), at: 1601, color: 4, eraseEOL: true)
                    continue
                }
                break
            }
            c.display(" ", at: 1601, eraseEOL: true)
            wsDate = SLB.convBin(s, sih.int("sih-date")).wsDate
            readDetails()
            // date-input
            while true {
                c.display(wsDate, at: 550, color: 3)
                wsDate = Cobol.x(try acc(550, 10, wsDate, color: 3), 10)
                if crt == SLB920.esc || wsDate == Cobol.x("", 10) { z = 1; return }
                let v = SLB.validateDate(s, wsDate)
                if v.bin == 0 { wsDate = v.uDate; continue }
                sih.setInt("sih-date", v.bin)
                break
            }
            // customer-input
            while true {
                c.display(sih.str("sih-customer"), at: 653, color: 3)
                sih["sih-customer"] = try acc(653, 7, sih.str("sih-customer"), color: 3).uppercased()
                if crt == SLB920.esc || sih.str("sih-customer") == Cobol.x("", 7) { escapeCode = "Q"; return }
                showDelivery = crt == SLB920.f8 ? "Y" : "N"
                guard let r = salesFile.read(key: sih.raw("sih-customer")) else {
                    sales.setRaw("sales-key", sih.raw("sih-customer"))
                    continue
                }
                sales = r
                break
            }
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
            c.display(sih.str("sih-ref"), at: 669, color: 3)
            sih["sih-ref"] = try acc(669, 10, sih.str("sih-ref"), color: 3)
            c.display(sih.str("sih-order"), at: 769, color: 3)
            sih["sih-order"] = try acc(769, 10, sih.str("sih-order"), color: 3)
            // type-input
            while true {
                c.display(String(sih.int("sih-type")), at: 1007, color: 3)
                let type = try accNum(1007, 1, sih.int("sih-type"), color: 3)
                sih.setInt("sih-type", type)
                if type == 0 { return }
                if type > 4 { continue }
                if type == 3 {
                    try crNote()
                    if escapeCode == "Q" { continue }
                }
                break
            }
            z = 0
            if sih.int("sih-type") > 2 { return }
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
            z = Int(try accNum(2280, 2, 0, color: 3))
            if crt == SLB920.esc { z = 1; crt = 1 }
        }

        // MARK: cr-note

        func crNote() throws {
            let ownNos = s.sys.str("sl-own-nos") == "Y"
            section: while true {
                for p in [1001, 1101, 1201, 1301, 1401] { c.display(" ", at: p, eraseEOL: true) }
                mainInput: while true {
                    c.display(t("sl920.inv_to_credit"), at: 1001, color: 2)
                    if !ownNos { c.display("] ", at: 1030, color: 2) }
                    let cr = abs(sih.int("sih-cr")) % Cobol.pow10(8)
                    c.display(Cobol.z(cr, 8), at: 1022, color: 3)
                    sih.setInt("sih-cr", try accNum(1022, 8, cr, color: 3))
                    if sih.int("sih-cr") == 0 { wsNamed = "Z"; break section }
                    wsNamed = " "
                    if sih.int("sih-cr") == 99999999 { escapeCode = "Q"; return }
                    escapeCode = " "
                    var letter = " "
                    if ownNos { letter = try acc(1030, 1, " ", color: 3) }
                    guard let r = inv.read(key: invKey(sih.int("sih-cr"), letter, 0)) else {
                        c.display(t("sl920.sl193"), at: 1132, color: 4)
                        // check-inv-no-ok
                        while true {
                            c.display(t("sl920.use_inv_no"), at: 1201, color: 2)
                            c.display(t("sl920.use_inv_no2"), at: 1301, color: 2)
                            c.display(t("sl920.use_inv_no3"), at: 1401, color: 2)
                            wsReply = try acc(1239, 1, "N", color: 6).uppercased()
                            if wsReply == "Y" { break section }
                            if wsReply == "N" { continue section }
                        }
                    }
                    c.display(" ", at: 1101, eraseEOL: true)
                    if r.int("invoice-type") != 2 {
                        c.display(t("sl910.sl184"), at: 1101, color: 4)
                        continue mainInput
                    }
                    if r.str("invoice-customer") != sales.str("sales-key") {
                        c.display(t("sl920.sl196"), at: 1101, color: 4)
                        continue mainInput
                    }
                    break section
                }
            }
            // no-inv-restart
            for p in [1101, 1201, 1301, 1401] { c.display(" ", at: p, eraseEOL: true) }
        }
    }
}
