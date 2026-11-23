import Foundation

/// sales/sl110.cbl: Statement Production (顧客明細書発行)
enum SLB110 {
    static let progName = "SL110 (3.01.08)"

    static func run(_ s: Session) throws {
        let c = s.console
        if SLB.fileStatus(s, 19) != 1 {
            try SLB.maps99(s, 19)
            try SLB.maps99(s, 15)
            return
        }
        c.display(progName, at: 202, color: 2, eraseEOS: true)
        c.display(s.t("sl110.title"), at: 232, color: 2)
        var wsDate = SLB.wsDate(s)
        c.display(wsDate, at: 271, color: 2)

        let prt = SLB.Printer(s, "prt-2", size: 132)
        let salesFile = SLB.salesFile(s)
        let oisPath = s.ledgers + "oisort.wrk"
        let sys = s.sys
        let delim = Character(Cobol.x(sys.str("sl-delim"), 1))
        func sp(_ n: Int) -> String { String(repeating: " ", count: n) }

        // statements
        let stars = String(repeating: "*", count: 40)
        c.display(stars, at: 441, color: 2)
        c.display(s.t("sl110.box_date"), at: 541, color: 2)
        c.display(s.t("sl110.box_ac"), at: 641, color: 2)
        c.display(s.t("sl110.box_value"), at: 741, color: 2)
        c.display(stars, at: 841, color: 2)
        c.display(s.t("sl110.notes"), at: 1101, color: 2)
        c.display("*****", at: 1201, color: 2)
        c.display(s.t("sl110.note1"), at: 1401, color: 2)
        c.display(s.t("sl110.note2"), at: 1501, color: 2)
        c.display(s.t("sl110.note3"), at: 1601, color: 2)

        // date-input
        var wsTestDate = wsDate
        var payDate: Int64 = 0
        while true {
            c.display(wsDate, at: 551, color: 3)
            wsDate = Cobol.x(try c.accept(at: 551, size: 10, initial: wsDate, options: [.update], color: 3), 10)
            if wsDate == Cobol.x("", 10) { return }
            wsTestDate = wsDate
            let v = SLB.validateDate(s, wsTestDate)
            if v.bin == 0 { wsDate = v.uDate; continue }
            wsDate = v.uDate
            payDate = v.bin
            break
        }
        // customer-input
        var customerIn = Cobol.x(try c.accept(at: 654, size: 7, initial: Cobol.x("", 7), options: [.update], color: 2), 7).uppercased()
        // value-input (accept-money)
        c.display("000000.00", at: 752, color: 3)
        let m = Array(Cobol.x(try c.accept(at: 752, size: 9, initial: "000000.00", options: [.update], color: 3), 9))
        func dg(_ a: ArraySlice<Character>) -> Int64 { a.reduce(Int64(0)) { $0 * 10 + Int64($1.wholeNumberValue ?? 0) } }
        let payValue = dg(m[0..<6]) * 100 + dg(m[7...])
        // flavour-in
        var flavour1 = Cobol.x("", 64), flavour2 = Cobol.x("", 64)
        repeat {
            c.display(s.t("sl110.msg1"), at: 1801, color: 2)
            c.display("]", at: 1879, color: 2)
            c.display(s.t("sl110.msg2"), at: 1901, color: 2)
            c.display("]", at: 1979, color: 2)
            flavour1 = Cobol.x(try c.accept(at: 1815, size: 64, initial: flavour1, options: [.update], color: 3), 64)
            flavour2 = Cobol.x(try c.accept(at: 1915, size: 64, initial: flavour2, options: [.update], color: 3), 64)
        } while flavour2.hasPrefix("<")

        salesFile.open()
        let raw = s.store.readRaw(oisPath) ?? []
        let oiSize = SLB.oiLayout.size
        var oiPos = 0
        prt.openOutput()
        if customerIn != Cobol.x("", 7) {
            _ = salesFile.start(notLessThan: SJIS.encode(customerIn, size: 7))
            customerIn = customerIn.replacingOccurrences(of: " ", with: "Z")
        }

        var bal0: Int64 = 0, bal30: Int64 = 0, bal60: Int64 = 0, bal90: Int64 = 0, balT: Int64 = 0
        var lp = 0
        var firstTime = 0
        var lastRead = Cobol.x("", 7)
        var oi = Record(SLB.oiLayout)
        var addressLine = Cobol.x("", 36)
        var head: [(String, Int)] = []

        func headings1() throws {
            while true {
                for (text, n) in head { prt.after(text, n) }
                if firstTime != 0 { break }
                c.display(s.t("sl110.aligned"), at: 2001, color: 2)
                var reply = try c.accept(at: 2044, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                if reply == "Y" { break }
                c.display(s.t("sl110.sl150"), at: 2101, color: 2)
                c.display(s.t("sl110.sl003"), at: 2201, color: 2)
                reply = try c.accept(at: 2044, size: 1, color: 2)
                c.display(" ", at: 2101, eraseEOL: true)
                c.display(" ", at: 2201, eraseEOL: true)
            }
            if firstTime == 0 { c.display(sp(80), at: 2001) }
            firstTime = 1
            prt.after("", 3)
        }
        func endStatement(skipFlavour: Bool = false) {
            if !skipFlavour {
                lp = abs(32 - lp) % 100
                if lp >= 6 {
                    lp -= 4
                    prt.after(" " + flavour1, lp)
                    prt.after(" " + flavour2, 1)
                    lp = 3
                }
            }
            // end-stat-do
            let l13 = SLB.z99cr(bal0, 7) + sp(2) + SLB.z99cr(bal30, 7) + " " + SLB.z99cr(bal60, 7) + " "
                + SLB.z99cr(bal90, 7) + " " + SLB.z99cr(balT, 7) + sp(12) + SLB.z99cr(balT, 7)
            prt.after(l13, lp)
            prt.after("", 4)
            bal0 = 0; bal30 = 0; bal60 = 0; bal90 = 0; balT = 0; lp = 0
        }
        func line12(_ sInv: Int64, _ date: String, _ desc: String, _ sAmt: Int64, _ rInv: Int64, _ rAmt: Int64) -> String {
            func bwz(_ v: Int64) -> String { v == 0 ? sp(8) : Pic.edit("z(7)9", value: v, scale: 0) }
            return sp(2) + bwz(sInv) + sp(3) + Cobol.x(date, 11) + Cobol.x(desc, 31) + SLB.z99cr(sAmt, 7) + sp(3)
                + bwz(rInv) + SLB.z99cr(rAmt, 8)
        }

        readSales: while true {
            guard var sales = salesFile.readNext() else { break }
            if sales.int("sales-unapplied") != 0 {
                sales.setInt("sales-current", sales.int("sales-current") - sales.int("sales-unapplied"))
            }
            if sales.int("sales-current") == 0 { continue }
            if payValue != 0 && sales.int("sales-current") < payValue { continue }
            let salesKey = sales.str("sales-key")
            if customerIn != Cobol.x("", 7) && salesKey > customerIn { break }

            let src = Array(Cobol.x(sales.str("sales-addr1") + sales.str("sales-addr2"), 96))
            var a = 1
            var parts: [String] = []
            for n in 0..<5 {
                if n > 0 { addressLine = Cobol.x("", 36) }
                if let x = SLB940.unstring(src, delim, size: 36, pointer: &a) { addressLine = x }
                parts.append(Cobol.x(addressLine, 32))
            }
            let usera = sys.str("usera")
            head = [
                (sp(24) + Cobol.x(usera, 32), 1),
                (sp(24) + Cobol.x(sys.str("address-1"), 24) + sp(21) + Cobol.x(usera, 23), 1),
                (sp(24) + Cobol.x(sys.str("address-2"), 24) + sp(21) + Cobol.x(sys.str("address-1"), 23), 1),
                (sp(24) + Cobol.x(sys.str("address-3"), 24) + sp(21) + Cobol.x(sys.str("address-2"), 23), 1),
                (sp(24) + Cobol.x(sys.str("address-4"), 24) + sp(21) + Cobol.x(sys.str("address-3"), 23), 1),
                (sp(9) + sales.str("sales-name"), 2),
                (sp(9) + parts[0] + sp(15) + wsTestDate + sp(3) + wsTestDate + sp(5) + salesKey, 1),
                (sp(9) + parts[1], 1),
                (sp(9) + parts[2], 1),
                (sp(9) + parts[3], 1),
                (sp(9) + parts[4] + sp(18) + salesKey, 1),
            ]
            try headings1()

            if sales.int("sales-unapplied") != 0 {
                let u = -sales.int("sales-unapplied")
                sales.setInt("sales-unapplied", u)
                bal0 += u; balT += u
                lp += 1
                prt.after(line12(0, wsTestDate, s.t("sl110.unapplied"), u, 0, u), 1)
            }
            // read-open-item
            while true {
                if lastRead == Cobol.x("", 7) {
                    if oiPos + oiSize > raw.count {
                        endStatement()
                        break readSales
                    }
                    oi = Record(SLB.oiLayout, bytes: Array(raw[oiPos..<(oiPos + oiSize)]))
                    oiPos += oiSize
                }
                lastRead = oi.str("oi-customer")
                if lastRead > salesKey { endStatement(); continue readSales }
                if lastRead != salesKey { lastRead = Cobol.x("", 7); continue }
                let type = oi.int("oi-type")
                if type == 1 || type == 4 { lastRead = Cobol.x("", 7); continue }
                if type == 5 || type == 6 { oi.setInt("oi-invoice", 0) }
                let invoice = oi.int("oi-invoice")
                let date = SLB.convBin(s, oi.int("oi-date")).wsDate
                var desc: String
                switch type {
                case 2:
                    var d = oi.str("oi-description")
                    if let r = d.range(of: "  ") { d = String(d[..<r.lowerBound]) }
                    desc = s.t("sl110.goods_as_per") + d
                    if oi.str("oi-description") == Cobol.x("", oi.str("oi-description").count) { desc = s.t("sl110.goods") }
                case 3: desc = s.t("sl110.credit_note") + Pic.edit("z(7)9", value: oi.int("oi-cr"), scale: 0)
                case 6: desc = s.t("sl110.unapplied_alloc")
                default: desc = s.t("sl110.payment")
                }
                var invAmount = oi.int("oi-net") + oi.int("oi-extra") + oi.int("oi-carriage") + oi.int("oi-vat")
                    + oi.int("oi-discount") + oi.int("oi-e-vat") + oi.int("oi-deduct-amt") + oi.int("oi-deduct-vat") + oi.int("oi-c-vat")
                var amountOut: Int64 = 0
                var sAmt: Int64 = 0, rAmt: Int64 = 0
                if type == 2 {
                    amountOut = invAmount - oi.int("oi-paid")
                    sAmt = amountOut + oi.int("oi-p-c")
                    rAmt = amountOut
                    if amountOut == 0 && oi.int("oi-p-c") == 0 { sAmt = invAmount }
                }
                if type == 3 {
                    sAmt = invAmount
                    invAmount += oi.int("oi-paid")
                    rAmt = invAmount
                }
                if type == 5 || type == 6 {
                    if oi.int("oi-paid") >= 0 { oi.setInt("oi-paid", -oi.int("oi-paid")) }
                    if oi.int("oi-approp") >= 0 { oi.setInt("oi-approp", -oi.int("oi-approp")) }
                    amountOut = oi.int("oi-paid") - oi.int("oi-approp")
                    rAmt = amountOut
                    sAmt = oi.int("oi-paid")
                }
                let work1 = payDate - oi.int("oi-date")
                if work1 < 30 { bal0 += amountOut }
                else if work1 < 60 { bal30 += amountOut }
                else if work1 < 90 { bal60 += amountOut }
                else { bal90 += amountOut }
                balT += amountOut
                // bypass-ageing
                lp += 1
                if lp > 28 {
                    prt.after("", 8)
                    try headings1()
                    lp = 1
                }
                prt.after(line12(invoice, date, desc, sAmt, invoice, rAmt), 1)
                lastRead = Cobol.x("", 7)
            }
        }
        // main-end
        salesFile.close(); prt.close()
        s.store.writeRaw(oisPath, [])
        prt.spool()
    }
}
