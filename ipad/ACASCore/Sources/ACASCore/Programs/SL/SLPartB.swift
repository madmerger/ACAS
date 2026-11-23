import Foundation

/// sl100〜sl200, sl900〜sl960
enum SLPartB {
    static func register(_ s: Session) {
        s.programs["sl900"] = SLB900.run
        SLBDevMenu.registerIfMissing(s)
    }
}
