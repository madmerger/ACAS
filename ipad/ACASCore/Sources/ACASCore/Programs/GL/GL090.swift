import Foundation

/// general/gl090.cbl: Trial Balance メニュー
enum GL090 {
    static let progName = "gl090 (3.00.03)"

    static func run(_ s: Session) throws {
        let c = s.console
        func t(_ k: String) -> String { s.t("gl090." + k) }
        let dates = GLDates(s)
        while true {
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            c.display(t("title"), at: 135, color: 2)
            dates.zz070()
            c.display(dates.wsDate, at: 171, color: 2)
            c.display(s.sys.str("usera"), at: 301, color: 3)
            c.display(t("select"), at: 801, color: 2)
            c.display(t("opt1"), at: 1001, color: 2)
            if s.sys.str("p-c") == "P" {
                c.display(t("opt2_pc"), at: 1201, color: 2)
            } else if s.sys.str("p-c") == "B" {
                c.display(t("opt2_branch"), at: 1201, color: 2)
            }
            c.display(t("opt9"), at: 1701, color: 2)
            let reply = Cobol.moveNumeric(try c.accept(at: 829, size: 1, kind: .numeric, initial: "9", options: [.update], color: 7), digits: 1, scale: 0)
            if reply == 1 { _ = try s.call("gl090b") }
            if reply == 2 { _ = try s.call("gl090a") }
            if reply == 9 { return }
        }
    }
}
