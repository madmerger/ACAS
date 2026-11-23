import Foundation

/// sl100〜sl200, sl900〜sl960
enum SLPartB {
    static func register(_ s: Session) {
        s.programs["sl100"] = SLB100.run
        s.programs["sl115"] = SLB115.run
        s.programs["sl130"] = SLB130.run
        s.programs["sl140"] = SLB140.run
        s.programs["sl160"] = SLB160.run
        s.programs["sl165"] = SLB165.run
        s.programs["sl170"] = SLB170.run
        s.programs["sl180"] = SLB180.run
        s.programs["sl200"] = SLB200.run
        s.programs["sl900"] = SLB900.run
        s.programs["sl930"] = SLB930.run
        s.programs["sl940"] = SLB940.run
        SLBDevMenu.registerIfMissing(s)
    }
}
