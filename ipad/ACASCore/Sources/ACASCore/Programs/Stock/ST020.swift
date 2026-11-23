import Foundation

/// stock/st020.cbl: Stock Movements (入庫・出庫・バーコード入庫・発注入力・期間末監査帳票)
enum ST020 {
    static let progName = "ST020 (3.01.29)"

    static func run(_ s: Session) throws { try Run(s).main() }

    /// Stock-Audit-Record (fdaudit.cob、104 バイト、順編成)
    struct Audit {
        var type = 0
        var invoicePO: Int64 = 0
        var crForInvoice: Int64 = 0
        var stockKey = Cobol.x("", 13)
        var desc = Cobol.x("", 32)
        var processDate = Cobol.x("", 10)
        var reverse = 0
        var qty: Int64 = 0          // s9(6)
        var unitCost: Int64 = 0     // s9(6)v9999
        var valueChange: Int64 = 0  // s9(8)v99
        var auditNo: Int64 = 0

        /// 符号付き外部 10 進 (負は末尾桁に 0x40 を重ねる)
        static func signed(_ v: Int64, _ digits: Int) -> [UInt8] {
            var b = Array(Cobol.z(abs(v) % Cobol.pow10(digits), digits).utf8)
            if v < 0 { b[digits - 1] |= 0x40 }
            return b
        }
        static func unsignedValue(_ b: ArraySlice<UInt8>) -> Int64 {
            b.reduce(Int64(0)) { $0 * 10 + Int64($1 & 0x0f) }
        }
        static func signedValue(_ b: ArraySlice<UInt8>) -> Int64 {
            let v = unsignedValue(b)
            return (b.last ?? 0) & 0x40 != 0 ? -v : v
        }

        var bytes: [UInt8] {
            var b = Array(String(type % 10).utf8)
            b += Array(Cobol.z(invoicePO % 100_000_000, 8).utf8) + Array(Cobol.z(crForInvoice % 100_000_000, 8).utf8)
            b += SJIS.encode(stockKey, size: 13) + SJIS.encode(desc, size: 32) + SJIS.encode(processDate, size: 10)
            b += Array(String(reverse % 10).utf8)
            b += Audit.signed(qty, 6) + Audit.signed(unitCost, 10) + Audit.signed(valueChange, 10)
            b += Array(Cobol.z(auditNo % 100_000, 5).utf8)
            return b
        }

        init() {}
        init(bytes b: [UInt8]) {
            type = Int(b[0] & 0x0f)
            invoicePO = Audit.unsignedValue(b[1..<9]); crForInvoice = Audit.unsignedValue(b[9..<17])
            stockKey = SJIS.decode(b[17..<30]); desc = SJIS.decode(b[30..<62]); processDate = SJIS.decode(b[62..<72])
            reverse = Int(b[72] & 0x0f)
            qty = Audit.signedValue(b[73..<79]); unitCost = Audit.signedValue(b[79..<89]); valueChange = Audit.signedValue(b[89..<99])
            auditNo = Audit.unsignedValue(b[99..<104])
        }
        static let size = 104
    }

    private final class Run {
        let s: Session
        let c: Console
        let f: IndexedFile
        var rec = ST.blankRecord()
        var audit = Audit()
        var printer: ST.Printer?
        var menuReply = 0
        var procMth = 0
        var procDate = ""
        var lineCnt = 99, pageNos = 0
        var i = 0
        var unit6 = "000000", sign6 = " "
        var qty: Int64 = 0, newQty: Int64 = 0
        var price: Int64 = 0, value: Int64 = 0, oldValue: Int64 = 0, newValue: Int64 = 0, newCost: Int64 = 0
        var addTotal: Int64 = 0, dedTotal: Int64 = 0
        var amtOk6: Int64 = 0
        var orderDate = Cobol.x("", 10), orderDue = Cobol.x("", 10)
        // 帳票見出し (Line-1 / Line-2 / Line-3b の可変部)
        var l1Title: String
        var l2Batch = ""
        var l3Proc: String, l3Price: String, l3Stock: String, l3Dates: String
        // Line-4 (明細行) の各欄。EOM 帳票では前行の値が残る欄がある
        var l4ProcDate = "", l4StockNumber = "", l4Desc = "", l4Qty = "", l4Cost = "", l4NewValue = "", l4Source = ""

        init(_ s: Session) {
            self.s = s; c = s.console; f = ST.stockFile(s)
            l1Title = s.l10n.raw("report.st020.title_addition")
            l3Proc = s.l10n.raw("report.st020.proc_date")
            l3Price = s.l10n.raw("report.st020.price")
            l3Stock = s.l10n.raw("report.st020.stock_value")
            l3Dates = s.l10n.raw("report.st020.dates_status")
        }

        var pageLines: Int { Int(s.sys.int("page-lines")) }
        var auditUsed: Bool { s.sys.int("stk-audit-used") == 1 }
        var averaging: Bool { s.sys.int("stk-averaging") == 1 }
        func err(_ key: String, col: Int = 1, color: UInt8 = 4) { c.display(s.t(key), at: 23, col, color: color, highlight: true) }
        func clearLine23() { c.display(" ", at: 23, 1, eraseEOL: true) }
        func spaces4() {
            l4ProcDate = ""; l4StockNumber = ""; l4Desc = ""; l4Qty = ""; l4Cost = ""; l4NewValue = ""; l4Source = ""
        }
        var line4: String {
            Cobol.x(l4ProcDate, 11) + Cobol.x(l4StockNumber, 14) + Cobol.x(l4Desc, 32) + Cobol.x(l4Qty, 8) + Cobol.x(l4Cost, 11)
                + Cobol.x(l4NewValue, 13) + "   " + Cobol.x(l4Source, 39)
        }

        // MARK: aa000-Core

        func main() throws {
            if ST.fileStatus(s, 11) != 1 {
                err("st020.st219")
                try ST.maps99(s, 45)
                return
            }
            if f.open() != "00" {
                err("st020.st201")
                c.display(f.status, at: 23, 28, color: 2, highlight: true)
                try ST.maps99(s, 45)
                return
            }
            menuReply = 0
            procDate = ST.convDate(s)
            while true {
                // aa010-Display-Headings
                displayHeadings()
                // aa020-DH-End: 表示形式に変換済みの日付の 4-5 桁目を月として扱う (レガシーと同じ)
                let wsDate = Array(Cobol.x(ST.convDate(s), 10))
                let mth = String(wsDate[3..<5])
                if let m = Int(mth), mth.allSatisfy({ $0.isASCII && $0.isNumber }), (1...12).contains(m) {
                    procMth = m
                } else {
                    err("st020.st213")
                    c.display(mth, at: 23, 25, color: 2, highlight: true)
                    c.display(String(wsDate), at: 23, 28, color: 2, highlight: true)
                    try ST.maps99(s, 45)
                    return
                }
                // aa100-Main-Menu
                c.display(s.t("st020.select"), at: 401, color: 2)
                c.display(s.t("st020.menu_1"), at: 604, color: 2)
                c.display(s.t("st020.menu_2"), at: 704, color: 2)
                c.display(s.t("st020.menu_3"), at: 804, color: 2)
                c.display(s.t("st020.menu_4"), at: 904, color: 2)
                if auditUsed {
                    let cur = s.sys.str("stk-period-cur")
                    c.display(s.t(cur == "Q" ? "st020.menu_5_quarter" : (cur == "W" ? "st020.menu_5_week" : "st020.menu_5_month")), at: 1104, color: 2)
                }
                c.display(s.t("st020.menu_9"), at: 1404, color: 2)
                // aa110-Accept-Loop
                while true {
                    menuReply = Int(Cobol.numval(try c.accept(at: 443, size: 1, kind: .numeric, initial: String(menuReply), options: [.auto, .update], color: 6)).0)
                    if menuReply == 9 {
                        f.close()
                        return
                    }
                    if menuReply == 0 || menuReply > 5 { continue }
                    break
                }
                let auditPath = ST.auditPath(s)
                if ST.fileStatus(s, 10) != 1 && auditUsed {
                    s.store.writeRaw(auditPath, [])
                    ST.setFileStatus(s, 10, 1)
                }
                var fsReply = "00"
                if auditUsed {
                    // select optional: 無いファイルの OPEN は 05
                    if !s.store.exists(auditPath) {
                        fsReply = "05"
                        if menuReply < 5 { s.store.writeRaw(auditPath, []) }
                    }
                }
                if fsReply != "00" {
                    err("st020.st202")
                    c.display(fsReply, at: 23, 28, color: 2, highlight: true)
                    try ST.maps99(s, 45)
                    f.close()
                    return
                }
                switch menuReply {
                case 1:
                    l1Title = s.l10n.raw("report.st020.title_addition")
                    l3Dates = s.l10n.raw("report.st020.dates_status")
                    l3Proc = s.l10n.raw("report.st020.proc_date")
                    l3Price = s.l10n.raw("report.st020.price")
                    l3Stock = s.l10n.raw("report.st020.stock_value")
                    l2Batch = ""
                    try withPrint { try self.manualAdditions() }
                case 2:
                    l1Title = s.l10n.raw("report.st020.title_deduction")
                    l3Dates = ""; l3Price = ""; l2Batch = ""
                    l3Proc = s.l10n.raw("report.st020.proc_date")
                    l3Stock = s.l10n.raw("report.st020.stock_value")
                    try withPrint { try self.manualDeductions() }
                case 3:
                    l2Batch = ""
                    try withPrint { try self.barcodeAdditions() }
                case 4:
                    l1Title = s.l10n.raw("report.st020.title_orders")
                    l3Dates = s.l10n.raw("report.st020.dates")
                    l3Price = s.l10n.raw("report.st020.b_qty")
                    l3Stock = ""; l3Proc = ""; l2Batch = ""
                    spaces4()
                    try withPrint { try self.processOrders() }
                default:
                    if auditUsed {
                        l2Batch = s.l10n.raw("report.st020.batch") + Pic.edit("zz9", value: s.sys.int("stk-audit-no"), scale: 0)
                        try endOfMonth()
                    }
                }
                menuReply = 0
            }
        }

        /// open output Print-File 〜 close 〜 (頁があれば) 印刷
        func withPrint(_ body: () throws -> Void) throws {
            let p = ST.Printer(s)
            printer = p
            defer { p.close(); if pageNos != 0 { p.spool() } }
            try body()
        }

        func displayHeadings() {
            pageNos = 0
            lineCnt = 99
            let (key, at): (String, Int)
            switch menuReply {
            case 1: (key, at) = ("st020.title_add", 130)
            case 2: (key, at) = ("st020.title_del", 130)
            case 3: (key, at) = ("st020.title_barcode", 123)
            case 4: (key, at) = ("st020.title_eom", 126)
            case 5: (key, at) = ("st020.title_order", 132)
            default: (key, at) = ("st020.title_menu", 131)
            }
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            c.display(s.t(key), at: at, color: 2)
            c.display(ST.convDate(s), at: 171, color: 2)
        }

        // MARK: 共通部品

        /// 入力欄の枠を 5 行目から 22 行目まで描く
        func grid(_ cols: [(Int, String)]) {
            for lin in 5...22 {
                for (n, (col, text)) in cols.enumerated() {
                    c.display(text, at: lin, col, color: 2, eraseEOL: n == 0)
                }
            }
        }

        /// 品目番号の入力と読み込み。nil = 終了、false = 同じ行でやり直し
        func acceptStock(abrevAllowed: Bool) throws -> Bool? {
            let key = Cobol.x(try c.accept(at: i, 2, size: 13, initial: Cobol.x("", 13), options: [.update], color: 3), 13)
            if key == Cobol.x("", 13) || c.crtStatus == 2005 { return nil }
            let k = key.uppercased()
            c.display(k, at: i, 2, color: 3)
            let a = Array(k)
            if abrevAllowed && String(a[7..<13]) == "      " {
                guard let r = ST.read(f, abrev: String(a[0..<7])) else {
                    rec["stock-abrev-key"] = String(a[0..<7])
                    err("st020.st203")
                    return false
                }
                rec = r
            } else {
                guard let r = f.read(key: ST.key(k)) else {
                    rec["stock-key"] = k
                    err("st020.st214")
                    return false
                }
                rec = r
            }
            return true
        }

        func desc20() -> String { String(Array(Cobol.x(rec.str("stock-desc"), 32))[0..<20]) }

        /// ws-qty-screen-display6 (数量 6 桁 + 符号 1 桁) の入力
        func acceptQty() throws {
            let a = Array(Cobol.x(try c.accept(at: i, 39, size: 7, initial: unit6 + sign6, options: [.update], color: 3), 7))
            unit6 = String(a[0..<6]); sign6 = String(a[6])
        }
        var unit6Value: Int64 { ST.digits(unit6) }
        var isBackKey: Bool { c.crtStatus == 2005 || c.crtStatus == 2003 || c.crtStatus == 2001 }

        /// 「整数部.小数部」を小数点込みの集団項目として入力する (zz200-accept-money)
        func acceptMoney(_ col: Int, _ v: Int64, int: Int) throws -> Int64 {
            let text = Cobol.z(v / 100, int) + "." + Cobol.z(v % 100, 2)
            c.display(text, at: i, col, color: 3)
            let a = Array(Cobol.x(try c.accept(at: i, col, size: int + 3, initial: text, options: [.update], color: 3), int + 3))
            return ST.digits(String(a[0..<int])) * 100 + ST.digits(String(a[(int + 1)...]))
        }

        func writeAudit() throws -> Bool {
            audit.auditNo = s.sys.int("stk-audit-no")
            s.sys.setInt("stk-activity-rep-run", 0)
            audit.processDate = procDate
            s.store.appendRaw(ST.auditPath(s), audit.bytes)
            return true
        }

        func addUnsigned(_ name: String, _ v: Int64) {
            rec.setInt(name, ST.unsignedValue(rec.int(name) + v, digits: 8))
        }

        func rewriteStock() throws -> Bool {
            if ST.rewrite(f, rec) != "00" {
                err("st.st000")
                c.display(f.status, at: 23, 38, color: 2, highlight: true)
                try ST.maps99(s, 45)
                return false
            }
            return true
        }

        func dateText(_ bin: Int64) -> String { bin != 0 ? ST.convertDate(s, bin) : "" }

        // MARK: zz010-Print-Heads

        func printHeads() {
            guard lineCnt > pageLines, let p = printer else { return }
            pageNos = (pageNos + 1) & 0xff
            let line1 = Cobol.x(progName, 16) + Cobol.x("", 39) + Cobol.x(l1Title, 42) + Cobol.x("", 27)
                + Cobol.x(s.l10n.raw("report.st020.page"), 5) + Pic.edit("zz9", value: Int64(pageNos), scale: 0)
            let t = s.time
            var hh = "  ", mm = "  "
            if t.hour != 0 || t.minute != 0 || t.second != 0 { hh = Cobol.z(t.hour, 2); mm = Cobol.z(t.minute, 2) }
            let line2 = Cobol.x(s.sys.str("usera"), 61) + Cobol.x(l2Batch, 55) + Cobol.x(ST.convDate(s), 10) + " " + hh + ":" + mm
            if pageNos != 1 {
                p.afterPage(line1)
                p.after(1, line2)
                p.after(1, "")
            } else {
                p.before(1, line1)
                p.before(1, line2)
            }
            lineCnt = 6
            if menuReply != 5 {
                p.after(1, Cobol.x("", 78) + s.l10n.raw("report.st020.change_in"))
            } else {
                lineCnt -= 1
            }
            p.after(1, Cobol.x(l3Proc, 11) + Cobol.x(s.l10n.raw("report.st020.line_3b"), 57) + Cobol.x(l3Price, 5) + Cobol.x(l3Stock, 19) + Cobol.x(l3Dates, 39))
            p.after(1, "")
        }

        func printLine4() {
            if lineCnt > pageLines { printHeads() }
            printer?.after(1, line4)
            lineCnt = (lineCnt + 1) & 0xff
        }

        // MARK: 入庫の共通処理 (ba030 の価格入力後 〜 ba040 / da030 〜 da040)

        /// 戻り値 false = セクション終了
        func postAddition() throws -> Bool {
            if auditUsed {
                audit.type = 1
                audit.stockKey = rec.str("stock-key")
                audit.desc = rec.str("stock-desc")
                audit.qty = qty
                audit.unitCost = Cobol.truncate(price * 100, digits: 10)
            }
            rec.setInt("stock-last-actual-cost", price)
            let held = rec.int("stock-held"), wip = rec.int("stock-work-in-progress")
            if held != 0 || wip != 0 {
                oldValue = Cobol.truncate(Cobol.rescale((held + wip) * rec.int("stock-cost"), from: 4, to: 2), digits: 10)
            } else {
                oldValue = 0
            }
            value = Cobol.truncate(qty * price, digits: 10)
            if auditUsed { audit.valueChange = value }
            newValue = value + oldValue
            if abs(newValue) >= Cobol.pow10(10) {
                err("st020.st212")
                newValue = 9_999_999_999
            }
            newQty = Cobol.truncate(qty + held, digits: 6)
            c.display(Pic.edit("z(6)", value: abs(newQty), scale: 0), at: i, 59, color: 3)
            if !averaging {
                let v = try acceptMoney(68, abs(newValue), int: 8)
                if v != 0 { newValue = v }
            }
            // divide ws-New-Qty into ws-New-Value giving ws-New-Cost rounded (0 除算は結果を変えない)
            if newQty != 0 {
                let num = newValue * 100
                var q = abs(num) / abs(newQty)
                if (abs(num) % abs(newQty)) * 2 >= abs(newQty) { q += 1 }
                if (num < 0) != (newQty < 0) { q = -q }
                newCost = Cobol.truncate(q, digits: 10)
            }
            if averaging {
                c.display(s.t("st020.value_box"), at: i, 67, color: 2)
                let v = abs(newValue)
                c.display(Cobol.z(v / 100, 8) + "." + Cobol.z(v % 100, 2), at: i, 68, color: 3)
            }
            if auditUsed {
                if try !writeAudit() { return false }
            }
            var onOrder = rec.int("stock-on-order")
            if qty > 0 { onOrder -= qty } else { onOrder += qty }
            var back = rec.int("stock-back-ordered")
            if onOrder != 0 {
                back = Cobol.truncate(back + onOrder, digits: 6)
                onOrder = 0
            }
            if back < 0 { back = 0 }
            rec.setInt("stock-on-order", onOrder)
            rec.setInt("stock-back-ordered", back)
            addUnsigned("stock-adds", qty)
            addUnsigned("stock-td-adds-\(procMth)", qty)
            if rec.int("stock-adds") < 1 { err("st020.st215") }
            if rec.int("stock-td-adds-\(procMth)") < 1 { err("st020.st216", col: 41) }
            // ba040-Setup-Print-Transaction
            spaces4()
            l4ProcDate = procDate
            l4StockNumber = rec.str("stock-key")
            l4Desc = rec.str("stock-desc")
            l4Qty = Pic.edit("z(6)9-", value: qty, scale: 0)
            l4Cost = Pic.edit("z(6)9.99-", value: price, scale: 2)
            l4NewValue = Pic.edit("z(5),zz9.99-", value: value, scale: 2)
            var source = Cobol.x(dateText(rec.int("stock-order-date")), 13) + Cobol.x(dateText(rec.int("stock-order-due")), 13)
            let today = Maps04.toBinary(s.toDay)
            if today == 0 {
                err("st020.st005")
                c.display(Cobol.x(s.toDay, 10), at: 23, 20, color: 2, highlight: true)
            }
            var late = Cobol.x("", 3), lit = ""
            if rec.int("stock-order-due") != 0 {
                let days = (Int64(today) - rec.int("stock-order-due")) % 1000
                if days > 0 {
                    late = Pic.edit("zz9", value: days, scale: 0); lit = s.l10n.raw("report.st020.days_late")
                } else if days < 0 {
                    late = Pic.edit("zz9", value: -days, scale: 0); lit = s.l10n.raw("report.st020.days_early")
                }
            }
            source += late + Cobol.x(lit, 10)
            l4Source = source
            if rec.int("stock-on-order") == 0 && rec.int("stock-back-ordered") == 0 {
                rec.setInt("stock-order-date", 0); rec.setInt("stock-order-due", 0)
            }
            printLine4()
            rec.setInt("stock-value", ST.unsignedValue(newValue, digits: 11))
            rec.setInt("stock-held", newQty)
            rec.setInt("stock-cost", ST.unsignedValue(newCost, digits: 11))
            return try rewriteStock()
        }

        // MARK: ba000-Process-Manual-Additions

        func manualAdditions() throws {
            displayHeadings()
            c.display(s.t("st020.add_heading"), at: 301, color: 2)
            grid([(1, "[             ]"), (16, "{                    }"), (38, "[       ]"), (47, "[         ]"), (58, "{      }"), (67, "[           ]")])
            i = 4
            while true {
                // ba010-Accept-Data1
                i += 1
                if i > 22 { try manualAdditions() }   // 画面末で同じセクションを再帰実行する (レガシーと同じ)
                audit = Audit()
                guard let ok = try acceptStock(abrevAllowed: true) else { return }
                if !ok { i -= 1; continue }
                c.display(desc20(), at: i, 17, color: 3)
                if rec.str("stock-services-flag") == "Y" {
                    err("st020.st217", color: 2)
                    c.display(Cobol.x("", 20), at: i, 17)
                    i -= 1
                    continue
                }
                clearLine23()
                var again = false
                qtyLoop: while true {
                    // ba020-Accept-Qty
                    unit6 = Cobol.z(abs(rec.int("stock-on-order")) % 1_000_000, 6); sign6 = " "
                    try acceptQty()
                    if unit6Value == 0 || isBackKey {
                        i -= 1
                        c.display(Cobol.x("", 20), at: i + 1, 17)
                        again = true
                        break
                    }
                    if unit6Value > 999_998 { err("st020.st204"); continue }
                    if unit6Value + rec.int("stock-held") > 999_999 { err("st020.st205"); continue }
                    if sign6 != "-" && sign6 != " " { err("st020.st207"); continue }
                    clearLine23()
                    qty = unit6Value
                    if sign6 == "-" {
                        audit.reverse = 1
                        qty = -qty
                    }
                    if qty + rec.int("stock-held") < 0 { err("st020.st206"); continue }
                    if qty + rec.int("stock-held") == 0 {
                        err("st020.st208")
                        try ST.maps99(s, 15)
                    }
                    // ba030-Accept-Price
                    amtOk6 = try acceptMoney(48, 0, int: 6)
                    if amtOk6 == 0 { continue qtyLoop }
                    price = amtOk6
                    break
                }
                if again { continue }
                if try !postAddition() { return }
            }
        }

        // MARK: ca000-Process-Manual-Deductions

        func manualDeductions() throws {
            displayHeadings()
            c.display(s.t("st020.del_heading"), at: 301, color: 2)
            grid([(1, "[             ]"), (16, "{                    }"), (38, "[       ]"), (47, "{      }")])
            i = 4
            item: while true {
                // ca010-Accept-Data1
                i += 1
                if i > 22 { try manualDeductions() }
                audit = Audit()
                guard let ok = try acceptStock(abrevAllowed: true) else { return }
                if !ok { i -= 1; continue }
                c.display(desc20(), at: i, 17, color: 3)
                let z6 = Cobol.truncate(rec.int("stock-work-in-progress") + rec.int("stock-held"), digits: 6)
                c.display(Pic.edit("z(6)", value: abs(z6), scale: 0), at: i, 48, color: 3)
                clearLine23()
                while true {
                    // ca020-Accept-Qty
                    unit6 = "000000"; sign6 = " "
                    try acceptQty()
                    if unit6Value == 0 || isBackKey {
                        i -= 1
                        c.display(Cobol.x("", 20), at: i + 1, 17)
                        continue item
                    }
                    if unit6Value > 999_998 { err("st020.st204"); continue }
                    if sign6 != "-" && sign6 != " " { err("st020.st207"); continue }
                    clearLine23()
                    qty = unit6Value
                    if sign6 == "-" {
                        audit.reverse = 1
                        qty = -qty
                        if unit6Value + rec.int("stock-held") > 999_999 { err("st020.st205"); continue }
                    }
                    if rec.int("stock-held") - qty < 0 { err("st020.st206"); continue }
                    clearLine23()
                    break
                }
                if rec.str("stock-services-flag") == "Y" {
                    err("st020.st217", color: 2)
                    i -= 1
                    continue
                }
                if rec.int("stock-held") - qty == 0 {
                    err("st020.st208")
                    try ST.maps99(s, 15)
                    c.display(" ", at: 23, 1, eraseEOS: true)
                }
                newQty = Cobol.truncate(rec.int("stock-held") - qty, digits: 6)
                c.display(Pic.edit("z(6)", value: abs(newQty), scale: 0), at: i, 48, color: 3)
                audit.type = 2
                audit.stockKey = rec.str("stock-key")
                audit.desc = rec.str("stock-desc")
                audit.qty = qty
                audit.unitCost = Cobol.truncate(rec.int("stock-cost"), digits: 10)
                audit.valueChange = Cobol.truncate(Cobol.rescale(qty * rec.int("stock-cost") * -1, from: 4, to: 2), digits: 10)
                audit.auditNo = s.sys.int("stk-audit-no")
                if auditUsed {
                    if try !writeAudit() { return }
                }
                addUnsigned("stock-deducts", qty)
                addUnsigned("stock-td-deds-\(procMth)", qty)
                if rec.int("stock-deducts") < 1 { err("st020.st210") }
                if rec.int("stock-td-deds-\(procMth)") < 1 { err("st020.st211", col: 41) }
                // ca040-Setup-Print-Transaction
                spaces4()
                l4ProcDate = procDate
                l4StockNumber = rec.str("stock-key")
                l4Desc = rec.str("stock-desc")
                l4Qty = Pic.edit("z(6)9-", value: qty, scale: 0)
                l4NewValue = Pic.edit("z(5),zz9.99-", value: audit.valueChange, scale: 2)
                printLine4()
                rec.setInt("stock-held", Cobol.truncate(rec.int("stock-held") - qty, digits: 6))
                let v = Cobol.rescale((rec.int("stock-held") + rec.int("stock-work-in-progress")) * rec.int("stock-cost"), from: 4, to: 2)
                if abs(v) >= Cobol.pow10(11) {
                    err("st020.st212")
                    rec.setInt("stock-value", 9_999_999_999)
                } else {
                    rec.setInt("stock-value", abs(v))
                }
                if try !rewriteStock() { return }
            }
        }

        // MARK: da000-Process-Barcode-Additions

        func barcodeAdditions() throws {
            displayHeadings()
            c.display(s.t("st020.add_heading"), at: 301, color: 2)
            grid([(1, "[             ]"), (16, "{                    }"), (38, "[       ]"), (47, "[         ]"), (58, "{      }"), (67, "[           ]")])
            i = 4
            while true {
                // da010-Accept-Data1
                i += 1
                if i > 22 { try barcodeAdditions() }
                audit = Audit()
                guard let ok = try acceptStock(abrevAllowed: false) else { return }
                if !ok {
                    c.display(s.t("st020.missing_record"), at: i, 2, color: 3, highlight: true)
                    continue
                }
                c.display(desc20(), at: i, 17, color: 3)
                if rec.str("stock-services-flag") == "Y" {
                    err("st020.st217", color: 2)
                    c.display(Cobol.x("", 20), at: i, 17)
                    continue
                }
                clearLine23()
                qty = 1; unit6 = "000001"
                // 最終仕入単価、無ければ原価 (9(6)v99 へ切り捨て)
                if rec.int("stock-last-actual-cost") != 0 {
                    amtOk6 = Cobol.truncate(rec.int("stock-last-actual-cost"), digits: 8, signed: false)
                } else {
                    amtOk6 = Cobol.truncate(Cobol.rescale(rec.int("stock-cost"), from: 4, to: 2), digits: 8, signed: false)
                }
                price = amtOk6
                c.display(unit6 + sign6, at: i, 39, color: 3)
                // da020-Accept-Qty は到達しない (da030 へ直接進む)
                // da030-Accept-Price
                c.display(Cobol.z(amtOk6 / 100, 6) + "." + Cobol.z(amtOk6 % 100, 2), at: i, 48, color: 3)
                if try !postAddition() { return }
            }
        }

        // MARK: ea000-Process-End-of-Month

        func endOfMonth() throws {
            c.display(s.t("st020.printing"), at: 1337, eraseEOS: true)
            var p = ST.Printer(s)
            printer = p
            printAdditions()
            p.close()
            if pageNos != 0 { p.spool() }
            p = ST.Printer(s)
            printer = p
            printDeductions()
            p.close()
            if pageNos != 0 { p.spool() }
            s.sys.setInt("stk-activity-rep-run", 1)
            // ea010-Accept-Delete
            while true {
                c.display(s.t("st020.delete_audit"), at: 401, color: 2)
                c.display(s.t("st020.delete_warn_1"), at: 601, color: 4, highlight: true)
                c.display(s.t("st020.delete_warn_2"), at: 802, color: 4, highlight: true)
                let reply = try c.accept(at: 435, size: 1, initial: "N", options: [.update], color: 3).uppercased()
                if reply == "N" { return }
                if reply != "Y" { continue }
                s.store.writeRaw(ST.auditPath(s), [])
                let no = s.sys.int("stk-audit-no") + 1
                s.sys.setInt("stk-audit-no", no > 255 ? 1 : no)
                return
            }
        }

        func auditRecords() -> [Audit] {
            let d = s.store.readRaw(ST.auditPath(s)) ?? []
            return stride(from: 0, to: d.count - Audit.size + 1, by: Audit.size).map { Audit(bytes: Array(d[$0..<($0 + Audit.size)])) }
        }

        func printTotals() {
            guard let p = printer else { return }
            if lineCnt > pageLines - 7 { printHeads() }
            func total(_ key: String, _ v: Int64) -> String {
                Cobol.x("", 55) + s.l10n.raw(key) + Pic.edit("zzz,zzz,zz9.99", value: abs(v) % Cobol.pow10(11), scale: 2)
            }
            p.after(3, total("report.st020.total_additions", addTotal))
            p.after(1, total("report.st020.total_deductions", dedTotal))
            p.after(1, Cobol.x("", 74) + "-------------- ")
            p.after(1, total("report.st020.total_changes", addTotal + dedTotal))
            p.after(1, Cobol.x("", 74) + "============== ")
        }

        // ea100-Print-Additions
        func printAdditions() {
            pageNos = 0; addTotal = 0; dedTotal = 0
            lineCnt = 99
            l1Title = s.l10n.raw("report.st020.title_audit_add")
            l3Proc = s.l10n.raw("report.st020.proc_date")
            l3Price = s.l10n.raw("report.st020.price")
            l3Stock = s.l10n.raw("report.st020.stock_value")
            l3Dates = s.l10n.raw("report.st020.source_po")
            spaces4()
            for a in auditRecords() {
                if a.type == 2 || a.type == 3 || a.type == 5 { dedTotal = Cobol.truncate(dedTotal + a.valueChange, digits: 11) }
                if a.type != 1 && a.type != 4 { continue }
                l4StockNumber = a.stockKey
                l4Desc = a.desc
                l4Qty = Pic.edit("z(6)9-", value: a.qty, scale: 0)
                l4Cost = Pic.edit("z(6)9.99-", value: Cobol.rescale(a.unitCost, from: 4, to: 2), scale: 2)
                l4NewValue = Pic.edit("z(5),zz9.99-", value: a.valueChange, scale: 2)
                l4ProcDate = a.processDate
                addTotal = Cobol.truncate(addTotal + a.valueChange, digits: 11)
                l4Source = a.type == 4 ? s.l10n.raw("report.st020.purchasing") + Cobol.z(a.invoicePO, 8) : ""
                printLine4()
            }
            printTotals()
        }

        // ea200-Print-Deductions
        func printDeductions() {
            pageNos = 0
            lineCnt = 99
            l1Title = s.l10n.raw("report.st020.title_audit_del")
            l3Proc = s.l10n.raw("report.st020.proc_date")
            l3Stock = s.l10n.raw("report.st020.stock_value")
            l3Dates = s.l10n.raw("report.st020.source_inv")
            spaces4()
            for a in auditRecords() {
                if a.type != 2 && a.type != 3 && a.type != 5 { continue }
                l4StockNumber = a.stockKey
                l4Desc = a.desc
                l4Qty = Pic.edit("z(6)9-", value: a.qty, scale: 0)
                l4NewValue = Pic.edit("z(5),zz9.99-", value: a.valueChange, scale: 2)
                l4ProcDate = a.processDate
                l4Source = ""
                if a.type == 3 { l4Source = s.l10n.raw("report.st020.invoicing") + Cobol.z(a.invoicePO, 8) }
                if a.type == 5 {
                    l4Source = s.l10n.raw("report.st020.credit_note") + Cobol.z(a.invoicePO, 8) + s.l10n.raw("report.st020.for") + Cobol.z(a.crForInvoice, 8)
                }
                printLine4()
            }
            printTotals()
        }

        // MARK: fa000-Process-Orders

        func processOrders() throws {
            displayHeadings()
            c.display(s.t("st020.order_heading"), at: 301, color: 2)
            grid([(1, "[             ]"), (16, "{                    }"), (38, "[      ]"), (46, "[          ]"), (58, "[          ]"), (70, "[      ]")])
            i = 4
            item: while true {
                // fa010-Accept-Data1
                i += 1
                if i > 22 { try processOrders() }
                guard let ok = try acceptStock(abrevAllowed: true) else { return }
                if !ok { i -= 1; continue }
                c.display(desc20(), at: i, 17, color: 3)
                if rec.str("stock-services-flag") == "Y" {
                    err("st020.st217", color: 2)
                    c.display(Cobol.x("", 20), at: i, 17)
                    i -= 1
                    continue
                }
                clearLine23()
                sign6 = " "
                while true {
                    // fa020-Accept-Qty
                    unit6 = Cobol.z(abs(rec.int("stock-on-order")) % 1_000_000, 6)
                    unit6 = Cobol.z(Cobol.numval(try c.accept(at: i, 39, size: 6, kind: .numeric, initial: unit6, options: [.update], color: 3)).0, 6)
                    if isBackKey {
                        i -= 1
                        c.display(Cobol.x("", 20), at: i + 1, 17)
                        continue item
                    }
                    if unit6Value > 999_998 { err("st020.st204"); continue }
                    break
                }
                clearLine23()
                rec.setInt("stock-on-order", unit6Value)
                orderDate = Cobol.x(dateText(rec.int("stock-order-date")), 10)
                orderDue = Cobol.x(dateText(rec.int("stock-order-due")), 10)
                while true {
                    // fa030-Accept-Date-Ord
                    orderDate = Cobol.x(try c.accept(at: i, 47, size: 10, initial: orderDate, options: [.update], color: 3), 10)
                    if orderDate == Cobol.x("", 10) { rec.setInt("stock-order-date", 0); break }
                    let bin = ST.validateDate(s, orderDate)
                    if bin != 0 { rec.setInt("stock-order-date", Int64(bin)); break }
                    err("st020.st005")
                    err("st020.st250", col: 19)
                }
                while true {
                    // fa040-Accept-Date-Due
                    orderDue = Cobol.x(try c.accept(at: i, 59, size: 10, initial: orderDue, options: [.update], color: 3), 10)
                    if orderDue == Cobol.x("", 10) { rec.setInt("stock-order-due", 0); break }
                    let bin = ST.validateDate(s, orderDue)
                    if bin != 0 { rec.setInt("stock-order-due", Int64(bin)); break }
                    err("st020.st005")
                    err("st020.st251", col: 19)
                }
                clearLine23()
                while true {
                    // fa050-Accept-B-ord
                    unit6 = Cobol.z(abs(rec.int("stock-back-ordered")) % 1_000_000, 6)
                    unit6 = Cobol.z(Cobol.numval(try c.accept(at: i, 71, size: 6, kind: .numeric, initial: unit6, options: [.update], color: 3)).0, 6)
                    if unit6Value > 999_998 { err("st020.st204"); continue }
                    break
                }
                clearLine23()
                rec.setInt("stock-back-ordered", unit6Value)
                // fa060-Setup-Print-Transaction
                spaces4()
                l4StockNumber = rec.str("stock-key")
                l4Desc = rec.str("stock-desc")
                l4Qty = Pic.edit("z(6)9-", value: rec.int("stock-on-order"), scale: 0)
                l4Cost = "  " + Pic.edit("z(5)9", value: rec.int("stock-back-ordered"), scale: 0) + "   "
                l4Source = Cobol.x(dateText(rec.int("stock-order-date")), 13) + Cobol.x(dateText(rec.int("stock-order-due")), 13)
                printLine4()
                if try !rewriteStock() { return }
            }
        }
    }
}
