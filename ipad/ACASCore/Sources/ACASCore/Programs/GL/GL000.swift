import Foundation

/// general/gl000.cbl: Start Of Day (日付入力)
enum GL000 {
    static let progName = "GL000 (3.00.04)"

    static func run(_ s: Session) throws {
        let c = s.console
        let d = s.today
        var uDate = "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/20\(Cobol.z(d.year % 100, 2))"
        s.toDay = uDate
        c.display(s.t("gl.client"), at: 101, color: 2, eraseEOS: true)
        c.display(s.sys.str("usera"), at: 110, color: 3)
        c.display(progName, at: 301, color: 2)
        c.display(s.t("gl000.title"), at: 328, color: 2)
        Common.displaySerial(s)
        Common.displayTime(s, labelAt: 370, timeAt: 373)
        var bin = 0
        while true {
            // date-entry
            let form = Int(s.sys.int("date-form"))
            if !(1...3).contains(form) { s.sys.setInt("date-form", 1) }
            uDate = Common.convDate(s, uDate)
            c.display(s.t(["gl000.enter_date_uk", "gl000.enter_date_usa", "gl000.enter_date_intl"][Int(s.sys.int("date-form")) - 1]), at: 812, color: 2)
            c.display(uDate, at: 847, color: 3)
            uDate = try c.accept(at: 847, size: 10, initial: uDate, options: [.update], color: 3)
            uDate = Common.toUK(s, uDate)
            bin = Maps04.toBinary(uDate)
            if bin == 0 {
                c.display(s.t("gl000.gl009"), at: 860, color: 4)
            } else {
                c.display(" ", at: 860, eraseEOL: true)
                uDate = Maps04.normalized(uDate)
                break
            }
        }
        // chain-menu
        s.sys.setInt("run-date", Int64(bin))
        s.toDay = uDate
        s.termCode = 0
    }
}

extension Maps04 {
    /// maps04 が a-date 内の区切り文字 . , - を / へ置換した結果
    static func normalized(_ date: String) -> String {
        String(Cobol.x(date, 10).map { ".,-".contains($0) ? Character("/") : $0 })
    }
}
