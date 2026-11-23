import Foundation

/// pl940.cbl: 小切手印刷ファイルの生成 (Cheque Print File Generation)
enum PLB940 {
    static let progName = "PL940 (3.01.04)"

    /// wordn (1...99): 金額の英語読み
    static let ones = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
                       "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
    static let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]
    static func wordn(_ y: Int) -> String {
        if y < 20 { return ones[y] }
        return y % 10 == 0 ? tens[y / 10] : tens[y / 10] + "-" + ones[y % 10]
    }

    /// 金額 (銭単位, 9(7)v99) を c-words-1 / c-words-2 (各 64 桁) へ
    static func words(_ amount: Int64) -> (String, String) {
        var test = amount
        var w1 = PLB.Buf(64), w2 = PLB.Buf(64)
        var z = 1
        var poundFlag = false
        var y = Int(test / 100_000_000) % 100
        test -= 100_000_000 * Int64(y)
        if y > 0 { PLB.string(&w1, &z, wordn(y), " Million ") }
        y = Int(test / 10_000_000) % 100
        test -= 10_000_000 * Int64(y)
        if y > 0 { PLB.string(&w1, &z, wordn(y), " Hundred and ") }
        y = Int(test / 100_000) % 100
        test -= 100_000 * Int64(y)
        if y > 0 { PLB.string(&w1, &z, wordn(y), " Thousand ") }
        if z > 1 { poundFlag = true }
        PLB.string(&w1, &z, String(repeating: "*", count: 64))
        y = Int(test / 10_000) % 100
        test -= 10_000 * Int64(y)
        z = 1
        if y > 0 { PLB.string(&w2, &z, wordn(y), " Hundred and ") }
        y = Int(test / 100) % 100
        test -= Int64(y) * 100
        if y > 0 { PLB.string(&w2, &z, wordn(y)) }
        if z > 1 { poundFlag = true }
        if y > 0 || poundFlag { PLB.string(&w2, &z, " Pounds ") }
        y = Int(test) % 100
        if y > 0 { PLB.string(&w2, &z, wordn(y), " Pence ") }
        if y == 0 { PLB.string(&w2, &z, "ONLY") }
        return (w1.text, w2.text)
    }

    static func run(_ s: Session) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("pl940.title"), at: 128, color: 2)
        let wsDate = PLB.wsDate(s)
        c.display(wsDate, at: 171, color: 2)
        let pf = PLB.purchFile(s), payFile = PLB.payFile(s)
        let purchOpen = pf.open() == "00"
        if payFile.open() != "00" {
            c.display(s.t("pl940.pl903"), at: 401, color: 2)
            _ = try c.accept(at: 438, size: 1)
            pf.close(); payFile.close()
            return
        }
        let chequePath = s.ledgers + "cheque.dat"
        var out: [UInt8] = []
        s.store.writeRaw(chequePath, [])
        c.display(s.t("pl940.first_cheque"), at: 611, color: 2)
        var chequeNos = try PLB.acceptNum(s, at: 634, digits: 8, color: 3)
        c.display(s.t("pl940.payment_date"), at: 811, color: 2)
        var testDate = Cobol.x(wsDate, 10)
        var uBin: Int64 = 0
        repeat {
            c.display(testDate, at: 834, color: 3)
            testDate = Cobol.x(try c.accept(at: 834, size: 10, initial: testDate, options: [.update], color: 3), 10)
            uBin = Int64(PLB.validateDate(s, testDate))
        } while uBin == 0
        let cDate = testDate

        var purchName = Cobol.x("", 30), purchAddress = Cobol.x("", 96)
        let delim = Cobol.x(s.sys.str("pl-delim"), 1).first!
        while var pay = payFile.readNext() {
            if pay.int("pay-gross") < 1 { continue }
            if purchOpen {
                if let p = pf.read(key: pay.raw("pay-supl-key")) {
                    purchName = p.str("purch-name")
                    purchAddress = Cobol.x(p.str("purch-addr1"), 48) + Cobol.x(p.str("purch-addr2"), 48)
                } else {
                    purchName = Cobol.x(s.l10n.raw("report.pl940.pl902"), 30)
                    purchAddress = Cobol.x(s.l10n.raw("report.pl940.pl902"), 96)
                }
            }
            // UNSTRING purch-address DELIMITED BY pl-delim INTO c-address (y) POINTER z を 5 回
            let addr = Array(purchAddress)
            var z = 1
            var cAddress = [String](repeating: Cobol.x("", 32), count: 5)
            for y in 0..<5 {
                if z < 1 || z > addr.count { continue }
                var e = z - 1
                while e < addr.count && addr[e] != delim { e += 1 }
                cAddress[y] = Cobol.x(String(addr[(z - 1)..<e]), 32)
                z = e < addr.count ? e + 2 : e + 1
            }
            let gross = abs(pay.int("pay-gross")) % 1_000_000_000
            let (w1, w2) = words(gross)
            var rec = Cobol.x(pay.str("pay-supl-key"), 7) + "," + Cobol.x(purchName, 30) + ","
            for a in cAddress { rec += a + "," }
            rec += w1 + "," + w2 + "," + Pic.edit("z(6)9.99", value: gross, scale: 2) + ","
            if pay.int("pay-sortcode") == 0 {
                rec += Pic.edit("z(8)9", value: chequeNos, scale: 0)
                pay.setInt("pay-cheque", chequeNos)
                chequeNos = (chequeNos + 1) % 100_000_000
            } else {
                pay.setInt("pay-cheque", 0)
                rec += Cobol.x("BACS", 9)
            }
            rec += "," + cDate + ","
            for i in 1...9 {
                rec += Cobol.x(pay.str("pay-invoice-\(i)"), 10) + ","
                    + PLB.bwz("z(7)9", pay.int("pay-folio-\(i)")) + ","
                    + PLB.bwz("z(6)9.99", pay.int("pay-value-\(i)"), scale: 2) + (i < 9 ? "," : " ")
            }
            // LINE SEQUENTIAL: 行末の空白を落として改行
            var bytes = SJIS.encode(rec, size: 645)
            while let last = bytes.last, last == 0x20 { bytes.removeLast() }
            out += bytes + [0x0a]
            pay.setInt("pay-date", uBin)
            payFile.rewrite(pay)
        }
        s.store.writeRaw(chequePath, out)
        pf.close(); payFile.close()
    }
}
