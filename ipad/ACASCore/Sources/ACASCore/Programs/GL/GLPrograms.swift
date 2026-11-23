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
        s.programs["gl060"] = GL060.run
        s.programs["gl080"] = GL080.run
        s.programs["gl090"] = GL090.run
        s.programs["gl090a"] = GL090A.run
        s.programs["gl090b"] = GL090B.run
        s.programs["gl070"] = GL070.run
        s.programs["gl071"] = GL071.run
        s.programs["gl072"] = GL072.run
        if s.programs["maps99"] == nil { s.programs["maps99"] = GLMaps99.run }
    }
}
