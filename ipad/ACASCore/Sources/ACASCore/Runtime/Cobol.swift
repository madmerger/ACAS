import Foundation

/// COBOL の数値・編集規則を再現する補助。
/// 金額等は「スケール付き整数」(例: scale 2 なら 12.34 → 1234) で扱い、桁・丸め・符号をレガシーと同一に保つ。
public enum Cobol {
    public static func pow10(_ n: Int) -> Int64 { (0..<max(n, 0)).reduce(Int64(1)) { a, _ in a * 10 } }

    /// 文字列から数値を読む (空白無視、符号・小数点対応)。戻り値は (スケール付き整数, スケール)。
    public static func numval(_ s: String) -> (Int64, Int) {
        var v: Int64 = 0
        var scale = 0
        var seenPoint = false
        var neg = false
        let up = s.uppercased()
        if up.contains("CR") || up.contains("DB") { neg = true }
        for ch in s {
            if let d = ch.wholeNumberValue, ch.isASCII {
                v = v &* 10 &+ Int64(d)
                if seenPoint { scale += 1 }
            } else if ch == "." { seenPoint = true }
            else if ch == "-" { neg = true }
        }
        return (neg ? -v : v, scale)
    }

    /// スケール変換 (切り捨て。COBOL の MOVE と同じ)
    public static func rescale(_ v: Int64, from: Int, to: Int) -> Int64 {
        if to >= from { return v * pow10(to - from) }
        return v / pow10(from - to)
    }

    /// スケール変換 (ROUNDED: 四捨五入、0 から遠い方向)
    public static func rescaleRounded(_ v: Int64, from: Int, to: Int) -> Int64 {
        if to >= from { return v * pow10(to - from) }
        let p = pow10(from - to)
        let q = v / p
        let r = abs(v % p)
        if r * 2 >= p { return v < 0 ? q - 1 : q + 1 }
        return q
    }

    /// 文字列を数値項目へ MOVE (桁あふれは上位切り捨て)
    public static func moveNumeric(_ s: String, digits: Int, scale: Int, signed: Bool = false) -> Int64 {
        let (v, sc) = numval(s)
        return truncate(rescale(v, from: sc, to: scale), digits: digits, signed: signed)
    }

    /// PIC 桁数に収める (上位桁切り捨て、符号なし項目は絶対値)
    public static func truncate(_ v: Int64, digits: Int, signed: Bool = true) -> Int64 {
        let m = pow10(digits)
        let t = abs(v) % m
        return (signed && v < 0) ? -t : t
    }

    /// ゼロ埋め固定桁 (PIC 9(n))
    public static func z(_ v: Int64, _ digits: Int) -> String {
        let s = String(abs(v) % pow10(digits))
        return String(repeating: "0", count: max(digits - s.count, 0)) + s
    }
    public static func z(_ v: Int, _ digits: Int) -> String { z(Int64(v), digits) }

    /// 左詰め・空白埋め (PIC X(n) への MOVE)
    public static func x(_ s: String, _ size: Int) -> String { FixedWidth.fit(s, size) }

    /// 右側の空白を除く
    public static func rtrim(_ s: String) -> String {
        var t = Substring(s)
        while t.last == " " { t.removeLast() }
        return String(t)
    }

    public static func upper(_ s: String) -> String { s.uppercased() }
}

/// PIC 編集 (zz9.99-, z(6)9.99cr, -(5)9.99, 99/99/9999, £££,££9.99 等)
public enum Pic {
    /// `z(3)9.99` → `zzz9.99` に展開
    public static func expand(_ pic: String) -> [Character] {
        var out: [Character] = []
        let chars = Array(pic.lowercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "(", let close = chars[i...].firstIndex(of: ")"), let last = out.last,
               let n = Int(String(chars[(i + 1)..<close])) {
                if n > 1 { out.append(contentsOf: [Character](repeating: last, count: n - 1)) }
                else if n == 0 { out.removeLast() }
                i = close + 1
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }

    public static func size(_ pic: String) -> Int { expand(pic).filter { $0 != "v" && $0 != "s" }.count }

    public static func edit(_ pic: String, value: Int64, scale: Int) -> String {
        var sym = expand(pic).filter { $0 != "s" }
        // CR/DB は 2 文字で 1 記号
        var trailer = ""
        if sym.count >= 2 {
            let tail = String(sym.suffix(2))
            if tail == "cr" || tail == "db" { trailer = tail; sym.removeLast(2) }
        }
        // 浮動挿入文字の判定
        var floatChar: Character?
        for c in ["-", "+", "$", "£"] as [Character] {
            if sym.filter({ $0 == c }).count > 1 { floatChar = c; break }
        }
        // 小数点位置
        let pointIdx = sym.firstIndex { $0 == "." || $0 == "v" }
        // 桁位置の一覧
        var isDigitPos = [Bool](repeating: false, count: sym.count)
        var firstFloatSeen = false
        for (i, c) in sym.enumerated() {
            if c == "9" || c == "z" || c == "*" { isDigitPos[i] = true }
            else if let f = floatChar, c == f {
                if firstFloatSeen { isDigitPos[i] = true } else { firstFloatSeen = true }
            }
        }
        let intPositions = sym.indices.filter { isDigitPos[$0] && (pointIdx == nil || $0 < pointIdx!) }
        let decPositions = sym.indices.filter { isDigitPos[$0] && pointIdx != nil && $0 > pointIdx! }
        let picScale = decPositions.count
        let neg = value < 0
        let mag = abs(Cobol.rescale(value, from: scale, to: picScale))
        let digitsStr = Cobol.z(mag, intPositions.count + picScale)
        let digitChars = Array(digitsStr)
        var digitAt = [Int: Character]()
        for (k, p) in (intPositions + decPositions).enumerated() { digitAt[p] = digitChars[k] }
        let allZero = mag == 0
        let allSuppress = sym.indices.allSatisfy { !isDigitPos[$0] || sym[$0] != "9" }
        var out = [Character](repeating: " ", count: sym.count)
        var significant = false
        var floatPos: Int?
        let fill: Character = sym.contains("*") ? "*" : " "
        for (i, c) in sym.enumerated() {
            if isDigitPos[i] {
                let d = digitAt[i] ?? "0"
                let afterPoint = pointIdx != nil && i > pointIdx!
                if c == "9" || significant || d != "0" || (afterPoint && !(allZero && allSuppress)) {
                    significant = true
                    out[i] = d
                } else {
                    out[i] = fill
                    if floatChar != nil, c == floatChar { floatPos = i }
                }
            } else {
                switch c {
                case ".":
                    if allZero && allSuppress { out[i] = fill == "*" ? "." : " " } else { out[i] = "."; significant = true }
                case "v": out[i] = "\u{0}"
                case ",": out[i] = significant ? "," : fill
                case "b": out[i] = " "
                case "/": out[i] = "/"
                case "0": out[i] = "0"
                case "-":
                    if floatChar == "-" { floatPos = floatPos ?? i; out[i] = " " } else { out[i] = neg ? "-" : " " }
                case "+":
                    if floatChar == "+" { floatPos = floatPos ?? i; out[i] = " " } else { out[i] = neg ? "-" : "+" }
                case "$", "£":
                    if floatChar == c { floatPos = floatPos ?? i; out[i] = " " } else { out[i] = c }
                default: out[i] = c
                }
            }
        }
        if let f = floatChar, !(allZero && allSuppress) {
            // 浮動記号は最初の有効数字の直前
            var p = floatPos ?? 0
            if let firstSig = out.indices.first(where: { isDigitPos[$0] && out[$0] != " " && out[$0] != "*" }) {
                p = firstSig - 1
                while p > 0, !(isDigitPos[p] || sym[p] == f) { p -= 1 }
            } else if let last = sym.indices.last(where: { isDigitPos[$0] || sym[$0] == f }) { p = last }
            switch f {
            case "-": out[max(p, 0)] = neg ? "-" : " "
            case "+": out[max(p, 0)] = neg ? "-" : "+"
            default: out[max(p, 0)] = f
            }
        }
        var s = String(out.filter { $0 != "\u{0}" })
        if !trailer.isEmpty { s += neg ? trailer.uppercased() : "  " }
        return s
    }
}
