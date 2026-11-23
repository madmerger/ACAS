import Foundation

/// システム共通 (ACAS メニュー、sys002、maps04/09 等) のプログラム登録
public enum SystemPrograms {
    public static func register(_ s: Session) {
        s.programs["acas"] = ACASMenu.run
        Sys002Part.register(s)
        XL150Part.register(s)
    }
}

/// common/maps04.cbl: 日付の検証と変換。バイナリ日付は 1600-12-31 からの日数 (integer-of-date)。
public enum Maps04 {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private static let epoch = cal.date(from: DateComponents(year: 1600, month: 12, day: 31))!

    public static func integerOfDate(year: Int, month: Int, day: Int) -> Int {
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return 0 }
        return cal.dateComponents([.day], from: epoch, to: d).day ?? 0
    }

    public static func dateOfInteger(_ n: Int) -> (year: Int, month: Int, day: Int) {
        let d = cal.date(byAdding: .day, value: n, to: epoch)!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year!, c.month!, c.day!)
    }

    static func validYMD(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard y >= 1601, y <= 9999, (1...12).contains(m), d >= 1 else { return false }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let dim = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return d <= dim[m - 1]
    }

    /// dd/mm/ccyy (区切りは . , - も可) → バイナリ日付。不正は 0。
    public static func toBinary(_ date: String) -> Int {
        let a = Array(Cobol.x(date, 10).map { ".,-".contains($0) ? Character("/") : $0 })
        guard a.filter({ $0 == "/" }).count == 2 else { return 0 }
        func num(_ r: Range<Int>) -> Int? {
            let s = String(a[r])
            return s.allSatisfy({ $0.isASCII && $0.isNumber }) ? Int(s) : nil
        }
        guard let dd = num(0..<2), let mm = num(3..<5), let cc = num(6..<8), let yy = num(8..<10),
              (1...31).contains(dd), (1...12).contains(mm) else { return 0 }
        let y = cc * 100 + yy
        guard validYMD(y, mm, dd) else { return 0 }
        return integerOfDate(year: y, month: mm, day: dd)
    }

    /// バイナリ日付 → dd/mm/ccyy
    public static func toDate(_ bin: Int) -> String {
        guard bin > 0 else { return "00/00/0000" }
        let d = dateOfInteger(bin)
        return "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/\(Cobol.z(d.year, 4))"
    }

    /// UK 形式 dd/mm/ccyy を Date-Form (1=UK, 2=USA, 3=Intl) の表示形式へ
    public static func format(_ uk: String, dateForm: Int) -> String {
        let a = Array(Cobol.x(uk, 10))
        switch dateForm {
        case 2: return String(a[3..<5]) + "/" + String(a[0..<2]) + "/" + String(a[6..<10])
        case 3: return String(a[6..<10]) + "/" + String(a[3..<5]) + "/" + String(a[0..<2])
        default: return String(a)
        }
    }
}
