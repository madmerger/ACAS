import Foundation

/// pl920.cbl: 支払予定の修正 (Cheque Due Amendment)
enum PLB920 {
    static let progName = "PL920 (3.01.03)"

    static func run(_ s: Session) throws {
        let c = s.console
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("pl920.title"), at: 132, color: 2)
        c.display(PLB.wsDate(s), at: 171, color: 2)

        // payment-amend section
        let pf = PLB.purchFile(s), payFile = PLB.payFile(s)
        let purchOpen = pf.open() == "00"
        let payOpen = payFile.open() == "00"
        var pay = Record(PLB.pay)
        var purchName = Cobol.x("", 30)
        // ws-amount-screen-display (10 桁): 9(7) "." v99。ws-amount-screen-accept (9(7) + v99 の 9 桁) が
        // 先頭から重なるため、銭 2 桁は "." と銭の 1 桁目へ入り、10 桁目は初期値のまま残る (レガシーどおり)。
        var amountScreen = Array("0000000.00".utf8)

        c.display(s.t("pl920.supplier"), at: 501, color: 2)
        for z in 1...9 {
            c.display(Cobol.z(Int64(z), 2), at: (8 + z) * 100 + 1, color: 3)
            c.display("   {        } [          ]", at: (8 + z) * 100 + 3, color: 2)
        }
        getKey: while true {
            let key = try c.accept(at: 513, size: 7, color: 3).uppercased()
            pay.set("pay-supl-key", key)
            if key.allSatisfy({ $0 == " " }) { break }
            let nos = try PLB.acceptNum(s, at: 521, digits: 2, initial: 1, color: 3)
            pay.setInt("pay-nos", nos)
            // 開けていないファイルの READ は INVALID KEY にならず、レコード領域はそのまま先へ進む
            if payOpen {
                guard let r = payFile.read(key: pay.raw("pay-supl-key") + pay.raw("pay-nos")) else { continue }
                pay = r
            }
            if purchOpen {
                guard let p = pf.read(key: pay.raw("pay-supl-key")) else { continue }
                purchName = p.str("purch-name")
            }
            c.display(Cobol.x(purchName, 30), at: 526, color: 3)
            for z in 1...9 {
                let lin = (8 + z) * 100
                c.display(Pic.edit("z(7)9", value: pay.int("pay-folio-\(z)"), scale: 0), at: lin + 7, color: 3)
                c.display(Pic.edit("z(6)9.99", value: pay.int("pay-value-\(z)"), scale: 2), at: lin + 18, color: 3)
                c.display(Cobol.x(pay.str("pay-invoice-\(z)"), 10), at: lin + 32, color: 3)
            }
            while true {
                c.display(s.t("pl920.gross"), at: 556, color: 2)
                c.display(Pic.edit("z(6)9.99", value: pay.int("pay-gross"), scale: 2), at: 565, color: 3)
                c.display(s.t("pl920.line_to_alter"), at: 2201, color: 2)
                let y = Int(try PLB.acceptNum(s, at: 2218, digits: 1, color: 6))
                if y == 0 { break }
                let old = pay.int("pay-value-\(y)")
                if old == 0 { continue }
                let at = (8 + y) * 100 + 18
                var gross = Cobol.truncate(pay.int("pay-gross") - old, digits: 9)
                // accept-money2
                let amtOk = Array(Cobol.z(abs(old) % 1_000_000_000, 9).utf8)
                for i in 0..<9 { amountScreen[i] = amtOk[i] }
                c.display(String(decoding: amountScreen, as: UTF8.self), at: at, color: 3)
                let entered = try c.accept(at: at, size: 9, initial: String(decoding: amountScreen[0..<9], as: UTF8.self),
                                           options: [.update], color: 3)
                let bytes = Array(Cobol.x(entered, 9).utf8)
                for i in 0..<9 { amountScreen[i] = i < bytes.count ? bytes[i] : 0x20 }
                // 数字以外の桁はゾーンを落とした下位 4 ビットで詰められる
                var value: Int64 = 0
                for i in 0..<9 { value = value * 10 + Int64(amountScreen[i] & 0x0f) }
                pay.setInt("pay-value-\(y)", value)
                gross = Cobol.truncate(gross + pay.int("pay-value-\(y)"), digits: 9)
                pay.setInt("pay-gross", gross)
            }
            if payOpen { payFile.rewrite(pay) }
        }
        pf.close(); payFile.close()
    }
}
