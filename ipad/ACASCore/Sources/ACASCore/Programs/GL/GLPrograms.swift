import Foundation

/// 総勘定元帳 (general, gl000-gl120) のプログラム登録
public enum GLPrograms {
    public static func register(_ s: Session) {
        s.programs["general"] = General.run
        s.programs["gl000"] = GL000.run
    }
}
