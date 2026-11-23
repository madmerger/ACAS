import Foundation

/// common/maps99.cbl: エラーメッセージ表示。error.txt (行順) を検索し、無ければ既定文言を出して入力を待つ。
/// 呼び出し側は `Sys002Maps99.call(s, code)` を使う (error-pass は `s.shared["error-code"]` で渡す)。
enum Sys002Maps99 {
    static func call(_ s: Session, _ code: Int) throws {
        s.shared["error-code"] = code
        try s.call("maps99")
    }

    static func run(_ s: Session) throws {
        let c = s.console
        let errorPass = (s.shared["error-code"] as? Int) ?? 0
        var lin = 23
        s.termCode = 0
        var serv = "T", errno = errorPass, mess = s.l10n.raw("maps99.not_in_file")
        var wait = true
        // error.txt は実行ディレクトリから開く (無ければ error-close)
        if let data = s.store.readRaw("error.txt") {
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
                let a = Array(Cobol.x(String(line), 57))
                guard Int(String(a[0..<3])) == errorPass else { continue }
                errno = errorPass
                serv = String(a[3]); let response = String(a[4])
                let key = "maps99.e" + Cobol.z(errorPass, 3)
                mess = s.l10n.en[key] != nil ? s.l10n.raw(key) : String(a[7..<57])
                let errorLine = Int(String(a[5..<7])) ?? 0
                if errorLine != 0 { lin = errorLine > 19 ? 24 - (24 - errorLine) : errorLine }
                wait = response == "T" || (serv == "S" && response == "S")
                if !wait && serv == "T" { s.termCode = 9 }
                break
            }
        }
        c.display(serv + "-" + Cobol.z(errno, 3) + " " + Cobol.x(mess, 50), at: lin, 1, color: 4)
        if wait { _ = try c.accept(at: 24, 79, size: 1) }
    }
}
