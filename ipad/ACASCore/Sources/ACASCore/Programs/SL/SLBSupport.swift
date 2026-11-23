import Foundation

/// 売掛元帳 後半 (sl100〜sl200, sl900〜sl960) の共通補助
enum SLB {
    /// 数値項目 (pic 9(n)) の ACCEPT。戻り値は項目へ MOVE した値。
    static func acceptNum(_ s: Session, at llcc: Int, digits: Int, initial: Int64? = nil,
                          options: AcceptOptions = [], color: UInt8 = 0) throws -> Int64 {
        var o = options
        if initial != nil { o.insert(.update) }
        let r = try s.console.accept(at: llcc, size: digits, kind: .numeric,
                                     initial: Cobol.z(initial ?? 0, digits), options: o, color: color)
        return Cobol.moveNumeric(r, digits: digits, scale: 0)
    }

    /// zz070-Convert-Date: to-day (UK) を Date-Form の表示形式へ
    static func wsDate(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, s.toDay)
    }

    static func upper(_ x: String) -> String { x.uppercased() }
}
