import Foundation

/// 売掛元帳 前半 (sales, sl000〜sl095) 共通部品
enum SLA {
    /// System-Record の File-Status (n) (pic 9 occurs 32)
    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        let b = s.sys.raw("file-statuses")
        let v = Int(b[n - 1]) - 0x30
        return (0...9).contains(v) ? v : 0
    }

    static func setFileStatus(_ s: Session, _ n: Int, _ v: Int) {
        var b = s.sys.raw("file-statuses")
        b[n - 1] = UInt8(0x30 + v)
        s.sys.setRaw("file-statuses", b)
    }

    /// zz070-Convert-Date: to-day を Date-Form の表示形式へ
    static func convertDate(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, s.toDay)
    }

    /// 帳票ファイル (レコード順編成、WRITE ... BEFORE/AFTER ADVANCING)
    final class Printer {
        let s: Session
        let path: String
        let recLen: Int
        init(_ s: Session, name: String = "prt-1", recLen: Int = 132) {
            self.s = s; self.path = s.ledgers + name; self.recLen = recLen
        }
        func open() { s.store.writeRaw(path, []) }
        private func rec(_ line: String) -> [UInt8] { SJIS.encode(line, size: recLen) }
        func after(_ n: Int, _ line: String) {
            s.store.appendRaw(path, [UInt8](repeating: 0x0a, count: n) + rec(line))
        }
        func before(_ n: Int, _ line: String) {
            s.store.appendRaw(path, rec(line) + [UInt8](repeating: 0x0a, count: n))
        }
        func afterPage(_ line: String) { s.store.appendRaw(path, [0x0c] + rec(line)) }
        func beforePage(_ line: String) { s.store.appendRaw(path, rec(line) + [0x0c]) }
        /// close + CALL "SYSTEM" using Print-Report (印刷スプールは iPad 版では UI へ通知)
        func close(spool: Bool = true) { if spool { s.onReport?(path) } }
    }

    static func spaces(_ n: Int) -> String { String(repeating: " ", count: n) }
}
