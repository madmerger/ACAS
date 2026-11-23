enum BookkeepingRecords {
    static let systemLayout: Layout = {
        let l = Layout("irs-system", [
            ("run-date", .x(8)), ("suser", .x(24)), ("client", .x(24)),
            ("address-1", .x(24)), ("address-2", .x(24)), ("address-3", .x(24)), ("address-4", .x(24)),
            ("start-date", .x(8)), ("end-date", .x(8)),
            ("fn-1", .x(9)), ("fn-2", .x(10)), ("fn-3", .x(8)), ("fn-4", .x(8)), ("fn-5", .x(12)),
            ("fn-filler", .x(1)), ("system-ops", .x(1)),
            ("pass-word", .x(4)), ("next-post", .n9(digits: 5, scale: 0, signed: false)),
            ("vat", .n9(digits: 4, scale: 2, signed: false)), ("vat2", .n9(digits: 4, scale: 2, signed: false)),
            ("vat3", .n9(digits: 4, scale: 2, signed: false)),
            ("pass-value", .n9(digits: 1, scale: 0, signed: false)), ("save-sequ", .n9(digits: 1, scale: 0, signed: false)),
            ("system-work-group", .x(18)), ("pl-app-created", .x(1)),
            ("pl-approp-ac", .n9(digits: 5, scale: 0, signed: false)),
            ("print-spool-name", .x(32)), ("first-time-flag", .n9(digits: 1, scale: 0, signed: false)),
            ("filler-9", .n9(digits: 7, scale: 0, signed: false)), ("filler-x", .x(8)),
        ])
        l.redefine("system-files", .x(49), at: l.offset("fn-1"))
        return l
    }()

    /// wsnl.cob (nl-record, 116 桁)
    static let nlLayout: Layout = {
        var defs: [(String, FieldType)] = [
            ("owning", .n9(digits: 5, scale: 0, signed: false)), ("sub-nominal", .n9(digits: 5, scale: 0, signed: false)),
            ("type", .x(1)), ("name", .x(24)),
            ("dr", .comp(digits: 10, scale: 2, signed: false)), ("cr", .comp(digits: 10, scale: 2, signed: false)),
        ]
        for i in 1...4 { defs.append(("dr-last-\(i)", .comp(digits: 10, scale: 2, signed: false))) }
        for i in 1...4 { defs.append(("cr-last-\(i)", .comp(digits: 10, scale: 2, signed: false))) }
        defs.append(("ac", .x(1)))
        let l = Layout("irs-nl", defs)
        l.redefine("key", .x(10), at: 0)
        l.redefine("pointer", .n9(digits: 5, scale: 0, signed: false), at: 11)
        l.redefine("data", .x(105), at: 11)
        return l
    }()

    /// wspost.cob (posting-record, 77 桁)
    static let postLayout: Layout = {
        let l = Layout("irs-post", [
            ("key", .n9(digits: 5, scale: 0, signed: false)), ("code", .x(2)), ("date", .x(8)),
            ("dr", .n9(digits: 5, scale: 0, signed: false)), ("cr", .n9(digits: 5, scale: 0, signed: false)),
            ("amount", .x(9)), ("legend", .x(32)),
            ("vat-ac-def", .n9(digits: 2, scale: 0, signed: false)), ("vat-side", .x(2)),
            ("vat-amount", .x(9)),
        ])
        return l
    }()

    /// fdpost-irs.cob (postings2irs.dat: SL/PL から IRS への転記受け渡しファイル, 84 桁)
    static let ledgerPostLayout = Layout("irs-ledger-post", [
        ("batch", .n9(digits: 5, scale: 0, signed: false)), ("post-number", .n9(digits: 5, scale: 0, signed: false)),
        ("code", .x(2)), ("date", .x(8)),
        ("dr", .n9(digits: 5, scale: 0, signed: false)), ("cr", .n9(digits: 5, scale: 0, signed: false)),
        ("amount", .x(9)), ("legend", .x(32)),
        ("vat-ac-def", .n9(digits: 2, scale: 0, signed: false)), ("vat-side", .x(2)),
        ("vat-amount", .x(9)),
    ])

    static func getSigned(_ rec: Record, _ name: String) -> Int64 {
        let b = rec.raw(name)
        var v: Int64 = 0
        var neg = false
        for (i, c) in b.enumerated() {
            var d = c
            if i == 0, c >= 0x70, c <= 0x79 { neg = true; d = c - 0x40 }
            v = v * 10 + ((d >= 0x30 && d <= 0x39) ? Int64(d - 0x30) : 0)
        }
        return neg ? -v : v
    }

    static func setSigned(_ rec: inout Record, _ name: String, _ value: Int64) {
        var b = Array(Cobol.z(abs(value) % Cobol.pow10(rec.raw(name).count), rec.raw(name).count).utf8)
        if value < 0 { b[0] += 0x40 }
        rec.setRaw(name, b)
    }
}
