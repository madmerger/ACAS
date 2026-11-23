import Foundation

/// IRS 不完全記録システム (irs, irs010-irs090) のプログラム登録
public enum IRSPrograms {
    public static func register(_ s: Session) {
        s.programs["irs"] = IRSMenu.run
        s.programs["irs010"] = IRS010.run
        s.programs["irs020"] = IRS020.run
        s.programs["irs030"] = IRS030.run
    }
}
