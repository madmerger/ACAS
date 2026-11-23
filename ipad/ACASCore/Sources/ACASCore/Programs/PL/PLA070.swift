import Foundation

/// purchase/pl070.cbl: 仕入分析コード保守 (Product Analysis File Set-Up & Maintenance)
final class PLA070 {
    static let progName = "PL070 (3.01.11)"
    static func run(_ s: Session) throws {
        let p = PLA070(s)
        defer { s.shared["pla070.analysis-record"] = p.anal.bytes; s.shared["pla070.ws"] = [p.wsReply, p.l6Ledger, p.printMode] }
        try p.main()
    }

    let s: Session
    var c: Console { s.console }
    let analysis: PLA.CheckedFile
    /// analysis-record (FD のレコード領域。CALL をまたいで保持される)
    var anal: Record
    var menuReply = 0
    var wsReply = " "
    var wsErrFlag = 0
    var escapeCode = " "
    var printMode = " "
    var lin = 0
    var l6Ledger = " "

    init(_ s: Session) {
        self.s = s
        analysis = PLA.analysisFile(s)
        anal = PLA.fdArea(PLA.analLayout)
        if let b = s.shared["pla070.analysis-record"] as? [UInt8] { anal = Record(PLA.analLayout, bytes: b) }
        if let w = s.shared["pla070.ws"] as? [String], w.count == 3 { wsReply = w[0]; l6Ledger = w[1]; printMode = w[2] }
    }

    /// 数字項目 (内容が 2 進ゼロ等でも落とさない)
    func paGl() -> Int64 { anal.raw("pa-gl").reduce(Int64(0)) { $0 * 10 + Int64($1 & 0x0F) } }
    func key() -> [UInt8] { Array(anal.bytes[0..<3]) }

    func main() throws {
        if s.processFunc != 1 { c.display(" ", at: 101, eraseEOS: true) }
        if PLA.fileStatus(s, 15) == 0 { paSetup() }
        if s.processFunc == 1 { return }
        while true {
            menuReply = 0
            displayHeading()
            while true {
                c.display(s.t("pl070.select"), at: 701, color: 2)
                c.display(s.t("pl070.menu_1"), at: 1004, color: 2)
                c.display(s.t("pl070.menu_2"), at: 1204, color: 2)
                c.display(s.t("pl070.menu_3"), at: 1404, color: 2)
                c.display(s.t("pl070.menu_4"), at: 1604, color: 2)
                c.display(s.t("pl070.menu_5"), at: 1804, color: 2)
                c.display(s.t("pl070.menu_9"), at: 2004, color: 2)
                menuReply = Int(try c.accept(at: 743, size: 1, kind: .numeric, initial: String(menuReply), options: [.update, .auto], color: 6)) ?? 0
                if menuReply == 9 { return }
                if (1...5).contains(menuReply) { break }
            }
            displayHeading()
            switch menuReply {
            case 1: try create()
            case 2: try amend()
            case 3: try report1(ledLit: Cobol.x("", 4))
            case 4:
                printMode = "A"
                try report1(ledLit: Cobol.x(s.l10n.raw("pl070.rep_lgr"), 4))
            default: try show()
            }
        }
    }

    // MARK: create section

    func acceptEscape() throws {
        escapeCode = "S"
        c.display(escapeCode, at: 18, 77, color: 6)
        escapeCode = try c.accept(at: 18, 77, size: 1, initial: escapeCode, options: [.update], color: 6).uppercased()
    }

    func create() throws {
        analysis.open()
        defer { analysis.close() }
        displayOutline()
        lin = 6
        while true {
            // product-loop
            anal.set("pa-group", try c.accept(at: lin, 2, size: 2, initial: "  ", options: [.update], color: 3))
            if anal.str("pa-group") == "  " { return }
            anal.set("pa-system", "P")
            if case .ok(let r) = analysis.read(key: key()) {
                anal = r
                productDisplay()
                c.display(s.t("pl070.pl008"), at: 23, 1, color: 3)
                continue
            }
            let saveCode = anal.raw("pa-code")
            if anal.raw("pa-group")[1] != 0x20 {
                var k = anal.raw("pa-group"); k[1] = 0x20
                anal.setRaw("pa-group", k)
                switch analysis.read(key: key()) {
                case .invalidKey:
                    c.display(s.t("pl070.pl009"), at: 23, 1, color: 3)
                    continue
                case .ok(let r): anal = r
                case .notOpen: break
                }
                if paGl() != 0 {
                    c.display(s.t("pl070.pl010"), at: 23, 1, color: 3)
                    continue
                }
                c.display(" ", at: 23, 1, eraseEOL: true)
            }
            // get-details
            anal.setRaw("pa-code", saveCode)
            anal.setInt("pa-gl", 0)
            anal.set("pa-desc", "")
            try analysisData(from: 0)
            try acceptEscape()
            if escapeCode == "B" { try analysisData(from: 1) }
            if escapeCode == "Q" || escapeCode == "K" { return }
            analysis.write(anal)
            lin += 1
            if lin > 22 {
                displayOutline()
                lin = 6
            }
        }
    }

    // MARK: amend section

    func amend() throws {
        analysis.open()
        defer { analysis.close() }
        displayOutline()
        lin = 6
        while true {
            anal.set("pa-group", try c.accept(at: lin, 2, size: 2, initial: "  ", options: [.update], color: 3))
            if anal.str("pa-group") == "  " { return }
            anal.set("pa-system", "P")
            switch analysis.read(key: key()) {
            case .invalidKey:
                c.display(s.t("pl070.pl009"), at: 23, 1, color: 3)
                continue
            case .ok(let r): anal = r
            case .notOpen: break
            }
            c.display(" ", at: 23, 1, eraseEOL: true)
            productDisplay()
            try analysisData(from: 0)
            try acceptEscape()
            if escapeCode == "B" { try analysisData(from: 1) }
            if escapeCode == "Q" { return }
            if escapeCode == "K" { analysis.delete(key: key()) } else { analysis.rewrite(anal) }
            lin += 1
            if lin > 21 {
                displayOutline()
                lin = 6
            }
        }
    }

    // MARK: report1 section

    func report1(ledLit: String) throws {
        analysis.open()
        let p = PLA.Printer(s)
        p.openOutput()
        var a = 0, lineCnt = 0
        func headings() {
            a += 1
            let line1 = Cobol.x(PLA070.progName, 33) + Cobol.x(s.t("pl070.rep_title"), 39) + s.t("pl070.rep_page") + Pic.edit("zz9", value: Int64(a % 1000), scale: 0)
            if a != 1 {
                p.writePage(line1)
                p.write("", after: 1)
            } else {
                p.writeBefore(line1, before: 1)
            }
            p.write(Cobol.x(s.sys.str("usera"), 30) + Cobol.x("", 40) + Cobol.x(PLA.toDayDisplay(s), 10), after: 1)
            p.write(ledLit + Cobol.x(s.t("pl070.rep_line4"), 59) + s.t("pl070.rep_type"), after: 2)
            lineCnt = 5
        }
        headings()
        while true {
            if !analysis.opened {
                // レガシーではファイルが開けていないと AT END にならず、レコード領域が変わらないまま読み続ける。
                // 条件が変わらない限り終了しない (帳票を出し続けて戻らない) ため、ここで止まったままにする。
                if anal.str("pa-system") != "P" && printMode != "A" { break }
                while true { _ = try c.waitKey() }
            }
            guard let r = analysis.readNext() else { break }
            anal = r
            if anal.str("pa-system") != "P" && printMode != "A" { break }
            let second = anal.raw("pa-group")[1]
            var l6Type: String
            if second == 0x20 && paGl() == 0 {
                p.write("", after: 1)
                lineCnt += 1
                l6Type = s.l10n.raw("pl070.type_group")
                if printMode == "A" { l6Ledger = anal.str("pa-system") }
            } else {
                l6Type = s.l10n.raw("pl070.type_detail")
                l6Ledger = " "
            }
            if lineCnt > 70 { headings() }
            if second != 0x20 && paGl() == 0 { wsErrFlag = 1 }
            let gl = PLA.irsUsed(s) ? paGl() : paGl() / 100
            let line6 = " " + l6Ledger + "   " + Cobol.x(anal.str("pa-group"), 7) + (gl == 0 ? Cobol.x("", 6) : Cobol.z(gl % 1_000_000, 6))
                + Cobol.x("", 7) + anal.str("pa-desc") + Cobol.x("", 4) + anal.str("pa-print") + Cobol.x("", 7) + Cobol.x(l6Type, 6)
            p.write(line6, after: 1)
            lineCnt += 1
            if lineCnt > 70 { headings() }
        }
        // end-report
        if wsErrFlag != 0 { p.write(s.t("pl070.rep_warning"), after: 2) }
        p.close()
        p.spool()
        analysis.close()
    }

    // MARK: show section

    func productDisplay() {
        c.display(PLA.shown(anal.raw("pa-group")), at: lin, 2, color: 3)
        c.display(PLA.shown(anal.raw("pa-gl")), at: lin, 8, color: 3)
        c.display(PLA.shown(anal.raw("pa-desc")), at: lin, 20, color: 3)
        let type = anal.raw("pa-group")[1] == 0x20 && paGl() == 0 ? "pl070.type_group" : "pl070.type_detail"
        c.display(PLA.shown(anal.raw("pa-print")), at: lin, 48, color: 3)
        c.display(Cobol.x(s.l10n.raw(type), 6), at: lin, 55, color: 3)
    }

    func show() throws {
        analysis.open()
        defer { analysis.close() }
        lin = 6
        displayOutline()
        lin = 6
        c.display(s.t("pl070.show_prompt"), at: 23, 31, color: 2)
        while true {
            // show-read
            if lin > 21 { return }
            var display = true
            if analysis.opened {
                if let r = analysis.readNext() {
                    anal = r
                } else {
                    lin = 24; display = false
                }
            }
            if display && anal.str("pa-system") != "P" { lin = 24; display = false }
            if display { productDisplay() }
            // accept-of-show
            lin += 1
            if lin < 22 { continue }
            wsReply = try c.accept(at: 23, 76, size: 1, initial: wsReply, options: [.update], color: 6).uppercased()
            if lin > 23 { return }
            if wsReply != "X" {
                displayOutline()
                lin = 6
                continue
            }
            return
        }
    }

    // MARK: display-heading / display-outline section

    func displayHeading() {
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA070.progName, at: 101, color: 2)
        c.display(PLA.toDayDisplay(s), at: 171, color: 2)
        switch menuReply {
        case 0:
            c.display(s.t("pl070.title"), at: 120, color: 2)
            c.display(s.t("pl070.function_menu"), at: 434, color: 2)
        case 1: c.display(s.t("pl070.title_1"), at: 132, color: 2)
        case 2: c.display(s.t("pl070.title_2"), at: 129, color: 2)
        case 3: c.display(s.t("pl070.title_3"), at: 132, color: 2)
        case 4: c.display(s.t("pl070.title_4"), at: 132, color: 2)
        case 5: c.display(s.t("pl070.title_5"), at: 131, color: 2)
        default: break
        }
    }

    func displayOutline() {
        c.display(s.t("pl070.col_head"), at: 401, color: 2)
        c.display(s.t("pl070.col_ref"), at: 448, color: 2)
        c.display(s.t("pl070.col_type"), at: 456, color: 2)
        lin = 6
        repeat {
            c.display("[  ]  [      ]    [                        ]  [   ]          ", at: lin, 1, color: 2)
            lin += 1
        } while lin < 23
        if menuReply != 5 {
            c.display("*******************", at: 17, 62, color: 2)
            for l in 18...22 {
                c.display("*", at: l, 62, color: 2)
                c.display("*", at: l, 80, color: 2)
            }
            c.display("*******************", at: 23, 62, color: 2)
            c.display(s.t("pl070.escape_code"), at: 18, 64, color: 2)
            c.display(s.t("pl070.esc_back"), at: 19, 64, color: 2)
            c.display(s.t("pl070.esc_save"), at: 20, 64, color: 2)
            c.display(s.t("pl070.esc_quit"), at: 21, 64, color: 2)
            c.display(s.t("pl070.esc_deleted"), at: 22, 64, color: 2)
        }
    }

    // MARK: analysis-data section

    /// from: 0 = 先頭 (G/L 番号) から、1 = get-pa-desc から
    func analysisData(from: Int) throws {
        if from == 0 {
            let gl = Cobol.z(paGl() % 1_000_000, 6)
            anal.setInt("pa-gl", Int64(try c.accept(at: lin, 8, size: 6, kind: .numeric, initial: gl, options: [.update], color: 3)) ?? 0)
        }
        anal.set("pa-desc", try c.accept(at: lin, 20, size: 24, initial: PLA.shown(anal.raw("pa-desc")), options: [.update], color: 3))
        if menuReply == 1 { anal.set("pa-print", anal.str("pa-group")) }
        anal.set("pa-print", try c.accept(at: lin, 48, size: 3, initial: PLA.shown(anal.raw("pa-print")), options: [.update], color: 3))
    }

    // MARK: p-a-setup section

    /// 初期の分析コードを作成する。名称は文言キー (英語ではレガシーと同じバイト列。24 バイトを超える分は切り捨て)。
    func paSetup() {
        let value = PLA.valueFile(s)
        if value.open() != "00" {
            value.close()
            PLA.setFileStatus(s, 13, 1)
            value.openOutput()
        }
        value.close()
        _ = value.open()
        analysis.openOutput()
        func createValue() {
            if value.read(key: key()) == nil {
                var va = Record(PLA.valueLayout, bytes: anal.bytes + [UInt8](repeating: 0x20, count: 30))
                for f in ["va-v-this", "va-v-last", "va-v-year", "va-t-this", "va-t-last", "va-t-year"] { va.setInt(f, 0) }
                value.write(va)
            }
            analysis.write(anal)
        }
        func d(_ key: String) -> String { s.l10n.raw(key) }
        func put(_ system: String? = nil, _ group: String? = nil, _ desc: String? = nil, print: String? = nil) {
            if let v = system { anal.set("pa-system", v) }
            if let v = group { anal.set("pa-group", v) }
            if let v = print { anal.set("pa-print", v) }
            if let v = desc { anal.set("pa-desc", v) }
            createValue()
        }
        anal.setInt("pa-gl", 0)
        put("S", "v ", d("pl070.setup_vat_control"), print: "")
        put("P")
        put(nil, "vi", d("pl070.setup_vat_input_inv"))
        put(nil, "vj", d("pl070.setup_vat_input_rec"))
        put("S", "z ", d("pl070.setup_computer_control"))
        put("P")
        put(nil, "za", d("pl070.setup_purch_carriage"), print: "P&P")
        put(nil, "zb", d("pl070.setup_purch_late"), print: "LCG")
        put("S", "zc", d("pl070.setup_sales_carriage"), print: "P&P")
        put(nil, "zd", d("pl070.setup_sales_late"), print: "LCG")
        put(nil, "vo", d("pl070.setup_vat_output_inv"), print: "")
        put(nil, "vp", d("pl070.setup_vat_output_rec"))
        put("P", "a ", d("pl070.setup_default_group"))
        put(nil, "a1", d("pl070.setup_default_purchases"))
        put("S", "a ", d("pl070.setup_default_group"))
        put(nil, "a1", d("pl070.setup_default_sales"))
        analysis.close(); value.close()
        PLA.setFileStatus(s, 15, 1)
        if s.processFunc != 1 { c.display(" ", at: 23, 1, eraseEOL: true) }
    }
}
