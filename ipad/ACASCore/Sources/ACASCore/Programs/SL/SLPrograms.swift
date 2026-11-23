import Foundation

/// 売掛元帳 (sales, sl000-sl960) のプログラム登録
public enum SLPrograms {
    public static func register(_ s: Session) {
        SLPartA.register(s)
        SLPartB.register(s)
    }
}
