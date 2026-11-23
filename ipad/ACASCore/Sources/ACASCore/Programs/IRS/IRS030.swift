import Foundation

/// incomplete_records_system/irs030.cbl: 取引の転記入力 (デフォルト科目に対するバッチ入力、SL/PL 転記ファイルの取込)
enum IRS030 {
    static let progName = "irs030 (3.01.15)"
    struct ExitProgram: Error {}

    /// 段落 (init-main section の GO TO / PERFORM THRU を再現するための並び)
    enum L: Int {
        case mainLoop, mainLoopClear, getDefault, getDefault1, chkAns, getChar, getNewVatDone, setUp, setUp1, setUp2,
             inputLoop, dateInp, accountInput, vatInput, vatInputSkip, inputTidy, creditTidy, inputEnd, inputEnd1,
             clearScreen, endBatch, batchClose, batchCloseReturn, mainExit
    }

    static func s9(_ v: Int64) -> Int64 { v < 0 ? -((-v) % 1_000_000_000) : v % 1_000_000_000 }
    static func roundDiv(_ n: Int64, _ d: Int64) -> Int64 {
        let q = (abs(n) * 2 + abs(d)) / (abs(d) * 2)
        return (n < 0) != (d < 0) ? -q : q
    }
    static func money(_ v: Int64) -> String { Pic.edit("z(6)9.99-", value: v, scale: 2) }

    final class Run {
        let s: Session
        let c: Console
        let ctx: IRS.Context
        var a = 0, b = 0, cFlag = 0, d = 0, e = 0
        var wsLines = 24
        var l20: Int { wsLines - 4 }
        var l21: Int { wsLines - 3 }
        var l22: Int { wsLines - 2 }
        var l23: Int { wsLines - 1 }
        var demoFlag = 0
        var revFlag = 0
        var wsReply = " "
        var w = 0, y = 0
        var wsType = "  ", wsType2 = "  ", wsTypeDisplay = "  "
        var wsDefault: Int64 = 0, wsVat: Int64 = 0, wsBatch: Int64 = 0
        var inputAccount: Int64 = 0
        var wsVatCode = " "
        var postTrue = 0
        var displayAccount = "     "
        var netDisplay = "", vatDisplay = ""
        var vatFlag = 0, vatFlag2 = 0
        var lin = 0, cole = 0, lin2 = 0, col2 = 0
        var wsDefName = Cobol.x("", 24)
        var wsVatAc = Cobol.x("", 20)
        var displayLegend = Cobol.x("", 16)
        var postRecordCnt = 0
        var amtOk: Int64 = 0
        var screenAccept = Cobol.x("", 11)
        var nl = IRS.newNL()
        var post = IRS.newPost()
        var curs: Int { lin * 100 + cole }
        var curs2: Int { lin2 * 100 + col2 }
        var postAmount: Int64 {
            get { IRS.getSigned(post, "amount") }
            set { IRS.setSigned(&post, "amount", newValue) }
        }
        var vatAmount: Int64 {
            get { IRS.getSigned(post, "vat-amount") }
            set { IRS.setSigned(&post, "vat-amount", newValue) }
        }

        init(_ s: Session) { self.s = s; c = s.console; ctx = IRS.context(s) }

        func acceptNum(_ at: Int, size: Int, value: Int64, color: UInt8 = 3) throws -> Int64 {
            Int64(IRS.num(try c.accept(at: at, size: size, kind: .numeric, initial: Cobol.z(abs(value), size),
                                       options: [.update], color: color)))
        }

        // MARK: PERFORM 制御

        func perform(_ from: L, thru: L? = nil) throws {
            let last = thru ?? from
            var cur = from
            while true {
                if let next = try paragraph(cur) {
                    if next == .mainExit { throw ExitProgram() }
                    cur = next
                } else {
                    if cur == last { return }
                    guard let n = L(rawValue: cur.rawValue + 1), n != .mainExit else { throw ExitProgram() }
                    cur = n
                }
            }
        }

        func paragraph(_ l: L) throws -> L? {
            switch l {
            case .mainLoop: return try mainLoop()
            case .mainLoopClear: return try mainLoopClear()
            case .getDefault: return getDefault()
            case .getDefault1: return try getDefault1()
            case .chkAns: return try chkAns()
            case .getChar: return try getChar()
            case .getNewVatDone: return try getNewVatDone()
            case .setUp: return try setUp()
            case .setUp1: c.display(" ", at: 101, eraseEOS: true); return nil
            case .setUp2: return setUp2()
            case .inputLoop: return try inputLoop()
            case .dateInp: return try dateInp()
            case .accountInput: return try accountInput()
            case .vatInput: return try vatInput()
            case .vatInputSkip: return try vatInputSkip()
            case .inputTidy: return inputTidy()
            case .creditTidy: return creditTidy()
            case .inputEnd: headingScreen(); IRSub1.rewrite(s, nl); return nil
            case .inputEnd1: return inputEnd1()
            case .clearScreen: return clearScreen()
            case .endBatch: return endBatch()
            case .batchClose: return batchClose()
            case .batchCloseReturn: return .mainLoop
            case .mainExit: return .mainExit
            }
        }

        // MARK: init-main section

        func mainLoop() throws -> L? {
            w = 0
            c.display(progName, at: 101, color: 2, eraseEOS: true)
            c.display(s.t("irs030.title"), at: 131, color: 1, reverse: true)
            c.display(s.t("irs030.run_option"), at: 501, color: 2)
            c.display(s.t("irs030.opt_99"), at: 532, color: 2)
            c.display(s.t("irs030.opt_88"), at: 632, color: 2)
            c.display(s.t("irs030.opt_77"), at: 732, color: 2)
            c.display(s.t("irs030.opt_66"), at: 832, color: 2)
            c.display(s.t("irs030.opt_return"), at: 1032, color: 2)
            w = Int(try acceptNum(528, size: 2, value: 0))
            return nil
        }

        func mainLoopClear() throws -> L? {
            if w == 0 {
                IRSub1.close(s)
                return .mainExit
            }
            if w == 99 { try showDefault() }
            if w == 77 {
                try fileInit()
                if wsReply == "Z" { return .mainLoop }
                ctx.sys.setInt("next-post", 0); ctx.sys.setInt("save-sequ", 0)
                return .getDefault
            }
            if w == 66 {
                ctx.sys.setInt("save-sequ", 0)
                try ledgerPostingsAdd()
            }
            if w != 88 { return .mainLoop }
            return nil
        }

        func getDefault() -> L? {
            c.display(s.t("irs030.default_number"), at: wsLines, 1, color: 2, eraseEOL: true)
            return nil
        }

        func getDefault1() throws -> L? {
            w = Int(try acceptNum(wsLines * 100 + 28, size: 2, value: 0))
            if w < 1 || w > 32 { return .getDefault }
            nl.setInt("owning", Int64(IRS.defAc(ctx.dflt, w))); nl.setInt("sub-nominal", 0)
            if IRSub1.readIndexed(s, &nl) == 2 {
                c.display(s.t("irs030.account_deleted"), at: wsLines, 34, color: 2, eraseEOL: true)
                return .getDefault1
            }
            let owning = nl.int("owning")
            vatFlag = (w > 30 || owning == Int64(IRS.defAc(ctx.dflt, 31)) || owning == Int64(IRS.defAc(ctx.dflt, 32))) ? 1 : 0
            c.display(nl.str("name"), at: wsLines, 1, color: 2, eraseEOL: true)
            switch IRS.defVat(ctx.dflt, w) {
            case "N": c.display(s.t("irs030.no_vat"), at: wsLines, 26, color: 2)
            case "O": c.display(s.t("irs030.output_vat"), at: wsLines, 26, color: 2)
            default: c.display(s.t("irs030.input_vat"), at: wsLines, 26, color: 2)
            }
            wsDefName = nl.str("name")
            return nil
        }

        func chkAns() throws -> L? {
            c.display(s.t("irs030.correct_account"), at: wsLines, 51, color: 2)
            wsReply = try c.accept(at: wsLines, 77, size: 1, color: 3)
            if wsReply == "N" || wsReply == "n" { return .getDefault }
            if wsReply != "Y" && wsReply != "y" { return .chkAns }
            return nil
        }

        func getChar() throws -> L? {
            c.display(s.t("irs030.run_characteristic"), at: wsLines, 1, color: 2, eraseEOL: true)
            c.display(s.t("irs030.dr_or_cr"), at: wsLines, 31, color: 2)
            wsType2 = try c.accept(at: wsLines, 27, size: 2, color: 3)
            wsType = wsType2.uppercased()
            if wsType != "DR" && wsType != "CR" { return .getChar }
            c.display(" ", at: wsLines, 1, eraseEOL: true)
            wsTypeDisplay = wsType
            wsType = wsType == "DR" ? "CR" : "DR"
            wsDefault = s9(nl.int("dr") - nl.int("cr"))
            if IRS.defVat(ctx.dflt, w) == "N" {
                wsVatAc = Cobol.x("", 20)
                wsVat = 0; post.setInt("vat-ac-def", 0)
                return .setUp
            }
            y = IRS.defVat(ctx.dflt, w) == "O" ? 32 : 31
            nl.setInt("owning", Int64(IRS.defAc(ctx.dflt, y)))
            post.setInt("vat-ac-def", Int64(y))
            nl.setInt("sub-nominal", 0)
            a = IRSub1.readIndexed(s, &nl)
            return nil
        }

        var weError = 0

        func getNewVatDone() throws -> L? {
            if a == 2 {
                c.display(s.t("irs030.vat_not_present"), at: wsLines, 1, color: 4, eraseEOL: true)
                wsReply = try c.accept(at: wsLines, 74, size: 1)
                c.display(" ", at: wsLines, 1, eraseEOL: true)
                return .mainExit
            }
            wsVat = s9(nl.int("cr") - nl.int("dr"))
            wsVatAc = Cobol.x(nl.str("name"), 20)
            return nil
        }

        func setUp() throws -> L? {
            try IRSub4.open(s, .io)
            wsBatch = 0; ctx.sys.setInt("save-sequ", 0)
            return nil
        }

        func setUp2() -> L? {
            headingScreen()
            c.display(s.t("irs030.col_date_account"), at: 501, color: 2)
            c.display(s.t("irs030.col_narrative"), at: 543, color: 2)
            lin = 6
            post["date"] = ctx.sys.str("run-date")
            post.setInt("key", ctx.sys.int("next-post"))
            post["code"] = IRS.defCode(ctx.dflt, w)
            post["legend"] = ""
            return nil
        }

        func amountPrompts() {
            c.display(s.t("irs030.amount"), at: l23, 1, color: 2)
            c.display(s.t("irs030.vat_code"), at: l23, 41, color: 2)
        }

        func inputLoop() throws -> L? {
            c.display(s.t("irs030.date"), at: l21, 1, color: 2)
            c.display(s.t("irs030.account"), at: l21, 41, color: 2)
            c.display(s.t("irs030.narrative"), at: l22, 1, color: 2)
            c.display("]", at: l22, 46, color: 2)
            postTrue = Int((post.int("key") + 1) % 100000)
            if demoFlag == 1 && postTrue > 50 {
                c.display(" ", at: 101, eraseEOS: true)
                c.display(s.t("irs030.demo_limit"), at: 1220)
                c.display(s.t("irs030.hit_return_menu"), at: 1426)
                wsReply = try c.accept(at: 1453, size: 1)
                try perform(.endBatch, thru: .batchClose)
                w = 0
                return .mainLoopClear
            }
            c.display(s.t("irs030.posting_number"), at: l22, 51, color: 2)
            c.display(Pic.edit("z(4)9", value: Int64(postTrue), scale: 0), at: l22, 70, color: 3)
            c.display("}", at: l22, 75, color: 2)
            amountPrompts()
            postAmount = 0
            c.display(post.str("date"), at: l21, 14, color: 3)
            return nil
        }

        func dateInp() throws -> L? {
            post["date"] = try c.accept(at: l21, 14, size: 8, initial: post.str("date"), options: [.update], color: 3)
            if c.crtStatus == 1003 {
                try perform(.endBatch, thru: .batchClose)
                try perform(.getDefault, thru: .setUp)
                try perform(.setUp2)
                post.setInt("key", ctx.sys.int("next-post"))
                post["code"] = IRS.defCode(ctx.dflt, w)
                return .dateInp
            }
            if Cobol.rtrim(post.str("date")).isEmpty { return .endBatch }
            let (bin, norm) = IRSMenu.dateValidate(post.str("date"))
            if bin == 0 { return .dateInp }
            post["date"] = norm
            cole = 1
            c.display(post.str("date"), at: curs, color: 3)
            return nil
        }

        func accountInput() throws -> L? {
            inputAccount = try acceptNum(l21 * 100 + 67, size: 5, value: inputAccount)
            displayAccount = Pic.edit("zzzz9", value: abs(inputAccount), scale: 0)
            if inputAccount == 0 { return .endBatch }
            if inputAccount < 0 { return .accountInput }
            if inputAccount == Int64(IRS.defAc(ctx.dflt, w)) {
                c.display(s.t("irs030.same_account"), at: wsLines, 1, color: 2)
                return .accountInput
            }
            c.display(Cobol.x("", 80), at: wsLines, 1)
            cole = 11
            c.display(displayAccount, at: curs, color: 3)
            nl.setInt("owning", inputAccount); nl.setInt("sub-nominal", 0)
            if IRSub1.readIndexed(s, &nl) == 2 {
                c.display(s.t("irs030.no_account"), at: wsLines, 1, color: 2)
                return .accountInput
            }
            c.display(Cobol.x("", 80), at: wsLines, 1)
            vatFlag2 = (inputAccount == Int64(IRS.defAc(ctx.dflt, 31)) || inputAccount == Int64(IRS.defAc(ctx.dflt, 32))
                        || vatFlag == 1) ? 1 : 0
            amountPrompts()
            cole = 18
            c.display(nl.str("name"), at: curs, color: 3)
            c.display(post.str("legend"), at: l22, 14, color: 3)
            post["legend"] = try c.accept(at: l22, 14, size: 32, initial: post.str("legend"), options: [.update], color: 3)
            displayLegend = Cobol.x(post.str("legend"), 16)
            cole = 43
            c.display(displayLegend, at: curs, color: 3)
            lin2 = l23; col2 = 14
            amtOk = 0
            if vatFlag2 == 0 { try acceptMoney() }
            postAmount = amtOk
            cole = 61
            c.display(money(postAmount), at: curs, color: 3)
            if IRS.defVat(ctx.dflt, w) == "N" {
                vatAmount = 0; wsVat = 0
                return .inputTidy
            }
            return nil
        }

        func vatInput() throws -> L? {
            wsVatCode = " "
            if vatFlag2 == 1 {
                vatAmount = 0
                return .vatInputSkip
            }
            wsVatCode = try c.accept(at: l23, 68, size: 1, color: 3)
            if wsVatCode == "P" || wsVatCode == "p" {
                wsVatCode = "P"
                // net section
                vatAmount = s9(roundDiv(postAmount * ctx.sys.int("vat"), 10000))
            } else if wsVatCode == "M" || wsVatCode == "m" {
                wsVatCode = "M"
                // gross section
                let v = ctx.sys.int("vat")
                vatAmount = s9(roundDiv(postAmount * v, v + 10000))
                postAmount = s9(postAmount - vatAmount)
            } else if wsVatCode == " " {
                vatAmount = 0
            } else {
                return .vatInput
            }
            return nil
        }

        func vatInputSkip() throws -> L? {
            cole = 61
            c.display(money(postAmount), at: curs, color: 3)
            cole = 71
            c.display(money(vatAmount), at: curs, color: 3)
            amtOk = vatAmount
            lin2 = lin; col2 = cole
            try acceptMoney2()
            if vatAmount != amtOk && wsVatCode == "M" {
                postAmount = s9(postAmount + vatAmount)
                postAmount = s9(postAmount - amtOk)
                cole = 61
                c.display(money(postAmount), at: curs, color: 3)
            }
            vatAmount = amtOk
            if vatAmount < 0 { vatAmount = -vatAmount }
            if postAmount == 0 && vatAmount == 0 { return .inputLoop }
            return nil
        }

        func addNL(_ name: String, _ v: Int64) {
            nl.setInt(name, (nl.int(name) + v) % 10_000_000_000)
        }

        func inputTidy() -> L? {
            if wsType == "CR" && postAmount > 0 { return .creditTidy }
            if wsType == "DR" && postAmount < 0 { return .creditTidy }
            if postAmount < 0 {
                revFlag = 1
                postAmount = -postAmount
            }
            post.setInt("dr", Int64(IRS.defAc(ctx.dflt, w)))
            post.setInt("cr", inputAccount)
            if revFlag == 1 { wsBatch = s9(wsBatch - postAmount - vatAmount) }
            if revFlag != 1 { wsBatch = s9(wsBatch + postAmount + vatAmount) }
            post["vat-side"] = "CR"
            wsDefault = s9(wsDefault + postAmount + vatAmount)
            wsVat = s9(wsVat + vatAmount)
            addNL("cr", postAmount)
            if inputAccount == Int64(IRS.defAc(ctx.dflt, w)) { wsDefault = s9(wsDefault - postAmount) }
            if IRS.defVat(ctx.dflt, w) == "N" { return .inputEnd }
            if inputAccount == Int64(IRS.defAc(ctx.dflt, y)) { wsVat = s9(wsVat + postAmount) }
            return .inputEnd
        }

        func creditTidy() -> L? {
            post.setInt("cr", Int64(IRS.defAc(ctx.dflt, w)))
            post.setInt("dr", inputAccount)
            if postAmount < 0 {
                revFlag = 1
                postAmount = -postAmount
            }
            if revFlag == 1 { wsBatch = s9(wsBatch - postAmount - vatAmount) }
            if revFlag != 1 { wsBatch = s9(wsBatch + postAmount + vatAmount) }
            post["vat-side"] = "DR"
            wsDefault = s9(wsDefault - postAmount - vatAmount)
            wsVat = s9(wsVat - vatAmount)
            addNL("dr", postAmount)
            if inputAccount == Int64(IRS.defAc(ctx.dflt, w)) { wsDefault = s9(wsDefault + postAmount) }
            if IRS.defVat(ctx.dflt, w) == "N" { return .inputEnd }
            if inputAccount == Int64(IRS.defAc(ctx.dflt, y)) { wsVat = s9(wsVat + postAmount) }
            return nil
        }

        func inputEnd1() -> L? {
            if revFlag == 1 { postAmount = -postAmount; vatAmount = -vatAmount }
            netDisplay = money(postAmount)
            vatDisplay = money(vatAmount)
            cole = 61
            c.display(netDisplay, at: curs, color: 3)
            cole = 71
            c.display(vatDisplay, at: curs, color: 3)
            post.setInt("key", (post.int("key") + 1) % 100000)
            lin += 1
            if revFlag == 1 { postAmount = -postAmount; vatAmount = -vatAmount; revFlag = 0 }
            IRSub4.write(s, &post)
            if lin < l20 { return .inputLoop }
            lin = 6
            return nil
        }

        func clearScreen() -> L? {
            repeat {
                cole = 1
                c.display(Cobol.x("", 80), at: curs)
                lin += 1
            } while lin < l20
            c.display(post.str("date"), at: 601, color: 3)
            c.display(displayAccount, at: 611, color: 3)
            c.display(nl.str("name"), at: 618, color: 3)
            c.display(displayLegend, at: 643, color: 3)
            c.display(netDisplay, at: 661, color: 3)
            c.display(vatDisplay, at: 671, color: 3)
            lin = 7
            return .inputLoop
        }

        func endBatch() -> L? {
            nl.setInt("owning", Int64(IRS.defAc(ctx.dflt, w))); nl.setInt("sub-nominal", 0)
            _ = IRSub1.readIndexed(s, &nl)
            if wsDefault < 0 {
                wsDefault = -wsDefault
                nl.setInt("cr", wsDefault); nl.setInt("dr", 0)
            } else {
                nl.setInt("dr", wsDefault); nl.setInt("cr", 0)
            }
            IRSub1.rewrite(s, nl)
            if IRS.defVat(ctx.dflt, w) == "N" { return .batchClose }
            nl.setInt("owning", Int64(IRS.defAc(ctx.dflt, y))); nl.setInt("sub-nominal", 0)
            _ = IRSub1.readIndexed(s, &nl)
            // DR/CR いずれの場合も同じ: 正なら貸方、0 以下なら借方 (符号なし項目へ絶対値で入る)
            if wsVat > 0 { nl.setInt("cr", wsVat); nl.setInt("dr", 0) }
            if wsVat < 1 { nl.setInt("dr", abs(wsVat)); nl.setInt("cr", 0) }
            IRSub1.rewrite(s, nl)
            return nil
        }

        func batchClose() -> L? {
            IRSub4.close(s)
            ctx.sys.setInt("next-post", post.int("key"))
            IRSub2.write(s)
            return nil
        }

        func headingScreen() {
            c.display(progName, at: 101, color: 2)
            c.display(s.t("irs030.title"), at: 131, color: 1, reverse: true)
            c.display(ctx.sys.str("run-date"), at: 173, color: 2)
            c.display(s.t("irs030.default"), at: 201, color: 2)
            c.display(Pic.edit("z9", value: Int64(w), scale: 0), at: 211, color: 3)
            c.display(s.t("irs030.run_is"), at: 214, color: 2)
            c.display(wsTypeDisplay, at: 223, color: 3)
            c.display(Cobol.x(wsDefName, 20), at: 250, color: 3)
            c.display(money(wsDefault), at: 270, color: 3)
            c.display(s.t("irs030.client"), at: 301, color: 2)
            c.display(ctx.sys.str("client"), at: 308, color: 3)
            c.display(s.t("irs030.end_date"), at: 332, color: 2)
            c.display(ctx.sys.str("end-date"), at: 341, color: 3)
            c.display(wsVatAc, at: 350, color: 3)
            c.display(money(wsVat), at: 370, color: 3)
            c.display(s.t("irs030.batch_total"), at: 450, color: 2)
            c.display(money(wsBatch), at: 470, color: 3)
        }

        // MARK: accept-money / accept-money2 / justify-accept-money

        func acceptMoney() throws {
            while true {
                screenAccept = Cobol.x("", 11)
                c.display(screenAccept, at: curs2, color: 3)
                screenAccept = try c.accept(at: curs2, size: 11, color: 3)
                justifyAcceptMoney()
                if cFlag > 1 || d > 1 {
                    c.display(s.t("irs030.not_numeric"), at: wsLines, 1, color: 4)
                    continue
                }
                c.display(Cobol.x("", 28), at: wsLines, 1)
                break
            }
        }

        func acceptMoney2() throws {
            while true {
                let sign = amtOk < 0 ? "-" : " "
                let v = abs(amtOk)
                screenAccept = Cobol.z(v / 100, 7) + "." + Cobol.z(v % 100, 2) + sign
                screenAccept = try c.accept(at: curs2, size: 11, initial: screenAccept, options: [.update], color: 3)
                justifyAcceptMoney()
                if cFlag > 1 || d > 1 {
                    c.display(s.t("irs030.not_numeric"), at: wsLines, 1, color: 4)
                    continue
                }
                c.display(Cobol.x("", 28), at: wsLines, 1)
                break
            }
        }

        /// c = 負号フラグ、d = 小数点フラグ、e = 小数桁数 (e は初期化されず前回値が残る: レガシーのまま)
        func justifyAcceptMoney() {
            amtOk = 0; cFlag = 0; d = 0
            var nstrg = [Int](repeating: 0, count: 9)
            b = 10
            let chars = Array(Cobol.x(screenAccept, 11))
            var i = 11
            while i >= 1 {
                let ch = chars[i - 1]
                i -= 1
                if ch == "-" && cFlag == 1 { cFlag = 2; break }
                if ch == "." && d == 1 { d = 2; break }
                if ch == "-" { cFlag = 1; continue }
                if ch == "." { d = 1; e = 10 - b; continue }
                let numeric = ch.isASCII && ch.isNumber
                if !numeric && b != 10 { cFlag = 3; break }
                if numeric {
                    b -= 1
                    if b >= 1 { nstrg[b - 1] = Int(String(ch))! }
                    continue
                }
            }
            if cFlag < 2 && d < 2 {
                let n = nstrg.reduce(Int64(0)) { $0 * 10 + Int64($1) }
                if e == 2 { amtOk = n % 1_000_000_000 }
                else if e == 1 { amtOk = (n * 10) % 1_000_000_000 }
                else { amtOk = (n * 100) % 1_000_000_000 }
                if cFlag == 1 { amtOk = -amtOk }
            }
        }

        // MARK: show-default / input-headings section

        func showDefault() throws {
            IRS.heading(s, prog: progName, titleKey: "irs020.display_title", col: 27)
            IRS020.setupAmendScreen3(s, IRS020.State())
            w = 1; cole = 1; lin = 7
            while true {
                c.display(Cobol.z(w, 2), at: curs, color: 2)
                let acs = IRS.defAc(ctx.dflt, w)
                c.display(Cobol.z(acs, 5), at: curs + 4, color: 3)
                nl.setInt("owning", Int64(acs)); nl.setInt("sub-nominal", 0)
                if acs != 0 {
                    _ = IRSub1.readIndexed(s, &nl)
                    c.display(Cobol.x(nl.str("name"), 22), at: curs + 10, color: 3)
                }
                c.display(IRS.defCode(ctx.dflt, w), at: curs + 33, color: 3)
                c.display(IRS.defVat(ctx.dflt, w), at: curs + 38, color: 3)
                c.display("]", at: curs + 39, color: 2)
                w += 1
                if w > 32 { break }
                if w == 17 { cole = 41; lin = 6 }
                lin += 1
            }
            w = 1; cole = 1; lin = 7
            c.display(Cobol.x("", 80), at: l23, 1, eraseEOS: true)
            c.display(s.t("irs020.end_listing"), at: wsLines, 1, color: 7)
            wsReply = try c.accept(at: wsLines, 79, size: 1)
        }

        // MARK: file-init section

        func fileInit() throws {
            wsReply = " "
            c.display(s.t("irs030.backed_up"), at: 301, color: 4, highlight: true)
            c.display(" ", at: 401, eraseEOL: true)
            c.display(s.t("irs030.enter_password"), at: 432, color: 2)
            let pass = try c.accept(at: 451, size: 4, options: [.secure])
            if pass != ctx.sys.str("pass-word") { wsReply = "Z"; return }
            try IRSub4.open(s, .output)
            IRSub4.close(s)
        }

        // MARK: Ledger-Postings-Add section

        func ledgerPostingsAdd() throws {
            let path = s.irsDir + "postings2irs.dat"
            guard let raw = s.store.readRaw(path) else {
                c.display(s.t("irs030.no_ledger_file"), at: 2301, color: 2)
                return
            }
            try IRSub3.read(s)
            try IRSub1.open(s, .io)
            var nl31 = IRS.newNL(), nl32 = IRS.newNL()
            for (n, key) in [(31, "irs030.irsub1_31"), (32, "irs030.irsub1_32")] {
                nl.setInt("owning", Int64(IRS.defAc(ctx.dflt, n))); nl.setInt("sub-nominal", 0)
                let err = IRSub1.readIndexed(s, &nl)
                if err != 0 {
                    c.display(s.t(key), at: 2301, color: 4, highlight: true)
                    c.display(String(err), at: 2319, color: 4, highlight: true)
                    _ = try c.accept(at: 2340, size: 1, kind: .numeric)
                    return
                }
                if n == 31 { nl31 = nl } else { nl32 = nl }
            }
            c.display(s.t("irs030.updating"), at: 2401, color: 2)
            try IRSub4.open(s, .io)
            let size = IRS.ledgerPostLayout.size
            var pos = 0
            while pos + size <= raw.count {
                let ip = Record(IRS.ledgerPostLayout, bytes: Array(raw[pos..<(pos + size)]))
                pos += size
                postRecordCnt = (postRecordCnt + 1) % 100000
                let amount = IRS.getSigned(ip, "amount"), vat = IRS.getSigned(ip, "vat-amount")
                let side = ip.str("vat-side")
                nl.setInt("owning", ip.int("dr")); nl.setInt("sub-nominal", 0)
                if IRSub1.readIndexed(s, &nl) == 2 {
                    c.display(s.t("irs030.invalid_key_1"), at: 2301, color: 4, highlight: true)
                    c.display(Cobol.z(ip.int("dr"), 5), at: 2317, color: 4, highlight: true)
                    _ = try c.accept(at: 2340, size: 1, kind: .numeric)
                    continue
                }
                addNL("dr", amount)
                if side == "CR" { addNL("dr", vat) }
                IRSub1.rewrite(s, nl)
                nl.setInt("owning", ip.int("cr")); nl.setInt("sub-nominal", 0)
                if IRSub1.readIndexed(s, &nl) == 2 {
                    c.display(s.t("irs030.invalid_key_2"), at: 2301, color: 4, highlight: true)
                    c.display(Cobol.z(ip.int("cr"), 5), at: 2317, color: 4, highlight: true)
                    _ = try c.accept(at: 2340, size: 1, kind: .numeric)
                    continue
                }
                addNL("cr", amount)
                if side == "DR" { addNL("cr", vat) }
                IRSub1.rewrite(s, nl)
                post.setRaw("code", ip.raw("code"))
                post.setRaw("date", ip.raw("date"))
                post.setInt("cr", ip.int("cr"))
                post.setInt("dr", ip.int("dr"))
                postAmount = amount
                post.setRaw("legend", ip.raw("legend"))
                post.setRaw("vat-ac-def", ip.raw("vat-ac-def"))
                post.setRaw("vat-side", ip.raw("vat-side"))
                vatAmount = vat
                post.setInt("key", ctx.sys.int("next-post"))
                ctx.sys.setInt("next-post", (ctx.sys.int("next-post") + 1) % 100000)
                IRSub4.write(s, &post)
                let def = ip.int("vat-ac-def")
                if def == 0 { continue }
                func add(_ r: inout Record, _ f: String) { r.setInt(f, (r.int(f) + vat) % 10_000_000_000) }
                if def == 31 && side == "CR" { add(&nl31, "cr") }
                else if def == 31 && side == "DR" { add(&nl31, "dr") }
                else if def == 32 && side == "CR" { add(&nl32, "cr") }
                else if def == 32 && side == "DR" { add(&nl32, "dr") }
            }
            // eoj
            nl = nl31
            IRSub1.rewrite(s, nl)
            nl = nl32
            IRSub1.rewrite(s, nl)
            IRSub4.close(s)
            IRSub1.close(s)
            IRSub2.write(s)
            c.display(" ", at: 1201, eraseEOL: true)
            c.display(s.t("irs030.complete_on") + Cobol.z(postRecordCnt, 5) + s.t("irs030.records"), at: 1202)
            repeat {
                c.display(s.t("irs030.clear_ledger_file"), at: 1401, eraseEOL: true)
                wsReply = try c.accept(at: 1440, size: 1, color: 6).uppercased()
            } while wsReply != "Y" && wsReply != "N"
            if wsReply == "Y" { s.store.writeRaw(path, []) }
            c.display(s.t("irs030.note_counts"), at: 1401, eraseEOL: true)
            wsReply = try c.accept(at: 1430, size: 1)
        }

        // MARK: initialise-main section

        func initialiseMain() throws {
            c.display(" ", at: 101, eraseEOS: true)
            wsLines = 24
            ctx.fileNames = ctx.sys.str("system-files")
            try IRSub3.read(s)
            try IRSub1.open(s, .io)
            a = 0
            for yy in 31...32 {
                y = yy
                nl.setInt("owning", Int64(IRS.defAc(ctx.dflt, yy))); nl.setInt("sub-nominal", 0)
                if IRSub1.readIndexed(s, &nl) == 2 {
                    c.display(s.t("irs030.vat_accounts_missing"), at: wsLines, 1, color: 4, eraseEOL: true)
                    wsReply = try c.accept(at: wsLines, 77, size: 1)
                    c.display(" ", at: wsLines, 1, eraseEOL: true)
                    a += 1
                }
            }
            y = 33
            if a > 0 {
                c.display(" ", at: 101, eraseEOS: true)
                c.display(s.t("irs030.fix_vat"), at: 1201, color: 4, eraseEOS: true)
                c.display(s.t("irs030.hit_return_main"), at: 1401, color: 4)
                wsReply = try c.accept(at: 1440, size: 1)
            }
        }
    }

    static func run(_ s: Session) throws {
        let r = Run(s)
        try r.initialiseMain()
        if r.a > 0 { return }
        do {
            try r.perform(.mainLoop, thru: .mainExit)
        } catch is ExitProgram { return }
    }
}
