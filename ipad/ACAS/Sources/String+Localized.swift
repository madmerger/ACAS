import SwiftUI

/// アプリの表示言語。完全日本語化のため端末の言語設定に依らず日本語を既定とし、
/// 起動引数 `-acasLanguage en` のときだけ英語 (レガシー原文) に切り替える。
enum AppLanguage {
    static let code: String = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-acasLanguage"), i + 1 < args.count, args[i + 1] == "en" { return "en" }
        return "ja"
    }()
    static let bundle: Bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
}

extension String {
    /// SwiftUI の Text など LocalizedStringKey を受け取る箇所用
    var localized: LocalizedStringKey { LocalizedStringKey(localizedString) }

    /// 解決済みの String が必要な箇所用
    var localizedString: String {
        AppLanguage.bundle.localizedString(forKey: self, value: nil, table: nil)
    }
}
