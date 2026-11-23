import Foundation

/// purchase.cbl, pl000〜pl095
enum PLPartA {
    static func register(_ s: Session) {
        s.programs["purchase"] = PLAPurchase.run
        s.programs["pl000"] = PLA000.run
    }
}
