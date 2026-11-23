import Foundation

/// sys002.cbl (システム設定) と maps99 等の共通ルーチン
enum Sys002Part {
    static func register(_ s: Session) {
        s.programs["maps99"] = Sys002Maps99.run
        s.programs["sys002"] = Sys002.run
    }
}
