import Foundation

/// purchase/pl095.cbl: 支払検証帳票 (Payment Proof Report)
final class PLA095 {
    static let progName = "PL095 (3.01.04)"
    static func run(_ s: Session) throws { try PLA095(s).main() }

    let s: Session
    var c: Console { s.console }
    var p: PLA.Printer
    var pageNos = 0, lineCnt = 0
    var pageLines: Int { Int(s.sys.int("page-lines")) }

    // line-6 (項目は行をまたいで保持される)
    var l6BNos: Int64 = 0, l6Slash = "/", l6BItem: Int64 = 0, l6Trans = "  "
    var l6Date = Cobol.x("", 11), l6Ac = Cobol.x("", 8), l6Name = Cobol.x("", 29)
    var l6Value: Int64 = 0, l6Approp: Int64 = 0, l6Dedn: Int64 = 0
    var l6Invoice: Int64 = 0, l6IDate = Cobol.x("", 10), l6IApprop: Int64 = 0, l6IBalance: Int64 = 0

    init(_ s: Session) {
        self.s = s
        p = PLA.Printer(s)
    }

    func main() throws {
        if s.sys.int("p-flag-p") == 0 { return }
        s.sys.set("oi-5-flag", "Y")
        s.sys.setInt("p-flag-p", 2)
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA095.progName, at: 101, color: 2)
        c.display(s.t("pl095.title"), at: 132, color: 2)
        c.display(PLA.toDayDisplay(s), at: 171, color: 2)
        c.display(s.t("pl095.printing"), at: 1201, color: 2)
        report1()
    }

    /// 編集項目 + 後続の B (空白)。BLANK WHEN ZERO
    func bwzB(_ pic: String, _ v: Int64, int: Int, scale: Int, b: Int) -> String {
        let t = abs(v) % Cobol.pow10(int + scale)
        let size = Pic.size(pic) + b
        return t == 0 ? Cobol.x("", size) : Cobol.x(Pic.edit(pic, value: t, scale: scale), size)
    }

    func line6() -> String {
        let bal = (l6IBalance < 0 ? -1 : 1) * (abs(l6IBalance) % Cobol.pow10(10))
        return bwzB("z(4)9", l6BNos, int: 5, scale: 0, b: 0) + l6Slash
            + (l6BItem % 1000 == 0 ? "    " : Cobol.z(l6BItem % 1000, 3) + " ")
            + l6Trans + l6Date + l6Ac + l6Name
            + bwzB("z(5)9.99", l6Value, int: 6, scale: 2, b: 2)
            + bwzB("z(5)9.99", l6Approp, int: 6, scale: 2, b: 2)
            + bwzB("z(3)9.99", l6Dedn, int: 4, scale: 2, b: 1)
            + bwzB("z(7)9", l6Invoice, int: 8, scale: 0, b: 2)
            + l6IDate
            + bwzB("z(5)9.99", l6IApprop, int: 6, scale: 2, b: 0)
            + (bal == 0 ? Cobol.x("", 13) : Pic.edit("z(7)9.99cr", value: bal, scale: 2))
    }

    func headings() {
        pageNos = (pageNos + 1) % 100
        let line1 = Cobol.x(PLA095.progName, 48) + Cobol.x(s.t("pl095.rep_title"), 76) + s.t("pl095.rep_page") + Pic.edit("z9", value: Int64(pageNos), scale: 0)
        let line2 = Cobol.x(s.sys.str("usera"), 20) + Cobol.x("", 102) + Cobol.x(PLA.toDayDisplay(s), 10)
        if pageNos != 1 {
            p.writePage(line1)
            p.write(line2, after: 1)
            p.write("", after: 1)
        } else {
            p.writeBefore(line1, before: 1)
            p.writeBefore(line2, before: 1)
        }
        p.write(Cobol.x(s.t("pl095.rep_line4a"), 61) + Cobol.x(s.t("pl095.rep_line4b"), 71), after: 1)
        p.write(Cobol.x("", 22) + Cobol.x(s.t("pl095.rep_line5a"), 70) + Cobol.x(s.t("pl095.rep_line5b"), 40), after: 1)
        lineCnt = 5
    }

    func report1() {
        let sorted = PLA090.sortFile(s)
        if !sorted.openInput() {
            sorted.close()
            return
        }
        let purchase = PLA.purchaseFile(s)
        _ = purchase.open()
        p.openOutput()
        headings()
        var saveCustomer = Cobol.x("", 7)
        var savApprop: Int64 = 0
        var tPay: Int64 = 0, tApprop: Int64 = 0, tDeducts: Int64 = 0
        var jPay: Int64 = 0, jApprop: Int64 = 0, jDeducts: Int64 = 0
        func acc(_ t: inout Int64, _ v: Int64) { t = Cobol.truncate(t + v, digits: 9) }
        while let bytes = sorted.read() {
            let oi = Record(PLA.oiLayout, bytes: bytes)
            let type = oi.int("oi-type")
            if type == 2 {
                // process-invoice
                if oi.int("oi-paid") == 0 { continue }
                if oi.str("oi-supplier") != saveCustomer { continue }
                l6Invoice = oi.int("oi-invoice")
                l6IDate = Cobol.x(PLA.dateDisplay(s, oi.int("oi-date")), 10)
                l6Slash = " "
                l6IApprop = oi.int("oi-paid") > savApprop ? savApprop : oi.int("oi-paid")
                let work1 = abs(oi.int("oi-net") + oi.int("oi-vat") + oi.int("oi-carriage") + oi.int("oi-c-vat")) % 100_000_000
                l6IBalance = work1 - oi.int("oi-paid")
                p.write(line6(), after: 1)
                lineCnt += 1
                if lineCnt > pageLines { headings() }
                continue
            }
            if type < 5 || type > 6 || oi.int("oi-status") != 0 { continue }
            saveCustomer = oi.str("oi-supplier")
            l6BNos = oi.int("oi-b-nos")
            l6Slash = "/"
            l6BItem = oi.int("oi-b-item")
            l6Trans = type == 6 ? "J " : "P "
            l6Date = Cobol.x(PLA.dateDisplay(s, oi.int("oi-date")), 11)
            l6Ac = Cobol.x(saveCustomer, 8)
            if let pr = purchase.read(key: saveCustomer) {
                l6Name = Cobol.x(PLA.shown(Array(pr.raw("purch-name").prefix(29))), 29)
            } else {
                l6Name = Cobol.x(s.t("pl095.supplier_unknown"), 29)
            }
            if type == 6 {
                acc(&jPay, oi.int("oi-paid")); acc(&jApprop, oi.int("oi-approp")); acc(&jDeducts, oi.int("oi-deduct-amt"))
            } else {
                acc(&tPay, oi.int("oi-paid")); acc(&tApprop, oi.int("oi-approp")); acc(&tDeducts, oi.int("oi-deduct-amt"))
            }
            l6Value = oi.int("oi-paid")
            l6Approp = oi.int("oi-approp"); savApprop = oi.int("oi-approp")
            l6Dedn = oi.int("oi-deduct-amt")
            l6Invoice = 0; l6IApprop = 0; l6IBalance = 0
            l6IDate = Cobol.x("", 10)
            if lineCnt > pageLines - 2 { headings() }
            p.write(line6(), after: 2)
            lineCnt += 2
            l6BNos = 0; l6BItem = 0; l6Dedn = 0; l6Value = 0; l6Approp = 0
            l6Date = Cobol.x("", 11); l6Ac = Cobol.x("", 8); l6Name = Cobol.x("", 29); l6Trans = "  "
        }
        // loop-end
        if lineCnt > pageLines - 22 { headings() }
        func line9(_ key: String, _ v: Int64) -> String {
            Cobol.x("", 23) + Cobol.x(s.t(key), 17) + PLA.ed("z(6)9.99", v, int: 7)
        }
        func totals(_ titleKey: String, _ pay: Int64, _ approp: Int64, _ deducts: Int64) {
            p.write(Cobol.x("", 30) + s.t(titleKey), after: 3)
            p.write(Cobol.x("", 30) + "**************", after: 1)
            p.write(line9("pl095.payments", pay), after: 3)
            p.write(line9("pl095.appropriations", approp), after: 1)
            p.write(line9("pl095.unapplied_cash", pay - approp), after: 1)
            p.write(line9("pl095.deductions_taken", deducts), after: 2)
        }
        totals("pl095.payment_totals", tPay, tApprop, tDeducts)
        totals("pl095.journal_totals", jPay, jApprop, jDeducts)
        sorted.close(); purchase.close()
        p.close()
        p.spool()
    }
}
