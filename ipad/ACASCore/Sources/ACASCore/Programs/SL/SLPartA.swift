import Foundation

/// sales.cbl, sl000〜sl095
enum SLPartA {
    static func register(_ s: Session) {
        s.programs["sales"] = SLASales.run
        s.programs["sl000"] = SLA000.run
        s.programs["sl010"] = SLA010.run
        s.programs["sl020"] = SLA020.run
        s.programs["sl050"] = SLA050.run
        s.programs["sl055"] = SLA055.run
        s.programs["sl060"] = SLA060.run
        s.programs["sl070"] = SLA070.run
    }
}
