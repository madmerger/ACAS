import Foundation

/// common/xl150.cbl: 期末 (サイクル末) 処理。得意先・仕入先元帳、未決済明細、請求書、分析値ファイルを繰り越す。
enum XL150 {
    static let progName = "xl150 (3.00.03)"
    struct MenuExit: Error {}
    struct MenuEx: Error {}

    private static let c3 = FieldType.comp3(digits: 10, scale: 2, signed: true)
    private static let c3s = FieldType.comp3(digits: 9, scale: 2, signed: true)
    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static let bc = FieldType.native(bytes: 1, signed: true)
    private static let d1 = FieldType.n9(digits: 1, scale: 0, signed: false)

    /// fdsl.cob (sales-record, 300 バイト) のうち本処理が参照する項目
    static let salesLayout = Layout("xl150-sales", [
        ("key", .x(7)), ("", .filler(186)), ("status", d1), ("", .filler(22)), ("activety", bl), ("", .filler(8)),
        ("average", bl), ("", .filler(16)), ("current", c3), ("last", c3),
        ("turnover-q1", c3), ("turnover-q2", c3), ("turnover-q3", c3), ("turnover-q4", c3), ("unapplied", c3), ("", .filler(10))
    ])
    /// fdpl.cob (purch-record, 300 バイト)
    static let purchLayout = Layout("xl150-purch", [
        ("key", .x(7)), ("status", d1), ("", .filler(202)), ("activety", bl), ("", .filler(8)),
        ("average", bl), ("", .filler(16)), ("current", c3), ("last", c3),
        ("turnover-q1", c3), ("turnover-q2", c3), ("turnover-q3", c3), ("turnover-q4", c3), ("unapplied", c3), ("", .filler(16))
    ])
    /// fdval.cob (value-record, 66 バイト)
    static let valueLayout = Layout("xl150-value", [
        ("system", .x(1)), ("", .filler(35)),
        ("t-this", .comp(digits: 5, scale: 0, signed: false)), ("t-last", .comp(digits: 5, scale: 0, signed: false)), ("", .filler(4)),
        ("v-this", c3), ("v-last", c3), ("", .filler(6))
    ])
    /// sales/wssoi.cob (soi-header, 114 バイト)
    static let soiLayout = Layout("xl150-soi", [
        ("", .filler(7)), ("invoice", bl), ("", .filler(10)), ("type", d1), ("", .filler(27)), ("p-c", c3s), ("", .filler(40)),
        ("status", d1), ("", .filler(1)), ("deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("", .filler(9)),
        ("applied", .x(1)), ("", .filler(4))
    ])
    /// purchase/wssoi.cob (poi-header, 109 バイト)
    static let poiLayout = Layout("xl150-poi", [
        ("", .filler(7)), ("invoice", bl), ("", .filler(10)), ("type", d1), ("", .filler(22)), ("p-c", c3s), ("", .filler(40)),
        ("status", d1), ("", .filler(1)), ("deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("", .filler(9)),
        ("applied", .x(1)), ("", .filler(4))
    ])
    /// sales/wsinv.cob (sinvoice-header, 137 バイト)
    static let sihLayout = Layout("xl150-sih", [
        ("", .filler(9)), ("test", bc), ("", .filler(7)), ("date", bl), ("", .filler(10)), ("type", d1), ("", .filler(82)),
        ("status", .x(1)), ("", .filler(5)), ("lines", bc), ("", .filler(14)), ("day-book-flag", .x(1)), ("", .filler(1))
    ])
    /// purchase/wspinv.cob (pinvoice-header, 100 バイト)
    static let pihLayout = Layout("xl150-pih", [
        ("", .filler(8)), ("test", bc), ("", .filler(21)), ("type", d1), ("", .filler(50)),
        ("status", .x(1)), ("lines", bc), ("", .filler(14)), ("day-book-flag", .x(1)), ("", .filler(2))
    ])
    static let tempInvoiceSize = 129
    static let openItemSSize = 114

    final class Run {
        let s: Session
        let c: Console
        var ledgers: String
        var irs: String
        var wsReply = " "
        var newQuarter = 0, newYear = 0
        var slEoc = 0, plEoc = 0
        var uBin = 0
        var sys: Record { get { s.sys } set { s.sys = newValue } }

        init(_ s: Session) {
            self.s = s; c = s.console
            ledgers = s.ledgers; irs = s.irsDir
        }

        func path(_ name: String) -> String { ledgers + name }
        func fileStatus(_ n: Int) -> Int { IRS.num(String(Array(sys.str("file-statuses"))[n - 1])) }
        func upperReply(at: Int, initial: String? = nil, color: UInt8) throws -> String {
            let r = initial == nil ? try c.accept(at: at, size: 1, color: color)
                : try c.accept(at: at, size: 1, initial: initial!, options: [.update], color: color)
            return r.uppercased()
        }
        func maps99(_ code: Int) throws {
            s.shared["error-code"] = code
            try s.call("maps99")
        }
        func fit(_ b: [UInt8], _ size: Int) -> [UInt8] {
            b.count >= size ? Array(b[0..<size]) : b + [UInt8](repeating: 0x20, count: size - b.count)
        }
        func clearIndexed(_ file: String) {
            s.store.deleteFile(file)
            s.store.createIndexed(file)
        }

        // MARK: init01 section

        func main() throws {
            try getProgramArgs()
            do {
                do {
                    do {
                        try confirm()
                    } catch is MenuExit {}
                    // menu-exit
                    if slEoc == 1 { sys["oi-3-flag"] = "Y" }
                    if plEoc == 1 { sys["oi-5-flag"] = "Y" }
                }
            } catch is MenuEx {}
        }

        func callFoul() throws -> Never {
            try maps99(15)
            try menuError()
        }
        func menuError() throws -> Never {
            s.termCode = 2
            throw MenuExit()
        }

        func confirm() throws {
            displayHeads()
            uBin = Maps04.toBinary(s.toDay)
            if fileStatus(15) != 1 {
                try maps99(26)
                try callFoul()
            }
            acptReply: while true {
                wsReply = "N"
                c.display(s.t("xl150.warning_date"), at: 501, color: 4)
                c.display(s.t("xl150.backup"), at: 612, color: 2)
                c.display(s.t("xl150.confirm"), at: 712, color: 2)
                wsReply = try upperReply(at: 763, initial: wsReply, color: 6)
                if wsReply == "N" { try menuError() }
                if wsReply != "Y" { continue }
                if sys.int("s-flag-i") == 1 || sys.int("p-flag-i") == 1 {
                    c.display(s.t("xl150.xl101"), at: 1201, color: 4)
                    c.display(s.t("xl150.ok_to_proceed"), at: 1301, color: 2)
                    wsReply = try upperReply(at: 1324, initial: "Y", color: 2)
                    if wsReply == "N" { try menuError() }
                }
                let sp = sys.int("s-flag-p"), pp = sys.int("p-flag-p")
                if sp == 1 || sp == 2 || pp == 1 || pp == 2 {
                    c.display(s.t("xl150.xl102"), at: 1201, color: 4)
                    c.display(s.t("xl150.xl001"), at: 1301, color: 2)
                    wsReply = try c.accept(at: 1331, size: 1, color: 2)
                    try menuError()
                }
                if sys.int("s-flag-a") == 1 || sys.int("p-flag-a") == 1 {
                    c.display(s.t("xl150.xl103"), at: 1201, color: 4)
                    c.display(s.t("xl150.xl001"), at: 1301, color: 2)
                    wsReply = try c.accept(at: 1331, size: 1, color: 2)
                    s.termCode = 1
                    throw MenuExit()
                }
                c.display(s.t("xl150.password"), at: 1601, color: 2)
                let passwd = try c.accept(at: 1616, size: 4, options: [.secure], color: 2)
                var encoded = "    "
                if passwd != "    " { encoded = Cobol.x(Maps01.encodePassword(passwd), 4) }
                if sys.str("pass-word") != encoded {
                    s.termCode = 3
                    throw MenuEx()
                }
                // request-ledgers
                if sys.int("level-3") == 1 {
                    c.display(s.t("xl150.run_sales"), at: 1601, color: 2)
                    wsReply = try upperReply(at: 1643, color: 6)
                    if wsReply == "Y" { slEoc = 1 }
                }
                if sys.int("level-2") == 1 {
                    c.display(s.t("xl150.run_purchase"), at: 1701, color: 2)
                }
                // レガシーでは上の IF が DISPLAY の直後のピリオドで終わるため、以下は仕入先元帳の有無に関係なく実行される
                wsReply = try upperReply(at: 1746, color: 6)
                if wsReply == "Y" { plEoc = 1 }
                if slEoc == 0 && plEoc == 0 {
                    c.display(s.t("xl150.xl104"), at: 1901, color: 2)
                    continue acptReply
                }
                if fileStatus(29) != 1 && plEoc == 1 {
                    try maps99(25)
                    try callFoul()
                }
                if fileStatus(19) != 1 && slEoc == 1 {
                    try maps99(19)
                    try callFoul()
                }
                break
            }
            displayHeads()
            // display-end
            try checkEndOfCycle()
            if slEoc == 1 {
                slProcessing()
                sys.setInt("s-end-cycle-date", Int64(uBin))
            }
            if plEoc == 1 {
                plProcessing()
                sys.setInt("bl-end-cycle-date", Int64(uBin))
            }
        }

        func displayHeads() {
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            c.display(s.t("xl150.title"), at: 130, color: 2)
            // zz070-Convert-Date
            if sys.int("date-form") == 0 { sys.setInt("date-form", 1) }
            c.display(Common.convDate(s, s.toDay), at: 171, color: 2)
        }

        // MARK: 元帳レコードの繰越 (phase-1 / 1B)

        func ledgerPhase1(file: String, layout: Layout) {
            if newQuarter == 1 { c.display("A", at: 1208, color: 2) }
            let quarter = Int(sys.int("current-quarter"))
            for (key, data) in s.store.all(file) {
                var r = Record(layout, bytes: data)
                if r.int("current") == 0 && r.int("last") == 0 && r.int("unapplied") == 0 { r.setInt("status", 0) }
                if r.int("current") < 0 {
                    let cur = -r.int("current")
                    r.setInt("unapplied", IRS060.wrap(r.int("unapplied") + cur, 10))
                    r.setInt("current", 0)
                }
                r.setInt("last", r.int("current"))
                if newQuarter == 1 && (1...4).contains(quarter) { r.setInt("turnover-q\(quarter)", 0) }
                if newYear == 1 { r.setInt("average", 0); r.setInt("activety", 0) }
                // new-quarter = 1 の場合は作業ファイル経由で全件を書き直す (結果は同じ)
                _ = s.store.rewrite(file, key: key, data: r.bytes)
            }
            if newQuarter == 1 {
                c.display("1B", at: 1207, color: 2)
                s.store.writeRaw(path("work.tmp"), [])
            }
        }

        // MARK: 未決済明細 (phase-2 / 2B)

        func openItemPhase2(file: String, layout: Layout, kill: (Record) -> Void) {
            c.display("2A", at: 1207, color: 2)
            var kept = [[UInt8]]()
            for (_, data) in s.store.all(file) {
                var h = Record(layout, bytes: fit(data, layout.size))
                if h.int("status") == 1 {
                    kill(h)
                    continue
                }
                let type = h.int("type")
                if type == 1 { continue }
                if type == 5 || type == 6 { h.setInt("deduct-amt", 0) }
                h["applied"] = "z"
                h.setInt("p-c", 0)
                kept.append(fit(h.bytes, XL150.openItemSSize))
            }
            c.display("2B", at: 1207, color: 2)
            clearIndexed(file)
            for rec in kept {
                let out = fit(rec, layout.size)
                _ = s.store.write(file, key: Array(out[0..<11]), data: out)
            }
            s.store.writeRaw(path("oisort.wrk"), [])
        }

        // MARK: 分析値ファイル (phase-3)

        func valuePhase3(system: String) {
            c.display("3 ", at: 1207, color: 2)
            let file = path("value.dat")
            if newYear == 1 {
                clearIndexed(file)
                c.display(s.t("xl150.value_reset"), at: 1401, color: 2)
                return
            }
            for (key, data) in s.store.all(file) {
                var r = Record(XL150.valueLayout, bytes: data)
                if r.str("system") != system { continue }
                r.setInt("t-last", r.int("t-this")); r.setInt("t-this", 0)
                r.setInt("v-last", r.int("v-this")); r.setInt("v-this", 0)
                _ = s.store.rewrite(file, key: key, data: r.bytes)
            }
        }

        // MARK: 請求書ファイルの書き直し (phase-5)

        func rewriteInvoices(file: String, temp: [[UInt8]], recordSize: Int, keyLength: Int) {
            c.display("4B", at: 1207, color: 2)
            clearIndexed(file)
            for t in temp {
                let out = fit(t, recordSize)
                _ = s.store.write(file, key: Array(out[0..<keyLength]), data: out)
            }
            s.store.writeRaw(path("work.tmp"), [])
        }

        /// system-record-4 の当月残高を前月へ移し、当月値をゼロにする (phase-6)
        func phase6(base: Int) {
            c.display("5 ", at: 1207, color: 2)
            var r4 = s.sysRecord4
            for i in 0..<6 { r4[base + i] = r4[base + 6 + i] }
            for f in 1...7 {
                for i in 0..<6 { r4[base + f * 6 + i] = i == 5 ? 0x0c : 0 }
            }
            s.sysRecord4 = r4
        }

        // MARK: sl-processing section

        func slProcessing() {
            c.display(s.t("xl150.phase1_sales"), at: 1201, color: 2)
            c.display("*******", at: 1301, color: 2)
            c.display(s.t("xl150.please_wait_sales"), at: 1501, color: 2)
            ledgerPhase1(file: path("salesled.dat"), layout: XL150.salesLayout)
            let invFile = path("invoice.dat")
            openItemPhase2(file: path("openitm3.dat"), layout: XL150.soiLayout) { self.killInvoices($0, invFile) }
            valuePhase3(system: "S")
            // phase-4
            c.display("4A", at: 1207, color: 2)
            let pfTest = uBin - Int(sys.int("pf-retention"))
            let invTest = abs(uBin - 92) % 100000
            let recs = s.store.all(invFile).map { $0.data }
            let recordSize = recs.first?.count ?? 134
            let ownNos = sys.str("sl-own-nos")
            var temp = [[UInt8]]()
            var i = 0
            phase4: while i < recs.count {
                var h = Record(XL150.sihLayout, bytes: fit(recs[i], XL150.sihLayout.size))
                i += 1
                let type = h.int("type"), lines = Int(h.int("lines")), date = Int(h.int("date"))
                func skip() -> Bool {
                    for _ in 0..<max(lines, 0) {
                        if i >= recs.count { return false }
                        i += 1
                    }
                    return true
                }
                func copyOut() { temp.append(fit(h.bytes, XL150.tempInvoiceSize)) }
                if h.int("test") != 0 { copyOut(); continue }
                if type == 4 && pfTest > date {
                    if !skip() { break phase4 }
                    continue
                }
                if !"zZ".contains(h.str("status")) { copyOut(); continue }
                if type < 4 { h["day-book-flag"] = "B" }
                if lines != 0 && type == 2 {
                    if !skip() { break phase4 }
                    h.setInt("lines", 0)
                    copyOut(); continue
                }
                if type == 1 || type == 3 {
                    if !skip() { break phase4 }
                    continue
                }
                if ownNos != "Y" { copyOut(); continue }
                if type == 2 && invTest > date { continue }
                copyOut()
            }
            rewriteInvoices(file: invFile, temp: temp, recordSize: recordSize, keyLength: 10)
            phase6(base: 0)
        }

        // MARK: kill-invoices section

        func killInvoices(_ soi: Record, _ file: String) {
            if soi.int("type") != 2 { return }
            if sys.str("sl-own-nos") == "Y" { return }
            let nos = Array(Cobol.z(abs(soi.int("invoice")) % 100_000_000, 8).utf8)
            func key(_ item: Int) -> [UInt8] { nos + [0x20, UInt8(truncatingIfNeeded: item)] }
            killCommon(file, key: key, linesOf: { Int(Record(XL150.sihLayout, bytes: self.fit($0, XL150.sihLayout.size)).int("lines")) })
        }

        func killCommon(_ file: String, key: (Int) -> [UInt8], linesOf: ([UInt8]) -> Int) {
            var item = 0
            if let rec = s.store.read(file, key: key(0)) {
                if !s.store.delete(file, key: key(0)) { return }
                let lines = linesOf(rec)
                if lines <= 0 { return }
                // actual-delete
                for _ in 0..<lines {
                    item += 1
                    _ = s.store.delete(file, key: key(item))
                }
                return
            }
            // test-for-subs
            while true {
                item += 1
                if s.store.read(file, key: key(item)) == nil { return }
                if !s.store.delete(file, key: key(item)) { return }
            }
        }

        // MARK: pl-processing section

        func plProcessing() {
            c.display(s.t("xl150.phase1_purchase"), at: 1201, color: 2)
            c.display("*******", at: 1301, color: 2)
            c.display(s.t("xl150.please_wait_purchase"), at: 1501, color: 2)
            ledgerPhase1(file: path("purchled.dat"), layout: XL150.purchLayout)
            let invFile = path("pinvoice.dat")
            openItemPhase2(file: path("openitm5.dat"), layout: XL150.poiLayout) { self.killInvoiceP($0, invFile) }
            valuePhase3(system: "P")
            // phase-4
            c.display("4A", at: 1207, color: 2)
            let recs = s.store.all(invFile).map { $0.data }
            let recordSize = recs.first?.count ?? 129
            var temp = [[UInt8]]()
            var i = 0
            phase4: while i < recs.count {
                var h = Record(XL150.pihLayout, bytes: fit(recs[i], XL150.pihLayout.size))
                i += 1
                let type = h.int("type"), lines = Int(h.int("lines"))
                func skip() -> Bool {
                    for _ in 0..<max(lines, 0) {
                        if i >= recs.count { return false }
                        i += 1
                    }
                    return true
                }
                func copyOut() { temp.append(fit(h.bytes, XL150.tempInvoiceSize)) }
                if h.int("test") != 0 { copyOut(); continue }
                if !"zZ".contains(h.str("status")) { copyOut(); continue }
                if type < 4 { h["day-book-flag"] = "B" }
                if type == 1 || type == 3 {
                    if !skip() { break phase4 }
                    continue
                }
                if lines != 0 && type == 2 {
                    if !skip() { break phase4 }
                    h.setInt("lines", 0)
                }
                copyOut()
            }
            rewriteInvoices(file: invFile, temp: temp, recordSize: recordSize, keyLength: 9)
            phase6(base: 60)
        }

        // MARK: kill-invoicep section

        func killInvoiceP(_ poi: Record, _ file: String) {
            if poi.int("type") != 2 { return }
            let nos = Array(Cobol.z(abs(poi.int("invoice")) % 100_000_000, 8).utf8)
            func key(_ item: Int) -> [UInt8] { nos + [UInt8(truncatingIfNeeded: item)] }
            killCommon(file, key: key, linesOf: { Int(Record(XL150.pihLayout, bytes: self.fit($0, XL150.pihLayout.size)).int("lines")) })
        }

        // MARK: check-end-of-cycle section

        func checkEndOfCycle() throws {
            var cyclea = Int(sys.int("scycle")) + 1
            var quarter = Int(sys.int("current-quarter"))
            func nextQuarter() { quarter = (quarter + 1) % 10; newQuarter = 1 }
            func reset() { cyclea = 1; quarter = 1; newYear = 1; newQuarter = 1 }
            let period = sys.int("period")
            if period == 3 {
                if cyclea == 4 || cyclea == 7 || cyclea == 10 { nextQuarter() } else if cyclea == 13 { reset() }
            } else if period == 13 {
                if cyclea == 14 || cyclea == 27 || cyclea == 40 { nextQuarter() } else if cyclea == 53 { reset() }
            } else {
                // query-check
                while true {
                    c.display(s.t("xl150.end_of_quarter"), at: 1601, color: 2)
                    wsReply = try upperReply(at: 1639, color: 6)
                    if wsReply == "N" { break }
                    if wsReply != "Y" { continue }
                    if quarter != 4 { nextQuarter() } else { reset() }
                    break
                }
            }
            sys.setInt("scycle", Int64(cyclea))
            sys.setInt("current-quarter", Int64(quarter))
        }

        // MARK: zz010-Get-Env-Set-Files / zz020-Get-Program-Args

        func abort(_ show: () -> Void) throws -> Never {
            show()
            c.display(s.t("xl150.xl008"), at: 1210, color: 3, highlight: true)
            wsReply = try c.accept(at: 1243, size: 1)
            throw StopRun()
        }

        func getProgramArgs() throws {
            let env = s.environment
            if (env["ACAS_IRS"] ?? "").isEmpty || (env["ACAS_LEDGERS"] ?? "").isEmpty || (env["ACAS_BIN"] ?? "").isEmpty {
                try abort { c.display(s.t("xl150.xl009"), at: 505, color: 3, highlight: true, eraseEOS: true) }
            }
            let args = s.arguments
            if args.count > 2 {
                try abort {
                    c.display(s.t("xl150.xl006"), at: 101, color: 3, eraseEOS: true)
                    c.display(String(args.count % 10), at: 164, color: 3)
                }
            }
            for a in args {
                if a.hasPrefix("ACAS_LEDGERS=") {
                    let v = String(a.dropFirst(13))
                    ledgers = v.hasSuffix("/") ? v : v + "/"
                } else if a.hasPrefix("ACAS_IRS=") {
                    let v = String(a.dropFirst(9))
                    irs = v.hasSuffix("/") ? v : v + "/"
                } else {
                    try abort { c.display(s.t("xl150.xl007"), at: 101, color: 3, eraseEOS: true) }
                }
            }
            // zz020-Set-the-Paths: ファイル名の試験表示は直後の display-heads で消去される
            c.display(" ", at: 101, eraseEOS: true)
        }
    }

    static func run(_ s: Session) throws { try Run(s).main() }
}
