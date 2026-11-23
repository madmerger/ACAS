import Foundation

/// purchase/pl055.cbl: 仕入転記の前処理 (Invoice Post Extract)
final class PLA055 {
    static let progName = "PL055 (3.01.03)"
    static func run(_ s: Session) throws { try PLA055(s).main() }

    let s: Session
    var c: Console { s.console }
    let invoice: IndexedFile, value: IndexedFile
    let analysis: PLA.CheckedFile
    let oi4: PLA.SeqFile
    var anal = PLA.fdArea(PLA.analLayout)
    var va = PLA.fdArea(PLA.valueLayout)
    /// open-item-file-4 のレコード領域 (oi-header)
    var oi = PLA.fdArea(PLA.oiLayout)
    var analCreated = false
    var wsInvAmt: Int64 = 0

    init(_ s: Session) {
        self.s = s
        invoice = PLA.invoiceFile(s); value = PLA.valueFile(s); analysis = PLA.analysisFile(s)
        oi4 = PLA.SeqFile(s, path: PLA.openItem4Path(s), recSize: 109)
    }

    func addCount(_ f: String, _ n: Int64) { va.setInt(f, abs(va.int(f) + n) % 100_000) }
    func addValue(_ f: String, _ v: Int64) { va.setInt(f, Cobol.truncate(va.int(f) + v, digits: 10)) }
    func zeroTotals() { for f in ["va-t-this", "va-t-last", "va-t-year", "va-v-this", "va-v-last", "va-v-year"] { va.setInt(f, 0) } }
    func vaKey() -> [UInt8] { Array(va.bytes[0..<3]) }
    func valueFromAnalysis() {
        va = Record(PLA.valueLayout, bytes: anal.bytes + [UInt8](repeating: 0x20, count: 30))
        zeroTotals()
    }
    /// read value-file invalid key → false
    func readValue() -> Bool {
        if let r = value.read(key: vaKey()) { va = r; return true }
        return false
    }
    /// read analysis-file: true = INVALID KEY
    func readAnalysisInvalid() -> Bool {
        switch analysis.read(key: Array(anal.bytes[0..<3])) {
        case .ok(let r): anal = r; return false
        case .invalidKey: return true
        case .notOpen: return false
        }
    }

    func main() throws {
        if value.open() != "00" {
            value.close()
            value.openOutput()
        }
        value.close()
        if PLA.fileStatus(s, 15) == 0 {
            try PLA.maps99(s, 29)
            try PLA.maps99(s, 15)
            return
        }
        c.display(" ", at: 101, eraseEOS: true)
        c.display(PLA055.progName, at: 101, color: 2)
        c.display(s.t("pl055.title"), at: 133, color: 2)
        c.display(PLA.toDayDisplay(s), at: 171, color: 2)
        _ = invoice.open(); _ = value.open(); analysis.open()
        oi4.openExtend()

        var vatV: Int64 = 0, vatrV: Int64 = 0, carrV: Int64 = 0, discV: Int64 = 0
        var vatT: Int64 = 0, vatrT: Int64 = 0, carrT: Int64 = 0, discT: Int64 = 0
        func acc(_ t: inout Int64, _ v: inout Int64, _ work: Int64) {
            t = Cobol.truncate(t + 1, digits: 5)
            v = Cobol.truncate(v + work, digits: 9)
        }
        while let rec = invoice.readNext() {
            if rec.int("ih-test") != 0 {
                // 明細行 (fdpinv2.cob の invoice-line として参照)
                var il = Record(PLA.invLineLayout, bytes: rec.bytes)
                if il.str("il-update").uppercased() == "Z" { continue }
                va.set("va-system", "P")
                va.set("va-group", il.str("il-pa"))
                var vExists = true
                if !readValue() { create(); vExists = false }
                addCount("va-t-this", 1); addCount("va-t-year", 1)
                let n = il.str("il-type") != "3" ? il.int("il-net") : -il.int("il-net")
                addValue("va-v-this", n); addValue("va-v-year", n)
                if vExists { value.rewrite(va) } else { value.write(va) }
                if va.str("va-second") == " " { continue }
                va.set("va-second", " ")
                if !readValue() { continue }
                addCount("va-t-this", 1); addCount("va-t-year", 1)
                addValue("va-v-this", n); addValue("va-v-year", n)
                value.rewrite(va)
                il.set("il-update", "z")
                invoice.rewrite(Record(PLA.invHeaderLayout, bytes: il.bytes))
                continue
            }
            // header-analysis
            var ih = rec
            let analysed = ih.str("ih-update").uppercased() == "Z"
            let applied = ih.str("ih-status").uppercased() == "Z"
            if analysed && applied { continue }
            extract(&ih)
            if analysed {
                invoice.rewrite(ih)
                continue
            }
            let type = ih.int("ih-type")
            var work2 = Cobol.truncate(ih.int("ih-c-vat") + ih.int("ih-vat"), digits: 9)
            if type == 3 { work2 = -work2 }
            if work2 != 0 && type != 1 { acc(&vatT, &vatV, work2) }
            if work2 != 0 && type == 1 { acc(&vatrT, &vatrV, work2) }
            work2 = ih.int("ih-carriage")
            if type == 3 { work2 = -work2 }
            if work2 != 0 { acc(&carrT, &carrV, work2) }
            work2 = ih.int("ih-deduct-amt")
            if work2 != 0 { acc(&discT, &discV, work2) }
            ih.set("ih-update", "z")
            invoice.rewrite(ih)
        }
        // close-files
        va.set("va-system", "P")
        for (g, t, v) in [("vi", vatT, vatV), ("vj", vatrT, vatrV), ("za", carrT, carrV), ("zb", discT, discV)] {
            va.set("va-group", g)
            storeSpecials(t, v)
        }
        invoice.close(); analysis.close(); value.close(); oi4.close()
        PLA.setFileStatus(s, 28, 1)
        if analCreated {
            c.display(s.t("pl055.pl201"), at: 1201, color: 2)
            c.display(s.t("pl055.pl202"), at: 1401, color: 2)
            c.display(s.t("pl055.pl006"), at: 1601, color: 2)
            _ = try c.accept(at: 1645, size: 1)
        }
    }

    // MARK: create section

    func create() {
        while true {
            anal.set("pa-code", va.str("va-code"))
            if readAnalysisInvalid() {
                // create-anal
                anal.set("pa-code", va.str("va-code"))
                anal.setInt("pa-gl", 0)
                anal.set("pa-print", "")
                anal.set("pa-desc", s.l10n.raw("pl055.emergency_name"))
                analCreated = true
                analysis.write(anal)
                if anal.str("pa-group").last != " " {
                    anal.set("pa-group", String(anal.str("pa-group").prefix(1)) + " ")
                    analysis.write(anal)
                }
                continue
            }
            valueFromAnalysis()
            if va.str("va-second") == " " { return }
            let saveCode = va.str("va-code")
            va.set("va-second", " ")
            anal.set("pa-code", va.str("va-code"))
            if readAnalysisInvalid() {
                anal.set("pa-code", saveCode)
                return
            }
            valueFromAnalysis()
            value.write(va)
            va.set("va-code", saveCode); anal.set("pa-code", saveCode)
            if readAnalysisInvalid() { return }
            valueFromAnalysis()
            return
        }
    }

    // MARK: store-specials section

    func storeSpecials(_ work3: Int64, _ work2: Int64) {
        var vExists = true
        if !readValue() { create(); vExists = false }
        addCount("va-t-this", work3); addCount("va-t-year", work3)
        addValue("va-v-this", work2); addValue("va-v-year", work2)
        if vExists { value.rewrite(va) } else { value.write(va) }
        va.set("va-second", " ")
        if !readValue() { return }
        addCount("va-t-this", work3); addCount("va-t-year", work3)
        addValue("va-v-this", work2); addValue("va-v-year", work2)
        value.rewrite(va)
    }

    // MARK: extract section

    func extract(_ ih: inout Record) {
        if ih.str("ih-status").uppercased() == "Z" { return }
        let type = ih.int("ih-type")
        let sign: Int64 = type == 3 ? -1 : 1
        oi.setInt("oi-p-c", 0)
        oi.setInt("oi-invoice", ih.int("ih-invoice"))
        oi.set("oi-supplier", ih.str("ih-supplier"))
        oi.setInt("oi-date", ih.int("ih-date"))
        oi.setInt("oi-b-nos", 0); oi.setInt("oi-b-item", 0)
        oi.set("oi-order", ih.str("ih-order"))
        oi.set("oi-ref", ih.str("ih-ref"))
        oi.setInt("oi-net", sign * ih.int("ih-net"))
        oi.setInt("oi-extra", 0)
        oi.setInt("oi-carriage", sign * ih.int("ih-carriage"))
        oi.setInt("oi-vat", sign * ih.int("ih-vat"))
        oi.setInt("oi-c-vat", sign * ih.int("ih-c-vat"))
        oi.setInt("oi-e-vat", 0); oi.setInt("oi-discount", 0); oi.setInt("oi-paid", 0)
        oi.setInt("oi-days", ih.int("ih-days"))
        oi.setInt("oi-deduct-amt", ih.int("ih-deduct-amt"))
        oi.setInt("oi-deduct-vat", 0)
        oi.setInt("oi-deduct-days", ih.int("ih-deduct-days"))
        oi.setInt("oi-status", 0); oi.setInt("oi-date-cleared", 0)
        oi.setInt("oi-type", type)
        oi.set("oi-applied", " "); oi.set("oi-hold-flag", " ")
        oi.setInt("oi-cr", ih.int("ih-cr"))
        if type != 1 {
            wsInvAmt = Cobol.truncate(ih.int("ih-net") + ih.int("ih-carriage") + ih.int("ih-vat") + ih.int("ih-c-vat"), digits: 9)
        }
        if type == 2 { PLA.setSys4(s, "pl-invoices-this-month", PLA.sys4(s, "pl-invoices-this-month") + wsInvAmt) }
        if type == 3 { PLA.setSys4(s, "pl-credit-notes-this-month", PLA.sys4(s, "pl-credit-notes-this-month") + wsInvAmt) }
        ih.set("ih-status", "z")
        oi4.write(oi.bytes)
    }
}
