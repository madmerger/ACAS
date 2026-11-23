import Foundation

extension PLA {
    /// 行順編成の print-file への WRITE ... AFTER ADVANCING
    struct Printer {
        let s: Session
        let path: String
        init(_ s: Session, path: String? = nil) { self.s = s; self.path = path ?? PLA.printPath(s) }
        func openOutput() { s.store.writeRaw(path, []) }
        func write(_ line: String, after n: Int) {
            s.store.appendRaw(path, [UInt8](repeating: 0x0a, count: n) + Array(Cobol.rtrim(line).utf8))
        }
        func writePage(_ line: String) {
            s.store.appendRaw(path, [0x0c] + Array(Cobol.rtrim(line).utf8))
        }
        func writeBefore(_ line: String, before n: Int) {
            s.store.appendRaw(path, Array(Cobol.rtrim(line).utf8) + [UInt8](repeating: 0x0a, count: n))
        }
        /// close + call "SYSTEM" using Print-Report
        func closeAndSpool() { s.onReport?(path) }
    }

    /// 符号なし編集項目への MOVE (絶対値・上位桁切り捨て)
    static func ed(_ pic: String, _ v: Int64, int: Int, scale: Int = 2) -> String {
        var m: Int64 = 1
        for _ in 0..<(int + scale) { m *= 10 }
        return Pic.edit(pic, value: abs(v) % m, scale: scale)
    }
}

/// purchase/pl015.cbl: 買掛元帳照会
final class PLA015 {
    static let progName = "PL015 (3.01.07)"
    static func run(_ s: Session) throws { try PLA015(s).main() }

    let s: Session
    var c: Console { s.console }
    let purchase: IndexedFile, oi5: IndexedFile, work: IndexedFile
    static let workLayout = Layout("work-record", [("work-supplier", .x(7)), ("work-invoice", PLA.bl), ("work-amount", PLA.money(10))])

    var a = 0, b = 0
    var bodyLines = 13
    var screenSize = 0, screenStart = 1, screenEnd = 0
    var invAmount: Int64 = 0, amountOut: Int64 = 0
    var customerIn = ""
    var workFileData = false
    var bal0: Int64 = 0, bal30: Int64 = 0, bal60: Int64 = 0, bal90: Int64 = 0, balT: Int64 = 0
    var l1Name = "", l2Address = "", l3Address = "", l4Address = "", l5Address = ""
    var l2Account = "", l2Balance = "", l3Ytd = "", l3Unapplied = "", l4Credit = "", l4Unposted = ""
    var rows = [String](repeating: String(repeating: " ", count: 80), count: 100)
    var line21 = String(repeating: " ", count: 79)

    init(_ s: Session) {
        self.s = s
        purchase = PLA.purchaseFile(s); oi5 = PLA.openItem5(s)
        work = IndexedFile(s.store, path: s.ledgers + "work.tmp", layout: PLA015.workLayout, keyLength: 11)
        l2Balance = Cobol.x("", 10); l3Ytd = Cobol.x("", 7); l3Unapplied = Cobol.x("", 9); l4Credit = Cobol.x("", 7); l4Unposted = Cobol.x("", 10)
        l2Account = Cobol.x("", 7)
    }

    func main() throws {
        if PLA.fileStatus(s, 29) != 1 {
            try PLA.maps99(s, 25)
            try PLA.maps99(s, 15)
            return
        }
        if try !setUpWorkFile() { return }
        _ = purchase.open(); _ = oi5.open(); _ = work.open()
        try enquiry()
        purchase.close(); oi5.close(); work.close()
    }

    func main001() {
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA015.progName, at: 101, color: 2)
        c.display(s.t("pl015.title"), at: 129, color: 2)
        c.display(PLA.toDayDisplay(s), at: 171, color: 2)
    }

    func key(_ supplier: String, _ invoice: Int64) -> [UInt8] {
        var r = Record(PLA015.workLayout)
        r.set("work-supplier", supplier); r.setInt("work-invoice", invoice)
        return Array(r.bytes[0..<11])
    }

    // MARK: enquiry section

    func enquiry() throws {
        enquiry: while true {
            main001()
            c.display("****************************************", at: 241, color: 2)
            c.display(s.t("pl015.box_acnos"), at: 341, color: 2)
            c.display(s.t("pl015.box_ytd"), at: 441, color: 2)
            c.display(s.t("pl015.box_credit"), at: 541, color: 2)
            c.display("****************************************", at: 641, color: 2)
            var purch: Record
            while true {
                // main-display-end
                customerIn = try c.accept(at: 351, size: 7, color: 3)
                if Cobol.rtrim(customerIn).isEmpty { return }
                if c.crtStatus == 2005 { return }
                customerIn = customerIn.uppercased()
                c.display(customerIn, at: 351, color: 3)
                l2Account = customerIn
                invAmount = 0
                let okP = purchase.start(notLessThan: SJIS.encode(customerIn, size: 7))
                _ = oi5.start(notLessThan: key(customerIn, 0))
                if workFileData { _ = work.start(notLessThan: key(customerIn, 0)) }
                // read-sales
                guard okP, let p = purchase.readNext(), p.str("purch-key") == customerIn else { continue }
                purch = p
                break
            }
            rows = [String](repeating: String(repeating: " ", count: 80), count: 100)
            l1Name = purch.str("purch-name")
            var ptr = 1
            let addr = Array(purch.str("purch-address"))
            let delim = s.sys.str("pl-delim").first ?? " "
            l2Address = Cobol.x(PLA.unstring(addr, delim: delim, pointer: &ptr, size: 36), 30)
            l3Address = Cobol.x(PLA.unstring(addr, delim: delim, pointer: &ptr, size: 36), 30)
            l4Address = Cobol.x(PLA.unstring(addr, delim: delim, pointer: &ptr, size: 36), 30)
            l5Address = Cobol.x(PLA.unstring(addr, delim: delim, pointer: &ptr, size: 36), 30)
            c.display(s.t("pl015.supplier") + l1Name, at: 201, color: 2)
            c.display(s.t("pl015.address") + l2Address, at: 301, color: 2)
            c.display(Cobol.x("", 10) + l3Address, at: 401, color: 2)
            c.display(Cobol.x("", 10) + l4Address, at: 501, color: 2)
            c.display(Cobol.x("", 10) + l5Address, at: 601, color: 2)
            l2Balance = PLA.ed("z(6)9.99", purch.int("purch-current"), int: 7)
            l3Unapplied = PLA.ed("z(5)9.99", purch.int("purch-unapplied"), int: 6)
            let ytd = purch.int("turnover-q1") + purch.int("turnover-q2") + purch.int("turnover-q3") + purch.int("turnover-q4")
            l3Ytd = PLA.ed("z(6)9", Cobol.rescale(ytd, from: 2, to: 0), int: 7, scale: 0)
            l4Credit = PLA.ed("z(6)9", purch.int("purch-limit"), int: 7, scale: 0)
            getUnposted()
            c.display(l2Balance, at: 369, color: 3)
            c.display(l3Ytd, at: 451, color: 3)
            if purch.int("purch-unapplied") != 0 { c.display(l3Unapplied, at: 470, color: 3) }
            c.display(l4Credit, at: 551, color: 3)
            if invAmount != 0 { c.display(l4Unposted, at: 569, color: 3) }
            c.display(s.t("pl015.line6"), at: 701, color: 2)
            a = 0; b = 0
            screenSize = bodyLines * 80
            screenStart = 1
            screenEnd = screenSize
            readOpenItems(purch)

            var redisplay = true
            statement: while true {
                if redisplay {
                    // end-statement
                    displayBody()
                    b += bodyLines
                    if a > b {
                        screenStart += screenSize
                        screenEnd += screenSize
                        if b > 100 {
                            b -= 100
                            screenEnd = 8000
                            let l = (bodyLines - b + 1) + 7
                            c.display(" ", at: l, 1, eraseEOS: true)
                        }
                    }
                    // disp-totals
                    c.display(s.t("pl015.line20"), at: 21, 1, color: 2)
                    line21 = Cobol.x("", 5) + PLA.ed("zz,zzz,zz9.99", balT, int: 8) + PLA.ed("z(6),zzz,zz9.99", bal0, int: 8)
                        + PLA.ed("zzzz,zzz,zz9.99", bal30, int: 8) + PLA.ed("zzzz,zzz,zz9.99", bal60, int: 8) + PLA.ed("zzzz,zzz,zz9.99", bal90, int: 8)
                    c.display(line21, at: 22, 1, color: 2)
                }
                redisplay = false
                // es-disp
                c.display(s.t("pl015.select"), at: 24, 1, color: 2)
                c.display(s.t(a > b ? "pl015.more_or_end" : "pl015.or_end"), at: 24, 55, color: 2)
                while true {
                    // es-accept
                    let cole = a > b ? 72 : 65
                    let s1 = try c.accept(at: 24, cole, size: 1, initial: " ", options: [.update, .auto], color: 6).uppercased()
                    if c.crtStatus == 2005 { return }
                    if s1 == "E" { return }
                    if s1 == "M" { redisplay = true; continue statement }
                    if s1 == "P" { printScreen(); continue statement }
                    if s1 == "N" {
                        bal0 = 0; bal30 = 0; bal60 = 0; bal90 = 0; balT = 0
                        continue enquiry
                    }
                    if s1 == "T" { try setQueryFlag(); continue statement }
                }
            }
        }
    }

    func setRow(_ i: Int, _ off: Int, _ text: String) {
        var r = Array(rows[i - 1])
        for (k, ch) in Array(text).enumerated() where off + k < 80 { r[off + k] = ch }
        rows[i - 1] = String(r)
    }

    func readOpenItems(_ purch: Record) {
        let runDate = s.sys.int("run-date")
        while let rec = oi5.readNext() {
            if rec.str("oi-supplier") != purch.str("purch-key") { break }
            var oi = rec
            a += 1
            if a > 100 {
                setRow(100, 22, Cobol.x(s.l10n.raw("pl015.screen_overflow"), 22))
                a = 100
            } else {
                if oi.int("oi-type") == 5 || oi.int("oi-type") == 6 { oi.setInt("oi-invoice", 0) }
                let inv = oi.int("oi-invoice")
                setRow(a, 0, inv == 0 ? Cobol.x("", 8) : PLA.ed("z(7)9", inv, int: 8, scale: 0))
                setRow(a, 11, Cobol.x(PLA.dateDisplay(s, oi.int("oi-date")), 11))
                if oi.str("oi-hold-flag") != " " { setRow(a, 9, "H") }
                var desc = ""
                switch oi.int("oi-type") {
                case 1: desc = s.l10n.raw("pl015.desc_receipt")
                case 2:
                    var ref = oi.str("oi-ref")
                    if let r = ref.range(of: "  ") { ref = String(ref[..<r.lowerBound]) }
                    desc = s.l10n.raw("pl015.desc_goods") + ref
                case 3: desc = s.l10n.raw("pl015.desc_cn") + PLA.ed("z(7)9", oi.int("oi-cr"), int: 8, scale: 0)
                case 5: desc = s.l10n.raw("pl015.desc_payment")
                case 6: desc = s.l10n.raw("pl015.desc_journal")
                default: break
                }
                setRow(a, 22, Cobol.x(Cobol.x(desc, 20), 22))
            }
            // item-comp-1
            let type = oi.int("oi-type")
            invAmount = oi.int("oi-net") + oi.int("oi-carriage") + oi.int("oi-vat") + oi.int("oi-c-vat")
            if type == 2 && oi.int("oi-deduct-amt") != 0 {
                setRow(a, 8, "P")
                if oi.int("oi-date") + oi.int("oi-deduct-days") >= runDate { invAmount -= oi.int("oi-deduct-amt") }
            }
            var paid = oi.int("oi-paid")
            if type == 3 { paid = -paid }
            if type == 2 || type == 3 { amountOut = invAmount - paid }
            let e = { (v: Int64) in PLA.ed("zzzzz,zz9.99", v, int: 8) }
            if type == 2 || type == 3 { self.setRow(a, 68, e(amountOut)) }
            setRow(a, 44, e(invAmount))
            setRow(a, 56, e(paid))
            if type == 1 {
                setRow(a, 44, e(invAmount)); setRow(a, 56, e(invAmount)); setRow(a, 68, e(0))
                continue
            }
            if type == 5 || type == 6 {
                setRow(a, 68, e(0)); setRow(a, 44, e(0))
                continue
            }
            // calc-age
            let work1 = runDate - oi.int("oi-date")
            if work1 < 30 { bal0 += amountOut } else if work1 < 60 { bal30 += amountOut } else if work1 < 90 { bal60 += amountOut } else { bal90 += amountOut }
            balT += amountOut
        }
    }

    /// display line-7-19 (Screen-Start:Screen-End) at 0801 — 第 2 引数は「長さ」として働く (レガシーの癖)
    func displayBody() {
        var mem = Array(rows.joined())
        mem += Array(Cobol.x(s.t("pl015.line20"), 77)) + Array(Cobol.x(line21, 79))
        var line = 8
        var pos = screenStart - 1
        var remain = screenEnd
        while line <= 24 && remain > 0 {
            let n = min(80, remain)
            var seg = [Character](repeating: " ", count: n)
            for k in 0..<n where pos + k < mem.count { seg[k] = mem[pos + k] }
            c.display(String(seg), at: line, 1, color: 2)
            pos += n; remain -= n; line += 1
        }
    }

    // MARK: print-screen section

    func printScreen() {
        let p = PLA.Printer(s)
        p.openOutput()
        let line0 = Cobol.x(PLA015.progName, 16) + Cobol.x("", 13) + s.t("pl015.title") + Cobol.x("", 18) + Cobol.x(PLA.toDayDisplay(s), 10)
        p.write(line0, after: 1)
        let stars = String(repeating: "*", count: 40)
        func heads1() {
            p.write(s.t("pl015.supplier") + l1Name + stars, after: 1)
            p.write(s.t("pl015.address") + l2Address + s.t("pl015.prt_acno") + l2Account + "]" + s.t("pl015.prt_balance") + l2Balance + "]*", after: 1)
            p.write(Cobol.x("", 10) + l3Address + s.t("pl015.prt_ytd") + l3Ytd + s.t("pl015.prt_unapplied") + l3Unapplied + "]*", after: 1)
            p.write(Cobol.x("", 10) + l4Address + s.t("pl015.prt_credit") + l4Credit + s.t("pl015.prt_unposted") + l4Unposted + "]*", after: 1)
            p.write(Cobol.x("", 10) + l5Address + stars, after: 1)
            p.write(s.t("pl015.line6"), after: 1)
        }
        heads1()
        var l = 1
        while l <= a {
            p.write(rows[l - 1], after: 1)
            if l == 59 {
                p.writePage(line0)
                heads1()
            }
            l += 1
        }
        p.write(s.t("pl015.line20"), after: 2)
        p.write(line21, after: 2)
        p.closeAndSpool()
    }

    // MARK: set-up-work-file section

    /// false = menu-exit (書込エラー)
    func setUpWorkFile() throws -> Bool {
        main001()
        c.display(s.t("pl015.creating_work"), at: 1201, color: 2)
        var lin = 14, cole = 0, n = 0
        if s.sys.int("p-flag-i") == 1 {
            work.openOutput()
            let invoice = PLA.invoiceFile(s)
            if invoice.open() != "00" {
                work.close(); invoice.close()
                return true
            }
            invoice.startFirst()
            while let ih = invoice.readNext() {
                if ih.int("ih-test") != 0 { continue }
                if ih.str("ih-status") == "z" { continue }
                if ih.int("ih-type") == 1 || ih.int("ih-type") == 4 { continue }
                var w = Record(PLA015.workLayout)
                w.setInt("work-invoice", ih.int("ih-invoice"))
                w.set("work-supplier", ih.str("ih-supplier"))
                var amt = ih.int("ih-net") + ih.int("ih-carriage") + ih.int("ih-vat") + ih.int("ih-c-vat")
                if ih.int("ih-type") == 3 { amt = -amt }
                w.setInt("work-amount", amt)
                if work.write(w) != "00" {
                    c.display(s.t("pl015.pl111"), at: 24, 1, color: 4)
                    _ = try c.accept(at: 24, 53, size: 1, color: 6)
                    invoice.close(); work.close()
                    return false
                }
                n += 1
                if n > 9 {
                    n = 0
                    cole += 1
                    c.display(".", at: lin, cole, color: 3)
                }
                if cole > 79 { lin += 1; cole = 0 }
            }
            invoice.close(); work.close()
        }
        // eof-test
        if lin == 14 && cole == 0 && n == 0 {
            c.display(s.t("pl015.pl117"), at: 1801, color: 2)
        } else {
            workFileData = true
            c.display(s.t("pl015.pl118"), at: 1801, color: 2)
        }
        return true
    }

    func getUnposted() {
        if workFileData {
            while let w = work.readNext() {
                if customerIn != w.str("work-supplier") { break }
                invAmount += w.int("work-amount")
            }
        }
        l4Unposted = PLA.ed("z(6)9.99", invAmount, int: 7)
    }

    // MARK: set-query-flag section

    func setQueryFlag() throws {
        c.display(s.t("pl015.toggle_prompt"), at: 23, 1, color: 2)
        c.display(customerIn, at: 23, 14, color: 3)
        let tinv = Int64(try c.accept(at: 23, 51, size: 8, kind: .numeric, initial: "00000000", options: [.update], color: 3)) ?? 0
        if tinv == 0 { return }
        c.display(" ", at: 23, 1, eraseEOL: true)
        oi5.close()
        var errKey: String?
        var errColor: UInt8 = 4
        if oi5.open() != "00" {
            errKey = "pl015.pl112"
        } else if var oi = oi5.read(key: key(customerIn, tinv)) {
            if oi.int("oi-type") != 2 {
                errKey = "pl015.pl119"; errColor = 2
            } else {
                oi.set("oi-hold-flag", oi.str("oi-hold-flag") == " " ? "H" : " ")
                if oi5.rewrite(oi) != "00" { errKey = "pl015.pl115" }
            }
        } else {
            errKey = "pl015.pl113"
        }
        if let k = errKey {
            c.display(s.t(k), at: 23, 1, color: errColor)
            c.display(s.t("pl015.pl116"), at: 24, 1, color: 2)
            _ = try c.accept(at: 24, 34, size: 1, color: 6)
            c.display(" ", at: 23, 1, eraseEOL: true)
        }
        oi5.close()
        _ = oi5.open()
    }
}
