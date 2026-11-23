import Foundation

/// pl950.cbl: 小切手・BACS 台帳の印刷と未決済明細の更新 (Cheque Register)
enum PLB950 {
    static let progName = "PL950 (3.01.09)"

    static func run(_ s: Session) throws {
        let c = s.console
        let st = PLB100.State(s)
        st.batchDescKey = "report.pl950.batch_desc"
        st.replySize = 3
        let l1Date = PLB.wsDate(s)
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("pl950.title"), at: 132, color: 2)
        c.display(l1Date, at: 171, color: 2)
        while true {
            c.display(s.t("pl950.warning"), at: 1201, color: 2)
            let reply = Cobol.x(try c.accept(at: 1269, size: 3, color: 6).uppercased(), 3)
            if reply == "NO " { return }
            if reply == "YES" { break }
        }
        c.display(" ", at: 1201, eraseEOL: true)
        let pf = PLB.purchFile(s), payFile = PLB.payFile(s)
        let purchOpen = pf.open() == "00"
        var payOpen = payFile.open() == "00"
        let prt = st.prt
        prt.openOutput()
        // 開けていない pay-file の READ NEXT は AT END にならず、処理が戻らない
        if !payOpen { try PLB.hang(s) }

        var p = 0, lineCnt = 0
        var l3Date = ""
        func headings() {
            p = (p + 1) % 100
            let line1 = Cobol.x(progName, 33) + Cobol.x(s.l10n.raw("report.pl950.title"), 39)
                + Cobol.x(s.l10n.raw("report.plb.page"), 5) + Pic.edit("zz9", value: Int64(p), scale: 0)
            let line2 = Cobol.x(s.sys.str("usera"), 33) + Cobol.x("", 37) + Cobol.x(l1Date, 10)
            if p != 1 {
                prt.afterPage(line1)
                prt.after(line2, 1)
                prt.after("", 1)
            } else {
                prt.before(line1, 1)
                prt.before(line2, 1)
            }
            prt.after(Cobol.x(s.l10n.raw("report.pl950.cheques_date"), 16) + Cobol.x(l3Date, 10), 1)
            prt.after(Cobol.x(s.l10n.raw("report.pl950.line4"), 66), 2)
            prt.after(Cobol.x(s.l10n.raw("report.pl950.line4a1"), 16) + Cobol.x(s.l10n.raw("report.pl950.line4a2"), 24), 1)
            prt.after("", 1)
            lineCnt = 8
        }
        /// purchase-file の READ: INVALID KEY で名前だけ "Record Missing" になる (開けていなければ何も変わらない)
        func readPurchase(_ key: [UInt8]) {
            guard purchOpen else { return }
            if let r = pf.read(key: key) { st.purch = r } else {
                st.purch.setRaw("purch-key", key)
                st.purch.set("purch-name", s.l10n.raw("report.pl950.record_missing"))
            }
        }

        var firstTime = true
        var balT: Int64 = 0
        let pageLines = Int(s.sys.int("page-lines"))
        while let pay = payFile.readNext() {
            if firstTime {
                l3Date = PLB.binDate(s, pay.int("pay-date"))
                headings()
                firstTime = false
            }
            readPurchase(pay.raw("pay-supl-key"))
            var details: String
            if pay.int("pay-cheque") != 0 {
                details = Pic.edit("z(9)9", value: pay.int("pay-cheque"), scale: 0) + Cobol.x("", 6)
            } else {
                details = Cobol.z(abs(pay.int("pay-sortcode")) % 1_000_000, 6) + " "
                    + Cobol.z(abs(pay.int("pay-account")) % 100_000_000, 8) + " "
            }
            details += Cobol.x(st.purch.str("purch-key"), 9) + Cobol.x(st.purch.str("purch-name"), 30)
                + Pic.edit("z(7)9.99", value: pay.int("pay-gross"), scale: 2)
            balT = abs(balT + pay.int("pay-gross")) % 1_000_000_000
            prt.after(details, 1)
            lineCnt = PLB.addChar(lineCnt, 1)
            if lineCnt > pageLines { headings() }
        }
        let line6 = Cobol.x("", 55) + String(repeating: "=", count: 11)
        prt.after(line6, 2)
        prt.after(Cobol.x("", 25) + Cobol.x(s.l10n.raw("report.pl950.total"), 30) + Pic.edit("z(7)9.99", value: balT, scale: 2), 1)
        prt.after(line6, 1)
        prt.close()
        payFile.close()
        prt.spool()

        payOpen = payFile.open() == "00"
        let oiFile = PLB.oi5File(s)
        let oiOpen = oiFile.open() == "00"
        if st.gl { PLB100.blOpen(st) }
        if s.sys.int("bl-next-batch") == 0 { s.sys.setInt("bl-next-batch", 1) }
        var paySeries: Int64 = 0
        var apropAmount: Int64 = 0, deductTaken: Int64 = 0
        if !payOpen { try PLB.hang(s) }
        while let pay = payFile.readNext() {
            readPurchase(pay.raw("pay-supl-key"))
            apropAmount = 0
            paySeries += 1
            if paySeries > 999 {
                paySeries = 1
                s.sys.setInt("bl-next-batch", s.sys.int("bl-next-batch") + 1)
            }
            let batchNos = s.sys.int("bl-next-batch")
            for z in 1...9 {
                let value = pay.int("pay-value-\(z)")
                if value == 0 { continue }
                let folio = pay.int("pay-folio-\(z)")
                var keyRec = Record(PLB.oi)
                keyRec.setRaw("oi-supplier", pay.raw("pay-supl-key"))
                keyRec.setInt("oi-invoice", folio)
                guard oiOpen, let r = oiFile.read(key: keyRec.raw("oi-supplier") + keyRec.raw("oi-invoice")) else {
                    // 開けていないファイルの READ は INVALID KEY にならないが、以降の REWRITE も失敗するため結果は変わらない
                    if oiOpen { continue }
                    continue
                }
                st.oi = r
                if st.oi.int("oi-type") != 2 {
                    c.display(s.t("pl950.pl904"), at: 2401, color: 4)
                    _ = try c.accept(at: 2441, size: 3)
                    continue
                }
                if st.oi.raw("oi-supplier") != pay.raw("pay-supl-key") || st.oi.int("oi-invoice") != folio {
                    c.display(s.t("pl950.pl905"), at: 2401, color: 4)
                    _ = try c.accept(at: 2441, size: 3)
                    continue
                }
                let deduct = pay.int("pay-deduct-\(z)")
                st.oi.setInt("oi-paid", Cobol.truncate(st.oi.int("oi-paid") + value, digits: 9))
                let work1 = Cobol.truncate(Cobol.truncate(st.oi.int("oi-net") + st.oi.int("oi-carriage") + st.oi.int("oi-vat")
                                                          + st.oi.int("oi-c-vat"), digits: 8) - deduct, digits: 8)
                if st.oi.int("oi-paid") == work1 {
                    st.oi.setInt("oi-status", 1)
                    st.oi.setInt("oi-net", Cobol.truncate(st.oi.int("oi-net") - deduct, digits: 9))
                    deductTaken = Cobol.truncate(deductTaken + deduct, digits: 9)
                    st.oi.setInt("oi-deduct-amt", 0)
                    st.oi.setInt("oi-b-nos", batchNos)
                    st.oi.setInt("oi-b-item", paySeries)
                    st.oi.setInt("oi-date-cleared", pay.int("pay-date"))
                }
                oiFile.rewrite(st.oi)
                apropAmount = Cobol.truncate(apropAmount + value, digits: 9)
                st.oi.setInt("oi-p-c", Cobol.truncate(st.oi.int("oi-p-c") + value, digits: 9))
                st.oi.setInt("oi-cr", PLB.wrap32(value))
            }
            // 支払の未決済明細 (type 5)。oi-header は直前に読んだ明細の内容を引き継ぐ。
            st.oi.setInt("oi-invoice", PLB.wrap32(1000 * batchNos + paySeries))
            for f in ["oi-carriage", "oi-c-vat", "oi-vat", "oi-discount", "oi-status", "oi-p-c", "oi-extra", "oi-e-vat", "oi-cr",
                      "oi-deduct-days", "oi-days", "oi-deduct-vat"] { st.oi.setInt(f, 0) }
            for f in ["oi-order", "oi-hold-flag", "oi-applied"] { st.oi.set(f, "") }
            st.oi.setRaw("oi-supplier", pay.raw("pay-supl-key"))
            st.oi.setInt("oi-b-nos", batchNos)
            st.oi.setInt("oi-b-item", paySeries)
            st.oi.setInt("oi-date", pay.int("pay-date"))
            st.oi.setInt("oi-date-cleared", pay.int("pay-date"))
            st.uDate = Cobol.x(Maps04.toDate(Int(pay.int("pay-date"))), 10)
            st.oi.setInt("oi-paid", pay.int("pay-gross"))
            st.oi.setInt("oi-net", apropAmount)                 // oi-approp redefines oi-net
            st.oi.setInt("oi-deduct-amt", deductTaken)
            if st.oi.int("oi-deduct-amt") != 0 { st.nDeduct = PLB.wrap32(st.nDeduct + 1) }
            // binary-long → x(10) の MOVE: 符号無し 10 桁
            st.oi.set("oi-ref", Cobol.z(abs(pay.int("pay-cheque")), 10))
            st.oi.setInt("oi-type", 5)
            if oiOpen { oiFile.write(st.oi) }
            if st.gl { try PLB100.blWrite(st) }
            st.tDeduct = Cobol.truncate(st.tDeduct + deductTaken, digits: 9)
            deductTaken = 0; apropAmount = 0
        }
        // end-run
        s.sys.setInt("bl-next-batch", s.sys.int("bl-next-batch") + 1)
        oiFile.close(); payFile.close(); pf.close()
        payFile.openOutput()
        payFile.close()
        if st.tDeduct != 0 { PLB100.analiseDeductions(st) }
        if st.gl { try PLB100.blClose(st) }
    }
}
