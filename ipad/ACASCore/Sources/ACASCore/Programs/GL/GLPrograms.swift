import Foundation

/// 総勘定元帳 (general, gl000-gl120) のプログラム登録
public enum GLPrograms {
    public static func register(_ s: Session) {
        s.programs["general"] = General.run
        s.programs["gl000"] = GL000.run
        s.programs["gl020"] = GL020.run
        s.programs["gl030"] = GL030.run
        s.programs["gl050"] = GL050.run
        s.programs["gl051"] = GL051.run
        if s.programs["maps99"] == nil { s.programs["maps99"] = GLMaps99.run }
    }
}
