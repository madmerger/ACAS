import Foundation

/// sales/sl070.cbl: Product Analysis File Set-Up & Maintenance (売上分析コード保守)
enum SLA070 {
    static let progName = "SL070 (3.01.11)"

    static let analysisLayout = Layout("analysis-record", [
        ("pa-system", .x(1)), ("pa-first", .x(1)), ("pa-second", .x(1)),
        ("pa-gl", .n9(digits: 6, scale: 0, signed: false)), ("pa-desc", .x(24)), ("pa-print", .x(3)),
    ])
    static let valueLayout = Layout("value-record", [
        ("va-code", .x(3)), ("va-gl", .n9(digits: 6, scale: 0, signed: false)), ("va-desc", .x(24)), ("va-print", .x(3)),
        ("va-t-this", .comp(digits: 5, scale: 0, signed: false)), ("va-t-last", .comp(digits: 5, scale: 0, signed: false)),
        ("va-t-year", .comp(digits: 5, scale: 0, signed: false)),
        ("va-v-this", .comp3(digits: 10, scale: 2, signed: true)), ("va-v-last", .comp3(digits: 10, scale: 2, signed: true)),
        ("va-v-year", .comp3(digits: 10, scale: 2, signed: true)),
    ])
    static func analysisFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "analysis.dat", layout: analysisLayout, keyLength: 3)
    }
    static func valueFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "value.dat", layout: valueLayout, keyLength: 3)
    }

    /// working-storage (呼び出し 1 回分)
    final class WS {
        var menuReply = 0
        var wsReply = " "
        var errFlag = 0
        var printAll = false
        var ledLit = "Lgr"
        var lin = 0
        var rec = Record(analysisLayout)
        var group: String {
            get { rec.str("pa-first") + rec.str("pa-second") }
            set { let a = Array(Cobol.x(newValue, 2)); rec["pa-first"] = String(a[0]); rec["pa-second"] = String(a[1]) }
        }
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let w = WS()
        if s.processFunc != 1 { c.display(" ", at: 101, eraseEOS: true) }
        if SLA.fileStatus(s, 15) == 0 { setup(s) }
        if s.processFunc == 1 { return }
        while true {
            w.menuReply = 0
            heading(s, w)
            while true {
                c.display(s.t("sl070.select"), at: 701, color: 2)
                c.display(s.t("sl070.opt1"), at: 1004, color: 2)
                c.display(s.t("sl070.opt2"), at: 1204, color: 2)
                c.display(s.t("sl070.opt3"), at: 1404, color: 2)
                c.display(s.t("sl070.opt4"), at: 1604, color: 2)
                c.display(s.t("sl070.opt5"), at: 1804, color: 2)
                c.display(s.t("sl070.opt9"), at: 2004, color: 2)
                let r = try c.accept(at: 743, size: 1, kind: .numeric, initial: String(w.menuReply), options: [.update, .auto], color: 6)
                w.menuReply = Int(Cobol.moveNumeric(r, digits: 1, scale: 0))
                if w.menuReply == 9 { return }
                if w.menuReply >= 1 && w.menuReply <= 5 { break }
            }
            heading(s, w)
            switch w.menuReply {
            case 1: try create(s, w)
            case 2: try amend(s, w)
            case 3: w.ledLit = ""; try report(s, w)
            case 4: w.ledLit = "Lgr"; w.printAll = true; try report(s, w)
            default: try show(s, w)
            }
        }
    }

    // MARK: create section

    static func create(_ s: Session, _ w: WS) throws {
        let c = s.console
        let f = analysisFile(s)
        _ = f.open()
        outline(s, w)
        w.lin = 6
        while true {
            // product-loop
            w.group = "  "
            w.group = try c.accept(at: w.lin, 2, size: 2, initial: w.group, options: [.update], color: 3)
            if w.group == "  " { break }
            w.rec["pa-system"] = "S"
            if let found = f.read(key: f.key(of: w.rec)) {
                w.rec = found
                productDisplay(s, w)
                c.display(s.t("sl070.sl008"), at: 23, 1, color: 3)
                continue
            }
            let saveCode = w.rec.raw("pa-system") + w.rec.raw("pa-first") + w.rec.raw("pa-second")
            if w.rec.str("pa-second") != " " {
                w.rec["pa-second"] = " "
                guard let grp = f.read(key: f.key(of: w.rec)) else {
                    c.display(s.t("sl070.sl009"), at: 23, 1, color: 3)
                    continue
                }
                w.rec = grp
                if w.rec.int("pa-gl") != 0 {
                    c.display(s.t("sl070.sl010"), at: 23, 1, color: 3)
                    continue
                }
                c.display(" ", at: 23, 1, eraseEOL: true)
            }
            // get-details
            w.rec.bytes.replaceSubrange(0..<3, with: saveCode)
            w.rec.setInt("pa-gl", 0)
            w.rec["pa-desc"] = ""
            try analysisData(s, w, from: 0)
            let esc = try escapeCode(s)
            if esc == "B" { try analysisData(s, w, from: 1) }
            if esc == "Q" || esc == "K" { break }
            _ = f.write(w.rec)
            w.lin += 1
            if w.lin > 22 { outline(s, w); w.lin = 6 }
        }
        f.close()
    }

    // MARK: amend section

    static func amend(_ s: Session, _ w: WS) throws {
        let c = s.console
        let f = analysisFile(s)
        _ = f.open()
        outline(s, w)
        w.lin = 6
        while true {
            w.group = "  "
            w.group = try c.accept(at: w.lin, 2, size: 2, initial: w.group, options: [.update], color: 3)
            if w.group == "  " { break }
            w.rec["pa-system"] = "S"
            guard let found = f.read(key: f.key(of: w.rec)) else {
                c.display(s.t("sl070.sl009"), at: 23, 1, color: 3)
                continue
            }
            w.rec = found
            c.display(" ", at: 23, 1, eraseEOL: true)
            productDisplay(s, w)
            try analysisData(s, w, from: 0)
            let esc = try escapeCode(s)
            if esc == "B" { try analysisData(s, w, from: 1) }
            if esc == "Q" { break }
            if esc == "K" { _ = f.delete(key: f.key(of: w.rec)) } else { _ = f.rewrite(w.rec) }
            w.lin += 1
            if w.lin > 21 { outline(s, w); w.lin = 6 }
        }
        f.close()
    }

    static func escapeCode(_ s: Session) throws -> String {
        let c = s.console
        c.display("S", at: 18, 77, color: 6)
        return try c.accept(at: 18, 77, size: 1, initial: "S", options: [.update], color: 6).uppercased()
    }

    // MARK: report1 section

    /// analysis.dat に分析レコード長と異なるレコード (在庫経由の初期作成で書かれた集計レコード形式) が入っていると、
    /// レガシーでは OPEN が失敗し、READ NEXT が AT END にならず読み込みループから抜けない。
    static func analysisUnreadable(_ s: Session) -> Bool {
        s.store.all(s.ledgers + "analysis.dat").contains { $0.data.count != analysisLayout.size }
    }

    /// 回復不能なレガシーのループの再現。画面は変えず、以後のキー入力を読み捨て続ける。
    static func hang(_ s: Session) throws -> Never {
        while true { _ = try s.console.waitKey() }
    }

    static func report(_ s: Session, _ w: WS) throws {
        if analysisUnreadable(s) { try hang(s) }
        let f = analysisFile(s)
        _ = f.open()
        let p = SLA.Printer(s)
        p.open()
        var page = 0
        var lineCnt = 0
        func headings() {
            page = (page + 1) % 100
            let line1 = Cobol.x(progName, 33) + Cobol.x(s.l10n.raw("report.sl070.title"), 39) + Cobol.x(s.l10n.raw("report.sl070.page"), 5)
                + Pic.edit("zz9", value: Int64(page), scale: 0)
            if page != 1 {
                p.afterPage(line1)
                p.after(1, "")
            } else {
                p.before(1, line1)
            }
            p.after(1, Cobol.x(s.sys.str("usera"), 30) + SLA.spaces(40) + SLA.convertDate(s))
            p.after(2, Cobol.x(w.ledLit, 4) + Cobol.x(s.l10n.raw("report.sl070.cols"), 59) + Cobol.x(s.l10n.raw("report.sl070.type"), 6))
            lineCnt = 5
        }
        headings()
        f.startFirst()
        while let r = f.readNext() {
            if r.str("pa-system") != "S" && !w.printAll { continue }
            var type = "", ledger = " "
            if r.str("pa-second") == " " && r.int("pa-gl") == 0 {
                p.after(1, "")
                lineCnt += 1
                type = s.l10n.raw("report.sl070.group")
                if w.printAll { ledger = r.str("pa-system") }
            } else {
                type = s.l10n.raw("report.sl070.detail")
            }
            if lineCnt > 70 { headings() }
            if r.str("pa-second") != " " && r.int("pa-gl") == 0 { w.errFlag = 1 }
            let gl = s.sys.str("irs-instead") == "Y" ? r.int("pa-gl") : r.int("pa-gl") / 100
            let glText = gl == 0 ? SLA.spaces(6) : Cobol.z(gl, 6)
            p.after(1, " " + ledger + "   " + Cobol.x(r.str("pa-first") + r.str("pa-second"), 7) + glText + SLA.spaces(7)
                + Cobol.x(r.str("pa-desc"), 24) + SLA.spaces(4) + Cobol.x(r.str("pa-print"), 3) + SLA.spaces(7) + Cobol.x(type, 6))
            lineCnt += 1
            if lineCnt > 70 { headings() }
        }
        if w.errFlag != 0 { p.after(2, s.l10n.raw("report.sl070.warning")) }
        f.close()
        p.close()
    }

    // MARK: show section

    static func show(_ s: Session, _ w: WS) throws {
        let c = s.console
        let f = analysisFile(s)
        _ = f.open()
        f.startFirst()
        outline(s, w)
        w.lin = 6
        c.display(s.t("sl070.show_prompt"), at: 23, 31, color: 2)
        if analysisUnreadable(s) { try hang(s) }
        while true {
            // show-read
            if w.lin > 21 { break }
            var atEnd = true
            while let r = f.readNext() {
                if r.str("pa-system") != "S" { continue }
                w.rec = r; atEnd = false
                break
            }
            if atEnd { w.lin = 24 } else { productDisplay(s, w) }
            // accept-of-show
            w.lin += 1
            if w.lin < 22 { continue }
            w.wsReply = try c.accept(at: 23, 76, size: 1, initial: w.wsReply, options: [.update], color: 6).uppercased()
            if w.lin > 23 { break }
            if w.wsReply != "X" {
                outline(s, w)
                w.lin = 6
                continue
            }
            break
        }
        f.close()
    }

    static func productDisplay(_ s: Session, _ w: WS) {
        let c = s.console
        c.display(w.group, at: w.lin, 2, color: 3)
        c.display(Cobol.z(w.rec.int("pa-gl"), 6), at: w.lin, 8, color: 3)
        c.display(w.rec.str("pa-desc"), at: w.lin, 20, color: 3)
        let group = w.rec.str("pa-second") == " " && w.rec.int("pa-gl") == 0
        c.display(w.rec.str("pa-print"), at: w.lin, 48, color: 3)
        c.display(Cobol.x(s.t(group ? "sl070.type_group" : "sl070.type_detail"), 6), at: w.lin, 55, color: 3)
    }

    // MARK: display-heading / display-outline

    static func heading(_ s: Session, _ w: WS) {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(SLA.convertDate(s), at: 171, color: 2)
        switch w.menuReply {
        case 0:
            c.display(s.t("sl070.title"), at: 120, color: 2)
            c.display(s.t("sl070.function_menu"), at: 434, color: 2)
        case 1: c.display(s.t("sl070.title1"), at: 132, color: 2)
        case 2: c.display(s.t("sl070.title2"), at: 129, color: 2)
        case 3: c.display(s.t("sl070.title3"), at: 132, color: 2)
        case 4: c.display(s.t("sl070.title4"), at: 132, color: 2)
        case 5: c.display(s.t("sl070.title5"), at: 131, color: 2)
        default: break
        }
    }

    static func outline(_ s: Session, _ w: WS) {
        let c = s.console
        c.display(s.t("sl070.col_head"), at: 401, color: 2)
        c.display(s.t("sl070.col_ref"), at: 448, color: 2)
        c.display(s.t("sl070.col_type"), at: 456, color: 2)
        for lin in 6..<23 {
            c.display("[  ]  [      ]    [                        ]  [   ]          ", at: lin, 1, color: 2)
        }
        w.lin = 23
        if w.menuReply != 5 {
            c.display("*******************", at: 17, 62, color: 2)
            for l in 18...22 {
                c.display("*", at: l, 62, color: 2)
                c.display("*", at: l, 80, color: 2)
            }
            c.display("*******************", at: 23, 62, color: 2)
            c.display(s.t("sl070.escape_code"), at: 18, 64, color: 2)
            c.display(s.t("sl070.esc_b"), at: 19, 64, color: 2)
            c.display(s.t("sl070.esc_s"), at: 20, 64, color: 2)
            c.display(s.t("sl070.esc_q"), at: 21, 64, color: 2)
            c.display(s.t("sl070.esc_k"), at: 22, 64, color: 2)
        }
    }

    // MARK: analysis-data section (from: 0 = 先頭, 1 = get-pa-desc から)

    static func analysisData(_ s: Session, _ w: WS, from: Int) throws {
        let c = s.console
        if from == 0 {
            let r = try c.accept(at: w.lin, 8, size: 6, kind: .numeric, initial: Cobol.z(w.rec.int("pa-gl"), 6), options: [.update], color: 3)
            w.rec.setInt("pa-gl", Cobol.moveNumeric(r, digits: 6, scale: 0))
        }
        w.rec["pa-desc"] = try c.accept(at: w.lin, 20, size: 24, initial: w.rec.str("pa-desc"), options: [.update], color: 3)
        if w.menuReply == 1 { w.rec["pa-print"] = w.group }
        w.rec["pa-print"] = try c.accept(at: w.lin, 48, size: 3, initial: w.rec.str("pa-print"), options: [.update], color: 3)
    }

    // MARK: p-a-setup section (分析ファイル・集計ファイルの初期作成)

    static func setup(_ s: Session) {
        // 在庫 (stock / st010 / st060) から呼ばれた場合、呼び出し側の file-defs は在庫用の並びのため、
        // sl070 の file-13 (集計ファイル) は analysis.dat を指し、file-15 (分析ファイル) は file-defs の範囲外になる。
        // レガシー実測どおり、集計レコード形式を analysis.dat に書き、value.dat は作らない。
        let fromStock = (s.shared["file-defs-layout"] as? String) == "stock"
        let v = fromStock
            ? IndexedFile(s.store, path: s.ledgers + "analysis.dat", layout: valueLayout, keyLength: 3)
            : valueFile(s)
        if v.open() != "00" {
            SLA.setFileStatus(s, 13, 1)
            v.openOutput()
        }
        v.close()
        _ = v.open()
        let a = analysisFile(s)
        if !fromStock { a.openOutput() }
        var rec = Record(analysisLayout)
        func put(_ sys: String, _ group: String, _ descKey: String, _ print: String) {
            let g = Array(group)
            rec["pa-system"] = sys; rec["pa-first"] = String(g[0]); rec["pa-second"] = String(g[1])
            rec.setInt("pa-gl", 0)
            rec["pa-desc"] = s.l10n.raw(descKey); rec["pa-print"] = print
            let key = Array(rec.bytes[0..<3])
            if v.read(key: key) == nil {
                var vr = Record(valueLayout)
                vr.bytes.replaceSubrange(0..<36, with: rec.bytes)
                for n in ["va-v-this", "va-v-last", "va-v-year", "va-t-this", "va-t-last", "va-t-year"] { vr.setInt(n, 0) }
                _ = v.write(vr)
            }
            if !fromStock { _ = a.write(rec) }
        }
        put("S", "v ", "sl070.pa.vat_control", "")
        put("P", "v ", "sl070.pa.vat_control", "")
        put("P", "vi", "sl070.pa.vat_in_inv", "")
        put("P", "vj", "sl070.pa.vat_in_rec", "")
        put("S", "z ", "sl070.pa.computer", "")
        put("P", "z ", "sl070.pa.computer", "")
        put("P", "za", "sl070.pa.purch_carriage", "P&P")
        put("P", "zb", "sl070.pa.purch_late", "LCG")
        put("S", "zc", "sl070.pa.sales_carriage", "P&P")
        put("S", "zd", "sl070.pa.sales_late", "LCG")
        put("S", "vo", "sl070.pa.vat_out_inv", "")
        put("S", "vp", "sl070.pa.vat_out_rec", "")
        put("P", "a ", "sl070.pa.default_group", "")
        put("P", "a1", "sl070.pa.default_purch", "")
        put("S", "a ", "sl070.pa.default_group", "")
        put("S", "a1", "sl070.pa.default_sales", "")
        if !fromStock { a.close() }
        v.close()
        SLA.setFileStatus(s, 15, 1)
        if s.processFunc != 1 { s.console.display(" ", at: 23, 1, eraseEOL: true) }
    }
}
