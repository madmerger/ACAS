import Foundation

/// sales/sl190.cbl: Letter Production (督促状出力)
enum SLB190 {
    static let progName = "SL190 (3.01.04)"

    static func run(_ s: Session) throws {
        let c = s.console
        if SLB.fileStatus(s, 19) != 1 {
            try SLB.maps99(s, 19)
            try SLB.maps99(s, 15)
            _ = try c.accept(at: 2479, size: 1)
            return
        }
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 202, color: 2)
        c.display(s.t("sl190.title"), at: 233, color: 2)
        var wsDate = SLB.wsDate(s)
        c.display(wsDate, at: 271, color: 2)

        let letterPaths = ["letter.001", "letter.002", "letter.003"].map { s.ledgers + $0 }
        for p in letterPaths { s.store.writeRaw(p, []) }

        // statements
        let stars = String(repeating: "*", count: 40)
        c.display(stars, at: 441, color: 2)
        c.display(s.t("sl190.box_date"), at: 541, color: 2)
        c.display(s.t("sl190.box_ac"), at: 641, color: 2)
        c.display(s.t("sl190.box_value"), at: 741, color: 2)
        c.display(stars, at: 841, color: 2)
        c.display(s.t("sl190.notes"), at: 1201, color: 2)
        c.display("*****", at: 1301, color: 2)
        c.display(s.t("sl190.note1"), at: 1501, color: 2)
        c.display(s.t("sl190.note2"), at: 1601, color: 2)

        // date-input: zz050 は ws-test-date (本プログラムでは未設定 = spaces) を検査するため
        // 入力値は捨てられ、常に u-bin = 0 となって抜けられない (レガシーの癖をそのまま再現)
        let wsTestDate = Cobol.x("", 10)
        var payDate: Int64 = 0
        while true {
            c.display(wsDate, at: 551, color: 3)
            _ = try c.accept(at: 551, size: 10, initial: wsDate, options: [.update], color: 3)
            let v = SLB.validateDate(s, wsTestDate)
            wsDate = s.sys.int("date-form") == 3 ? "  /  /    " : wsTestDate
            if v.bin == 0 { continue }
            payDate = v.bin
            break
        }
        // customer-input
        let customerIn = Array(Cobol.x(try c.accept(at: 653, size: 7, color: 3), 7).uppercased())
        // value-input (accept-money)
        c.display("000000.00", at: 750)
        let m = Array(Cobol.x(try c.accept(at: 750, size: 9), 9))
        func dg(_ a: ArraySlice<Character>) -> Int64 { a.reduce(Int64(0)) { $0 * 10 + Int64($1.wholeNumberValue ?? 0) } }
        let payValue = dg(m[0..<6]) * 100 + dg(m[7...])
        // amounts-input
        c.display(s.t("sl190.low"), at: 1820, color: 2)
        c.display(s.t("sl190.medium"), at: 1920, color: 2)
        c.display(s.t("sl190.high"), at: 2020, color: 2)
        var days: [Int64] = []
        for (i, at) in [1835, 1935, 2035].enumerated() {
            days.append(s.sys.int("sl-days-\(i + 1)") % 100)
            c.display(Cobol.z(days[i], 2), at: at, color: 2)
        }
        for (i, at) in [1835, 1935, 2035].enumerated() {
            days[i] = dg(Array(Cobol.x(try c.accept(at: at, size: 2, kind: .numeric, color: 3), 2))[...])
        }
        for i in 0..<3 { s.sys.setInt("sl-days-\(i + 1)", days[i]) }

        let salesFile = SLB.salesFile(s)
        let oi3 = SLB.oi3File(s)
        salesFile.open(); oi3.open()
        var lastRead = Cobol.x("", 7)
        var oi = Record(SLB.oiLayout)
        var storeWork: Int64 = 0
        var siDate: Int64 = 0
        let delim = Character(Cobol.x(s.sys.str("sl-delim"), 1))
        var sales = Record(SLB.salesLayout)
        var lfLines = [String](repeating: Cobol.x("", 34), count: 4)

        func upTo2Spaces(_ t: String) -> [UInt8] {
            // delimited by "  " (バイト単位で最初の空白 2 連続まで)
            let b = SJIS.encode(t, size: 34)
            var i = 0
            while i < b.count {
                if b[i] == 0x20 && i + 1 < b.count && b[i + 1] == 0x20 { break }
                i += 1
            }
            return Array(b[0..<i])
        }
        func letterOut() {
            let letterNos = storeWork < s.sys.int("sl-days-2") * 100 ? 1 : (storeWork < s.sys.int("sl-days-3") * 100 ? 2 : 3)
            func semi(_ t: String) -> String { t.replacingOccurrences(of: ",", with: ";") }
            let lfName = semi(Cobol.x(sales.str("sales-name"), 34))
            // lf-os: 浮動通貨記号 (1 バイト 0xA3) 付き 6 桁 + .99
            let cur = abs(sales.int("sales-current")) % Cobol.pow10(8)
            var os = [UInt8](repeating: 0x20, count: 10)
            let digits = Array((String(cur / 100) + "." + Cobol.z(cur % 100, 2)).utf8)
            os.replaceSubrange((10 - digits.count)..<10, with: digits)
            os[10 - digits.count - 1] = 0xA3
            let date = SLB.convBin(s, siDate).wsDate
            let q: [UInt8] = [0x22], comma: [UInt8] = [0x2C]
            var b: [UInt8] = q + upTo2Spaces(lfName) + q + comma
            for l in lfLines { b += q + upTo2Spaces(semi(l)) + q + comma }
            b += q + SJIS.encode(sales.str("sales-key"), size: 7) + q + comma
            b += os + q + comma
            b += q + SJIS.encode(date, size: 10) + q
            if b.count > 208 { b = Array(b[0..<208]) }
            while let l = b.last, l == 0x20 { b.removeLast() }
            s.store.appendRaw(letterPaths[letterNos - 1], b + [0x0A])
        }
        func endStatement() {
            if storeWork >= s.sys.int("sl-days-1") * 100 { letterOut() }
            storeWork = 0; siDate = 0
        }

        readSales: while true {
            guard let rec = salesFile.readNext() else { break }
            sales = rec
            if sales.int("sales-dunning") != 1 { continue }
            sales.setInt("sales-current", sales.int("sales-current") - sales.int("sales-unapplied"))
            if sales.int("sales-current") < 1 { continue }
            if payValue != 0 && sales.int("sales-current") < payValue { continue }
            let salesKey = sales.str("sales-key")
            if String(customerIn) != Cobol.x("", 7) {
                var truth = true
                let k = Array(Cobol.x(salesKey, 7))
                for y in 0..<6 where truth && customerIn[y] != " " && customerIn[y] != k[y] { truth = false }
                if !truth { continue }
            }
            let src = Array(Cobol.x(sales.str("sales-addr1") + sales.str("sales-addr2"), 96))
            var a = 1
            for n in 0..<4 {
                lfLines[n] = Cobol.x(SLB940.unstring(src, delim, size: 36, pointer: &a) ?? "", 34)
            }
            // read-open-item
            while true {
                if lastRead == Cobol.x("", 7) {
                    guard let r = oi3.readNext() else {
                        endStatement()
                        break readSales
                    }
                    oi = r
                }
                lastRead = oi.str("oi-customer")
                if lastRead > salesKey { endStatement(); continue readSales }
                if lastRead != salesKey { lastRead = Cobol.x("", 7); continue }
                if oi.int("oi-type") != 2 || oi.int("oi-status") == 1 { lastRead = Cobol.x("", 7); continue }
                // work-1 pic s9(6)v99 (日数差を小数 2 桁スケールで保持)
                let work1 = (payDate - oi.int("oi-date")) * 100
                if work1 > storeWork {
                    storeWork = abs(work1) % Cobol.pow10(8)
                    if oi.int("oi-date") > siDate { siDate = oi.int("oi-date") }
                }
                lastRead = Cobol.x("", 7)
            }
        }
        oi3.close(); salesFile.close()
    }
}
