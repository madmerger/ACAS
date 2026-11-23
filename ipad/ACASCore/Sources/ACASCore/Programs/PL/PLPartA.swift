import Foundation

/// purchase.cbl, pl000〜pl095
enum PLPartA {
    static func register(_ s: Session) {
        s.programs["purchase"] = PLAPurchase.run
        s.programs["pl000"] = PLA000.run
        s.programs["pl010"] = PLA010.run
        s.programs["pl015"] = PLA015.run
        s.programs["pl020"] = PLA020.run
        s.programs["pl030"] = PLA030.run
        s.programs["pl040"] = PLA040.run
        s.programs["pl050"] = PLA050.run
        s.programs["pl055"] = PLA055.run
        s.programs["pl060"] = PLA060.run
        s.programs["pl070"] = PLA070.run
        s.programs["pl080"] = PLA080.run
    }
}
