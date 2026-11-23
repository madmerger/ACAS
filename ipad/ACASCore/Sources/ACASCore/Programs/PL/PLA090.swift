import Foundation

/// purchase/pl090.cbl: 支払検証帳票用の整列 (Payment Proof Sort)
enum PLA090 {
    static let progName = "PL090 (3.01.01)"

    /// file-20 (oisort.wrk)。open-item-record-s は 109 バイト
    static func sortFile(_ s: Session) -> PLA.SeqFile {
        PLA.SeqFile(s, path: s.ledgers + "oisort.wrk", recSize: PLA.oiLayout.size)
    }

    static func run(_ s: Session) throws {
        s.console.display(" ", at: 101, eraseEOS: true)
        if s.sys.int("p-flag-p") == 0 {
            try PLA.maps99(s, 30)
            try PLA.maps99(s, 15)
            return
        }
        s.sys.set("oi-5-flag", "Y")
        sorting1(s)
    }

    /// sort-record は 105 バイトで open-item-record-5 (109 バイト) より短い。
    /// RELEASE で末尾 4 バイト (oi-date-cleared) が切り捨てられ、GIVING で空白が埋められる (レガシーの癖)。
    static let sortRecordSize = 105

    static func sorting1(_ s: Session) {
        let out = sortFile(s)
        let oi5 = PLA.openItem5(s)
        var recs: [Record] = []
        if oi5.open() != "00" {
            oi5.close()
            out.openOutput()
            out.close()
        } else {
            while let r = oi5.readNext() {
                let t = r.int("oi-type")
                if t == 1 || t == 3 { continue }
                if r.int("oi-b-nos") == 0 && r.int("oi-b-item") == 0 { continue }
                recs.append(r)
            }
            oi5.close()
        }
        // ascending s-b-nos s-b-item / descending s-type / ascending s-date s-invoice (同順位は投入順)
        let sorted = recs.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            for (f, asc) in [("oi-b-nos", true), ("oi-b-item", true), ("oi-type", false), ("oi-date", true), ("oi-invoice", true)] {
                let p = x.int(f), q = y.int(f)
                if p != q { return asc ? p < q : p > q }
            }
            return a.offset < b.offset
        }
        out.openOutput()
        for (_, r) in sorted {
            let pad = [UInt8](repeating: 0x20, count: out.recSize - sortRecordSize)
            out.write(Array(r.bytes[0..<sortRecordSize]) + pad)
        }
        out.close()
    }
}
