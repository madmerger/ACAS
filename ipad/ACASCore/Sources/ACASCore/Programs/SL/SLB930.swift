import Foundation

/// sales/sl930.cbl: Invoice Printing (請求書印刷)
enum SLB930 {
    static let progName = "SL930 (3.01.12)"

    /// blank when zero
    static func bwz(_ value: Int64, _ text: String) -> String {
        value == 0 ? String(repeating: " ", count: text.count) : text
    }
    /// -(n)9.99 (浮動マイナス)。value は小数 2 桁のスケール付き整数。
    static func minus99(_ value: Int64, _ n: Int) -> String {
        let v = abs(value) % Cobol.pow10(n + 2)
        return SLB.minus(v / 100, n, negative: value < 0) + "." + Cobol.z(v % 100, 2)
    }

    static func run(_ s: Session) throws {
        let c = s.console
        if s.sys.int("full-invoicing") == 0 { return }
        if SLB.fileStatus(s, 15) != 1 {
            try SLB.maps99(s, 29)
            try SLB.maps99(s, 15)
            _ = try c.accept(at: 2479, size: 1)
            return
        }
        let wsDate = SLB.wsDate(s)

        // zz080-Setup-Company-Details
        let compPick = s.sys.str("sl-comp-head-pick") == "Y"
        var company = [[Character]](repeating: [Character](repeating: " ", count: 91), count: 7)
        if compPick {
            let fields: [(String, Int)] = [("usera", 32), ("address-1", 24), ("address-2", 24), ("address-3", 24),
                                           ("address-4", 24), ("post-code", 12), ("country", 24)]
            for (n, f) in fields.enumerated() {
                let src = Array(Cobol.x(s.sys.str(f.0), f.1))
                var h = f.1
                while h != 1 && src[h - 1] == " " { h -= 1 }
                let start = 45 - (h / 2 + 1)        // h98 - h99 (1 始まり)
                company[n].replaceSubrange((start - 1)..<(start - 1 + h), with: src[0..<h])
            }
        }

        // menu-return
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("sl930.title"), at: 134, color: 2)
        c.display(wsDate, at: 171, color: 2)

        let inv = SLB.invoiceFile(s)
        let salesFile = SLB.salesFile(s)
        let delivery = SLB.deliveryFile(s)
        inv.open(); salesFile.open(); delivery.open()
        let prt = SLB.Printer(s, "prt-2", size: 102)
        prt.openOutput()

        var sih = Record(SLB.sihLayout)
        var lines = [Record](repeating: Record(SLB.silLayout), count: 100)
        var sales = Record(SLB.salesLayout)
        var deliv = Record(SLB.deliveryLayout)
        var firstTime = true
        var line8 = [Character](repeating: " ", count: 87)
        var l7BDisc = s.t("report.sl930.disc")
        let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))
        var count1 = 0, count2 = 0
        var l0Type = "", l0Xs = "", l0Desc = ""
        var head: [String] = []     // line-0-d の日付まで以外の見出し行は都度組み立てる
        var l3Date = "", l3Invoice: Int64 = 0

        func pending() -> Bool { sih.str("sih-status") == "P" }
        func sapplied() -> Bool { sih.str("sih-status") == "z" || sih.str("sih-status") == "Z" }

        func headings1() {
            let t = s.time
            if compPick {
                if firstTime { prt.after(String(company[0]), 1) } else { prt.afterPage(String(company[0])) }
                for n in 1..<7 { prt.after(String(company[n]), 1) }
                prt.after(l0Type, 1)
            } else {
                if firstTime { prt.after(l0Type, 4) }
                else {
                    prt.afterPage("")
                    prt.after(l0Type, 4)
                }
            }
            prt.after(l0Xs, 1)
            prt.after(Cobol.x("", 37) + Cobol.x(l0Desc, 25), 2)
            prt.after(Cobol.x("", 25) + Cobol.x(s.t("report.sl930.invoice"), 7) + Cobol.x("", 25) + Cobol.x(s.t("report.sl930.page"), 5)
                      + String(count1 % 10) + Cobol.x(s.t("report.sl930.of"), 4) + String(count2 % 10) + " " + l3Date + " "
                      + Cobol.z(Int64(t.hour), 2) + ":" + Cobol.z(Int64(t.minute), 2), 1)
            prt.after(Cobol.x("", 72) + Cobol.x(s.t("report.sl930.inv"), 5) + SLB.zz(l3Invoice, 8), 2)
            for l in head { prt.after(l, 1) }
            prt.after("", 2)
            prt.after(Cobol.x(s.t("report.sl930.h_product"), 14) + Cobol.x(s.t("report.sl930.h_desc"), 30)
                      + Cobol.x(s.t("report.sl930.h_qty"), 6) + Cobol.x(s.t("report.sl930.h_cost"), 10) + Cobol.x(l7BDisc, 7)
                      + Cobol.x(s.t("report.sl930.h_net"), 10) + Cobol.x(s.t("report.sl930.h_vat"), 10), 1)
            firstTime = false
        }

        func printRoutine() {
            var i = 1
            for _ in 0..<max(0, Int(sih.int("sih-lines"))) {
                guard let rec = inv.readNext() else { break }
                if rec.int("item-nos") == 0 { break }
                lines[i] = SLB.sil(from: rec)
                if lines[i].str("sil-type") == "D" { break }
                i += 1
            }
            i -= 1
            var ii = abs(i - 1)
            if ii == 0 { ii = 1 }
            count2 = (ii / 15 + 1) % 10
            count1 = 1
            l0Desc = ""
            l0Xs = s.t("report.sl930.xs_invoice")
            switch sih.int("sih-type") {
            case 1: l0Type = s.t("report.sl930.type_receipt")
            case 2: l0Type = s.t("report.sl930.type_invoice")
            case 3: l0Type = s.t("report.sl930.type_credit"); l0Xs = s.t("report.sl930.xs_credit")
            default:
                l0Type = s.t("report.sl930.type_proforma"); l0Xs = s.t("report.sl930.xs_proforma")
                l0Desc = s.t("report.sl930.not_vat")
            }
            // get-customer (invalid key は無視: 直前のレコード内容が残る)
            if let r = salesFile.read(key: sih.raw("sih-customer")) { sales = r }
            if sales.int("delivery-tag") > 0 {
                if let d = delivery.read(key: Array(("D" + sales.str("sales-key")).utf8)) { deliv = d }
            }
            var iLine = [String](repeating: Cobol.x("", 31), count: 5)
            var dLine = [String](repeating: Cobol.x("", 30), count: 5)
            var a = 1
            let sAddr = Array(Cobol.x(sales.str("sales-addr1") + sales.str("sales-addr2"), 96))
            for n in 0..<5 {
                if let t = SLB940.unstring(sAddr, delim, size: 31, pointer: &a) { iLine[n] = t }
            }
            var dName = Cobol.x("", 30)
            if sales.int("delivery-tag") != 0 {
                dName = Cobol.x(deliv.str("deliv-name"), 30)
                a = 1
                let dAddr = Array(Cobol.x(deliv.str("deliv-address"), 96))
                for n in 0..<5 {
                    if let t = SLB940.unstring(dAddr, delim, size: 30, pointer: &a) { dLine[n] = t }
                }
            }
            l3Invoice = sih.int("sih-invoice")
            l3Date = SLB.convBin(s, sih.int("sih-date")).wsDate
            head = [
                Cobol.x(sales.str("sales-name"), 31) + "    " + dName,
                iLine[0] + "    " + dLine[0] + Cobol.x("", 7),
                iLine[1] + "    " + dLine[1] + Cobol.x("", 5) + Cobol.x(s.t("report.sl930.order"), 7) + Cobol.x(sih.str("sih-order"), 11),
                iLine[2] + "    " + dLine[2] + Cobol.x("", 5) + Cobol.x(s.t("report.sl930.ref"), 7) + Cobol.x(sih.str("sih-ref"), 11),
                iLine[3] + "    " + dLine[3] + Cobol.x("", 5) + Cobol.x(s.t("report.sl930.ac"), 7) + sih.str("sih-customer"),
                iLine[4] + "    " + dLine[4],
            ]
            headings1()

            var k = 1, j = 25
            var workN: Int64 = 0, workV: Int64 = 0
            let level2 = s.sys.int("invoicer") == 2
            func put(_ off: Int, _ text: String) { line8.replaceSubrange(off..<off + text.count, with: Array(text)) }
            var l9Terms = s.t("report.sl930.credit_terms"), l9Days: Int64 = 0, l9Desc = Cobol.x("", 24)
            var l9Net: Int64 = 0, l9Vat: Int64 = 0
            func line9() -> String {
                Cobol.x(l9Terms, 14) + bwz(l9Days, SLB.zz(l9Days, 3)) + Cobol.x("", 24) + Cobol.x(l9Desc, 24)
                    + bwz(l9Net, minus99(l9Net, 7)) + bwz(l9Vat, minus99(l9Vat, 7))
            }
            func totalPrint() {
                l9Desc = Cobol.x("", 24)
                l9Net = workN; l9Vat = workV
                l9Days = abs(sih.int("sih-days"))
                l9Terms = s.t("report.sl930.credit_terms")
                prt.after(line9(), k)
                l9Days = 0
                l9Terms = ""
            }
            while true {
                let l = lines[k]
                let comment = l.str("sil-product").hasPrefix("/")
                if comment { line8 = [Character](repeating: " ", count: 87) }
                if level2 { put(14, Cobol.x(l.str("sil-description"), 30)) }
                if comment {
                    put(44, Cobol.x("", 6)); put(50, Cobol.x("", 10)); put(60, Cobol.x("", 6))
                    put(77, Cobol.x("", 10)); put(67, Cobol.x("", 10))
                } else {
                    if level2 {
                        let q = abs(l.int("sil-qty")), u = l.int("sil-unit"), d = l.int("sil-discount")
                        put(44, bwz(q, SLB.zz(q, 6)))
                        put(50, bwz(u % 1_000_000_000, SLB.z99(u, 7)))
                        put(0, Cobol.x(l.str("sil-product"), 13) + " ")
                        put(60, bwz(d % 100_000, SLB.z99(d, 3)))
                    } else {
                        put(44, Cobol.x("", 6)); put(50, Cobol.x("", 10)); put(60, Cobol.x("", 6))
                        put(0, Cobol.x("", 14))
                    }
                    if level2 && l.int("sil-discount") > 0 {
                        put(66, "%")
                        l7BDisc = s.t("report.sl930.disc")
                    } else {
                        l7BDisc = ""
                        put(66, " ")
                    }
                    let n = l.int("sil-net"), v = l.int("sil-vat")
                    put(67, bwz(n, SLB.z99(n, 7)))
                    put(77, bwz(v, SLB.z99(v, 7)))
                }
                prt.after(String(line8), 1)
                workN = abs(workN + l.int("sil-net")) % 100_000_000
                workV = abs(workV + l.int("sil-vat")) % 100_000_000
                k += 1
                if k > i {
                    k = abs(count2 * 25 - i + 2) % 100
                    break
                }
                if k > j {
                    let kk = k
                    k = 2
                    j += 25
                    count1 += 1
                    totalPrint()
                    k = kk
                    prt.after("", 13)
                    headings1()
                }
            }
            totalPrint()
            // total-print-2
            let line7 = Cobol.x("", 72)
            let dAmt = sih.int("sih-deduct-amt"), dVat = sih.int("sih-deduct-vat")
            if dAmt == 0 && dVat == 0 {
                prt.after(line7, 1)
            } else {
                l9Desc = s.t("report.sl930.late_surcharge")
                l9Terms = ""
                l9Vat = dVat; l9Net = dAmt
                prt.after(line9(), 1)
                l9Desc = ""
            }
            // total-print-3
            if s.sys.str("extra-print") == "N" || (sih.int("sih-extra") == 0 && sih.int("sih-e-vat") == 0) {
                prt.after(line7, 1)
            } else {
                l9Terms = ""
                l9Desc = s.sys.str("extra-desc")
                l9Vat = sih.int("sih-e-vat"); l9Net = sih.int("sih-extra")
                prt.after(line9(), 1)
            }
            // total-print-4
            l9Terms = ""; l9Desc = ""
            l9Vat = sih.int("sih-c-vat"); l9Net = sih.int("sih-carriage")
            prt.after(line9(), 2)
            var l10Terms = "", l10Days: Int64 = 0
            if sales.int("sales-credit") != 0 {
                l10Terms = s.t("report.sl930.prompt_pay")
                l10Days = abs(sih.int("sih-deduct-days"))
            }
            if dAmt == 0 { l10Terms = ""; l10Days = 0 }
            let amount = dAmt + dVat
            let vat = sih.int("sih-vat") + sih.int("sih-e-vat") + sih.int("sih-c-vat") + dVat
            let net = sih.int("sih-net") + sih.int("sih-extra") + sih.int("sih-carriage") + dAmt
            let gross = vat + net
            prt.after(Cobol.x("", 14) + Cobol.x(l10Terms, 16) + bwz(l10Days, SLB.zz(l10Days, 3)), 1)
            prt.after(Cobol.x("", 13) + bwz(amount % 1_000_000, SLB.z99(amount, 4)) + Cobol.x("", 45)
                      + bwz(net % 10_000_000_000, SLB.z99(net, 8)) + bwz(vat % 10_000_000_000, SLB.z99(vat, 8)), 1)
            prt.after(Cobol.x("", 65) + Cobol.x(s.t("report.sl930.total_due"), 11) + SLB.z99(gross, 8), 2)
            prt.after("", 5)
            if !sapplied() {
                sih["sih-status"] = "I"
                sih["sih-status-l"] = "L"
                _ = inv.rewrite(SLB.invoiceRecord(from: sih))
            }
        }

        func mainEnd() {
            inv.close(); salesFile.close(); delivery.close()
            prt.close()
            prt.spool()
            if s.sys.int("pass-value") == 3 { s.sys.setInt("s-flag-i", 1) }
        }

        var key = Record(SLB.invoiceLayout)
        if s.sys.int("pass-value") == 3 {
            key.setInt("invoice-nos", s.sys.int("next-invoice") - 1)
            key.setInt("item-nos", 0)
            key["invoice-let"] = " "
            guard let rec = inv.read(key: inv.key(of: key)) else { mainEnd(); return }
            sih = SLB.sih(from: rec)
            if pending() || sih.str("sih-status-l") != "L" {
                printRoutine()
                mainEnd(); return
            }
            c.display(s.t("sl930.invoice_number"), at: 501, color: 2)
            c.display(Cobol.z(sih.int("sih-invoice"), 8), at: 518, color: 3)
            c.display(s.t("sl930.reprint"), at: 601, color: 2)
            let r = try c.accept(at: 644, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
            if r == "Y" { printRoutine() }
            c.display(" ", at: 501, eraseEOL: true)
            c.display(" ", at: 601, eraseEOL: true)
            mainEnd(); return
        }

        // all-print-start
        c.display(s.t("sl930.print_or_reprint"), at: 701, color: 2)
        // 応答の大文字化は ws-reply に対して行われ、print-path は入力のまま (レガシーどおり)
        let printPath = try c.accept(at: 744, size: 1, initial: "P", options: [.update], color: 6)
        enum Step { case go, read, getInv }
        var step: Step
        if printPath == "R" {
            step = .getInv
        } else {
            step = .read
            while true {
                c.display(s.t("sl930.any_amended"), at: 901, color: 2)
                let r = try c.accept(at: 938, size: 1, initial: "N", options: [.update], color: 6).uppercased()
                if r == "Y" {
                    s.sys.setInt("first-sl-inv", 0)
                    inv.startFirst()
                    break
                }
                if r != "N" { continue }
                if s.sys.int("first-sl-inv") == 0 { inv.startFirst(); break }
                key.setInt("invoice-nos", s.sys.int("first-sl-inv"))
                step = .go
                break
            }
        }
        var atEnd = false
        loop: while true {
            switch step {
            case .getInv:
                c.display(" ", at: 1301, eraseEOL: true)
                c.display(s.t("sl930.give_lowest"), at: 1301, color: 2)
                key.setInt("invoice-nos", try SLB.acceptNum(s, at: 1326, digits: 8, initial: 0, color: 3))
                step = .go
            case .go:
                s.sys.setInt("first-sl-inv", 0)
                key.setInt("item-nos", 0)
                key["invoice-let"] = " "
                atEnd = !inv.start(notLessThan: inv.key(of: key))
                step = .read
            case .read:
                guard !atEnd, let rec = inv.readNext() else { break loop }
                if rec.int("item-nos") != 0 { continue }
                sih = SLB.sih(from: rec)
                if sih.int("sih-lines") == 0 && sapplied() { continue }
                if pending() { printRoutine(); continue }
                if printPath == "P" { continue }
                c.display(s.t("sl930.invoice_number"), at: 1101, color: 2)
                c.display(Cobol.z(sih.int("sih-invoice"), 8), at: 1118, color: 3)
                c.display(s.t("sl930.reprint"), at: 1201, color: 2)
                let r = try c.accept(at: 1244, size: 1, color: 6).uppercased()
                if r == "Y" { printRoutine() }
                c.display(" ", at: 1101, eraseEOL: true)
                c.display(" ", at: 1201, eraseEOL: true)
                while true {
                    c.display(s.t("sl930.more_to_print"), at: 1101, color: 2)
                    let m = try c.accept(at: 1117, size: 1, initial: "Y", options: [.update], color: 6).uppercased()
                    if m == "N" { break loop }
                    if m == "Y" { step = .getInv; break }
                }
            }
        }
        mainEnd()
    }
}
