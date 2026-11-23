import Foundation

/// sales/sl095.cbl: Payment Proof Report (入金プルーフリスト)
enum SLA095 {
    static let progName = "SL095 (3.01.07)"

    final class WS {
        var saveCustomer = SLA.spaces(7)
        var savApprop: Int64 = 0
        var lineCnt = 0
        var pageNos = 0
        var uDate = SLA.spaces(10)
        var tPay: Int64 = 0, tApprop: Int64 = 0, tDeducts: Int64 = 0
        var jPay: Int64 = 0, jApprop: Int64 = 0, jDeducts: Int64 = 0
        // line-6 (各項目は書き込み後も残る)
        var bNos = SLA.spaces(5), slash = "/", bItem = SLA.spaces(4), trans = "  ", date = SLA.spaces(11), ac = SLA.spaces(8)
        var name = SLA.spaces(29), value = SLA.spaces(11), approp = SLA.spaces(11), dedn = SLA.spaces(9)
        var invoice = SLA.spaces(9), iDate = SLA.spaces(10), iApprop = SLA.spaces(9), iBalance = SLA.spaces(13)
        var line6: String { bNos + slash + bItem + trans + date + ac + name + value + approp + dedn + invoice + iDate + iApprop + iBalance }
        var p: SLA.Printer!
    }

    static func m9(_ v: Int64) -> Int64 { Cobol.truncate(v, digits: 9, signed: true) }
    /// BLANK WHEN ZERO 付き編集 (符号なし PIC は絶対値)
    static func bwz(_ pic: String, _ v: Int64, _ scale: Int, _ width: Int, digits: Int, signed: Bool = false) -> String {
        let t = Cobol.truncate(signed ? v : abs(v), digits: digits, signed: signed)
        return t == 0 ? SLA.spaces(width) : Cobol.x(Pic.edit(pic, value: t, scale: scale), width)
    }

    static func run(_ s: Session) throws {
        let c = s.console
        if s.sys.int("s-flag-p") == 0 { return }
        let w = WS()
        s.sys["oi-3-flag"] = "Y"
        s.sys.setInt("s-flag-p", 2)
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("sl095.title"), at: 132, color: 2)
        c.display(SLA.convertDate(s), at: 271, color: 2)
        c.display(s.t("sl095.printing"), at: 1201, color: 2)
        report1(s, w)
    }

    static func report1(_ s: Session, _ w: WS) {
        func r(_ k: String, _ n: Int) -> String { Cobol.x(s.l10n.raw(k), n) }
        guard let data = s.store.readRaw(SLA090.sortedPath(s)) else { return }
        let sales = SLA.salesFile(s)
        _ = sales.open()
        w.p = SLA.Printer(s)
        w.p.open()
        headings(s, w)
        let pageLines = Int(s.sys.int("page-lines"))
        var pos = 0
        while pos + 114 <= data.count {
            let oi = Record(SLA.oiLayout, bytes: Array(data[pos..<(pos + 114)]))
            pos += 114
            let type = oi.int("oi-type")
            if type == 2 {
                // process-invoice
                if oi.int("oi-paid") == 0 { continue }
                if oi.str("oi-customer") != w.saveCustomer { continue }
                w.invoice = bwz("z(7)9", oi.int("oi-invoice"), 0, 8, digits: 8) + " "
                w.iDate = Cobol.x(SLA.convertBin(s, oi.int("oi-date"), uDate: &w.uDate), 10)
                w.slash = " "
                w.iApprop = bwz("z(5)9.99", oi.int("oi-paid") > w.savApprop ? w.savApprop : oi.int("oi-paid"), 2, 9, digits: 8)
                let work1 = Cobol.truncate(abs(oi.int("oi-net") + oi.int("oi-extra") + oi.int("oi-vat") + oi.int("oi-discount") + oi.int("oi-carriage")
                    + oi.int("oi-e-vat") + oi.int("oi-c-vat") + oi.int("oi-deduct-amt") + oi.int("oi-deduct-vat")), digits: 8, signed: false)
                w.iBalance = bwz("z(7)9.99cr", work1 - oi.int("oi-paid"), 2, 13, digits: 10, signed: true)
                w.p.after(1, w.line6)
                w.lineCnt += 1
                if w.lineCnt > pageLines { headings(s, w) }
                continue
            }
            if type < 5 || type > 6 || oi.int("oi-status") != 0 { continue }
            w.saveCustomer = oi.str("oi-customer")
            w.bNos = bwz("z(4)9", oi.int("oi-b-nos"), 0, 5, digits: 5)
            w.slash = "/"
            w.bItem = oi.int("oi-b-item") == 0 ? SLA.spaces(4) : Cobol.z(oi.int("oi-b-item"), 3) + " "
            w.trans = type == 6 ? "J " : "P "
            w.date = Cobol.x(SLA.convertBin(s, oi.int("oi-date"), uDate: &w.uDate), 11)
            w.ac = Cobol.x(oi.str("oi-customer"), 8)
            if let sr = sales.read(key: oi.raw("oi-customer")) {
                w.name = Cobol.x(sr.str("sales-name"), 29)
            } else {
                w.name = r("report.sl095.unknown", 29)
            }
            if type == 6 {
                w.jPay = m9(w.jPay + oi.int("oi-paid")); w.jApprop = m9(w.jApprop + oi.int("oi-net")); w.jDeducts = m9(w.jDeducts + oi.int("oi-deduct-amt"))
            } else {
                w.tPay = m9(w.tPay + oi.int("oi-paid")); w.tApprop = m9(w.tApprop + oi.int("oi-net")); w.tDeducts = m9(w.tDeducts + oi.int("oi-deduct-amt"))
            }
            w.value = bwz("z(5)9.99", oi.int("oi-paid"), 2, 9, digits: 8) + "  "
            w.approp = bwz("z(5)9.99", oi.int("oi-net"), 2, 9, digits: 8) + "  "
            w.savApprop = oi.int("oi-net")
            w.dedn = bwz("z(3)9.99", oi.int("oi-deduct-amt"), 2, 7, digits: 6) + "  "
            w.invoice = SLA.spaces(9); w.iApprop = SLA.spaces(9); w.iBalance = SLA.spaces(13)
            w.iDate = SLA.spaces(10)
            if w.lineCnt > pageLines { headings(s, w) }
            w.p.after(2, w.line6)
            w.lineCnt += 2
            w.bNos = SLA.spaces(5); w.bItem = SLA.spaces(4); w.dedn = SLA.spaces(9); w.value = SLA.spaces(11); w.approp = SLA.spaces(11)
            w.date = SLA.spaces(11); w.ac = SLA.spaces(8); w.name = SLA.spaces(29); w.trans = "  "
        }
        // loop-end
        if w.lineCnt > pageLines - 8 { headings(s, w) }
        func line7(_ k: String) -> String { SLA.spaces(30) + r(k, 7) + r("report.sl095.totals", 7) }
        let line8 = SLA.spaces(30) + String(repeating: "*", count: 14)
        func line9(_ k: String, _ v: Int64) -> String {
            SLA.spaces(23) + r(k, 17) + Pic.edit("z(6)9.99", value: Cobol.truncate(abs(v), digits: 9, signed: false), scale: 2)
        }
        func block(_ pay: Int64, _ approp: Int64, _ deducts: Int64) {
            w.p.after(1, line8)
            w.p.after(3, line9("report.sl095.payments", pay))
            w.p.after(1, line9("report.sl095.appropriations", approp))
            w.p.after(1, line9("report.sl095.unapplied_cash", pay - approp))
            w.p.after(2, line9("report.sl095.deductions", deducts))
        }
        w.p.after(4, line7("report.sl095.payment"))
        block(w.tPay, w.tApprop, w.tDeducts)
        w.p.after(2, line7("report.sl095.journal"))
        block(w.jPay, w.jApprop, w.jDeducts)
        sales.close()
        w.p.close()
    }

    static func headings(_ s: Session, _ w: WS) {
        func r(_ k: String, _ n: Int) -> String { Cobol.x(s.l10n.raw(k), n) }
        w.pageNos = (w.pageNos + 1) % 100
        let line1 = Cobol.x(progName, 48) + r("report.sl095.title", 76) + r("report.sl095.page", 5) + Pic.edit("zz9", value: Int64(w.pageNos), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 48) + SLA.spaces(74) + Cobol.x(SLA.convertDate(s), 10)
        if w.pageNos != 1 {
            w.p.afterPage(line1)
            w.p.after(1, line2)
            w.p.after(1, "")
        } else {
            w.p.before(1, line1)
            w.p.before(1, line2)
        }
        w.p.after(2, r("report.sl095.line4a", 61) + r("report.sl095.line4b", 71))
        w.p.after(1, SLA.spaces(22) + r("report.sl095.line5a", 70) + r("report.sl095.line5b", 40))
        w.lineCnt = 6
    }
}
