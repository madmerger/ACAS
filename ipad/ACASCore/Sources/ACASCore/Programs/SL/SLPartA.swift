import Foundation

/// sales.cbl, sl000〜sl095
enum SLPartA {
    static func register(_ s: Session) {
        s.programs["sales"] = SLASales.run
        s.programs["sl000"] = SLA000.run
    }
}
