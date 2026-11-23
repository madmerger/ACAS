import Foundation

/// pl140.cbl: 仕入日計帳 (Purchase Ledger Day Book)
enum PLB140 {
    static let progName = "PL140 (3.01.07)"

    final class State {
        let s: Session
        let prt: PLBPrint
        var headType = 0, j = 0, lineCnt = 0
        var l1Date = ""
        // group-totals (1...4): gds, car, ded, net, vat, grs
        var gds = [Int64](repeating: 0, count: 5), car = [Int64](repeating: 0, count: 5), ded = [Int64](repeating: 0, count: 5)
        var net = [Int64](repeating: 0, count: 5), vat = [Int64](repeating: 0, count: 5), grs = [Int64](repeating: 0, count: 5)
        init(_ s: Session) { self.s = s; prt = PLBPrint(s) }
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let st = State(s)
        st.l1Date = PLB.wsDate(s)
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("pl140.title"), at: 136, color: 2)
        c.display(st.l1Date, at: 171, color: 2)
        let inv = PLB.pinvoiceFile(s), pf = PLB.purchFile(s)
        if inv.open() != "00" { return }
        if pf.open() != "00" { inv.close(); return }
        st.prt.openOutput()
        c.display(s.t("pl140.printing"), at: 1212, color: 2)
        st.j = 0
        headings(st)
        var purchName = Cobol.x("", 30)
        func add(_ a: inout [Int64], _ z: Int, _ v: Int64) {
            if z >= 1 && z <= 4 { a[z] = Cobol.truncate(a[z] + v, digits: 10) }
            a[4] = Cobol.truncate(a[4] + v, digits: 10)
        }
        while let ih = inv.readNext() {
            if ih.int("ih-test") != 0 { continue }          // item-nos
            let type = Int(ih.int("ih-type"))
            if type > 3 { continue }
            let flag = ih.str("ih-day-book-flag").uppercased(), status = ih.str("ih-status").uppercased()
            if flag == "B" || status != "Z" { continue }
            if st.lineCnt > Int(s.sys.int("page-lines")) { headings(st) }
            if let p = pf.read(key: ih.raw("ih-supplier")) { purchName = p.str("purch-name") }
            let deduct = ih.int("ih-deduct-amt")
            let sign: Int64 = type == 3 ? -1 : 1
            let v = ih.int("ih-vat") * sign, cv = ih.int("ih-c-vat") * sign
            let n = ih.int("ih-net") * sign, ca = ih.int("ih-carriage") * sign
            let typeText = s.l10n.raw(type == 1 ? "report.pl140.receipt" : type == 2 ? "report.pl140.invoice" : "report.pl140.cr_note")
            let line5 = Pic.edit("z(7)9", value: ih.int("ih-invoice"), scale: 0) + " "
                + Cobol.x(PLB.binDate(s, ih.int("ih-date")), 10) + " " + Cobol.x(ih.str("ih-supplier"), 8)
                + Cobol.x(purchName, 25) + "   " + Cobol.x(typeText, 11) + "      "
                + Pic.edit("z(6)9.99cr", value: Cobol.truncate(n + ca, digits: 9), scale: 2)
                + Pic.edit("z(6)9.99cr", value: Cobol.truncate(v + cv, digits: 9), scale: 2)
                + Pic.edit("z(6)9.99cr", value: Cobol.truncate(v + cv + n + ca, digits: 9), scale: 2)
                + "     " + PLB.bwz("z(6)9.99cr", deduct, scale: 2)
            add(&st.gds, type, n)
            add(&st.ded, type, deduct)
            add(&st.car, type, ca)
            var work1 = Cobol.truncate(v + cv, digits: 10)
            add(&st.vat, type, work1)
            work1 = Cobol.truncate(n + ca, digits: 10)
            add(&st.net, type, work1)
            work1 = Cobol.truncate(work1 + v + cv, digits: 10)
            add(&st.grs, type, work1)
            st.prt.after(line5, 1)
            st.lineCnt = PLB.addChar(st.lineCnt, 1)
        }
        pf.close(); inv.close()
        st.headType = 1
        headings(st)
        st.prt.after(Cobol.x("", 23) + s.l10n.raw("report.pl140.line7"), 2)
        st.prt.after("", 1)
        let lits = ["report.pl140.receipts", "report.pl140.invoices", "report.pl140.credit_notes", "report.pl140.total"]
        for z in 1...4 {
            func m(_ v: Int64) -> String { Pic.edit("z(7)9.99cr", value: v, scale: 2) }
            st.prt.after(Cobol.x(s.l10n.raw(lits[z - 1]), 17) + m(st.gds[z]) + m(st.car[z]) + m(st.net[z])
                         + m(st.vat[z]) + m(st.grs[z]) + m(st.ded[z]), 1)
        }
        st.prt.close()
        st.prt.spool()
    }

    static func headings(_ st: State) {
        let s = st.s
        st.j = (st.j + 1) % 1000
        let line1 = Cobol.x(progName, 54) + Cobol.x(s.l10n.raw("report.pl140.title"), 70)
            + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(st.j), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 62) + Cobol.x("", 60) + Cobol.x(st.l1Date, 10)
        if st.j != 1 {
            st.prt.afterPage(line1)
            st.prt.after(line2, 1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
            st.prt.before(line2, 1)
        }
        st.lineCnt = 2
        if st.headType == 0 {
            st.lineCnt += 3
            st.prt.after(Cobol.x(s.l10n.raw("report.pl140.line4a"), 74) + s.l10n.raw("report.pl140.line4b"), 2)
            st.prt.after("", 1)
        }
    }
}
