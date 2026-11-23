import Foundation

/// stock/st010.cbl: Stock File Set-Up & Maintenance (在庫品目マスタの登録・変更・削除・番号変更・照会・印刷)
enum ST010 {
    static let progName = "ST010 (3.01.37)"

    /// EXIT PROGRAM (セクションの途中からプログラムを抜ける)
    private struct ExitProgram: Error {}

    private final class State {
        var rec = ST.blankRecord()
        var menuReply = 0
        var escapeCode = " "
        var orderDate = Cobol.x("", 10)   // ws-Stock-Order-Date
        var orderDue = Cobol.x("", 10)    // ws-Stock-Order-Due
        var customerCode = Cobol.x("", 7)
        var wsStockKey = Cobol.x("", 13)
        /// Analysis-File が OPEN できたか (失敗時の START は INVALID KEY にならず素通りする)
        var analysisOpen = false
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let st = State()
        do {
            while true {
                // aa010-Menu-Return
                st.menuReply = 0
                displayHeading(s, st)
                // aa020-Menu-Input
                input: while true {
                    if ST.fileStatus(s, 11) != 1 {
                        try setupStock(s, st)
                        break input
                    }
                    c.display(s.t("st010.select"), at: 701, color: 2)
                    c.display(s.t("st010.menu_1"), at: 904, color: 2)
                    c.display(s.t("st010.menu_2"), at: 1104, color: 2)
                    c.display(s.t("st010.menu_3"), at: 1304, color: 2)
                    c.display(s.t("st010.menu_4"), at: 1504, color: 2)
                    c.display(s.t("st010.menu_5"), at: 1704, color: 2)
                    c.display(s.t("st010.menu_6"), at: 1904, color: 2)
                    c.display(s.t("st010.menu_9"), at: 2104, color: 2)
                    st.menuReply = Int(Cobol.numval(try c.accept(at: 743, size: 1, kind: .numeric, options: [.auto], color: 6)).0)
                    if st.menuReply == 9 { return }
                    if st.menuReply < 1 || st.menuReply > 6 { continue }
                    switch st.menuReply {
                    case 1: try setupStock(s, st)
                    case 2: try amendStock(s, st)
                    case 3: try deleteStock(s, st)
                    case 4: try renumberStock(s, st)
                    case 6: try reportStock(s, st)
                    default: try displayStock(s, st)
                    }
                    break input
                }
            }
        } catch is ExitProgram {
            return
        }
    }

    private static func clearErrorLine(_ s: Session) { s.console.display(" ", at: 23, 1, eraseEOL: true) }
    private static func error(_ s: Session, _ key: String, color: UInt8 = 4) {
        s.console.display(s.t(key), at: 23, 1, color: color, highlight: true)
    }

    // MARK: 画面 (SCREEN SECTION)

    private static let display01Literals: [(Int, Int, String)] = [
        (4, 1, "st010.d01_stock_number"), (4, 34, "st010.d01_close"), (4, 41, "st010.d01_fast_key"), (4, 64, "st010.d01_close"),
        (5, 1, "st010.d01_desc"), (5, 39, "st010.d01_close"), (5, 41, "st010.d01_location"), (5, 67, "st010.d01_close"),
        (6, 1, "st010.d01_supplier_1"), (6, 23, "st010.d01_supplier_2"), (6, 39, "st010.d01_close"), (6, 50, "st010.d01_supplier_3"), (6, 64, "st010.d01_close"),
        (7, 1, "st010.d01_stock_qty"), (7, 27, "st010.d01_close"), (7, 41, "st010.d01_qty_ordered"), (7, 67, "st010.d01_close"),
        (8, 1, "st010.d01_reorder_point"), (8, 27, "st010.d01_close"), (8, 41, "st010.d01_back_ordered"), (8, 67, "st010.d01_close"),
        (9, 1, "st010.d01_reorder_qty"), (9, 27, "st010.d01_close"), (9, 41, "st010.d01_sales_orders"), (9, 67, "st010.d01_close"),
        (10, 1, "st010.d01_sa_code"), (10, 23, "st010.d01_close"), (10, 41, "st010.d01_pa_code"), (10, 59, "st010.d01_close"),
        (11, 1, "st010.d01_services"), (11, 22, "st010.d01_services_yn"),
        (12, 1, "st010.d01_date_ordered"), (12, 27, "st010.d01_close"), (12, 41, "st010.d01_date_due"), (12, 67, "st010.d01_close"),
    ]
    private static let escapeBox: [(Int, String)] = [
        (18, "st010.box_line"), (19, "st010.box_escape"), (20, "st010.box_back"),
        (21, "st010.box_save"), (22, "st010.box_quit"), (23, "st010.box_line"),
    ]

    /// Display-01 の入力項目 (using)
    private static func fields01(_ st: State) -> [ScreenField] {
        let r = st.rec
        func n(_ line: Int, _ col: Int, _ name: String) -> ScreenField {
            ScreenField(line: line, col: col, size: 6, kind: .numeric, pic: "9(6)", value: Cobol.z(abs(r.int(name)) % 1_000_000, 6), color: 3)
        }
        func x(_ line: Int, _ col: Int, _ size: Int, _ v: String) -> ScreenField {
            ScreenField(line: line, col: col, size: size, value: v, color: 3)
        }
        let sa = Array(Cobol.x(r.str("stock-sa-code"), 3)), pa = Array(Cobol.x(r.str("stock-pa-code"), 3))
        return [
            x(5, 7, 32, r.str("stock-desc")), x(5, 57, 10, r.str("stock-location")),
            x(6, 16, 7, r.str("stock-supplier-p1")), x(6, 32, 7, r.str("stock-supplier-p2")), x(6, 57, 7, r.str("stock-supplier-p3")),
            n(7, 21, "stock-held"), n(7, 61, "stock-on-order"),
            n(8, 21, "stock-reorder-pnt"), n(8, 61, "stock-back-ordered"),
            n(9, 21, "stock-std-reorder"), n(9, 61, "stock-pre-sales"),
            x(10, 21, 2, String(sa[1...2])), x(10, 57, 2, String(pa[1...2])),
            x(11, 21, 1, r.str("stock-services-flag")),
            x(12, 17, 10, st.orderDate), x(12, 57, 10, st.orderDue),
        ]
    }

    private static func store01(_ st: State, _ f: [ScreenField]) {
        func num(_ i: Int) -> Int64 { Cobol.numval(f[i].value).0 }
        st.rec["stock-desc"] = f[0].value; st.rec["stock-location"] = f[1].value
        st.rec["stock-supplier-p1"] = f[2].value; st.rec["stock-supplier-p2"] = f[3].value; st.rec["stock-supplier-p3"] = f[4].value
        st.rec.setInt("stock-held", num(5)); st.rec.setInt("stock-on-order", num(6))
        st.rec.setInt("stock-reorder-pnt", num(7)); st.rec.setInt("stock-back-ordered", num(8))
        st.rec.setInt("stock-std-reorder", num(9)); st.rec.setInt("stock-pre-sales", num(10))
        setGroup(st, "stock-sa-code", f[11].value); setGroup(st, "stock-pa-code", f[12].value)
        st.rec["stock-services-flag"] = f[13].value
        st.orderDate = Cobol.x(f[14].value, 10); st.orderDue = Cobol.x(f[15].value, 10)
    }

    private static func group(_ st: State, _ name: String) -> String { String(Array(Cobol.x(st.rec.str(name), 3))[1...2]) }
    private static func setGroup(_ st: State, _ name: String, _ g: String) {
        st.rec[name] = String(Array(Cobol.x(st.rec.str(name), 3))[0]) + Cobol.x(g, 2)
    }
    private static func setSystem(_ st: State, _ name: String, _ sys: String) {
        st.rec[name] = sys + group(st, name)
    }

    private static func display01(_ s: Session, _ st: State) {
        let c = s.console
        for (l, col, key) in display01Literals { c.display(s.t(key), at: l, col, color: 2) }
        c.displayFields(fields01(st))
        for (l, key) in escapeBox { c.display(s.t(key), at: l, 61, color: 2, eraseEOL: true) }
    }

    private static func display01C(_ s: Session, _ st: State) {
        let c = s.console, r = st.rec
        c.display(s.t("st010.d01_retail"), at: 13, 1, color: 2)
        c.display(Cobol.z(r.int("stock-retail") / 100, 7) + "." + Cobol.z(r.int("stock-retail") % 100, 2), at: 13, 17, color: 3)
        c.display(s.t("st010.d01_close"), at: 13, 27, color: 2)
        c.display(s.t("st010.d01_cost"), at: 13, 41, color: 2)
        c.display(Cobol.z(r.int("stock-cost") / 10000, 7) + "." + Cobol.z(r.int("stock-cost") % 10000, 4), at: 13, 57, color: 3)
        c.display(s.t("st010.d01_close"), at: 13, 69, color: 2)
        c.display(s.t("st010.d01_value"), at: 14, 1, color: 2)
        c.display(Cobol.z(r.int("stock-value") / 100, 9) + "." + Cobol.z(r.int("stock-value") % 100, 2), at: 14, 17, color: 3)
        c.display(s.t("st010.d01_close"), at: 14, 29, color: 2)
    }

    private static func fields02(_ st: State) -> [ScreenField] {
        let r = st.rec
        func n(_ line: Int, _ col: Int, _ name: String) -> ScreenField {
            ScreenField(line: line, col: col, size: 6, kind: .numeric, pic: "9(6)", value: Cobol.z(abs(r.int(name)) % 1_000_000, 6), color: 3)
        }
        return [n(16, 21, "stock-construct-bundle"), n(16, 59, "stock-under-construction"), n(17, 21, "stock-work-in-progress"),
                ScreenField(line: 17, col: 59, size: 13, value: r.str("stock-construct-item"), color: 3)]
    }

    private static func display02(_ s: Session, _ st: State) {
        let c = s.console
        c.display(s.t("st010.d02_title"), at: 15, 21, color: 2, highlight: true)
        c.display(s.t("st010.d02_bundle"), at: 16, 1, color: 2); c.display(s.t("st010.d01_close"), at: 16, 27, color: 2)
        c.display(s.t("st010.d02_construction"), at: 16, 41, color: 2); c.display(s.t("st010.d01_close"), at: 16, 65, color: 2)
        c.display(s.t("st010.d02_wip"), at: 17, 1, color: 2); c.display(s.t("st010.d01_close"), at: 17, 27, color: 2)
        c.display(s.t("st010.d02_item"), at: 17, 41, color: 2); c.display(s.t("st010.d01_close"), at: 17, 72, color: 2)
        c.displayFields(fields02(st))
    }

    private static func displayKeys(_ s: Session, _ st: State) {
        s.console.display(st.rec.str("stock-key"), at: 421, color: 3)
        s.console.display(st.rec.str("stock-abrev-key"), at: 457, color: 3)
    }

    /// 発注日・納期を画面用の文字列へ
    private static func loadDates(_ s: Session, _ st: State) {
        st.orderDate = st.rec.int("stock-order-date") != 0 ? ST.convertDate(s, st.rec.int("stock-order-date")) : Cobol.x("", 10)
        st.orderDue = st.rec.int("stock-order-due") != 0 ? ST.convertDate(s, st.rec.int("stock-order-due")) : Cobol.x("", 10)
    }

    // MARK: zz010 / zz020 / zz030 / zz040 / zz100

    private static func displayHeading(_ s: Session, _ st: State) {
        let c = s.console
        if st.menuReply != 4 {
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            c.display(s.sys.str("usera"), at: 301, color: 3)
            c.display(ST.headingDate(s), at: 171, color: 2)
        }
        switch st.menuReply {
        case 0:
            c.display(s.t("st010.title"), at: 124, color: 2)
            c.display(s.t("st010.function_menu"), at: 434, color: 2)
        case 1: c.display(s.t("st010.title_create"), at: 129, color: 2)
        case 2: c.display(s.t("st010.title_amend"), at: 129, color: 2)
        case 3: c.display(s.t("st010.title_delete"), at: 129, color: 2)
        case 5: c.display(s.t("st010.title_display"), at: 129, color: 2)
        default: break
        }
    }

    private static func displayOutline(_ s: Session, _ st: State) {
        displayHeading(s, st)
        ST.initialize(&st.rec)
        st.orderDate = Cobol.x("", 10); st.orderDue = Cobol.x("", 10)
        display01(s, st)
    }

    /// zz030-accept-money: 表示は「整数部.小数部」、入力は小数点無しの集団項目 (整数部+小数部の桁数)
    private static func acceptMoney(_ s: Session, _ line: Int, _ col: Int, _ value: Int64, int: Int, dec: Int) throws -> Int64 {
        let c = s.console
        let p = Cobol.pow10(dec)
        let pounds = Cobol.z(value / p, int), pence = Cobol.z(value % p, dec)
        c.display(pounds + "." + pence, at: line, col, color: 3)
        let a = Array(Cobol.x(try c.accept(at: line, col, size: int + dec, initial: pounds + pence, options: [.update], color: 3), int + dec))
        return ST.digits(String(a[0..<int])) * p + ST.digits(String(a[int...]))
    }

    /// zz040-Check-for-Supplier。戻り値は Error-Code
    private static func checkSupplier(_ s: Session, _ supplier: inout String) -> Int {
        if supplier.allSatisfy({ $0 == " " }) { return 0 }
        if Array(supplier)[6] == " " {
            let (code, reply) = ST.maps09(supplier, "C")
            if reply != "Y" {
                error(s, "st010.st103")
                return 2
            }
            supplier = code
        }
        if s.store.read(ST.purchasePath(s), key: SJIS.encode(supplier, size: 7)) != nil { return 0 }
        error(s, "st010.st101")
        return 1
    }

    /// zz100-test-escape
    private static func testEscape(_ s: Session, _ st: State) throws {
        let c = s.console
        c.display(st.escapeCode, at: 1976, color: 6)
        while true {
            st.escapeCode = try c.accept(at: 1976, size: 1, initial: st.escapeCode, options: [.update], color: 6).uppercased()
            if "BSQKDRCN".contains(st.escapeCode) && !st.escapeCode.isEmpty { break }
        }
    }

    private static var esc: Int { 2005 }
    private static func isBack(_ c: Console) -> Bool { c.crtStatus == 2001 || c.crtStatus == 2003 }

    // MARK: ba000-Setup-Stock / ca000-Amend-Stock 共通の入力ブロック (ba040 / ca040)

    /// 戻り値 false = Esc (品目番号の入力へ戻る)
    private static func acceptBlock(_ s: Session, _ st: State, _ f: IndexedFile, amend: Bool) throws -> Bool {
        let c = s.console
        while true {
            let fields = fields01(st)
            try c.acceptScreen(fields)
            store01(st, fields)
            if c.crtStatus == esc { return false }
            if c.crtStatus == 1003 {
                s.termCode = 0
                try s.call("pl010")
                displayHeading(s, st)
                display01(s, st)
                displayKeys(s, st)
                continue
            }
            var shown = false
            for b in 1...3 {
                let name = "stock-supplier-p\(b)"
                if st.rec.str(name).allSatisfy({ $0 == " " }) { continue }
                var supplier = Cobol.x(st.rec.str(name).uppercased(), 7)
                st.rec[name] = supplier
                if checkSupplier(s, &supplier) != 0 {
                    if !shown {
                        shown = true
                        error(s, "st010.supplier_not_found")
                    }
                    c.display(String(b), at: 23, 20 + b * 2, color: 4, highlight: true)
                }
                st.rec[name] = supplier
            }
            if shown { continue }
            clearErrorLine(s)
            setGroup(st, "stock-pa-code", group(st, "stock-pa-code").lowercased())
            c.display(group(st, "stock-pa-code"), at: 1057, color: 3)
            if group(st, "stock-pa-code") != "  " {
                setSystem(st, "stock-pa-code", "P")
                if st.analysisOpen && s.store.read(ST.analysisPath(s), key: st.rec.raw("stock-pa-code")) == nil {
                    error(s, "st010.st111")
                    continue
                }
            }
            setGroup(st, "stock-sa-code", group(st, "stock-sa-code").lowercased())
            c.display(group(st, "stock-sa-code"), at: 1021, color: 3)
            if group(st, "stock-sa-code") != "  " {
                setSystem(st, "stock-sa-code", "S")
                if st.analysisOpen && s.store.read(ST.analysisPath(s), key: st.rec.raw("stock-sa-code")) == nil {
                    error(s, "st010.st110")
                    continue
                }
            }
            display01C(s, st)
            // ba042 / ba044 / ba046
            st.rec.setInt("stock-retail", try acceptMoney(s, 13, 17, st.rec.int("stock-retail"), int: 7, dec: 2))
            st.rec.setInt("stock-cost", try acceptMoney(s, 13, 57, st.rec.int("stock-cost"), int: 7, dec: 4))
            st.rec.setInt("stock-value", try acceptMoney(s, 14, 17, st.rec.int("stock-value"), int: 9, dec: 2))
            let manu = s.sys.int("stk-manu-used") == 1
            if manu {
                let f2 = fields02(st)
                try c.acceptScreen(f2)
                st.rec.setInt("stock-construct-bundle", Cobol.numval(f2[0].value).0)
                st.rec.setInt("stock-under-construction", Cobol.numval(f2[1].value).0)
                st.rec.setInt("stock-work-in-progress", Cobol.numval(f2[2].value).0)
                st.rec["stock-construct-item"] = f2[3].value
            }
            let averaging = s.sys.int("stk-averaging") == 1 && st.rec.int("stock-value") == 0
                && st.rec.int("stock-cost") != 0 && st.rec.int("stock-held") != 0
            if averaging {
                // multiply Stock-Held by Stock-Cost giving Stock-Value
                st.rec.setInt("stock-value", ST.unsignedValue(Cobol.rescale(st.rec.int("stock-held") * st.rec.int("stock-cost"), from: 4, to: 2), digits: 11))
            }
            // 変更 (ca046) は IF が終止符で切れているため、平均法の条件に関係なく仕掛分を加算する (レガシーの癖)
            if (amend || averaging) && manu {
                let v = st.rec.int("stock-value") * 100 + st.rec.int("stock-cost") * st.rec.int("stock-work-in-progress")
                st.rec.setInt("stock-value", ST.unsignedValue(Cobol.rescale(v, from: 4, to: 2), digits: 11))
            }
            if st.orderDate != Cobol.x("", 10) {
                let bin = ST.validateDate(s, st.orderDate)
                if bin != 0 {
                    st.rec.setInt("stock-order-date", Int64(bin))
                    c.display(" ", at: 1228)
                } else {
                    error(s, "st010.st005")
                    c.display("*", at: 1228, color: 4, highlight: true)
                    continue
                }
            }
            if st.orderDue != Cobol.x("", 10) {
                let bin = ST.validateDate(s, st.orderDue)
                if bin != 0 {
                    st.rec.setInt("stock-order-due", Int64(bin))
                    c.display(" ", at: 1268)
                } else {
                    error(s, "st010.st005")
                    c.display("*", at: 1268, color: 4, highlight: true)
                    continue
                }
            }
            c.display(" ", at: 1228)
            c.display(" ", at: 1268)
            clearErrorLine(s)
            if !st.rec.str("stock-construct-item").allSatisfy({ $0 == " " }) {
                st.rec["stock-construct-item"] = st.rec.str("stock-construct-item").uppercased()
                c.display(st.rec.str("stock-construct-item"), at: 1659, color: 3)
                if s.store.read(f.path, key: st.rec.raw("stock-construct-item")) == nil {
                    error(s, "st010.st115")
                    continue
                }
            }
            if st.rec.str("stock-services-flag") != " " {
                st.rec["stock-services-flag"] = st.rec.str("stock-services-flag").uppercased()
            }
            if st.rec.str("stock-services-flag") == "Y" {
                st.rec["stock-construct-item"] = ""
                st.orderDue = Cobol.x("", 10); st.orderDate = Cobol.x("", 10)
                for n in ["stock-construct-bundle", "stock-under-construction", "stock-work-in-progress", "stock-reorder-pnt",
                          "stock-std-reorder", "stock-back-ordered", "stock-on-order", "stock-pre-sales", "stock-value",
                          "stock-order-due", "stock-order-date"] { st.rec.setInt(n, 0) }
                display01(s, st)
                display01C(s, st)
                if manu { display02(s, st) }
                error(s, "st010.st118", color: 2)
            }
            st.escapeCode = "S"
            try testEscape(s, st)
            return true
        }
    }

    // MARK: ba000-Setup-Stock

    private static func setupStock(_ s: Session, _ st: State) throws {
        let c = s.console
        if !s.store.exists(ST.purchasePath(s)) {
            error(s, "st010.st104")
            try ST.maps99(s, 45)
            throw ExitProgram()
        }
        let f = ST.stockFile(s)
        if f.open() != "00" {
            f.openOutput()
            s.sys["stock-control"] = "Y"
            ST.setFileStatus(s, 11, 1)
        }
        if ST.fileStatus(s, 15) != 1 {
            s.processFunc = 1; s.subFunction = 1
            try s.call("sl070")
            if ST.fileStatus(s, 15) != 1 {
                error(s, "st010.st112")
                f.close()
                try ST.maps99(s, 45)
                return
            }
        }
        st.analysisOpen = ST.openAnalysis(s) == "00"   // open input Analysis-File (結果は検査しない)
        defer { f.close() }
        while true {
            // ba010-Display-Stock-Headings
            displayOutline(s, st)
            ST.initialize(&st.rec)
            st.customerCode = Cobol.x("", 7); st.orderDate = Cobol.x("", 10); st.orderDue = Cobol.x("", 10)
            st.rec["stock-services-flag"] = "N"
            item: while true {
                // ba020-Stock-Item-Accept
                c.display(" ", at: 467)
                st.rec["stock-key"] = try c.accept(at: 421, size: 13, color: 3)
                if st.rec.str("stock-key").allSatisfy({ $0 == " " }) || c.crtStatus == esc { return }
                st.rec["stock-key"] = st.rec.str("stock-key").uppercased()
                st.wsStockKey = st.rec.str("stock-key")
                c.display(st.rec.str("stock-key"), at: 421, color: 3)
                // ba030-Stock-Abrev-Item-Accept
                var back = false
                while true {
                    st.rec["stock-abrev-key"] = try c.accept(at: 457, size: 7, color: 3)
                    if c.crtStatus == esc || isBack(c) { back = true; break }
                    if !st.rec.str("stock-abrev-key").allSatisfy({ $0 == " " }) {
                        st.rec["stock-abrev-key"] = st.rec.str("stock-abrev-key").uppercased()
                        st.customerCode = st.rec.str("stock-abrev-key")
                        c.display(st.rec.str("stock-abrev-key"), at: 457, color: 3)
                        clearErrorLine(s)
                        break
                    }
                    error(s, "st010.st102")
                }
                if back { continue item }
                // 既存レコードを読めた場合はレコード領域がその内容に置き換わる (レガシーと同じ)
                if let found = f.read(key: st.rec.raw("stock-key")) {
                    st.rec = found
                    error(s, "st010.st113")
                    continue item
                }
                st.rec["stock-abrev-key"] = st.customerCode
                if !st.rec.str("stock-abrev-key").allSatisfy({ $0 == " " }), let found = ST.read(f, abrev: st.rec.str("stock-abrev-key")) {
                    st.rec = found
                    error(s, "st010.st116")
                    continue item
                }
                clearErrorLine(s)
                st.rec["stock-abrev-key"] = st.customerCode
                st.rec["stock-key"] = st.wsStockKey
                // ba040-Accept-Block
                if try !acceptBlock(s, st, f, amend: false) { continue item }
                // ba050-Main-Output
                if st.escapeCode == "Q" || c.crtStatus == esc { return }
                if st.escapeCode == "B" || isBack(c) { continue item }
                if ST.write(f, st.rec) != "00" {
                    error(s, "st.st000")
                    c.display(f.status, at: 23, 38, color: 4, highlight: true)
                    try ST.maps99(s, 45)
                    return
                }
                ST.initialize(&st.rec)
                st.orderDate = Cobol.x("", 10); st.orderDue = Cobol.x("", 10)
                break item
            }
        }
    }

    // MARK: ca000-Amend-Stock

    private static func amendStock(_ s: Session, _ st: State) throws {
        let c = s.console
        if !s.store.exists(ST.purchasePath(s)) {
            error(s, "st010.st105")
            try ST.maps99(s, 45)
            return
        }
        let f = ST.stockFile(s)
        if f.open() != "00" {
            f.openOutput()
            s.sys["stock-control"] = "Y"
            ST.setFileStatus(s, 11, 1)
            error(s, "st010.st106")
            f.close()
            return
        }
        st.analysisOpen = ST.openAnalysis(s) == "00"
        if !st.analysisOpen {
            error(s, "st010.st112")
            f.close()
            try ST.maps99(s, 45)
            return
        }
        defer { f.close() }
        while true {
            // ca010-Display-Stock-Headings
            displayOutline(s, st)
            item: while true {
                // ca020-Stock-Item-Accept
                ST.initialize(&st.rec)
                st.customerCode = Cobol.x("", 7); st.orderDate = Cobol.x("", 10); st.orderDue = Cobol.x("", 10)
                c.display(" ", at: 467)
                st.rec["stock-key"] = try c.accept(at: 421, size: 13, color: 3)
                if st.rec.str("stock-key").allSatisfy({ $0 == " " }) || c.crtStatus == esc { return }
                st.rec["stock-key"] = st.rec.str("stock-key").uppercased()
                st.wsStockKey = st.rec.str("stock-key")
                // ca030-Get-Record
                guard let found = f.read(key: st.rec.raw("stock-key")) else {
                    error(s, "st010.st114")
                    continue item
                }
                st.rec = found
                displayKeys(s, st)
                clearErrorLine(s)
                loadDates(s, st)
                display01(s, st)
                displayKeys(s, st)
                // ca040-Accept-Block
                if try !acceptBlock(s, st, f, amend: true) { continue item }
                // ca050-Main-Output
                if st.escapeCode == "Q" || c.crtStatus == esc { return }
                if st.escapeCode == "B" || isBack(c) { continue item }
                if ST.rewrite(f, st.rec) != "00" {
                    error(s, "st.st000")
                    c.display(f.status, at: 23, 38, color: 4, highlight: true)
                    try ST.maps99(s, 45)
                    return
                }
                ST.initialize(&st.rec)
                st.orderDate = Cobol.x("", 10); st.orderDue = Cobol.x("", 10)
                break item
            }
        }
    }

    // MARK: da000-Delete-Stock

    private static func deleteStock(_ s: Session, _ st: State) throws {
        let c = s.console
        let f = ST.stockFile(s)
        if f.open() != "00" {
            error(s, "st010.st106")
            return
        }
        while true {
            // da010-Display-Stock-Headings
            displayOutline(s, st)
            item: while true {
                // da020-Stock-Item-Accept
                st.rec["stock-key"] = ""; st.rec["stock-abrev-key"] = ""; st.customerCode = Cobol.x("", 7)
                c.display(" ", at: 2361, eraseEOL: true)
                display01(s, st)
                if s.sys.int("stk-manu-used") == 1 { display02(s, st) }
                st.rec["stock-key"] = try c.accept(at: 421, size: 13, color: 3)
                if st.rec.str("stock-key").allSatisfy({ $0 == " " }) || c.crtStatus == esc {
                    f.close()
                    return
                }
                st.rec["stock-key"] = st.rec.str("stock-key").uppercased()
                st.wsStockKey = st.rec.str("stock-key")
                c.display(" ", at: 23, 1, eraseEOS: true)
                // da030-Get-Record
                guard let found = f.read(key: st.rec.raw("stock-key")) else {
                    error(s, "st010.st114")
                    continue item
                }
                st.rec = found
                displayKeys(s, st)
                clearErrorLine(s)
                loadDates(s, st)
                display01(s, st)
                if s.sys.int("stk-manu-used") == 1 { display02(s, st) }
                c.display(s.t("st010.box_delete"), at: 2261, color: 2)
                c.display(s.t("st010.box_line"), at: 2361, color: 2)
                displayKeys(s, st)
                if st.rec.int("stock-on-order") != 0 || st.rec.int("stock-held") != 0 || st.rec.int("stock-back-ordered") != 0 {
                    error(s, "st010.st107")
                    continue item
                }
                st.escapeCode = "D"
                try testEscape(s, st)
                if st.escapeCode == "Q" || c.crtStatus == esc { return }
                if st.escapeCode == "B" || st.escapeCode == "S" || isBack(c) { continue item }
                if st.escapeCode != "D" { break item }
                // da040-Accept-Delete
                var reply = " "
                repeat {
                    c.display(s.t("st010.delete_sure"), at: 22, 1, color: 2, highlight: true)
                    reply = try c.accept(at: 22, 44, size: 1, color: 6).uppercased()
                } while reply != "Y" && reply != "N"
                if reply == "N" { break item }
                c.display(" ", at: 22, 1, eraseEOL: true)
                if f.delete(key: st.rec.raw("stock-key")) != "00" {
                    error(s, "st010.st108")
                    c.display(f.status, at: 23, 37, color: 4, highlight: true)
                    try ST.maps99(s, 15)
                }
                break item
            }
        }
    }

    // MARK: ea000-Report-Stock

    private static func reportStock(_ s: Session, _ st: State) throws {
        let p = ST.Printer(s)
        let f = ST.stockFile(s)
        if f.open() != "00" {
            p.close()
            error(s, "st010.st106")
            return
        }
        produceReport(s, st, f, p)
        f.close(); p.close()
        p.spool()
    }

    private static func produceReport(_ s: Session, _ st: State, _ f: IndexedFile, _ p: ST.Printer) {
        var lineCnt = 99, pageNos = 0, recCnt = 0
        let pageLines = Int(s.sys.int("page-lines"))
        let t = s.time
        var hh = "  ", mm = "  "
        if t.hour != 0 || t.minute != 0 || t.second != 0 { hh = Cobol.z(t.hour, 2); mm = Cobol.z(t.minute, 2) }
        let line2 = Cobol.x(s.sys.str("usera"), 40) + Cobol.x("", 76) + Cobol.x(ST.headingDate(s), 10) + " " + hh + ":" + mm

        func heads() {
            guard lineCnt > pageLines else { return }
            pageNos = (pageNos + 1) & 0xff
            let line1 = Cobol.x(progName, 16) + Cobol.x("", 41) + Cobol.x(s.l10n.raw("report.st010.title"), 17) + Cobol.x("", 50)
                + Cobol.x(s.l10n.raw("report.st010.page"), 5) + Pic.edit("zz9", value: Int64(pageNos), scale: 0)
            if pageNos != 1 {
                p.afterPage(line1)
                p.after(1, line2)
                p.after(1, "")
            } else {
                p.before(1, line1)
                p.before(1, line2)
            }
            p.after(1, s.l10n.raw("report.st010.line_3"))
            p.after(1, s.l10n.raw("report.st010.line_4"))
            lineCnt = 5
        }

        while let r = f.readNext() {
            st.rec = r
            heads()
            recCnt += 1
            let service = r.str("stock-services-flag") == "Y"
            var cost = Array(Pic.edit("z(6)9.9999", value: r.int("stock-cost"), scale: 4))
            if String(cost[10...11]) == "00" { cost[10] = " "; cost[11] = " " }
            func qty(_ name: String) -> String { service ? Cobol.x("", 7) : Pic.edit("z(6)9", value: abs(r.int(name)), scale: 0) }
            var line5 = Cobol.x(r.str("stock-abrev-key"), 8) + Cobol.x(r.str("stock-key"), 14) + Cobol.x(r.str("stock-supplier-p1"), 8)
            line5 += Cobol.x(r.str("stock-location"), 11) + Pic.edit("z(6)9.99", value: r.int("stock-retail"), scale: 2) + String(cost)
            line5 += service ? Cobol.x("", 12) : Pic.edit("zzzzz,zz9.99", value: r.int("stock-value"), scale: 2)
            line5 += qty("stock-held") + qty("stock-reorder-pnt") + qty("stock-std-reorder") + " "
            line5 += Cobol.x(r.int("stock-order-date") != 0 ? ST.convertDate(s, r.int("stock-order-date")) : "", 11)
            line5 += Cobol.x(r.int("stock-order-due") != 0 ? ST.convertDate(s, r.int("stock-order-due")) : "", 10)
            line5 += qty("stock-on-order") + qty("stock-back-ordered")
            // l6-vars (STRING ... WITH POINTER)
            var vars = ""
            func pad(_ n: Int) { vars += String(repeating: " ", count: n) }
            let p2 = r.str("stock-supplier-p2"), p3 = r.str("stock-supplier-p3")
            if p2 != Cobol.x("", 7) || p3 != Cobol.x("", 7) {
                vars += s.l10n.raw("report.st010.secondary")
                if p2 != Cobol.x("", 7) { vars += " 1: " + p2 }
                if p3 != Cobol.x("", 7) { vars += " 2: " + p3 }
                pad(2)
            }
            let sa = Array(Cobol.x(r.str("stock-sa-code"), 3)), pa = Array(Cobol.x(r.str("stock-pa-code"), 3))
            if String(sa) != "   " { vars += s.l10n.raw("report.st010.sa_code") + String(sa[1...2]); pad(2) }
            if String(pa) != "   " { vars += s.l10n.raw("report.st010.pa_code") + String(pa[1...2]) }
            if r.int("stock-pre-sales") != 0 {
                vars += s.l10n.raw("report.st010.pre_sales") + Pic.edit("z(6)", value: abs(r.int("stock-pre-sales")), scale: 0)
            }
            let line6 = Cobol.x("", 5) + Cobol.x(s.l10n.raw("report.st010.description"), 13) + Cobol.x(r.str("stock-desc"), 32) + Cobol.x("", 5) + Cobol.x(vars, 77)
            if lineCnt > 5 {
                p.after(1, String(repeating: "-", count: 132))
                p.after(1, line5)
            } else {
                p.after(2, line5)
            }
            p.after(1, line6)
            lineCnt = (lineCnt + 3) & 0xff
            if !service && (r.int("stock-construct-bundle") != 0 || r.int("stock-under-construction") != 0
                || r.int("stock-work-in-progress") != 0 || r.str("stock-construct-item") != Cobol.x("", 13)) {
                func z6(_ n: String) -> String { Pic.edit("z(6)", value: abs(r.int(n)), scale: 0) }
                p.after(1, s.l10n.raw("report.st010.bundle") + z6("stock-construct-bundle") + s.l10n.raw("report.st010.wip") + z6("stock-work-in-progress")
                    + s.l10n.raw("report.st010.under_construction") + z6("stock-under-construction")
                    + s.l10n.raw("report.st010.for_item") + r.str("stock-construct-item"))
                lineCnt = (lineCnt + 1) & 0xff
            }
            if service {
                p.after(1, s.l10n.raw("report.st010.services_only"))
                lineCnt = (lineCnt + 1) & 0xff
            }
        }
        // ea230-Totals
        if lineCnt > pageLines - 3 {
            lineCnt = (lineCnt + 60) & 0xff
            heads()
        }
        let total = Pic.edit("zzz,zzz,zz9", value: Int64(recCnt), scale: 0).drop(while: { $0 == " " })
        p.after(3, s.l10n.raw("report.st010.total") + total)
    }

    // MARK: fa000-Display-Stock

    private static func displayStock(_ s: Session, _ st: State) throws {
        let c = s.console
        let f = ST.stockFile(s)
        if f.open() != "00" {
            error(s, "st010.st106")
            c.display(s.t("st010.st003"), at: 24, 1, color: 4, highlight: true)
            return
        }
        while true {
            // fa010-Display-Stock-Headings
            displayOutline(s, st)
            item: while true {
                // fa020-Stock-Item-Accept
                st.rec["stock-key"] = ""; st.rec["stock-abrev-key"] = ""; st.customerCode = Cobol.x("", 7)
                display01(s, st)
                display01C(s, st)
                if s.sys.int("stk-manu-used") == 1 { display02(s, st) }
                st.rec["stock-key"] = try c.accept(at: 421, size: 13, color: 3)
                if st.rec.str("stock-key").allSatisfy({ $0 == " " }) || c.crtStatus == esc {
                    f.close()
                    return
                }
                // ws-Cob-Crt-Status は設定されない作業項目のため、F1 で "*" にする分岐は成立しない (レガシーと同じ)
                st.rec["stock-key"] = st.rec.str("stock-key").uppercased()
                st.wsStockKey = st.rec.str("stock-key")
                while true {
                    // fa030-Get-Record
                    if st.wsStockKey.hasPrefix("*") {
                        guard let found = f.readNext() else {
                            error(s, "st010.st119")
                            c.display(s.t("st010.st003"), at: 24, 1, color: 4, highlight: true)
                            continue item
                        }
                        st.rec = found
                    } else {
                        guard let found = f.read(key: st.rec.raw("stock-key")) else {
                            error(s, "st010.st114")
                            c.display(s.t("st010.st003"), at: 24, 1, color: 4, highlight: true)
                            continue item
                        }
                        st.rec = found
                    }
                    displayKeys(s, st)
                    clearErrorLine(s)
                    loadDates(s, st)
                    display01(s, st)
                    display01C(s, st)
                    if s.sys.int("stk-manu-used") == 1 { display02(s, st) }
                    displayKeys(s, st)
                    if st.wsStockKey == Cobol.x("*", 13) {
                        st.escapeCode = "N"
                        c.display(s.t("st010.box_next"), at: 20, 64, color: 2)
                    } else {
                        st.escapeCode = "S"
                    }
                    try testEscape(s, st)
                    if st.escapeCode == "N" || c.crtStatus == 1001 { continue }
                    break
                }
                if st.escapeCode == "Q" || c.crtStatus == esc {
                    f.close()
                    return
                }
                break item
            }
        }
    }

    // MARK: ga000-Renumber-Stock

    private static func renumberStock(_ s: Session, _ st: State) throws {
        let c = s.console
        let f = ST.stockFile(s)
        if f.open() != "00" {
            error(s, "st010.st106")
            return
        }
        heads: while true {
            // ga010-Display-Stock-Headings
            displayOutline(s, st)
            item: while true {
                // ga020-Stock-Item-Accept
                st.rec["stock-key"] = ""; st.rec["stock-abrev-key"] = ""; st.customerCode = Cobol.x("", 7)
                c.display(" ", at: 2361, eraseEOL: true)
                display01(s, st)
                display01C(s, st)
                if s.sys.int("stk-manu-used") == 1 { display02(s, st) }
                st.rec["stock-key"] = try c.accept(at: 421, size: 13, color: 3)
                if st.rec.str("stock-key").allSatisfy({ $0 == " " }) || c.crtStatus == esc {
                    f.close()
                    return
                }
                st.rec["stock-key"] = st.rec.str("stock-key").uppercased()
                st.wsStockKey = st.rec.str("stock-key")
                c.display(" ", at: 23, 1, eraseEOS: true)
                // ga030-Get-Record
                guard let found = f.read(key: st.rec.raw("stock-key")) else {
                    error(s, "st010.st114")
                    continue item
                }
                st.rec = found
                displayKeys(s, st)
                clearErrorLine(s)
                loadDates(s, st)
                display01(s, st)
                display01C(s, st)
                if s.sys.int("stk-manu-used") == 1 { display02(s, st) }
                c.display(s.t("st010.d01_stock_number"), at: 1601, color: 2, eraseEOL: true)
                c.display(s.t("st010.d01_close"), at: 1634, color: 2)
                c.display(s.t("st010.d01_fast_key"), at: 1641, color: 2)
                c.display(s.t("st010.d01_close"), at: 1664, color: 2)
                c.display(s.t("st010.box_renumber"), at: 2261, color: 2)
                c.display(s.t("st010.box_line"), at: 2361, color: 2)
                displayKeys(s, st)
                if st.rec.int("stock-on-order") != 0 || st.rec.int("stock-back-ordered") != 0 {
                    error(s, "st010.st109")
                    continue item
                }
                st.wsStockKey = st.rec.str("stock-key")
                let saveKey = st.rec.str("stock-key"), saveAbrev = st.rec.str("stock-abrev-key")
                var wsAbrev = saveAbrev
                newNo: while true {
                    // ga040-Accept-New-Stock-No
                    st.wsStockKey = Cobol.x(try c.accept(at: 1621, size: 13, initial: st.wsStockKey, options: [.update], color: 3), 13)
                    if st.wsStockKey == Cobol.x("", 13) || c.crtStatus == esc { continue heads }
                    st.wsStockKey = st.wsStockKey.uppercased()
                    c.display(st.rec.str("stock-key"), at: 1621, color: 3)
                    wsAbrev = Cobol.x(try c.accept(at: 1657, size: 7, color: 3), 7)
                    if c.crtStatus == esc || isBack(c) { continue newNo }
                    if wsAbrev != Cobol.x("", 7) {
                        wsAbrev = wsAbrev.uppercased()
                        clearErrorLine(s)
                    } else {
                        error(s, "st010.st102")
                        continue newNo
                    }
                    st.escapeCode = "R"
                    try testEscape(s, st)
                    if st.escapeCode == "Q" || c.crtStatus == esc { return }
                    if st.escapeCode == "B" || st.escapeCode == "S" || isBack(c) { continue item }
                    if st.escapeCode != "R" { continue heads }
                    // ga050-Accept-Renumber
                    var reply = " "
                    repeat {
                        c.display(s.t("st010.renumber_sure"), at: 22, 1, color: 2, highlight: true)
                        reply = try c.accept(at: 22, 47, size: 1, color: 6).uppercased()
                    } while reply != "Y" && reply != "N"
                    if reply == "N" { continue heads }
                    c.display(" ", at: 22, 1, eraseEOL: true)
                    st.rec["stock-key"] = st.wsStockKey
                    st.rec["stock-abrev-key"] = wsAbrev
                    let status = ST.write(f, st.rec)
                    if status == "22" {
                        error(s, "st010.st117")
                        continue newNo
                    }
                    if status != "00" {
                        error(s, "st.st000")
                        c.display(status, at: 23, 38, color: 4, highlight: true)
                        try ST.maps99(s, 45)
                        f.close()
                        return
                    }
                    st.rec["stock-key"] = saveKey
                    st.rec["stock-abrev-key"] = saveAbrev
                    if f.delete(key: st.rec.raw("stock-key")) != "00" {
                        error(s, "st010.st108")
                        c.display(f.status, at: 23, 37, color: 4, highlight: true)
                        try ST.maps99(s, 15)
                    }
                    continue heads
                }
            }
        }
    }
}
