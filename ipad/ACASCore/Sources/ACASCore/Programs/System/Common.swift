import Foundation

/// 各プログラム共通の表示部品 (レガシーの各プログラムに重複して書かれている定型処理)
public enum Common {
    /// conv-date: UK 形式 dd/mm/ccyy (または dd/mm/yy) を Date-Form の表示形式へ
    public static func convDate(_ s: Session, _ uk: String) -> String {
        let form = Int(s.sys.int("date-form"))
        return uk.count <= 8 ? Maps04.formatShort(uk, dateForm: form) : Maps04.format(uk, dateForm: form)
    }

    /// 入力された Date-Form 形式の日付を UK 形式 dd/mm/ccyy へ戻す
    public static func toUK(_ s: Session, _ date: String) -> String {
        let a = Array(Cobol.x(date, 10))
        switch Int(s.sys.int("date-form")) {
        case 2: return String(a[3..<5]) + "/" + String(a[0..<2]) + "/" + String(a[6..<10])
        case 3: return String(a[8..<10]) + "/" + String(a[5..<7]) + "/" + String(a[0..<4])
        default: return String(a)
        }
    }

    /// "at hh:mm:ss" (accept from time)
    public static func displayTime(_ s: Session, labelAt: Int, timeAt: Int, color: UInt8 = 2) {
        s.console.display(s.t("sys.at"), at: labelAt, color: color)
        s.console.display(s.timeHHMMSS, at: timeAt, color: color)
    }

    /// "on dd/mm/yy" (accept from date)
    public static func displayShortDate(_ s: Session, labelAt: Int, dateAt: Int, color: UInt8 = 2) {
        let d = s.today
        let short = "\(Cobol.z(d.day, 2))/\(Cobol.z(d.month, 2))/\(Cobol.z(d.year % 100, 2))"
        s.console.display(s.t("sys.on"), at: labelAt, color: color)
        s.console.display(convDate(s, short), at: dateAt, color: color)
    }

    /// サブシステムメニュー共通の枠 (display-menu 〜 display-go の定型部)
    public static func menuFrame(_ s: Session, progName: String, titleKey: String, titleAt: Int) {
        let c = s.console
        c.display(" ", at: 101, eraseEOS: true)
        c.display(s.sys.str("maps-ser-xx"), at: 2474, color: 3)
        c.display(Cobol.z(s.sys.int("maps-ser-nn"), 4), at: 2476, color: 3)
        c.display(s.t("sys.copyright_prefix"), at: 2401, color: 3)
        c.display(Cobol.z(s.today.year, 4), at: 2420, color: 3)
        c.display(s.t("sys.copyright_owner"), at: 2424, color: 3)
        c.display(s.sys.str("usera"), at: 101, color: 3)
        c.display(convDate(s, s.toDay), at: 171, color: 3)
        c.display(progName, at: 301, color: 2)
        c.display(s.t(titleKey), at: titleAt, color: 2)
        displayTime(s, labelAt: 355, timeAt: 358)
        displayShortDate(s, labelAt: 367, dateAt: 370)
    }

    /// maps-ser (画面右下の製品番号)
    public static func displaySerial(_ s: Session, color: UInt8 = 2) {
        s.console.display(s.sys.str("maps-ser-xx"), at: 2474, color: color)
        s.console.display(Cobol.z(s.sys.int("maps-ser-nn"), 4), at: 2476, color: color)
    }

    /// system.dat の RRN 1/2/4 をセッションへ読み込む (get-system-recs)。失敗したレコード番号を返す。
    public static func loadSystemRecords(_ s: Session) -> Int? {
        let f = s.systemFile
        guard let r4 = f.read(4) else { return 4 }
        guard let r2 = f.read(2) else { return 2 }
        guard let r1 = f.read(1) else { return 1 }
        s.sysRecord4 = r4; s.defaultRecord = r2; s.sys = Record(SystemLayout.layout, bytes: r1)
        return nil
    }

    /// overrewrite: RRN 1/2/4 を書き戻す
    public static func rewriteSystemRecords(_ s: Session) {
        let f = s.systemFile
        f.write(1, s.sys.bytes); f.write(2, s.defaultRecord); f.write(4, s.sysRecord4)
    }
}
