import Foundation

/// pl190.cbl: 仕入先マスタダンプ (Purchase Ledger Dump)
enum PLB190 {
    static let progName = "PL190 (3.01.04)"

    final class State {
        let s: Session
        let prt: PLBPrint
        let pf: IndexedFile
        let sel = PLB.Selection()
        var a = 0, z = 0, recCnt = 0
        var l3Date = ""
        var l3Report = PLB.Buf(70)
        var line4 = PLB.Buf(131)
        init(_ s: Session) { self.s = s; prt = PLBPrint(s); pf = PLB.purchFile(s) }
    }

    static func run(_ s: Session) throws {
        let st = State(s), sel = st.sel
        st.l3Date = PLB.wsDate(s)
        // report-selection
        let purchOpen = st.pf.open() == "00"
        try PLB160.screen(s, progName: progName, sel: sel, display: true, titleKey: "pl190.suppler_file", withDate: false)
        while true {
            try PLB160.screen(s, progName: progName, sel: sel, display: false, titleKey: "pl190.suppler_file", withDate: false)
            sel.customerIn = Cobol.x(sel.custIn.uppercased(), 7)      // supplier-in
            sel.statusIn = sel.statusIn.uppercased()
            if !["L", "D", " "].contains(sel.statusIn) { continue }
            sel.creditOp = sel.creditOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.creditOp) { continue }
            sel.invoiceOp = sel.invoiceOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.invoiceOp) { continue }
            sel.averageOp = sel.averageOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.averageOp) { continue }
            sel.overdueOp = sel.overdueOp.uppercased()
            if !["L", "G", "E", " "].contains(sel.overdueOp) { continue }
            break
        }
        // report-heading-setup: Keys Matching は supplier-in (7 桁)
        let saved = sel.custIn
        sel.custIn = sel.customerIn
        st.l3Report = PLB160.headingSetup(s, sel, overdueKey: "days_overdue_190")
        sel.custIn = saved
        try produceReport(st, purchOpen: purchOpen)
    }

    static func produceReport(_ st: State, purchOpen: Bool) throws {
        let s = st.s, sel = st.sel
        st.prt.openOutput()
        st.a = 0; st.z = 0
        headings1(st)
        var supplierIn = Array(sel.customerIn.utf8)
        let blank = supplierIn.allSatisfy { $0 == 0x20 }
        if !blank {
            if st.pf.read(key: supplierIn) == nil { st.a = 1 }
            supplierIn = supplierIn.map { $0 == 0x20 ? 0xff : $0 }
        }
        // 開けていない purchase-file の READ NEXT は AT END にならず戻らない
        if !purchOpen { try PLB.hang(s) }
        while let rec = st.pf.readNext() {
            let key = rec.raw("purch-key")
            if !blank && supplierIn.lexicographicallyPrecedes(key) { break }
            if !blank {
                // test-array: 空白以外の桁 (置換後は全桁) が一致すること
                var truth = true
                for y in 0..<6 where supplierIn[y] != 0x20 && supplierIn[y] != key[y] { truth = false }
                if !truth { continue }
            }
            if !PLB160.matches(s, sel, rec) { continue }
            listing(st, rec)
        }
        st.prt.close()
        st.pf.close()
        if st.recCnt != 0 { st.prt.spool() }
    }

    static func headings1(_ st: State) {
        let s = st.s
        st.a = (st.a + 1) % 1000
        let line1 = Cobol.x(progName, 57) + Cobol.x(s.l10n.raw("report.pl190.title"), 67)
            + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(st.a), scale: 0)
        if st.a != 1 {
            st.prt.afterPage(line1)
            st.prt.after("", 1)
        } else {
            st.prt.before(line1, 1)
        }
        st.prt.after(Cobol.x(s.sys.str("usera"), 40) + Cobol.x(s.l10n.raw("report.pl190.report_on"), 12)
                     + st.l3Report.text + Cobol.x(st.l3Date, 10), 1)
    }

    static func listing(_ st: State, _ p: Record) {
        let s = st.s
        func r(_ k: String) -> String { s.l10n.raw("report.pl190." + k) }
        func name1(_ k: String) { st.line4.put(0, 14, r(k)) }
        func value1(_ v: String) { st.line4.put(14, 56, v) }
        func name2(_ k: String) { st.line4.put(70, 16, r(k)) }
        func value2(_ v: Int64, scale: Int = 0) { st.line4.put(86, 14, Pic.edit("z(7)9.99bbb", value: v, scale: scale)) }
        func date(_ bin: Int64) { st.line4.put(89, 11, bin == 0 ? "" : PLB.binDate(s, bin)) }
        func name3(_ k: String) { st.line4.put(100, 18, r(k)) }
        func value3(_ v: Int64) { st.line4.put(118, 13, Pic.edit("z(7)9.99cr", value: v, scale: 2)) }
        func write(_ n: Int = 1) { st.prt.after(st.line4.text, n) }

        name1("f_key"); value1(p.str("purch-key"))
        name2("f_credit"); value2(p.int("purch-credit"))
        name3("f_current"); value3(Cobol.truncate(p.int("purch-current") - p.int("purch-unapplied"), digits: 10))
        write(2)
        name1("f_name"); value1(p.str("purch-name"))
        name2("f_discount"); value2(p.int("purch-discount"), scale: 2)
        name3("f_last"); value3(p.int("purch-last"))
        write()
        name1("f_addr1"); value1(p.str("purch-addr1"))
        name2("f_notes"); st.line4.put(86, 14, ""); st.line4.put(86, 8, Pic.edit("z(6)99", value: p.int("purch-notes-tag"), scale: 0))
        name3("f_q1"); value3(p.int("turnover-q1"))
        write()
        name1("f_addr2"); value1(p.str("purch-addr2"))
        name2("f_average"); value2(p.int("purch-average"))
        name3("f_q2"); value3(p.int("turnover-q2"))
        write()
        name1("f_phone"); value1(p.str("purch-phone"))
        name2("f_limit"); value2(p.int("purch-limit"))
        name3("f_q3"); value3(p.int("turnover-q3"))
        write()
        name1("f_fax"); value1(p.str("purch-fax"))
        name2("f_activety"); value2(p.int("purch-activety"))
        name3("f_q4"); value3(p.int("turnover-q4"))
        write()
        name1("f_status"); value1(r(p.int("purch-status") == 1 ? "live" : "dead"))
        name2("f_last_inv"); st.line4.put(86, 3, ""); date(p.int("purch-last-inv"))
        st.line4.put(100, 18, ""); st.line4.put(118, 13, "")
        write()
        name1("f_email"); value1(p.str("purch-email"))
        name2("f_last_pay"); date(p.int("purch-last-pay"))
        write()
        st.z = (st.z + 1) % 10
        st.recCnt = PLB.addChar(st.recCnt, 1)
        if st.z > 3 {
            headings1(st)
            st.z = 0
        } else {
            st.prt.after(Cobol.x("", 40) + "<" + String(repeating: "-", count: 50) + ">", 1)
        }
    }
}
