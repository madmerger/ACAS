import Foundation

/// stock/st050.cbl: Stock Compression Utility (在庫ファイルの圧縮・再作成)
enum ST050 {
    static let progName = "ST050 (3.01.06)"

    static func run(_ s: Session) throws {
        let c = s.console
        let convDate = ST.convDate(s)
        let a = ST.layout.size, b = 400   // length (Stock-Record) / length (Temp-Stock-Record)
        if a != b {
            c.display(" ", at: 401, eraseEOS: true)
            c.display(s.t("st050.st505"), at: 401, color: 4, highlight: true)
            c.display(s.t("st050.stock_file"), at: 601, color: 2)
            c.display(Cobol.z(a, 4), at: 614, color: 2, highlight: true)
            c.display(s.t("st050.temp_file"), at: 701, color: 2)
            c.display(Cobol.z(b, 4), at: 714, color: 2, highlight: true)
            try ST.maps99(s, 45)
            return
        }
        // aa010-Questions
        c.display(progName, at: 101, color: 2, eraseEOS: true)
        c.display(s.t("st050.title"), at: 128, color: 2)
        c.display(convDate, at: 171, color: 2)
        c.display(s.t("st050.clean_up"), at: 410, color: 2)
        c.display(s.t("st050.recovery"), at: 610, color: 2)
        // aa020-Recovery
        var recovery = "N"
        while true {
            recovery = try c.accept(at: 668, size: 1, initial: "N", options: [.update], color: 6).uppercased()
            if recovery == "N" || recovery == "Y" { break }
            c.display(s.t("st050.st502"), at: 23, 1, color: 4, highlight: true)
        }
        // aa030-U-Sure
        while true {
            c.display(s.t("st050.confirm"), at: 810, color: 2)
            let reply = try c.accept(at: 868, size: 1, initial: "N", options: [.update], color: 6).uppercased()
            if reply != "N" && reply != "Y" {
                c.display(s.t("st050.st502"), at: 23, 1, color: 4, highlight: true)
                continue
            }
            if reply == "N" { return }
            break
        }
        c.display(" ", at: 23, 1, eraseEOL: true)
        let f = ST.stockFile(s)
        let temp = ST.tempStockPath(s)

        func fail(_ key: String, _ status: String, _ col: Int) throws {
            c.display(s.t(key), at: 23, 1, color: 4, highlight: true)
            c.display(status, at: 23, col, color: 2, highlight: true)
            c.display(ST.evalStatus(s, status), at: 23, col + 3, color: 2, highlight: true)
            try ST.maps99(s, 45)
        }

        if recovery == "Y" {
            c.display(s.t("st050.recreating"), at: 1210, color: 2, highlight: true, eraseEOL: true)
        } else {
            if f.open() != "00" { try fail("st050.st501", f.status, 28); return }
            s.store.writeRaw(temp, [])   // open output Temp-Stock-File
            c.display(s.t("st050.updating"), at: 1210, color: 2, highlight: true, eraseEOL: true)
            // ba000-Process-Stock-Comp
            while var rec = f.readNext() {
                // compute Stock-Value = Stock-Held * Stock-Cost (9(9)v99、符号無し・切り捨て)
                let v = Cobol.rescale(rec.int("stock-held") * rec.int("stock-cost"), from: 4, to: 2)
                rec.setInt("stock-value", Cobol.truncate(abs(v), digits: 11, signed: false))
                s.store.appendRaw(temp, rec.bytes)
            }
            f.close()
        }
        // ba010-Build-Stock
        guard let data = s.store.readRaw(temp) else { try fail("st050.st503", "35", 31); return }
        f.openOutput()
        // ba020-Read-Temp
        var off = 0
        while off < data.count {
            let rec = Record(ST.layout, bytes: Array(data[off..<min(off + 400, data.count)]))
            off += 400
            if ST.write(f, rec) != "00" {
                try fail("st.st000", f.status, 38)
                break
            }
        }
        f.close()
    }
}
