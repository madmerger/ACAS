import SwiftUI

extension String {
    /// SwiftUI の Text など LocalizedStringKey を受け取る箇所用
    var localized: LocalizedStringKey { LocalizedStringKey(self) }

    /// 解決済みの String が必要な箇所用
    var localizedString: String {
        NSLocalizedString(self, comment: "\(self)_comment")
    }
}
