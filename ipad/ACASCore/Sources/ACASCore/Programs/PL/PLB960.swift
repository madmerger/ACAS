import Foundation

/// pl960.cbl: 送金案内の印刷 (Remittance Advices)
enum PLB960 {
    static let progName = "PL960 (3.01.05)"

    static func run(_ s: Session) throws {
        // cheque-file (行順編成 645 桁) が開けなければ何もせず戻る
        guard let raw = s.store.readRaw(s.ledgers + "cheque.dat") else { return }
        let prt = PLBPrint(s)
        prt.openOutput()
        func r(_ k: String) -> String { s.l10n.raw("report.pl960." + k) }
        var lines = raw.split(separator: 0x0a, omittingEmptySubsequences: false).map { Array($0) }
        if lines.last?.isEmpty == true { lines.removeLast() }
        var a = 0
        let lineBox = Cobol.x("", 29) + String(repeating: "*", count: 24)
        let line5 = Cobol.x("", 48) + String(repeating: "=", count: 10)
        for bytes in lines {
            let cheque = Array(Cobol.x(SJIS.decode(bytes[...]), 645))
            func f(_ offset: Int, _ size: Int) -> String { String(cheque[offset..<(offset + size)]) }
            if a == 1 { prt.afterPage("") } else { prt.after("", 1) }
            a = 1
            prt.after(lineBox, 1)
            prt.after(Cobol.x("", 29) + Cobol.x(r("heading"), 24), 1)
            prt.after(lineBox, 1)
            func line1(_ to: String, _ addr1: String, _ from: String, _ addr2: String) -> String {
                Cobol.x(to, 3) + Cobol.x(addr1, 32) + Cobol.x("", 6) + Cobol.x(from, 7) + Cobol.x(addr2, 32)
            }
            prt.after(line1(r("to"), f(8, 30), r("from"), s.sys.str("usera")), 3)
            for i in 0..<4 {
                prt.after(line1("", f(39 + 33 * i, 32), "", s.sys.str("address-\(i + 1)")), 1)
            }
            prt.after(line1("", f(39 + 33 * 4, 32), "", ""), 1)
            prt.after(Cobol.x(r("ac_number"), 16) + Cobol.x(f(0, 7), 19) + Cobol.x(r("date"), 5) + f(355, 10), 4)
            prt.after(Cobol.x("", 10) + Cobol.x(r("line3a"), 23) + Cobol.x("", 17) + Cobol.x(r("amount"), 7), 3)
            prt.after("", 1)
            for z in 0..<9 {
                let base = 366 + 31 * z
                let amount = Cobol.x(f(base + 20, 10), 12)
                if !amount.allSatisfy({ $0 == " " }) {
                    prt.after(Cobol.x("", 11) + Cobol.x(f(base, 10), 14) + Cobol.x(f(base + 11, 8), 23) + amount, 1)
                }
            }
            prt.after(line5, 3)
            let cCheque = f(345, 9)
            let bacs = cCheque == Cobol.x("BACS", 9)
            prt.after(Cobol.x("", 11) + Cobol.x(r("total_paid_by"), 14) + Cobol.x(r(bacs ? "bacs" : "cheque"), 7)
                      + Cobol.x(bacs ? r("to_your_bank") : cCheque, 16) + Cobol.x(f(334, 10), 12), 1)
            prt.after(line5, 1)
        }
        prt.close()
        prt.spool()
    }
}
