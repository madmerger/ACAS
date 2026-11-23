import Foundation

/// incomplete_records_system/irs080.cbl: 勘定元帳の修復 (残高を消去し、全転記から再集計する)
enum IRS080 {
    static let progName = "irs080 (3.01.13)"

    static func run(_ s: Session) throws {
        let c = s.console
        let ctx = IRS.context(s)
        var nl = IRS.newNL()
        var post = IRS.newPost()
        var cnt: Int64 = 0
        func add(_ r: inout Record, _ f: String, _ v: Int64) { r.setInt(f, abs(r.int(f) + v) % 10_000_000_000) }

        ctx.fileNames = ctx.sys.str("system-files")
        ctx.sys.setInt("save-sequ", 0)
        c.display(" ", at: 101, eraseEOS: true)
        c.display(progName, at: 101, color: 2)
        c.display(s.t("irs080.title"), at: 129, color: 1, reverse: true)
        c.display(ctx.sys.str("run-date"), at: 173, color: 2)
        c.display(s.t("irs080.backup_warning"), at: 301, color: 4)
        c.display(s.t("irs080.quit_help"), at: 410, color: 2)
        c.display(s.t("irs080.password"), at: 501, color: 2)
        let pass = try c.accept(at: 520, size: 4, options: [.secure])
        if pass != ctx.sys.str("pass-word") { return }
        c.display(s.t("irs080.clearing"), at: 101, color: 2, eraseEOS: true)
        try IRSub1.open(s, .io)
        // clear-nl
        while IRSub1.readNext(s, &nl) != 3 {
            nl.setInt("dr", 0); nl.setInt("cr", 0)
            IRSub1.rewrite(s, nl)
            cnt = (cnt + 1) % 100000
        }
        c.display(s.t("irs080.cleared"), at: 201, color: 2)
        c.display(Cobol.z(cnt, 5), at: 234)
        cnt = 0
        try IRSub3.read(s)
        c.display(s.t("irs080.got_default"), at: 301, color: 2)
        func vatAccount(_ i: Int, _ msgKey: String) throws -> Record {
            nl.setInt("owning", Int64(IRS.defAc(ctx.dflt, i))); nl.setInt("sub-nominal", 0)
            let err = IRSub1.readIndexed(s, &nl)
            if err != 0 {
                c.display(s.t(msgKey), at: 2301, color: 4, highlight: true)
                c.display(String(err % 10), at: 2319, color: 4, highlight: true)
                _ = try c.accept(at: 2340, size: 1, kind: .numeric)
                throw StopRun()
            }
            return nl
        }
        var nl31 = try vatAccount(31, "irs080.irsub1_31")
        var nl32 = try vatAccount(32, "irs080.irsub1_32")
        // repost
        c.display(s.t("irs080.updating"), at: 401, color: 2)
        if try IRSub4.open(s, .input) != 0 {
            c.display(s.t("irs080.no_postings"), at: 2301, color: 2)
        } else {
            while IRSub4.readNext(s, &post) != 3 {
                cnt = (cnt + 1) % 100000
                let amount = IRS.getSigned(post, "amount"), vat = IRS.getSigned(post, "vat-amount")
                let side = post.str("vat-side"), def = post.int("vat-ac-def")
                nl.setInt("owning", post.int("dr")); nl.setInt("sub-nominal", 0)
                if IRSub1.readIndexed(s, &nl) == 2 {
                    c.display(s.t("irs080.invalid_key_1"), at: 2301, color: 4, highlight: true)
                    c.display(Cobol.z(post.int("dr"), 5), at: 2317, color: 4, highlight: true)
                    _ = try c.accept(at: 2340, size: 1, kind: .numeric)
                    continue
                }
                add(&nl, "dr", amount)
                if side == "CR" { add(&nl, "dr", vat) }
                IRSub1.rewrite(s, nl)
                nl.setInt("owning", post.int("cr")); nl.setInt("sub-nominal", 0)
                if IRSub1.readIndexed(s, &nl) == 2 {
                    c.display(s.t("irs080.invalid_key_2"), at: 2301, color: 4, highlight: true)
                    c.display(Cobol.z(post.int("cr"), 5), at: 2317, color: 4, highlight: true)
                    _ = try c.accept(at: 2340, size: 1, kind: .numeric)
                    continue
                }
                add(&nl, "cr", amount)
                if side == "DR" { add(&nl, "cr", vat) }
                IRSub1.rewrite(s, nl)
                if def == 0 { continue }
                if def == 31 && side == "CR" { add(&nl31, "cr", vat) }
                else if def == 31 && side == "DR" { add(&nl31, "dr", vat) }
                else if def == 32 && side == "CR" { add(&nl32, "cr", vat) }
                else if def == 32 && side == "DR" { add(&nl32, "dr", vat) }
            }
        }
        // eoj
        IRSub1.rewrite(s, nl31)
        IRSub1.rewrite(s, nl32)
        IRSub4.close(s)
        IRSub1.close(s)
        c.display(" ", at: 501, eraseEOL: true)
        c.display(s.t("irs080.complete"), at: 501, color: 2)
        c.display(Cobol.z(cnt, 5), at: 524, color: 2)
        c.display(s.t("irs080.note_counts"), at: 701, color: 2)
        _ = try c.accept(at: 747, size: 1, color: 2)
    }
}
