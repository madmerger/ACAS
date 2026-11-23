import Foundation

/// common/maps09.cbl: 得意先・仕入先コードのチェックディジット (モジュラス 11)
public enum Maps09 {
    private static let alpha = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-".utf8)

    /// 6 桁コードのチェックディジット。コードに不正文字がある (合計 0) 場合は nil (maps09-reply = "N")。
    public static func checkDigit(_ code: String) -> Int? {
        modulus(code).map { $0 % 10 }
    }

    private static func modulus(_ code: String) -> Int? {
        let prefix = code.utf8.prefix(6)
        guard prefix.count == 6 else { return nil }
        var suma = 0
        for (offset, byte) in prefix.enumerated() {
            guard let q = alpha.firstIndex(of: byte) else { return nil }
            suma += (q + 1) * (7 - offset)
        }
        return 11 - suma % 11
    }

    /// 7 桁コード (6 桁 + チェックディジット) の検証 (maps09-reply = "V")
    public static func verify(_ code7: String) -> Bool {
        guard let byte = code7.utf8.dropFirst(6).first, (48...57).contains(byte) else { return false }
        return modulus(code7) == Int(byte - 48)
    }
}

/// レガシーの計算式 (同一性テスト CALC が抜き出して検証している箇所)
public enum Calc {
    /// sl910: `compute amt-ok6 rounded = (ws-net * ws-vat-rate) / 100`
    /// net: 9(7)v99 (符号なし), rate: 99v99, 結果: 9(6)v99 (四捨五入)
    public static func vat(net: Int64, rate: Int64) -> Int64 {
        let n = abs(net % 1_000_000_000), r = abs(rate % 10_000)
        let v = Cobol.rescaleRounded(n * r, from: 6, to: 2)   // scale 2+2 → /100 → scale 2
        return v % 100_000_000
    }

    /// st020: `divide ws-New-Qty into ws-New-Value giving ws-New-Cost rounded`
    /// value: s9(8)v99, qty: s9(6), 結果: s9(6)v9999 (四捨五入)。qty = 0 は nil (SIZE ERROR で値不変)。
    public static func averageCost(value: Int64, qty: Int64) -> Int64? {
        let qty = qty % 1_000_000
        guard qty != 0 else { return nil }
        let num = (value % 10_000_000_000) * 100
        let neg = (num < 0) != (qty < 0)
        let a = abs(num), b = abs(qty)
        var q = a / b
        if (a % b) * 2 >= b { q += 1 }
        q %= 10_000_000_000
        return neg ? -q : q
    }

    /// sl110: 経過日数による年齢区分 (0 / 30 / 60 / 90)
    public static func ageBucket(days: Int64) -> Int {
        if days < 30 { return 0 }
        if days < 60 { return 30 }
        if days < 90 { return 60 }
        return 90
    }

    public static func convertDate(_ input: String) -> (serial: Int, normalized: String)? {
        var legacy = input
        if let parts = input.wholeMatch(of: #/([0-9]{4})年([0-9]{1,2})月([0-9]{1,2})日/#) {
            legacy = "\(Cobol.z(Int(parts.3)!, 2))/\(Cobol.z(Int(parts.2)!, 2))/\(parts.1)"
        }
        guard legacy.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        let serial = Maps04.toBinary(legacy)
        guard serial != 0 else { return nil }
        return (serial, Cobol.rtrim(Maps04.normalized(legacy)))
    }

    public static func amount(_ input: String, scale: Int) -> Int64? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard let match = text.wholeMatch(of: #/([+-]?)([0-9]{1,12})(?:\.([0-9]{1,12}))?/#),
              scale == 0 || scale == 2 else { return nil }
        let integral = Int64(match.2)!
        let fraction = (String(match.3 ?? "") + "00").prefix(scale)
        let amount = integral * Cobol.pow10(scale) + (Int64(fraction) ?? 0)
        return match.1 == "-" ? -amount : amount
    }
}
