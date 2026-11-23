import Foundation

/// sales/sl950.cbl: Delivery / Picking Note Print (納品書・ピッキングリスト印刷)
enum SLB950 {
    static let progName = "SL950 (3.01.05)"

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
        c.display(s.t("sl950.title"), at: 126, color: 2)
        c.display(wsDate, at: 171, color: 2)

        let inv = SLB.invoiceFile(s)
        let salesFile = SLB.salesFile(s)
        let delivery = SLB.deliveryFile(s)
        inv.open(); salesFile.open(); delivery.open()
        let prt = SLB.Printer(s, "prt-3", size: 102)
        prt.openOutput()

        var sih = Record(SLB.sihLayout)
        var lines = [Record](repeating: Record(SLB.silLayout), count: 100)
        var sales = Record(SLB.salesLayout)
        var deliv = Record(SLB.deliveryLayout)
        var firstTime = true
        var line8 = [Character](repeating: " ", count: 84)
        var stock = [UInt8](repeating: 0x20, count: 400)
        let stockPath = s.ledgers + "stockctl.dat"
        let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))
        var count1 = 0, count2 = 0
        var l0Type = "", l0Desc = ""
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
            prt.after(Cobol.x("", 37) + Cobol.x(l0Desc, 25), 2)
            prt.after(Cobol.x("", 18) + Cobol.x(s.t("report.sl950.title"), 21) + Cobol.x("", 18) + Cobol.x(s.t("report.sl930.page"), 5)
                      + String(count1 % 10) + Cobol.x(s.t("report.sl930.of"), 4) + String(count2 % 10) + " " + l3Date + " "
                      + Cobol.z(Int64(t.hour), 2) + ":" + Cobol.z(Int64(t.minute), 2), 1)
            prt.after(Cobol.x("", 71) + Cobol.x(s.t("report.sl930.inv"), 5) + SLB.zz(l3Invoice, 8), 2)
            for l in head { prt.after(l, 1) }
            prt.after("", 2)
            prt.after(Cobol.x(s.t("report.sl950.h_abrev"), 11) + Cobol.x(s.t("report.sl950.h_product"), 15)
                      + Cobol.x(s.t("report.sl950.h_desc"), 34) + Cobol.x(s.t("report.sl950.h_qty"), 12)
                      + Cobol.x(s.t("report.sl950.h_location"), 10), 1)
            firstTime = false
        }

        func printRoutine() {
            var itemCount: Int64 = 0
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
            l0Type = ""
            if sih.int("sih-type") == 1 { l0Type = s.t("report.sl950.type_receipt") }
            else if sih.int("sih-type") == 2 { l0Type = s.t("report.sl950.type_invoice") }
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
            let level2 = s.sys.int("invoicer") == 2
            func put(_ off: Int, _ text: String) { line8.replaceSubrange(off..<off + text.count, with: Array(text)) }
            while true {
                let l = lines[k]
                let comment = l.str("sil-product").hasPrefix("/")
                if comment { line8 = [Character](repeating: " ", count: 84) }
                if level2 { put(26, Cobol.x(l.str("sil-description"), 32) + "  ") }
                if !comment && level2 {
                    let q = abs(l.int("sil-qty"))
                    put(60, SLB930.bwz(q, SLB.zz(q, 6)))
                    itemCount = abs(itemCount + l.int("sil-qty")) % 10_000
                    put(11, Cobol.x(l.str("sil-product"), 13) + "  ")
                    let product = SJIS.encode(l.str("sil-product"), size: 13)
                    stock.replaceSubrange(0..<13, with: product)
                    if s.sys.str("sl-stock-link") == "Y" {
                        if let r = s.store.read(stockPath, key: product) {
                            stock = r + [UInt8](repeating: 0x20, count: max(0, 400 - r.count))
                        } else {
                            stock.replaceSubrange(13..<20, with: product[0..<7])
                            if let r = s.store.all(stockPath).first(where: { $0.data.count >= 20 && Array($0.data[13..<20]) == Array(product[0..<7]) }) {
                                stock = r.data + [UInt8](repeating: 0x20, count: max(0, 400 - r.data.count))
                            } else {
                                stock.replaceSubrange(0..<13, with: [UInt8](repeating: 0x20, count: 13))
                            }
                        }
                        if stock[0..<13].contains(where: { $0 != 0x20 }) {
                            put(11, SJIS.decode(stock[0..<13]) + "  ")
                            put(2, SJIS.decode(stock[13..<20]) + "  ")
                            put(72, SJIS.decode(stock[86..<96]) + "  ")
                            put(26, SJIS.decode(stock[41..<73]) + "  ")
                        }
                    }
                }
                prt.after(String(line8), 1)
                k += 1
                if k > i { break }
                if k > j {
                    j += 25
                    count1 += 1
                    headings1()
                }
            }
            // total-print-2
            line8 = [Character](repeating: " ", count: 84)
            put(60, SLB930.bwz(itemCount, SLB.zz(itemCount, 6)))
            put(26, Cobol.x(s.t("report.sl950.total_items"), 32) + "  ")
            prt.after(String(line8), 3)
            if sih.str("sih-status-p") != "P" && sih.str("sih-status-p") != "p" {
                sih["sih-status-p"] = "P"
                _ = inv.rewrite(SLB.invoiceRecord(from: sih))
            }
        }

        func mainEnd() {
            inv.close(); salesFile.close(); delivery.close()
            prt.close()
            prt.spool()
        }

        var key = Record(SLB.invoiceLayout)
        if s.sys.int("pass-value") == 3 {
            key.setInt("invoice-nos", s.sys.int("next-invoice") - 1)
            key.setInt("item-nos", 0)
            key["invoice-let"] = " "
            guard let rec = inv.read(key: inv.key(of: key)) else { mainEnd(); return }
            sih = SLB.sih(from: rec)
            if pending() {
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
                if sih.str("sih-status-p") == "P" { continue }
                if pending() { printRoutine(); continue }
                if printPath == "P" { continue }
                if sih.int("sih-type") > 2 { continue }
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
