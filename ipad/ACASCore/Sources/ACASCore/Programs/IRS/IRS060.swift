import Foundation

/// incomplete_records_system/irs060.cbl: 決算書 (損益計算書・貸借対照表・売上比率) の作成と期末処理
enum IRS060 {
    static let progName = "irs060 (3.01.12)"
    static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    struct ExitProgram: Error {}

    static func wrap(_ v: Int64, _ digits: Int) -> Int64 {
        let m = Cobol.pow10(digits)
        return v < 0 ? -((-v) % m) : v % m
    }
    /// multiply x by 1 giving z(6)9 rounded (符号なし項目なので絶対値)
    static func whole(_ v: Int64) -> Int64 { ((abs(v) + 50) / 100) % 10_000_000 }
    static func z7(_ v: Int64) -> String { v == 0 ? "       " : Pic.edit("z(6)9", value: v, scale: 0) }
    static func justifyC(_ str: String, _ size: Int) -> String {
        let t = str.trimmingCharacters(in: .whitespaces)
        let w = CellWidth.of(t)
        if w >= size { return Cobol.x(t, size) }
        return Cobol.x(String(repeating: " ", count: (size - w) / 2) + t, size)
    }

    final class Run {
        let s: Session
        let c: Console
        let ctx: IRS.Context
        /// record-1 / work-record (SAME RECORD AREA)
        var rec = IRS.newNL()
        /// working-storage の nl-record
        var nl = IRS.newNL()
        var post = IRS.newPost()
        let nlFile: IndexedFile
        var work = [UInt8](), workPos = 0
        var printer: IRS.Printer!
        var wsClient = ""
        var wsReply = " "
        var total1 = [Int64](repeating: 0, count: 27), total2 = [Int64](repeating: 0, count: 27)
        var level11: Int64 = 0, level12: Int64 = 0, level21: Int64 = 0, level22: Int64 = 0
        var net1: Int64 = 0, net2: Int64 = 0
        var plAc: Int64 = 0
        var j = 0, y = 0
        var subTotal = false
        var work1: Int64 = 0, work2: Int64 = 0, work3: Int64 = 0
        var plTitle = "", plRepType = " "
        var wsAc = " "
        let hyphens = "---------", equals = "========="
        // 印字行
        var l2Title = "", line3 = Cobol.x("", 79)
        var l5Year1 = 0, l5Year2 = 0, l5Grp2Blank = false
        var l7Name = "", l7v = [Int64](repeating: 0, count: 5), l7s = [String](repeating: " ", count: 9)
        var l8 = [String](repeating: Cobol.x("", 9), count: 5)
        var l9Name = Cobol.x("", 34)
        var l11Ratio: Int64 = 0

        init(_ s: Session) {
            self.s = s; c = s.console; ctx = IRS.context(s)
            nlFile = IndexedFile(s.store, path: s.irsDir + "acnts.dat", layout: IRS.nlLayout, keyOffset: 0, keyLength: 10)
        }

        var ac: String { rec.str("ac") }
        func add(_ r: inout Record, _ f: String, _ v: Int64) { r.setInt(f, abs(r.int(f) + v) % 10_000_000_000) }

        var line1: String { Cobol.x("", 28) + Cobol.x(wsClient, 24) + Cobol.x("", 27) }
        var line2: String { Cobol.x("", 20) + Cobol.x(l2Title, 40) + Cobol.x("", 19) }
        var line5: String {
            let g1 = "--------20" + Cobol.z(l5Year1, 2) + "--------"
            let g2 = l5Grp2Blank ? Cobol.x("", 20) : "--------20" + Cobol.z(l5Year2, 2) + "--------"
            return Cobol.x("", 34) + g1 + Cobol.x("", 5) + g2
        }
        var line7: String {
            "  " + Cobol.x(l7Name, 27) + Cobol.x("", 5) + l7s[1] + z7(l7v[1]) + l7s[2] + "  " + l7s[3] + z7(l7v[2]) + l7s[4]
                + Cobol.x("", 5) + l7s[5] + z7(l7v[3]) + l7s[6] + "  " + l7s[7] + z7(l7v[4]) + l7s[8]
        }
        var line8: String { Cobol.x("", 34) + l8[1] + "  " + l8[2] + Cobol.x("", 5) + l8[3] + "  " + l8[4] }
        func clearLine8() { for i in 1...4 { l8[i] = Cobol.x("", 9) } }
        func pw(_ line: String, after n: Int) { printer.write(Cobol.x(line, 79), after: n) }
        func blank(_ n: Int = 1) { pw("", after: n) }

        func readWork() -> Bool {
            let size = IRS.nlLayout.size
            guard workPos + size <= work.count else { return false }
            rec = Record(IRS.nlLayout, bytes: Array(work[workPos..<(workPos + size)]))
            workPos += size
            return true
        }
        func openWork() -> Bool {
            guard let raw = s.store.readRaw(s.irsDir + IRS065.outputName) else { return false }
            work = raw; workPos = 0
            return true
        }
        /// READ nominal-ledger (キー指定)。読めた場合は以降の READ NEXT がその次から続く。
        func readKey() -> Bool {
            let key = rec.raw("key")
            guard nlFile.isOpen, nlFile.start(notLessThan: key), let r = nlFile.readNext(), r.raw("key") == key else { return false }
            rec = r
            return true
        }
        func readNextNL() -> Bool {
            guard nlFile.isOpen, let r = nlFile.readNext() else { return false }
            rec = r
            return true
        }
        func peAbort(_ code: String, msgKey: String = "irs060.hit_return_continue") throws -> Never {
            c.display(code, at: 2301)
            c.display(s.t(msgKey), at: 2401)
            wsReply = try c.accept(at: 2421, size: 1)
            throw StopRun()
        }

        func screenHeads() {
            c.display(" ", at: 101, eraseEOS: true)
            c.display(progName, at: 101, color: 2)
            c.display(s.t("irs060.title"), at: 129, color: 1, reverse: true)
            c.display(ctx.sys.str("run-date"), at: 173, color: 2)
        }

        // MARK: init01 section

        func main() throws {
            ctx.fileNames = ctx.sys.str("system-files")
            y = 0
            wsClient = justifyC(ctx.sys.str("client"), 24)
            screenHeads()
            for i in 1...26 { total1[i] = 0; total2[i] = 0 }
            repeat {
                c.display(s.t("irs060.comparative"), at: 801, color: 2)
                j = IRS.num(try c.accept(at: 839, size: 1, kind: .numeric, color: 3))
            } while j < 0 || j > 4
            c.display(s.t("irs060.pl_title_prompt"), at: 1001, color: 2)
            c.display("]", at: 1079, color: 2)
            plTitle = Cobol.x(s.t("report.irs060.pl_title"), 40)
            plTitle = try c.accept(at: 1039, size: 40, initial: plTitle, options: [.update], color: 3)
            repeat {
                c.display(s.t("irs060.period_or_year"), at: 1201, color: 2)
                plRepType = try c.accept(at: 1239, size: 1, color: 6).uppercased()
            } while plRepType != "P" && plRepType != "Y"
            let endDate = ctx.sys.str("end-date")
            l5Year1 = Int(String(Array(Cobol.x(endDate, 8))[6..<8])) ?? 0
            l5Year2 = abs(l5Year1 - 1)
            l5Grp2Blank = j == 0
            c.display(s.t("irs060.checking"), at: 1601, color: 2)
            if !openWork() {
                c.display(s.t("irs060.work_open_fail"), at: 2401, color: 2)
                c.display(s.t("irs060.hit_return_menu"), at: 2441)
                wsReply = try c.accept(at: 2461, size: 1)
                throw StopRun()
            }
            while readWork() {
                guard let w = IRS060.letters.firstIndex(of: Character(ac.uppercased())) else {
                    c.display(s.t("irs060.incorrectly_coded"), at: 501, color: 2)
                    c.display(s.t("irs060.account"), at: 701, color: 2)
                    c.display(Cobol.z(rec.int("owning"), 5), at: 713, color: 2)
                    c.display("/", at: 718, color: 2)
                    c.display(Cobol.z(rec.int("sub-nominal"), 5), at: 719, color: 2)
                    c.display(s.t("irs060.hit_return_menu"), at: 701)
                    wsReply = try c.accept(at: 721, size: 1)
                    throw StopRun()
                }
                let z = w + 1
                let a = ac
                // accumulate
                if a < "E" { crTotal(z) }
                else if a > "D" && a < "I" { drTotal(z) }
                else if a == "I" || a == "J" { crTotal(z) }
                else if a > "J" && a < "U" { drTotal(z) }
                else if a > "T" { crTotal(z) }
            }
            // read-end
            c.display(s.t("irs060.printing"), at: 1601, color: 2)
            _ = openWork()
            printer = IRS.Printer(s, "prt-1")
            l2Title = justifyC(plTitle, 40)
            if plRepType == "Y" {
                line3 = Cobol.x("", 25) + Cobol.x(s.t("report.irs060.year_ended"), 19) + endDate + Cobol.x("", 27)
            } else {
                line3 = Cobol.x("", 19) + Cobol.x(s.t("report.irs060.period_from"), 20) + ctx.sys.str("start-date")
                    + Cobol.x(s.t("report.irs060.to"), 4) + endDate + Cobol.x("", 20)
            }
            pw(line1, after: 1)
            pw(line2, after: 2)
            pw(line3, after: 2)
            pw(line5, after: 2)
            blank()
            y = 1
            if !readWork() {
                c.display("PE 005946", at: 2401)
                c.display(s.t("irs060.hit_return_menu"), at: 2441)
                wsReply = try c.accept(at: 2461, size: 1)
                throw StopRun()
            }
            func lines(until n: Int) throws {
                repeat {
                    try lineTotal()
                    y += 1
                } while y < n
            }
            func underline2(_ u: String) {
                l8[2] = u
                if j > 0 { l8[4] = u }
                pw(line8, after: 1)
            }
            // loop-1: 収益
            try lines(until: 5)
            l7Name = s.t("report.irs060.total_income")
            groupTotal()
            level21 = wrap(level11, 9); level22 = wrap(level12, 9)
            level11 = 0; level12 = 0
            blank(); blank()
            // loop-2: 直接原価
            try lines(until: 9)
            l7Name = s.t("report.irs060.less_direct_costs")
            groupTotal()
            level21 = wrap(level21 - level11, 9); level22 = wrap(level22 - level12, 9)
            level11 = level21; level12 = level22
            subTotal = true
            l7Name = s.t("report.irs060.gross_profit")
            underline2(hyphens)
            clearLine8()
            groupTotal()
            level11 = 0; level12 = 0
            subTotal = false
            blank()
            // loop-3: 雑収入
            try lines(until: 11)
            l7Name = s.t("report.irs060.plus_sundry_income")
            groupTotal()
            level21 = wrap(level21 + level11, 9); level22 = wrap(level22 + level12, 9)
            blank()
            level11 = 0; level12 = 0
            blank()
            // loop-4: 間接費
            try lines(until: 15)
            l7Name = s.t("report.irs060.less_indirect_costs")
            groupTotal()
            level21 = wrap(level21 - level11, 9); level22 = wrap(level22 - level12, 9)
            level11 = level21; net1 = level21
            level12 = level22; net2 = level22
            subTotal = true
            l7Name = s.t("report.irs060.net_profit")
            underline2(hyphens)
            clearLine8()
            groupTotal()
            subTotal = false
            level11 = 0; level12 = 0; level21 = 0; level22 = 0
            underline2(equals)
            clearLine8()
            printer.writePage(Cobol.x(line1, 79))
            l2Title = Cobol.x(s.t("report.irs060.balance_sheet"), 40)
            pw(line2, after: 2)
            pw(line3, after: 2)
            pw(line5, after: 2)
            clearLine8()
            // loop-5: 固定資産
            try lines(until: 18)
            l7Name = s.t("report.irs060.fixed_asset_total")
            groupTotal()
            level21 = wrap(level11, 9); level22 = wrap(level12, 9)
            level11 = 0; level12 = 0
            blank()
            // loop-6: 流動資産
            try lines(until: 21)
            l7Name = s.t("report.irs060.plus_current_assets")
            groupTotal()
            level21 = wrap(level21 + level11, 9); level22 = wrap(level22 + level12, 9)
            level11 = level21; level12 = level22
            subTotal = true
            l7Name = s.t("report.irs060.total_assets")
            underline2(hyphens)
            clearLine8()
            groupTotal()
            level11 = 0; level12 = 0
            subTotal = false
            blank()
            // loop-8: 流動負債
            try lines(until: 23)
            l7Name = s.t("report.irs060.less_current_liabilities")
            groupTotal()
            level21 = wrap(level21 - level11, 9); level22 = wrap(level22 - level12, 9)
            level11 = level21; level12 = level22
            underline2(hyphens)
            clearLine8()
            subTotal = true
            l7Name = s.t("report.irs060.net_current_assets")
            groupTotal()
            underline2(equals)
            level11 = 0; level12 = 0; level21 = 0; level22 = 0
            subTotal = false
            l8[2] = Cobol.x("", 9); l8[4] = Cobol.x("", 9)
            blank(2)
            // loop-9: 資本
            try lines(until: 27)
            l7Name = s.t("report.irs060.capital_total")
            groupTotal()
            pw(line8, after: 1)
            level21 = wrap(level11, 9); level22 = wrap(level12, 9)
            level11 = 0; level12 = 0
            l7Name = s.t("report.irs060.net_profits")
            clearLine8()
            blank()
            level11 = net1; level12 = net2
            groupTotal()
            level21 = wrap(level21 + level11, 9); level22 = wrap(level22 + level12, 9)
            level11 = level21; level12 = level22
            subTotal = true
            l7Name = s.t("report.irs060.net_current_assets")
            underline2(hyphens)
            clearLine8()
            groupTotal()
            level11 = 0; level12 = 0; level21 = 0; level22 = 0
            underline2(equals)
            ratio()
            printer.spool()
            screenHeads()
            c.display(s.t("irs060.eop_info_1"), at: 501, color: 2)
            c.display(s.t("irs060.eop_info_2"), at: 601, color: 2)
            try endOfPeriod()
        }

        // MARK: 期末処理 (e-o-p-option 以降)

        func endOfPeriod() throws {
            option: while true {
                c.display(s.t("irs060.eop_required"), at: 901, color: 2)
                wsReply = try c.accept(at: 950, size: 1, color: 6)
                if wsReply == "N" || wsReply == "n" { return }
                if wsReply != "Y" && wsReply != "y" { continue }
                try IRSub3.read(s)
                repeat {
                    c.display(s.t("irs060.comparative_field"), at: 1101, color: 2)
                    j = IRS.num(try c.accept(at: 1128, size: 1, kind: .numeric, color: 6))
                } while j < 1 || j > 4
                if IRS.defAc(ctx.dflt, 30) == 0 || IRS.defAc(ctx.dflt, 31) == 0 {
                    c.display(s.t("irs060.default_not_setup"), at: 1201, color: 4)
                    throw StopRun()
                }
                var askPl = true
                while true {
                    if askPl {
                        c.display(s.t("irs060.enter_pl_ac"), at: 1301, color: 2)
                        plAc = Int64(IRS.num(try c.accept(at: 1343, size: 5, kind: .numeric, color: 3)))
                    }
                    askPl = true
                    c.display(s.t("irs060.selected_eop"), at: 1501, color: 2)
                    c.display(String(j), at: 1577, color: 2)
                    c.display(s.t("irs060.with_pl_ac"), at: 1601, color: 2)
                    c.display(Cobol.z(plAc, 5), at: 1627, color: 2)
                    c.display(s.t("irs060.is_correct"), at: 1701, color: 2)
                    wsReply = try c.accept(at: 1727, size: 1, color: 6)
                    if wsReply != "Y" && wsReply != "y" { continue option }
                    nlFile.open()
                    rec.setInt("owning", plAc); rec.setInt("sub-nominal", 0)
                    if !readKey() {
                        c.display(" ", at: 101, eraseEOS: true)
                        c.display(Cobol.z(plAc, 5), at: 505, color: 2)
                        c.display(s.t("irs060.not_exist"), at: 513, color: 2)
                        wsReply = try c.accept(at: 565, size: 1, color: 2)
                        nlFile.close()
                        continue
                    }
                    break
                }
                break
            }
            wsAc = ac.uppercased()
            nlFile.close()
            nlFile.open()
            let jj = String(j)
            // loop-a / by-pass / loop-b
            if readNextNL() {
                var byPass = true
                loop: while true {
                    if byPass {
                        nl = rec
                        if nl.str("type") == "S" {
                            if !readNextNL() { break loop }
                            continue
                        }
                        rec.setInt("dr-last-" + jj, rec.int("dr"))
                        rec.setInt("cr-last-" + jj, rec.int("cr"))
                        if ac < "O" { rec.setInt("dr", 0); rec.setInt("cr", 0) }
                        nlFile.rewrite(rec)
                    }
                    // loop-b
                    repeat {
                        if !readNextNL() { break loop }
                    } while rec.str("type") == "S"
                    if rec.int("sub-nominal") == 0 { byPass = true; continue }
                    byPass = false
                    rec.setInt("dr-last-" + jj, rec.int("dr"))
                    rec.setInt("cr-last-" + jj, rec.int("cr"))
                    if nl.str("ac") < "O" { rec.setInt("dr", 0); rec.setInt("cr", 0) }
                    rec["ac"] = nl.str("ac")
                    nlFile.rewrite(rec)
                }
            }
            // e-o-p-fin
            try vatAcTidyup()
            do { try plCapitalAcTidyup() } catch is ExitProgram { return }
            rec.setInt("owning", plAc); rec.setInt("sub-nominal", 0)
            while true {
                if !readKey() {
                    c.display("PE 009610", at: 505)
                    c.display(s.t("irs060.hit_return_menu"), at: 701)
                    wsReply = try c.accept(at: 721, size: 1)
                    throw StopRun()
                }
                if rec.str("type") == "O" { break }
                rec.setInt("sub-nominal", rec.int("owning"))
                rec.setInt("owning", rec.int("pointer"))
            }
            // update-pl
            if net1 > 0 { add(&rec, "cr", net1) } else { add(&rec, "dr", net1) }
            nlFile.rewrite(rec)
            nlFile.close()
            try resetPostings()
        }

        // MARK: cr-total / dr-total

        func crTotal(_ z: Int) {
            total1[z] = wrap(total1[z] + rec.int("cr") - rec.int("dr"), 10)
            if j == 0 { return }
            total2[z] = wrap(total2[z] + rec.int("cr-last-\(j)") - rec.int("dr-last-\(j)"), 10)
        }
        func drTotal(_ z: Int) {
            total1[z] = wrap(total1[z] + rec.int("dr") - rec.int("cr"), 10)
            if j == 0 { return }
            total2[z] = wrap(total2[z] + rec.int("dr-last-\(j)") - rec.int("cr-last-\(j)"), 10)
        }

        // MARK: line-total section

        func lineTotal() throws {
            l7v[1] = whole(total1[y])
            if j > 0 {
                l7v[3] = whole(total2[y])
                level12 = wrap(level12 + total2[y], 10)
            }
            level11 = wrap(level11 + total1[y], 10)
            l7s[1] = total1[y] < 0 ? "(" : " "; l7s[2] = total1[y] < 0 ? ")" : " "
            let n2 = total2[y] < 0 && j > 0
            l7s[5] = n2 ? "(" : " "; l7s[6] = n2 ? ")" : " "
            let letter = String(IRS060.letters[y - 1])
            byPass: while true {
                if ac < letter {
                    c.display("PE009865", at: 2001)
                    c.display(s.t("irs060.note_error"), at: 2411)
                    wsReply = try c.accept(at: 2451, size: 1)
                    // loop-1 (終端後の READ は AT END として扱う)
                    if !readWork() { break byPass }
                    continue
                }
                if ac > letter { break byPass }
                nl = rec
                l9Name = Cobol.x(nl.str("name"), 34)
                // loop-2
                while true {
                    if !readWork() { break byPass }
                    if rec.int("sub-nominal") == 0 {
                        writeOut()
                        continue byPass
                    }
                    add(&nl, "dr", rec.int("dr"))
                    add(&nl, "cr", rec.int("cr"))
                    if j == 0 { continue }
                    add(&nl, "dr-last-\(j)", rec.int("dr-last-\(j)"))
                    add(&nl, "cr-last-\(j)", rec.int("cr-last-\(j)"))
                }
            }
            writeOut()
        }

        // MARK: group-total section

        func groupTotal() {
            l7v[2] = whole(level11)
            if j > 0 { l7v[4] = whole(level12) }
            if subTotal { l7v[1] = 0; l7v[3] = 0 }
            l7s[3] = level11 < 0 ? "(" : " "; l7s[4] = level11 < 0 ? ")" : " "
            let n2 = level12 < 0 && j > 0
            l7s[7] = n2 ? "(" : " "; l7s[8] = n2 ? ")" : " "
            l8[1] = hyphens
            if j > 0 { l8[3] = hyphens }
            if !subTotal { pw(line8, after: 1) }
            pw(line7, after: 1)
            for i in 1...8 { l7s[i] = " " }
            for i in 1...4 { l7v[i] = 0 }
            clearLine8()
        }

        // MARK: write-out section

        func writeOut() {
            let a = nl.str("ac")
            func crValue() {
                work1 = nl.int("cr") - nl.int("dr")
                work2 = j > 0 ? nl.int("cr-last-\(j)") - nl.int("dr-last-\(j)") : 0
            }
            func drValue() {
                work1 = nl.int("dr") - nl.int("cr")
                work2 = j > 0 ? nl.int("dr-last-\(j)") - nl.int("cr-last-\(j)") : 0
            }
            if a < "E" { crValue() }
            if a > "D" && a < "J" { drValue() }
            if a == "I" || a == "J" { crValue() }
            if a > "J" && a < "U" { drValue() }
            if a > "T" { crValue() }
            if !(work1 == 0 && work2 == 0) && l9Name != Cobol.x("", 34) {
                let n1 = work1 < 0, n2 = work2 < 0 && j > 0
                let v2 = j > 0 ? whole(work2) : l9Value2
                l9Value2 = v2
                pw(l9Name + (n1 ? "(" : " ") + z7(whole(work1)) + (n1 ? ")" : " ") + Cobol.x("", 16)
                    + (n2 ? "(" : " ") + z7(v2) + (n2 ? ")" : " ") + Cobol.x("", 11), after: 1)
            }
            l9Name = Cobol.x("", 34)
            work1 = 0; work2 = 0
        }
        var l9Value2: Int64 = 0

        // MARK: ratio section

        func ratio() {
            printer.writePage(Cobol.x(line1, 79))
            pw(line2, after: 2)
            pw(Cobol.x(ctx.sys.str("client"), 24) + Cobol.x("", 6) + Cobol.x(s.t("report.irs060.sales_ratios"), 23)
                + Cobol.x(s.t("report.irs060.period_to"), 18) + ctx.sys.str("end-date"), after: 2)
            blank()
            work1 = wrap(total1[1] + total1[2] + total1[3] + total1[4], 11)
            work2 = wrap(total1[5] + total1[6] + total1[7] + total1[8], 11)
            work2 = wrap(work1 - work2, 11)
            work3 = work1 / 100
            // ゼロ除算 (SIZE ERROR) の場合、l11-ratio は変更されない
            func setRatio() {
                if work3 != 0 { l11Ratio = abs(IRS030.roundDiv(work2 * 100, work3)) % 1_000_000 }
            }
            func line11(_ key: String) -> String { Cobol.x(s.t(key), 24) + Pic.edit("zzz9.99", value: l11Ratio, scale: 2) }
            setRatio()
            pw(line11("report.irs060.gross_ratio"), after: 2)
            work2 = wrap(work2 - total1[11] - total1[12] - total1[13] - total1[14], 11)
            setRatio()
            pw(line11("report.irs060.net_ratio"), after: 2)
        }

        // MARK: pl-capital-ac-tidyup section

        func plCapitalAcTidyup() throws {
            nl.setInt("cr", 0); nl.setInt("dr", 0)
            nlFile.close()
            nlFile.open()
            while readNextNL() {
                let ac2 = ac.uppercased()
                if ac2 != wsAc { continue }
                if rec.str("type") == "S" { continue }
                rec["ac"] = ac2
                add(&nl, "cr", rec.int("cr"))
                add(&nl, "dr", rec.int("dr"))
                rec.setInt("cr", 0); rec.setInt("dr", 0)
                if nlFile.rewrite(rec) != "00" { try peAbort("PE 014900") }
            }
            rec.setInt("owning", plAc); rec.setInt("sub-nominal", 0)
            if !readKey() { try peAbort("PE 015000") }
            if rec.str("type") == "S" {
                c.display(Cobol.z(plAc, 5), at: 2301, color: 2)
                c.display(s.t("irs060.is_sub_nominal"), at: 2307, color: 2)
                c.display(s.t("irs060.hit_return_menu"), at: 2441)
                wsReply = try c.accept(at: 2461, size: 1)
                throw ExitProgram()
            }
            rec.setInt("dr", nl.int("dr"))
            rec.setInt("cr", nl.int("cr"))
            if nlFile.rewrite(rec) != "00" { try peAbort("PE 015100") }
        }

        // MARK: vat-ac-tidyup section

        func vatAcTidyup() throws {
            rec.setInt("owning", Int64(IRS.defAc(ctx.dflt, 31))); rec.setInt("sub-nominal", 0)
            func abort(_ show: () -> Void) throws -> Never {
                c.display(" ", at: 101, eraseEOS: true)
                show()
                c.display(s.t("irs060.hit_return"), at: 2441)
                wsReply = try c.accept(at: 2461, size: 1)
                nlFile.close()
                throw StopRun()
            }
            while true {
                if !readKey() {
                    try abort {
                        c.display(Cobol.z(rec.int("owning"), 5), at: 501, color: 2)
                        c.display(s.t("irs060.default_31_missing"), at: 507, color: 2)
                    }
                }
                if rec.str("type") == "S" && rec.int("pointer") == rec.int("owning") {
                    try abort { c.display(s.t("irs060.pe_vat01"), at: 2301) }
                }
                if rec.str("type") == "S" {
                    rec.setInt("owning", rec.int("pointer"))
                    continue
                }
                break
            }
            nl = rec
            while readNextNL() {
                if rec.int("owning") != nl.int("owning") { break }
                if rec.str("type") == "S" { continue }
                add(&nl, "dr", rec.int("dr"))
                add(&nl, "cr", rec.int("cr"))
                rec.setInt("dr", 0); rec.setInt("cr", 0)
                if nlFile.rewrite(rec) != "00" { try peAbort(s.t("irs060.pe_015370"), msgKey: "irs060.hit_return_menu") }
            }
            rec = nl
            if nlFile.rewrite(rec) != "00" { try peAbort(s.t("irs060.pe_015470"), msgKey: "irs060.hit_return_menu") }
        }

        // MARK: reset-postings section

        /// date-validate の ws-unpack (u-bin → dd/mm/yy)
        static func unpack(_ bin: Int) -> String {
            let days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            var save = bin, yy = 0, mm = 1, dd = 0, w1 = 1, w2 = 0
            loop1: while true {
                save -= 365
                if save > 0 { yy += 1 } else { save += 365; break loop1 }
                if yy == w2 && save > 59 { w2 += 4; save -= 1 }
                if save == 0 { yy -= 1; save = 365; break loop1 }
            }
            if save == 365 {
                dd = 31; mm = 12
            } else {
                while true {
                    save -= days[w1 - 1]
                    if save > 0 && w1 < 12 { w1 += 1; mm += 1 } else { break }
                }
                dd += save + days[w1 - 1]
            }
            return Cobol.z(dd % 100, 2) + "/" + Cobol.z(mm % 100, 2) + "/" + Cobol.z(yy % 100, 2)
        }

        func resetPostings() throws {
            nlFile.open()
            try IRSub4.open(s, .output)
            plAc = 0
            ctx.sys.setInt("save-sequ", 0)
            let (bin, _) = IRSMenu.dateValidate(ctx.sys.str("end-date"))
            let uDate = Run.unpack(bin + 1)
            let def30 = Int64(IRS.defAc(ctx.dflt, 30))
            while readNextNL() {
                if rec.str("type") == "S" { continue }
                var dr = rec.int("dr"), cr = rec.int("cr")
                if cr == 0 && dr == 0 { continue }
                if dr == cr { continue }
                if dr > cr { dr -= cr; cr = 0 } else { cr -= dr; dr = 0 }
                rec.setInt("dr", dr); rec.setInt("cr", cr)
                post["date"] = uDate
                post["vat-side"] = "  "
                plAc = (plAc + 1) % 100000
                post.setInt("key", plAc)
                post["code"] = IRS.defCode(ctx.dflt, 30)
                post.setInt("vat-ac-def", 0)
                IRS.setSigned(&post, "vat-amount", 0)
                post["legend"] = s.t("report.irs060.balance_forward")
                post.setInt("cr", def30); post.setInt("dr", def30)
                if rec.int("sub-nominal") != 0 { rec.setInt("owning", rec.int("sub-nominal")) }
                if dr > 0 {
                    post.setInt("dr", rec.int("owning"))
                    IRS.setSigned(&post, "amount", dr)
                } else if cr > 0 {
                    post.setInt("cr", rec.int("owning"))
                    IRS.setSigned(&post, "amount", cr)
                }
                if def30 == post.int("cr") && def30 == post.int("dr") { continue }
                IRSub4.write(s, &post)
            }
            nlFile.close()
            IRSub4.close(s)
            ctx.sys.setInt("next-post", plAc)
        }
    }

    static func run(_ s: Session) throws { try Run(s).main() }
}
