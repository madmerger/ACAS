import Foundation

/// common/maps09.cbl: 得意先・仕入先コードのチェックディジット (モジュラス 11)
public enum Maps09 {
    static let alpha = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-")

    /// 6 桁コードのチェックディジット。コードに不正文字がある (合計 0) 場合は nil (maps09-reply = "N")。
    public static func checkDigit(_ code: String) -> Int? {
        let a = Array(Cobol.x(code, 6))
        var suma = 0
        for i in 0..<6 {
            guard let q = alpha.firstIndex(of: a[i]) else { suma = 0; break }
            suma += (q + 1) * (8 - (i + 1))
        }
        if suma == 0 { return nil }
        let z = suma / 11
        let r = 11 - (suma - 11 * z)
        return r % 10   // check-digit は pic 9 (上位桁は切り捨て)
    }

    /// 7 桁コード (6 桁 + チェックディジット) の検証 (maps09-reply = "V")
    public static func verify(_ code7: String) -> Bool {
        let a = Array(Cobol.x(code7, 7))
        guard let d = a[6].wholeNumberValue, let c = checkDigit(String(a[0..<6])) else { return false }
        return c == d
    }
}

/// レガシーの計算式 (同一性テスト CALC が抜き出して検証している箇所)
public enum Calc {
    /// sl910: `compute amt-ok6 rounded = (ws-net * ws-vat-rate) / 100`
    /// net: 9(7)v99 (符号なし), rate: 99v99, 結果: 9(6)v99 (四捨五入)
    public static func vat(net: Int64, rate: Int64) -> Int64 {
        let n = abs(net) % 1_000_000_000, r = abs(rate) % 10_000
        let v = Cobol.rescaleRounded(n * r, from: 6, to: 2)   // scale 2+2 → /100 → scale 2
        return v % 100_000_000
    }

    /// st020: `divide ws-New-Qty into ws-New-Value giving ws-New-Cost rounded`
    /// value: s9(8)v99, qty: s9(6), 結果: s9(6)v9999 (四捨五入)。qty = 0 は nil (SIZE ERROR で値不変)。
    public static func averageCost(value: Int64, qty: Int64) -> Int64? {
        guard qty != 0 else { return nil }
        let num = value * 100          // scale 2 → 4
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

    /// CALC ケースの実行 (program = drv09 / drv04 / drvvat / drvage / drvavg)。レガシー実測 (actual) と同じ形の辞書を返す。
    public static func run(program: String, input: [String: Any]) -> [String: Any]? {
        func str(_ k: String) -> String {
            if let s = input[k] as? String { return s }
            if let n = input[k] as? NSNumber { return n.stringValue }
            return ""
        }
        func dec(_ k: String, _ scale: Int) -> Int64 {
            let (v, sc) = Cobol.numval(str(k))
            return Cobol.rescale(v, from: sc, to: scale)
        }
        switch program {
        case "drv09":
            let c = Maps09.checkDigit(str("code"))
            return ["check": c ?? 0, "valid": c != nil]
        case "drv04":
            let bin = Maps04.toBinary(str("date"))
            return ["valid": bin != 0, "integer": bin, "normalized": bin != 0 ? Cobol.rtrim(Maps04.normalized(str("date"))) as Any : NSNull()]
        case "drvvat":
            return ["vat": Pic.edit("9(6).99", value: vat(net: dec("net", 2), rate: dec("rate", 2)), scale: 2).trimmingLeadingZeros()]
        case "drvage":
            return ["bucket": ageBucket(days: dec("days", 0))]
        case "drvavg":
            guard let c = averageCost(value: dec("value", 2), qty: dec("qty", 0)) else { return nil }
            return ["cost": Pic.edit("-(6)9.9999", value: c, scale: 4).trimmingCharacters(in: .whitespaces)]
        default:
            return nil
        }
    }
}

extension String {
    /// "000020.00" → "20.00"
    func trimmingLeadingZeros() -> String {
        var s = Substring(self)
        while s.count > 1, s.first == "0", s.dropFirst().first != "." { s = s.dropFirst() }
        return String(s)
    }
}
