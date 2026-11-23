import Foundation

/// pl900.cbl: 小切手メニュー (Cheque Menu)
enum PLB900 {
    static let progName = "PL900 (3.01.02)"

    static func run(_ s: Session) throws {
        let c = s.console
        s.delLink = s.caller
        s.caller = s.called
        var reply: Int64 = 0
        menu: while true {
            reply = 0
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            c.display(s.t("pl900.title"), at: 136, color: 2)
            c.display(PLB.wsDate(s), at: 171, color: 2)
            c.display(s.t("pl900.select"), at: 501, color: 2)
            c.display(s.t("pl900.opt1"), at: 811, color: 2)
            c.display(s.t("pl900.opt2"), at: 1011, color: 2)
            c.display(s.t("pl900.opt3"), at: 1211, color: 2)
            c.display(s.t("pl900.opt4"), at: 1411, color: 2)
            c.display(s.t("pl900.opt5"), at: 1611, color: 2)
            c.display(s.t("pl900.opt6"), at: 1811, color: 2)
            c.display(s.t("pl900.opt9"), at: 2111, color: 2)
            while true {
                reply = try PLB.acceptNum(s, at: 543, digits: 1, initial: reply, options: [.auto], color: 6)
                if reply == 9 { break menu }
                if (1...6).contains(reply) {
                    s.called = "pl9\(reply)0"
                    try s.call(s.called)
                    continue menu
                }
            }
        }
        s.called = s.caller
        s.caller = s.delLink
    }
}
