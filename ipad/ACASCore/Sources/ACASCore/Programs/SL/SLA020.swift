import Foundation

/// sales/sl020.cbl: Sales Ledger Enquiry (売掛元帳照会)
enum SLA020 {
    static let progName = "SL020 (3.01.08)"
    static let bodyLines = 13

    static let workLayout = Layout("work-record", [
        ("work-customer", .x(7)), ("work-invoice", .native(bytes: 4, signed: true)),
        ("work-amount", .comp3(digits: 10, scale: 2, signed: true)),
    ])

    final class WS {
        var a = 0, b = 0, c = 0
        var screenStart = 1, screenEnd = 0
        var amountOut: Int64 = 0, invAmount: Int64 = 0
        var customerIn = SLA.spaces(7)
        var workFileData = "N"
        var bal0: Int64 = 0, bal30: Int64 = 0, bal60: Int64 = 0, bal90: Int64 = 0, balT: Int64 = 0
        var l0date = ""
        var name = "", addr = [String](repeating: "", count: 4), account = ""
        var balance = "", ytd = "", unapplied = "", creditLimit = "", unposted = ""
        var lines = [String](repeating: SLA.spaces(80), count: 100)
        var line21 = ""
        var sales: IndexedFile!, oi3: IndexedFile!, work: IndexedFile!
    }

    static func run(_ s: Session) throws {
        let w = WS()
        w.l0date = SLA.convertDate(s)
        if SLA.fileStatus(s, 19) != 1 {
            try SLA.maps99(s, 19)
            try SLA.maps99(s, 15)
            return
        }
        w.sales = SLA.salesFile(s); w.oi3 = SLA.openItemFile3(s)
        w.work = IndexedFile(s.store, path: s.ledgers + "work.tmp", layout: workLayout, keyLength: 11)
        if try !setUpWorkFile(s, w) { return }
        _ = w.sales.open(); _ = w.oi3.open(); _ = w.work.open()
        try enquiry(s, w)
        w.sales.close(); w.oi3.close(); w.work.close()
    }

    static func main001(_ s: Session) {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("sl020.title"), at: 131, color: 2)
        c.display(SLA.convertDate(s), at: 171, color: 2)
    }

    static func edit(_ pic: String, _ v: Int64, _ scale: Int = 2) -> String { Pic.edit(pic, value: v, scale: scale) }

    // MARK: enquiry section

    static func enquiry(_ s: Session, _ w: WS) throws {
        let c = s.console
        enquiry: while true {
            main001(s)
            let stars = String(repeating: "*", count: 40)
            c.display(stars, at: 241, color: 2)
            c.display(s.t("sl020.box1"), at: 341, color: 2)
            c.display(s.t("sl020.box2"), at: 441, color: 2)
            c.display(s.t("sl020.box3"), at: 541, color: 2)
            c.display(stars, at: 641, color: 2)
            var sales = Record(SLA.salesLayout)
            while true {
                w.customerIn = try c.accept(at: 351, size: 7, color: 3)
                if w.customerIn.allSatisfy({ $0 == " " }) { return }
                if c.crtStatus == 2005 { return }
                w.customerIn = Cobol.x(w.customerIn.uppercased(), 7)
                c.display(w.customerIn, at: 351, color: 3)
                w.account = w.customerIn
                w.invAmount = 0
                _ = w.sales.start(notLessThan: SJIS.encode(w.customerIn, size: 7))
                _ = w.oi3.start(notLessThan: SLA.oiKey(w.customerIn, 0))
                if w.workFileData != "N" { _ = w.work.start(notLessThan: SLA.oiKey(w.customerIn, 0)) }
                guard let r = w.sales.readNext(), r.str("sales-key") == w.customerIn else { continue }
                sales = r
                break
            }
            w.lines = [String](repeating: SLA.spaces(80), count: 100)
            w.name = sales.str("sales-name")
            // unstring sales-address delimited by sl-delim into address-line count a pointer a (pointer が残る)
            let address = Array(sales.str("sales-addr1") + sales.str("sales-addr2"))
            let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))
            var ptr = 1
            for i in 0..<4 {
                var part = ""
                if ptr >= 1 && ptr <= address.count {
                    var j = ptr - 1
                    while j < address.count && address[j] != delim { part.append(address[j]); j += 1 }
                    ptr = j < address.count ? j + 2 : j + 1
                }
                w.addr[i] = Cobol.x(Cobol.x(part, 36), 30)
            }
            c.display(Cobol.x(s.t("sl020.customer"), 10) + Cobol.x(w.name, 30), at: 201, color: 2)
            c.display(Cobol.x(s.t("sl020.address"), 10) + w.addr[0], at: 301, color: 2)
            c.display(SLA.spaces(10) + w.addr[1], at: 401, color: 2)
            c.display(SLA.spaces(10) + w.addr[2], at: 501, color: 2)
            c.display(SLA.spaces(10) + w.addr[3], at: 601, color: 2)
            w.balance = edit("z(6)9.99", sales.int("sales-current"))
            w.unapplied = edit("z(6)9.99", sales.int("sales-unapplied"))
            let ytd = sales.int("turnover-q1") + sales.int("turnover-q2") + sales.int("turnover-q3") + sales.int("turnover-q4")
            w.ytd = edit("z(7)9", Cobol.rescale(ytd, from: 2, to: 0), 0)
            w.creditLimit = edit("z(7)9", sales.int("sales-limit"), 0)
            getUnposted(w)
            c.display(w.balance, at: 370, color: 2)
            c.display(w.ytd, at: 451, color: 2)
            if sales.int("sales-unapplied") != 0 { c.display(w.unapplied, at: 470, color: 2) }
            c.display(w.creditLimit, at: 551, color: 2)
            if w.invAmount != 0 { c.display(w.unposted, at: 570, color: 2) }
            c.display(Cobol.x(s.t("sl020.col_number"), 6), at: 702, color: 2)
            c.display(Cobol.x(s.t("sl020.col_date"), 4), at: 714, color: 2)
            c.display(Cobol.x(s.t("sl020.col_desc"), 11), at: 724, color: 2)
            c.display(Cobol.x(s.t("sl020.col_invoiced"), 8), at: 746, color: 2)
            c.display(Cobol.x(s.t("sl020.col_paid"), 4), at: 763, color: 2)
            c.display(Cobol.x(s.t("sl020.col_balance"), 7), at: 773, color: 2)
            w.a = 0; w.b = 0; w.c = 0
            let screenSize = bodyLines * 80
            w.screenStart = 1; w.screenEnd = screenSize
            readOpenItems(s, w, sales.str("sales-key"))
            // end-statement
            statement: while true {
                // display line-7-19 (Screen-Start:Screen-End): 第 2 引数は長さ (レガシーの癖)
                let all = Array(w.lines.joined())
                var row = 8, pos = w.screenStart - 1
                let end = min(pos + w.screenEnd, all.count)
                while pos < end && row <= 24 {
                    c.display(String(all[pos..<min(pos + 80, end)]), at: row, 1, color: 2)
                    pos += 80; row += 1
                }
                w.b += bodyLines
                if w.a > w.b {
                    w.screenStart += screenSize
                    w.screenEnd += screenSize
                    if w.b > 100 {
                        w.b -= 100
                        w.screenEnd = 8000
                        w.c = bodyLines - w.b + 1
                        c.display(" ", at: w.c + 7, 1, eraseEOS: true)
                    }
                }
                c.display(line20(s), at: 21, 1, color: 2)
                w.line21 = edit("zz9", Int64(w.a), 0) + "  " + edit("zz,zzz,zz9.99", w.balT) + edit("z(6),zzz,zz9.99", w.bal0)
                    + edit("zzzz,zzz,zz9.99", w.bal30) + edit("zzzz,zzz,zz9.99", w.bal60) + edit("zzzz,zzz,zz9.99", w.bal90)
                c.display(w.line21, at: 22, 1, color: 2)
                while true {
                    c.display(s.t("sl020.select"), at: 24, 1, color: 2)
                    c.display(s.t(w.a > w.b ? "sl020.more_end" : "sl020.or_end"), at: 24, 55, color: 2)
                    var s1 = ""
                    while true {
                        let col = w.a > w.b ? 72 : 65
                        s1 = try c.accept(at: 24, col, size: 1, initial: " ", options: [.update, .auto], color: 6).uppercased()
                        if c.crtStatus == 2005 || s1 == "E" { return }
                        if ["M", "P", "N", "T"].contains(s1) { break }
                    }
                    if s1 == "M" { continue statement }
                    if s1 == "P" { printScreen(s, w); continue }
                    if s1 == "N" {
                        w.bal0 = 0; w.bal30 = 0; w.bal60 = 0; w.bal90 = 0; w.balT = 0
                        continue enquiry
                    }
                    try setQueryFlag(s, w)
                }
            }
        }
    }

    static func line20(_ s: Session) -> String {
        func r(_ k: String, _ n: Int) -> String { Cobol.x(s.l10n.raw(k), n) }
        return r("report.sl020.inv_no", 7) + r("report.sl020.total_os", 9) + SLA.spaces(11) + r("report.sl020.current", 7)
            + SLA.spaces(11) + "30" + SLA.spaces(13) + "60" + SLA.spaces(12) + "90+"
    }

    static func setLine(_ w: WS, _ a: Int, _ from: Int, _ text: String) {
        var l = Array(w.lines[a - 1])
        let t = Array(text)
        for i in 0..<t.count where from - 1 + i < 80 { l[from - 1 + i] = t[i] }
        w.lines[a - 1] = String(l)
    }

    static func readOpenItems(_ s: Session, _ w: WS, _ salesKey: String) {
        while var oi = w.oi3.readNext() {
            if oi.str("oi-customer") != salesKey { break }
            w.a += 1
            let type = oi.int("oi-type")
            if w.a > 100 {
                setLine(w, 100, 23, Cobol.x(">> screen overflow <<", 19))
                w.a = 100
            } else {
                if type == 5 || type == 6 { oi.setInt("oi-invoice", 0) }
                let inv = Cobol.truncate(oi.int("oi-invoice"), digits: 8, signed: false)
                setLine(w, w.a, 1, inv == 0 ? SLA.spaces(8) : edit("z(7)9", inv, 0))
                setLine(w, w.a, 12, Cobol.x(SLA.convertBin(s, oi.int("oi-date")), 11))
                if oi.str("oi-hold-flag") != " " { setLine(w, w.a, 10, "Q") }
                var desc = [Character](repeating: " ", count: 20)
                var p = 1
                switch type {
                case 1: SLA.string(s.l10n.raw("report.sl020.receipt"), into: &desc, pointer: &p)
                case 2: SLA.string(s.l10n.raw("report.sl020.goods") + SLA.delimited(oi.str("oi-description")), into: &desc, pointer: &p)
                case 3: SLA.string(s.l10n.raw("report.sl020.cn") + edit("z(7)9", Cobol.truncate(oi.int("oi-cr"), digits: 8, signed: false), 0), into: &desc, pointer: &p)
                case 5: SLA.string(s.l10n.raw("report.sl020.payment"), into: &desc, pointer: &p)
                case 6: SLA.string(s.l10n.raw("report.sl020.journal"), into: &desc, pointer: &p)
                default: break
                }
                setLine(w, w.a, 23, String(desc.prefix(19)))
            }
            // item-comp-1
            w.invAmount = oi.int("oi-net") + oi.int("oi-extra") + oi.int("oi-carriage") + oi.int("oi-vat") + oi.int("oi-discount")
                + oi.int("oi-e-vat") + oi.int("oi-deduct-amt") + oi.int("oi-deduct-vat") + oi.int("oi-c-vat")
            var paid = oi.int("oi-paid")
            if type == 3 { paid = -paid }
            if type == 2 || type == 3 { w.amountOut = w.invAmount - paid }
            // (a > 100 は上で 100 に戻されるためレガシーでもここは通らない)
            if type == 2 || type == 3 { setLine(w, w.a, 68, edit("zz,zzz,zz9.99", w.amountOut)) }
            setLine(w, w.a, 42, edit("zz,zzz,zz9.99", w.invAmount))
            setLine(w, w.a, 55, edit("zz,zzz,zz9.99", paid))
            if type == 1 {
                setLine(w, w.a, 55, edit("zz,zzz,zz9.99", w.invAmount))
                setLine(w, w.a, 68, edit("zz,zzz,zz9.99", 0))
                continue
            }
            if type == 5 || type == 6 {
                setLine(w, w.a, 68, edit("zz,zzz,zz9.99", 0))
                setLine(w, w.a, 42, edit("zz,zzz,zz9.99", 0))
                continue
            }
            // calc-age
            let work1 = s.sys.int("run-date") - oi.int("oi-date")
            if work1 < 30 { w.bal0 += w.amountOut } else if work1 < 60 { w.bal30 += w.amountOut }
            else if work1 < 90 { w.bal60 += w.amountOut } else { w.bal90 += w.amountOut }
            w.balT += w.amountOut
        }
    }

    // MARK: print-screen section

    static func printScreen(_ s: Session, _ w: WS) {
        let p = SLA.Printer(s, recLen: 80)
        func r(_ k: String, _ n: Int) -> String { Cobol.x(s.l10n.raw(k), n) }
        let stars = String(repeating: "*", count: 40)
        let line0 = Cobol.x(progName, 15) + SLA.spaces(15) + r("report.sl020.title", 20) + SLA.spaces(20) + Cobol.x(w.l0date, 10)
        func heads1() {
            p.after(1, r("report.sl020.customer", 10) + Cobol.x(w.name, 30) + stars)
            p.after(1, r("report.sl020.address", 10) + w.addr[0] + r("report.sl020.ac_nos", 10) + Cobol.x(w.account, 8)
                + r("report.sl020.balance", 11) + w.balance + "*")
            p.after(1, SLA.spaces(10) + w.addr[1] + r("report.sl020.ytd", 10) + w.ytd + r("report.sl020.unapplied", 11) + w.unapplied + "*")
            p.after(1, SLA.spaces(10) + w.addr[2] + r("report.sl020.credit", 10) + w.creditLimit + r("report.sl020.unposted", 11) + w.unposted + "*")
            p.after(1, SLA.spaces(10) + w.addr[3] + stars)
            p.after(1, " " + r("report.sl020.col_number", 6) + SLA.spaces(6) + r("report.sl020.col_date", 4) + SLA.spaces(6)
                + r("report.sl020.col_desc", 11) + SLA.spaces(12) + r("report.sl020.col_invoiced", 8) + SLA.spaces(9)
                + r("report.sl020.col_paid", 4) + SLA.spaces(6) + r("report.sl020.col_balance", 7))
        }
        p.open()
        p.after(1, line0)
        heads1()
        var l = 1
        while l <= w.a {
            p.after(1, w.lines[l - 1])
            if l == 59 { p.afterPage(line0); heads1() }
            l += 1
        }
        p.after(2, line20(s))
        p.after(2, w.line21)
        p.close()
    }

    // MARK: set-up-work-file section

    /// 戻り値 false = 書き込みエラーで menu-exit
    static func setUpWorkFile(_ s: Session, _ w: WS) throws -> Bool {
        let c = s.console
        main001(s)
        var lin = 14, cole = 0, a = 0
        if s.sys.int("s-flag-i") == 1 {
            w.work.openOutput()
            let inv = SLA.invoiceFile(s)
            if inv.open() != "00" {
                w.work.close(); inv.close()
                return true
            }
            inv.startFirst()
            while let ih = inv.readNext() {
                if ih.int("ih-test") != 0 { continue }
                if ih.str("ih-status") == "z" { continue }
                let type = ih.int("ih-type")
                if type == 1 || type == 4 { continue }
                var rec = Record(workLayout)
                rec.setInt("work-invoice", ih.int("ih-invoice"))
                rec["work-customer"] = ih.str("ih-customer")
                var amount = ih.int("ih-net") + ih.int("ih-extra") + ih.int("ih-carriage") + ih.int("ih-discount") + ih.int("ih-vat")
                    + ih.int("ih-c-vat") + ih.int("ih-e-vat") + ih.int("ih-deduct-amt") + ih.int("ih-deduct-vat")
                if type == 3 { amount = -amount }
                rec.setInt("work-amount", amount)
                if w.work.write(rec) != "00" {
                    c.display(s.t("sl020.sl111"), at: 24, 1, color: 4)
                    _ = try c.accept(at: 24, 53, size: 1, color: 6)
                    inv.close(); w.work.close()
                    return false
                }
                a += 1
                if a > 9 {
                    a = 0; cole += 1
                    c.display(".", at: lin, cole, color: 2)
                }
                if cole > 79 { lin += 1; cole = 0 }
            }
            inv.close(); w.work.close()
        }
        if lin == 14 && cole == 0 && a == 0 {
            c.display(s.t("sl020.sl117"), at: 1801, color: 2)
        } else {
            w.workFileData = "Y"
            c.display(s.t("sl020.sl118"), at: 1801, color: 2)
        }
        return true
    }

    // MARK: get-unposted section

    static func getUnposted(_ w: WS) {
        if w.workFileData != "N" {
            while let r = w.work.readNext() {
                if r.str("work-customer") != w.customerIn { break }
                w.invAmount += r.int("work-amount")
            }
        }
        w.unposted = edit("z(6)9.99", w.invAmount)
    }

    // MARK: set-query-flag section

    static func setQueryFlag(_ s: Session, _ w: WS) throws {
        let c = s.console
        c.display(s.t("sl020.toggle"), at: 23, 1, color: 2)
        c.display(w.customerIn, at: 23, 14, color: 3)
        let tinv = Cobol.moveNumeric(try c.accept(at: 23, 51, size: 8, kind: .numeric, color: 3), digits: 8, scale: 0)
        if tinv == 0 { return }
        c.display(" ", at: 23, 1, eraseEOL: true)
        w.oi3.close()
        var err: String?
        if w.oi3.open() != "00" {
            err = "sl020.sl112"
        } else if var oi = w.oi3.read(key: SLA.oiKey(w.customerIn, tinv)) {
            if oi.int("oi-invoice") != tinv || oi.str("oi-customer") != w.customerIn {
                err = "sl020.sl114"
            } else {
                oi["oi-hold-flag"] = oi.str("oi-hold-flag") == " " ? "Q" : " "
                if w.oi3.rewrite(oi) != "00" { err = "sl020.sl115" }
            }
        } else {
            err = "sl020.sl113"
        }
        if let e = err {
            c.display(s.t(e), at: 23, 1, color: 4)
            c.display(s.t("sl020.sl116"), at: 24, 1, color: 2, eraseEOL: true)
            _ = try c.accept(at: 24, 34, size: 1)
            c.display(" ", at: 23, 1, eraseEOS: true)
        }
        w.oi3.close()
        _ = w.oi3.open()
    }
}
