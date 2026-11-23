import Foundation

/// incomplete_records_system/irs090.cbl: 月次分析表 (132 桁)
enum IRS090 {
    static let progName = "irs090 (3.01.10)"
    static let work2Name = "work2.tmp"
    struct EndProcess: Error {}

    final class Run {
        let s: Session
        let c: Console
        let ctx: IRS.Context
        let nlFile: IndexedFile
        var nl = IRS.newNL()
        var work = Record(IRS085.layout)
        var workData = [UInt8](), workPos = 0
        /// work-file-2 (科目番号 → l4-group)
        var work2 = [Int64: String]()
        var printer: IRS.Printer!
        var srReply = 0
        var pageNo = 0, lineCnt = 0
        var savedAccount: Int64 = 0
        var mths = [Int64](repeating: 0, count: 13)
        var years: Int64 = 0
        var litMonths = [String](repeating: Cobol.x("", 5), count: 13)

        init(_ s: Session) {
            self.s = s; c = s.console; ctx = IRS.context(s)
            nlFile = IndexedFile(s.store, path: s.irsDir + ctx.file1, layout: IRS.nlLayout, keyOffset: 0, keyLength: 10)
        }

        func pw(_ line: String, after n: Int) { printer.write(Cobol.x(line, 132), after: n) }

        /// pic -(7)9 への転記 (小数部切捨て)。切捨て後ゼロでも元が負なら負号が残る
        static func edit8(_ v: Int64, scale: Int) -> String {
            let whole = (abs(v) / Cobol.pow10(scale)) % 10_000_000
            if v < 0 && whole == 0 { return "      -0" }
            return Pic.edit("-(7)9", value: v < 0 ? -whole : whole, scale: 0)
        }

        func main() throws {
            try initialise()
            do { try process() } catch is EndProcess {}
            outputFinal()
            close()
        }

        // MARK: lb-init

        func initialise() throws {
            ctx.fileNames = ctx.sys.str("system-files")
            c.display(" ", at: 101, eraseEOS: true)
            c.display(progName, at: 101, color: 2)
            c.display(s.t("irs090.title"), at: 130, color: 1, reverse: true)
            c.display(ctx.sys.str("run-date"), at: 173, color: 2)
            c.display(s.t("irs090.paper"), at: 623, color: 3)
            c.display(s.t("irs090.year_start"), at: 1201, color: 2)
            repeat {
                srReply = IRS.num(try c.accept(at: 1248, size: 2, kind: .numeric, color: 3))
            } while srReply < 1 || srReply > 12
            workData = s.store.readRaw(s.irsDir + IRS085.outputName) ?? []
            workPos = 0
            nlFile.open()
            printer = IRS.Printer(s, "prt-1")
            work2 = [:]
            // lzc-set-report-months
            let lits = Array(Cobol.x(s.t("report.irs090.months"), 60))
            var b = srReply
            for a in 1...12 {
                litMonths[a] = String(lits[((b - 1) * 5)..<(b * 5)])
                b += 1
                if b > 12 { b = 1 }
            }
            headings()
        }

        // MARK: lc-process

        func readWork() -> Bool {
            let size = IRS085.layout.size
            guard workPos + size <= workData.count else { return false }
            work = Record(IRS085.layout, bytes: Array(workData[workPos..<(workPos + size)]))
            workPos += size
            return true
        }

        func process() throws {
            while true {
                if !readWork() {
                    try printLine()
                    try getNominal()
                    return
                }
                let account = work.int("account")
                if savedAccount == 0 {
                    try getNominal()
                    savedAccount = account
                }
                if savedAccount != account {
                    try printLine()
                    try getNominal()
                    savedAccount = account
                }
                var mm = IRS.num(work.str("mm"))
                if mm < 1 || mm > 12 { mm = 1 }
                mths[mm] = IRS060.wrap(mths[mm] + work.int("amount"), 10)
            }
        }

        // MARK: ld-output-final

        func outputFinal() {
            nlFile.close()
            nlFile.open()
            while nlFile.isOpen, let r = nlFile.readNext() {
                nl = r
                if nl.str("type") == "S" { continue }
                if nl.int("sub-nominal") != 0 { nl.setInt("owning", nl.int("sub-nominal")) }
                let no = nl.int("owning")
                guard let group = work2[no] else { continue }
                if lineCnt > 60 { headings() }
                pw(Pic.edit("z(4)9", value: no, scale: 0) + " " + group, after: 1)
                lineCnt += 1
            }
        }

        // MARK: le-close

        func close() {
            pw(s.t("report.irs090.rounding_note"), after: 3)
            nlFile.close()
            printer.spool()
            s.store.writeRaw(s.irsDir + IRS090.work2Name, [])
            s.store.writeRaw(s.irsDir + IRS085.outputName, [])
        }

        // MARK: lz-common-routines

        func headings() {
            pageNo = (pageNo + 1) % 100
            pw(Cobol.x(ctx.sys.str("client"), 32) + Cobol.x("", 23) + Cobol.x(s.t("report.irs090.heading"), 25) + Cobol.x("", 28)
                + ctx.sys.str("run-date") + Cobol.x("", 8) + Cobol.x(s.t("report.irs090.page"), 5) + Pic.edit("zz9", value: Int64(pageNo), scale: 0),
               after: 1)
            pw(Cobol.x(s.t("report.irs090.account_head"), 29) + "<" + String(repeating: "-", count: 46)
                + Cobol.x(s.t("report.irs090.year"), 4) + String(repeating: "-", count: 43) + ">", after: 2)
            var l3 = Cobol.x(s.t("report.irs090.columns"), 28)
            for a in 1...12 { l3 += "   " + litMonths[a] }
            pw(l3 + Cobol.x(s.t("report.irs090.total"), 9), after: 1)
            pw("", after: 1)
            lineCnt = 5
        }

        func printLine() throws {
            var months = ""
            var b = srReply
            for _ in 1...12 {
                years = IRS060.wrap(years + mths[b] / 100, 8)
                months += Run.edit8(mths[b], scale: 2)
                b += 1
                if b > 12 { b = 1 }
            }
            let no: Int64, type: String
            if nl.int("sub-nominal") == 0 { no = nl.int("owning"); type = "M" } else { no = nl.int("sub-nominal"); type = "S" }
            let group = type + " " + Cobol.x(nl.str("name"), 20) + months + Run.edit8(years, scale: 0)
            years = 0
            for i in 1...12 { mths[i] = 0 }
            if work2[no] != nil {
                c.display(s.t("irs090.reply"), at: 1601)
                c.display("FF", at: 1616)
                c.display(s.t("irs090.note_error"), at: 1625)
                _ = try c.accept(at: 1740, size: 2)
                throw EndProcess()
            }
            work2[no] = group
        }

        func getNominal() throws {
            nl.setInt("owning", work.int("account")); nl.setInt("sub-nominal", 0)
            while true {
                guard nlFile.isOpen, let r = nlFile.read(key: nl.raw("key")) else {
                    c.display(Cobol.z(nl.int("owning"), 5), at: 1401, color: 3)
                    c.display(s.t("irs090.not_exist"), at: 1407, color: 2)
                    c.display(s.t("irs090.note_error_continue"), at: 1434)
                    _ = try c.accept(at: 1471, size: 2)
                    throw StopRun()
                }
                nl = r
                if nl.str("type") != "S" { return }
                nl.setInt("sub-nominal", nl.int("owning"))
                nl.setInt("owning", nl.int("pointer"))
            }
        }
    }

    static func run(_ s: Session) throws { try Run(s).main() }
}
