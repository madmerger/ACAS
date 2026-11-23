public enum FixedWidth {
    public static func of(_ c: Character) -> Int {
        guard let s = c.unicodeScalars.first else { return 1 }
        let v = s.value
        // 半角カナの濁点・半濁点 (U+FF9E/FF9F) は前の文字と 1 書記素になるが、幅はそれぞれ 1 桁
        let marks = c.unicodeScalars.dropFirst().filter { $0.value == 0xFF9E || $0.value == 0xFF9F }.count
        if marks > 0 { return 1 + marks }
        if v < 0x1100 { return 1 }
        if (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v)
            || (0xFFE0...0xFFE6).contains(v) { return 2 }
        return 1
    }
    public static func of(_ s: String) -> Int { s.reduce(0) { $0 + of($1) } }

    /// 固定幅 `width` に切り詰め/空白埋めする。
    public static func fit(_ s: String, _ width: Int) -> String {
        var out = ""
        var w = 0
        for c in s {
            let cw = of(c)
            if w + cw > width { break }
            out.append(c)
            w += cw
        }
        if w < width { out += String(repeating: " ", count: width - w) }
        return out
    }
}
