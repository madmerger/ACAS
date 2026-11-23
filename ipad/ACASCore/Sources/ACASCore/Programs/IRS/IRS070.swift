import Foundation

/// incomplete_records_system/irs070.cbl: 転記の訂正 (逆仕訳して再入力、削除、転記番号の振り直し)
enum IRS070 {
    static let progName = "irs070 (3.01.06)"

    final class Run {
        let s: Session
        let c: Console
        let ctx: IRS.Context
        var b = 0, cFlag = 0, d = 0, e = 0
        var wsReply = " "
        var counter: Int64 = 0
        var y = 0
        var errorFlag = 0
        var amtOk: Int64 = 0
        var screenAccept = Cobol.x("", 10)
        var nl = IRS.newNL()
        var post = IRS.newPost()
        var postAmount: Int64 {
            get { IRS.getSigned(post, "amount") }
            set { IRS.setSigned(&post, "amount", newValue) }
        }
        var vatAmount: Int64 {
            get { IRS.getSigned(post, "vat-amount") }
            set { IRS.setSigned(&post, "vat-amount", newValue) }
        }
        var side: String { post.str("vat-side") }
        var vatAcDef: Int64 { post.int("vat-ac-def") }

        init(_ s: Session) { self.s = s; c = s.console; ctx = IRS.context(s) }

        /// 符号なし項目への加算 (結果は絶対値で入る)
        func add(_ f: String, _ v: Int64) { nl.setInt(f, abs(nl.int(f) + v) % 10_000_000_000) }
        func readNL(_ owning: Int64) -> Bool {
            nl.setInt("owning", owning); nl.setInt("sub-nominal", 0)
            return IRSub1.readIndexed(s, &nl) != 2
        }
        func dispAmount(_ v: Int64, _ at: Int) {
            c.display(Pic.edit("z(6)9.99", value: abs(v), scale: 2), at: at, color: 3)
        }
        func acceptNum(_ at: Int, _ field: String, _ size: Int) throws {
            post.setInt(field, Int64(IRS.num(try c.accept(at: at, size: size, kind: .numeric, initial: Cobol.z(post.int(field), size),
                                                          options: [.update], color: 3))))
        }

        func main() throws {
            ctx.fileNames = ctx.sys.str("system-files")
            ctx.sys.setInt("save-sequ", 0)
            try IRSub3.read(s)
            try IRSub1.open(s, .io)
            try IRSub4.open(s, .io)
            c.display(" ", at: 101, eraseEOS: true)
            c.display(progName, at: 101, color: 2)
            c.display(s.t("irs070.title"), at: 131, color: 1, reverse: true)
            c.display(ctx.sys.str("run-date"), at: 173, color: 2)
            inputLoop: while true {
                c.display(s.t("irs070.number"), at: 501, color: 2)
                c.display(s.t("irs070.return_to_quit"), at: 525, color: 2, eraseEOL: true)
                c.display(s.t("irs070.code"), at: 601, color: 2)
                c.display(s.t("irs070.date"), at: 701, color: 2)
                c.display(s.t("irs070.debit"), at: 801, color: 2)
                c.display(s.t("irs070.credit"), at: 901, color: 2)
                c.display(s.t("irs070.net"), at: 1001, color: 2)
                c.display(" ", at: 1101, color: 2, eraseEOL: true)
                c.display(s.t("irs070.narrative"), at: 1101, color: 2)
                c.display("]", at: 1147, color: 2)
                c.display(s.t("irs070.vat_type"), at: 1201, color: 2)
                c.display(s.t("irs070.vat_type_help"), at: 1301, color: 2)
                c.display(s.t("irs070.vat_side"), at: 1401, color: 2)
                c.display(s.t("irs070.vat"), at: 1501, color: 2)
                c.display(s.t("irs070.delete_help"), at: 2201, color: 2)
                c.display(s.t("irs070.exit_help"), at: 2301, color: 2)
                post.setInt("key", 0)
                try acceptNum(514, "key", 5)
                if post.int("key") == 0 { break }
                if IRSub4.readIndexed(s, &post) == 2 {
                    c.display(s.t("irs070.not_exist"), at: 542, color: 2)
                    continue
                }
                c.display(s.t("irs070.reversing"), at: 542, color: 2)
                c.display(post.str("code"), at: 614, color: 3)
                c.display(post.str("date"), at: 714, color: 3)
                c.display(Cobol.z(post.int("dr"), 5), at: 814, color: 3)
                c.display(Cobol.z(post.int("cr"), 5), at: 914, color: 3)
                dispAmount(postAmount, 1014)
                c.display(post.str("legend"), at: 1114, color: 3)
                c.display(Cobol.z(vatAcDef, 2), at: 1214, color: 3)
                c.display(side, at: 1414, color: 3)
                dispAmount(vatAmount, 1514)
                reverse()
                // reverse-end
                while true {
                    c.display(s.t("irs070.correct_transaction"), at: 525, color: 2, eraseEOL: true)
                    c.display(s.t("irs070.delete_here"), at: 641, color: 4)
                    post["code"] = try c.accept(at: 614, size: 2, initial: post.str("code"), options: [.update], color: 3)
                    if post.str("code") == "**" {
                        IRSub4.delete(s, key: post.raw("key"))
                        continue inputLoop
                    }
                    c.display(" ", at: 641, color: 2, eraseEOL: true)
                    while true {
                        post["date"] = try c.accept(at: 714, size: 8, initial: post.str("date"), options: [.update], color: 3)
                        let (bin, norm) = IRSMenu.dateValidate(post.str("date"))
                        if bin != 0 { post["date"] = norm; break }
                    }
                    try acceptNum(814, "dr", 5)
                    try acceptNum(914, "cr", 5)
                    amtOk = postAmount
                    try acceptMoney(1014)
                    postAmount = amtOk
                    post["legend"] = try c.accept(at: 1114, size: 32, initial: post.str("legend"), options: [.update], color: 3)
                    getAcDef: while true {
                        try acceptNum(1214, "vat-ac-def", 2)
                        if vatAcDef != 0 && vatAcDef != 31 && vatAcDef != 32 {
                            c.display(s.t("irs070.error"), at: 1218, color: 4)
                            continue
                        }
                        c.display("     ", at: 1218)
                        while true {
                            post["vat-side"] = try c.accept(at: 1414, size: 2, initial: side, options: [.update], color: 3).uppercased()
                            if side != "CR" && side != "DR" {
                                c.display(s.t("irs070.error"), at: 1418, color: 4)
                                continue
                            }
                            break
                        }
                        c.display("     ", at: 1418)
                        amtOk = vatAmount
                        try acceptMoney(1514)
                        if amtOk != 0 && vatAcDef == 0 {
                            c.display(s.t("irs070.inconsistent"), at: 1525, color: 4)
                            continue getAcDef
                        }
                        break
                    }
                    c.display(Cobol.x("", 12), at: 1525)
                    vatAmount = amtOk
                    if !readNL(post.int("dr")) { continue }
                    if !readNL(post.int("cr")) { continue }
                    if vatAcDef != 0 {
                        y = Int(vatAcDef)
                        if !readNL(Int64(IRS.defAc(ctx.dflt, y))) { continue }
                    }
                    break
                }
                // jump-to-dr
                _ = readNL(post.int("dr"))
                add("dr", postAmount)
                if side == "CR" { add("dr", vatAmount) }
                IRSub1.rewrite(s, nl)
                _ = readNL(post.int("cr"))
                add("cr", postAmount)
                if side == "DR" { add("cr", vatAmount) }
                IRSub1.rewrite(s, nl)
                if vatAcDef != 0 {
                    y = Int(vatAcDef)
                    _ = readNL(Int64(IRS.defAc(ctx.dflt, y)))
                    if side == "CR" { add("cr", vatAmount) }
                    if side == "DR" { add("dr", vatAmount) }
                    IRSub1.rewrite(s, nl)
                }
                IRSub4.rewrite(s, post)
            }
            try endOfAmend()
        }

        /// 既存の転記を勘定元帳から取り消す (reverse-cr / reverse-vat を含む)
        func reverse() {
            let amount = postAmount, vat = vatAmount
            if readNL(post.int("dr")) {
                errorFlag = 0
                if amount > 0 { add("cr", amount) } else { add("dr", -amount) }
                if side == "CR" && vat > 0 { add("cr", vat) }
                if side == "CR" && vat < 0 { add("dr", -vat) }
                IRSub1.rewrite(s, nl)
            } else {
                errorFlag = 1
            }
            guard readNL(post.int("cr")) else { errorFlag = 1; return reverseVat() }
            if amount > 0 { add("dr", amount) } else { add("cr", -amount) }
            if side == "DR" && vat > 0 { add("dr", vat) }
            if side == "DR" && vat < 0 { add("cr", -vat) }
            IRSub1.rewrite(s, nl)
            reverseVat()
        }

        func reverseVat() {
            if vatAcDef == 0 { return }
            y = Int(vatAcDef)
            guard readNL(Int64(IRS.defAc(ctx.dflt, y))) else { errorFlag = 1; return }
            let vat = vatAmount
            if side == "CR" && vat > 0 { add("dr", vat) }
            if side == "DR" && vat > 0 { add("cr", vat) }
            if side == "CR" && vat < 0 { add("cr", vat) }
            if side == "DR" && vat < 0 { add("dr", vat) }
            IRSub1.rewrite(s, nl)
        }

        func endOfAmend() throws {
            IRSub4.close(s)
            IRSub1.close(s)
            c.display(s.t("irs070.renumber"), at: 301, color: 2)
            while true {
                wsReply = try c.accept(at: 332, size: 1, color: 6)
                if wsReply == "N" || wsReply == "n" { return }
                if wsReply == "Y" || wsReply == "y" { break }
            }
            c.display(s.t("irs070.sorting"), at: 1331, color: 2)
            ctx.sys.setInt("pass-value", 2); ctx.sys.setInt("save-sequ", 2)
            try IRS055.run(s)
            ctx.sys.setInt("pass-value", 0)
            try IRSub4.open(s, .output)
            _ = IRSubP.open(s, .input)
            counter = 0
            while IRSubP.readNext(s, &post) == 0 {
                counter = (counter + 1) % 100000
                post.setInt("key", counter)
                IRSub4.write(s, &post)
            }
            IRSub4.close(s)
            IRSubP.close(s)
            ctx.sys.setInt("next-post", (post.int("key") + 1) % 100000)
            IRSub2.write(s)
        }

        // MARK: accept-money / justify-accept-money

        func acceptMoney(_ at: Int) throws {
            while true {
                let v = abs(amtOk)
                screenAccept = Cobol.z(v / 100, 7) + "." + Cobol.z(v % 100, 2)
                screenAccept = try c.accept(at: at, size: 10, initial: screenAccept, options: [.update], color: 3)
                justifyAcceptMoney()
                if cFlag > 1 || d > 1 {
                    c.display(s.t("irs070.not_numeric"), at: 2401, color: 4)
                    continue
                }
                c.display(Cobol.x("", 28), at: 2401)
                return
            }
        }

        /// c = 負号フラグ、d = 小数点フラグ、e = 小数桁数 (e は初期化されず前回値が残る: レガシーのまま)
        func justifyAcceptMoney() {
            amtOk = 0; cFlag = 0; d = 0
            var nstrg = [Int](repeating: 0, count: 9)
            b = 10
            let chars = Array(Cobol.x(screenAccept, 10))
            var a = 10
            while a >= 1 {
                let ch = chars[a - 1]
                a -= 1
                if ch == "-" && cFlag == 1 { cFlag = 2; break }
                if ch == "." && d == 1 { d = 2; break }
                if ch == "-" { cFlag = 1; continue }
                if ch == "." { d = 1; e = 10 - b; continue }
                let numeric = ch.isASCII && ch.isNumber
                if !numeric && b != 10 { cFlag = 3; break }
                if numeric {
                    b -= 1
                    if b >= 1 { nstrg[b - 1] = Int(String(ch))! }
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
    }

    static func run(_ s: Session) throws { try Run(s).main() }
}
