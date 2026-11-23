import Foundation

/// IRS 不完全記録システム (irs, irs010-irs090) のプログラム登録
public enum IRSPrograms {
    public static func register(_ s: Session) {
        s.programs["irs"] = IRSMenu.run
        s.programs["irs010"] = IRS010.run
        s.programs["irs020"] = IRS020.run
        s.programs["irs030"] = IRS030.run
        s.programs["irs040"] = IRS040.run
        s.programs["irs050"] = IRS050.run
        s.programs["irs055"] = IRS055.run
        s.programs["irs060"] = IRS060.run
        s.programs["irs065"] = IRS065.run
        s.programs["irs070"] = IRS070.run
        s.programs["irsubp"] = IRSubP.run
    }
}
