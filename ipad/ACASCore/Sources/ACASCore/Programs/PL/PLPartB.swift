import Foundation

/// pl100〜pl190, pl900〜pl960
enum PLPartB {
    static func register(_ s: Session) {
        s.programs["pl100"] = PLB100.run
        s.programs["pl115"] = PLB115.run
        s.programs["pl120"] = PLB120.run
        s.programs["pl130"] = PLB130.run
        s.programs["pl140"] = PLB140.run
        s.programs["pl160"] = PLB160.run
        s.programs["pl165"] = PLB165.run
        s.programs["pl170"] = PLB170.run
        s.programs["pl180"] = PLB180.run
        s.programs["pl190"] = PLB190.run
        s.programs["pl900"] = PLB900.run
        s.programs["pl910"] = PLB910.run
        s.programs["pl920"] = PLB920.run
        s.programs["pl930"] = PLB930.run
        s.programs["pl940"] = PLB940.run
        s.programs["pl950"] = PLB950.run
        s.programs["pl960"] = PLB960.run
        // 検証用の買掛メニュー (PLA 版が未登録の場合のみ)
        PLBDevMenu.registerIfMissing(s)
    }
}
