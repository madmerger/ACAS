import SwiftUI
import ACASCore

enum Theme {
    static let navy = Color(red: 0.03, green: 0.09, blue: 0.22)
    static let deep = Color(red: 0.05, green: 0.16, blue: 0.38)
    static let blue = Color(red: 0.12, green: 0.42, blue: 0.90)
    static let sky = Color(red: 0.55, green: 0.78, blue: 1.0)
    static let pale = Color(red: 0.86, green: 0.93, blue: 1.0)
    static let alert = Color(red: 1.0, green: 0.45, blue: 0.45)

    /// COBOL の foreground-color (0-7) → 青基調の配色 (エラーの赤だけ識別のため残す)
    static func color(_ c: UInt8, highlight: Bool) -> Color {
        switch c {
        case 4: return alert
        case 3: return Color(red: 0.45, green: 0.88, blue: 1.0)
        case 6: return .white
        case 2: return highlight ? pale : sky
        default: return highlight ? .white : pale
        }
    }
}

/// アプリ全体の状態: 文言テーブル・ケース一覧・端末内 DB の場所
@MainActor
final class AppModel: ObservableObject {
    let cases: [ReplayCase]
    let language: L10n.Language
    let autoCase: String?
    let autoSuite: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        language = AppLanguage.code == "en" ? .en : .ja
        autoCase = value("-acasCase")
        autoSuite = value("-acasSuite")
        let url = Bundle.main.url(forResource: "cases", withExtension: "json", subdirectory: "Cases")
        cases = (url.flatMap { try? Data(contentsOf: $0) }).flatMap { try? ReplayCase.load($0) } ?? []
    }

    func l10n() -> L10n {
        func table(_ lang: String) -> [String: String] {
            guard let p = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: lang),
                  let t = try? String(contentsOfFile: p, encoding: .utf8) else {
                // Xcode は .strings をバイナリ plist へ変換することがある
                if let p = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: lang),
                   let d = NSDictionary(contentsOfFile: p) as? [String: String] { return d }
                return [:]
            }
            return L10n.parse(t)
        }
        return L10n(en: table("en"), ja: table("ja"), language: language)
    }

    func seed(_ name: String) -> Data? {
        let n = name == "pure-function" ? "empty" : name
        return Bundle.main.url(forResource: n, withExtension: "json", subdirectory: "Seeds").flatMap { try? Data(contentsOf: $0) }
    }

    var databasePath: String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("acas.sqlite").path
    }

    /// 本番用セッション (端末内 SQLite)。初回はサンプル会社のデータを投入する。
    func productionSession() -> Session {
        let fresh = !FileManager.default.fileExists(atPath: databasePath)
        let store = FileStore(path: databasePath)
        if fresh, let s = seed("biz") { try? store.load(seed: s) }
        return Session(store: store, l10n: l10n())
    }

    func resetData() {
        let store = FileStore(path: databasePath)
        if let s = seed("biz") { try? store.load(seed: s) }
    }
}
