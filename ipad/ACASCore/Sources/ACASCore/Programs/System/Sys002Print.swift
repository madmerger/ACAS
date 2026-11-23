import Foundation

/// sys002.cbl print-params / sl-print: システム設定帳票
enum Sys002Print {
    static func run(_ s: Session, _ st: Sys002.State) throws {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(Sys002.t(s, "print_q"), at: 1201, color: 2)
        let r = try c.accept(at: 1233, size: 1, initial: "Y", options: [.update], color: 4)
        if r == "N" || r == "n" { return }
    }
}
