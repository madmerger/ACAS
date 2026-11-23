import Foundation

/// 文言テーブル。`en` はレガシー画面の英語原文 (= 英日対応表の英語側)、`ja` は製品で表示する日本語。
/// 日本語は英語原文と同じセル幅に揃えて描画するため、入力項目の位置はレガシーと一致する。
public final class L10n: @unchecked Sendable {
    public enum Language: String, Sendable { case ja, en }
    public let en: [String: String]
    public let ja: [String: String]
    public var language: Language

    public init(en: [String: String], ja: [String: String], language: Language = .ja) {
        self.en = en; self.ja = ja; self.language = language
    }

    /// `Resources/Localization` ディレクトリ (en.lproj / ja.lproj) から読む
    public convenience init(directory: URL, language: Language = .ja) throws {
        let en = try Self.parse(String(contentsOf: directory.appendingPathComponent("en.lproj/Localizable.strings"), encoding: .utf8))
        let ja = try Self.parse(String(contentsOf: directory.appendingPathComponent("ja.lproj/Localizable.strings"), encoding: .utf8))
        self.init(en: en, ja: ja, language: language)
    }

    /// 画面用文言。日本語は英語原文のセル幅へ揃える。
    public func t(_ key: String) -> String {
        guard let e = en[key] else { return key }
        if language == .en { return e }
        guard let j = ja[key] else { return e }
        return CellWidth.fit(j, CellWidth.of(e))
    }

    /// 幅を揃えない文言 (帳票見出し・UI ラベル等)
    public func raw(_ key: String) -> String {
        if language == .en { return en[key] ?? key }
        return ja[key] ?? en[key] ?? key
    }

    /// `"key" = "value";` 形式を読む
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        let chars = Array(text)
        var i = 0
        func readString() -> String? {
            guard i < chars.count, chars[i] == "\"" else { return nil }
            i += 1
            var s = ""
            while i < chars.count, chars[i] != "\"" {
                if chars[i] == "\\", i + 1 < chars.count {
                    i += 1
                    switch chars[i] {
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    default: s.append(chars[i])
                    }
                } else { s.append(chars[i]) }
                i += 1
            }
            i += 1
            return s
        }
        while i < chars.count {
            let c = chars[i]
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if c == "\"" {
                guard let k = readString() else { break }
                while i < chars.count, chars[i] != "\"" && chars[i] != ";" { i += 1 }
                if i < chars.count, chars[i] == "\"", let v = readString() { out[k] = v }
                while i < chars.count, chars[i] != ";" { i += 1 }
                i += 1
            } else { i += 1 }
        }
        return out
    }
}
