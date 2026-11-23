import Foundation

/// 売掛元帳 後半 (sl100〜sl200, sl900〜sl960) の共通補助
enum SLB {
    /// 数値項目 (pic 9(n)) の ACCEPT。戻り値は項目へ MOVE した値。
    static func acceptNum(_ s: Session, at llcc: Int, digits: Int, initial: Int64? = nil,
                          options: AcceptOptions = [], color: UInt8 = 0) throws -> Int64 {
        var o = options
        if initial != nil { o.insert(.update) }
        let r = try s.console.accept(at: llcc, size: digits, kind: .numeric,
                                     initial: Cobol.z(initial ?? 0, digits), options: o, color: color)
        return Cobol.moveNumeric(r, digits: digits, scale: 0)
    }

    /// zz070-Convert-Date: to-day (UK) を Date-Form の表示形式へ
    static func wsDate(_ s: Session) -> String {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return Common.convDate(s, s.toDay)
    }

    static func upper(_ x: String) -> String { x.uppercased() }

    // MARK: - 共通ルーチン

    /// common/maps99.cbl: エラー表示 (error.txt が無い場合は "T-nnn Error not in error.txt...")
    static func maps99(_ s: Session, _ code: Int) throws {
        let c = s.console
        var lin = 23
        s.termCode = 0
        var serv = "T", errno = code, mess = Cobol.x(s.t("slb.maps99_not_found"), 50)
        var found: (sev: String, resp: String)?
        if let raw = s.store.readRaw("error.txt") {
            for line in SJIS.decode(raw[...]).components(separatedBy: "\n") {
                let l = Array(Cobol.x(line, 57))
                guard Int(String(l[0..<3])) == code else { continue }
                errno = code
                serv = String(l[3])
                mess = String(l[7..<57])
                let el = Int(String(l[5..<7])) ?? 0
                if el != 0 { lin = el > 19 ? 24 - (24 - el) : el }
                found = (serv, String(l[4]))
                break
            }
        }
        let text = serv + "-" + Cobol.z(errno, 3) + " " + mess
        c.display(text, at: lin * 100 + 1, color: 4)
        if let f = found, f.resp != "T", !(f.sev == "S" && f.resp == "S") {
            if f.sev == "T" { s.termCode = 9 }
            return
        }
        _ = try c.accept(at: 24, 79, size: 1)
    }

    /// File-Status (n) (1 始まり)
    static func fileStatus(_ s: Session, _ n: Int) -> Int {
        let a = Array(Cobol.x(s.sys.str("file-statuses"), 32))
        return a[n - 1].wholeNumberValue ?? 0
    }
    static func setFileStatus(_ s: Session, _ n: Int, _ v: Int) {
        var a = Array(Cobol.x(s.sys.str("file-statuses"), 32))
        a[n - 1] = Character(String(v))
        s.sys["file-statuses"] = String(a)
    }

    /// zz060-Convert-Date: バイナリ日付 → (u-date (UK), ws-date (表示形式))
    static func convBin(_ s: Session, _ bin: Int64) -> (uDate: String, wsDate: String) {
        let u = Maps04.toDate(Int(bin))
        if u.trimmingCharacters(in: .whitespaces).isEmpty { return (u, Cobol.x("", 10)) }
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        return (u, Common.convDate(s, u))
    }

    /// zz050-Validate-Date: 表示形式の日付 → バイナリ (0 = 不正)
    static func validateDate(_ s: Session, _ test: String) -> (uDate: String, bin: Int64) {
        if s.sys.int("date-form") == 0 { s.sys.setInt("date-form", 1) }
        let u = Common.toUK(s, Cobol.x(test, 10))
        return (u, Int64(Maps04.toBinary(u)))
    }

    /// FileStat-Msgs.cpy
    static func fsMsg(_ s: Session, _ status: String) -> String {
        let known = ["00", "02", "04", "05", "07", "10", "14", "21", "22", "23", "30", "31", "34", "35", "37", "38",
                     "39", "41", "42", "43", "44", "46", "47", "48", "49", "51", "52", "57", "61", "91"]
        guard known.contains(status) else { return "" }
        return Cobol.x(s.t("slb.fs_" + status), 25)
    }

    /// 帳票ファイル (organization sequential の print-file、ADVANCING 付き WRITE)
    final class Printer {
        let s: Session
        let path: String
        let size: Int
        let variable: Bool
        private var needsNL = false
        private var closed = false
        /// variable: FD に長さの異なる 01 が複数ある場合 (可変長形式: 各レコード前に 4 バイトのレコード長ヘッダ)
        init(_ s: Session, _ name: String = "prt-1", size: Int = 132, variable: Bool = false) {
            self.s = s; self.path = s.ledgers + name; self.size = size; self.variable = variable
        }
        func openOutput() { s.store.writeRaw(path, []); needsNL = false; closed = false }
        private func rec(_ text: String) -> [UInt8] {
            let hdr: [UInt8] = variable ? [UInt8(size >> 8), UInt8(size & 0xFF), 0, 0] : []
            return hdr + SJIS.encode(text, size: size)
        }
        func after(_ text: String, _ n: Int) {
            s.store.appendRaw(path, [UInt8](repeating: 0x0A, count: n) + rec(text)); needsNL = true
        }
        func before(_ text: String, _ n: Int) {
            s.store.appendRaw(path, rec(text) + [UInt8](repeating: 0x0A, count: n)); needsNL = false
        }
        func afterPage(_ text: String) { s.store.appendRaw(path, [0x0C] + rec(text)); needsNL = true }
        func beforePage(_ text: String) { s.store.appendRaw(path, rec(text) + [0x0C]); needsNL = false }
        /// CLOSE (最後の WRITE が AFTER ADVANCING なら改行を補う)
        func close() {
            if closed { return }
            if needsNL { s.store.appendRaw(path, [0x0A]) }
            needsNL = false; closed = true
        }
        /// call "SYSTEM" using print-report (CLOSE 済みでなければ先に閉じる)
        func spool() { close(); s.onReport?(path) }
    }

    /// z(n)9.99 形式 (符号なし編集)。value は小数 2 桁のスケール付き整数。
    static func z99(_ value: Int64, _ intDigits: Int) -> String {
        let v = abs(value) % Cobol.pow10(intDigits + 2)
        let i = String(v / 100), f = Cobol.z(v % 100, 2)
        return String(repeating: " ", count: intDigits - i.count) + i + "." + f
    }
    static func z99cr(_ value: Int64, _ intDigits: Int) -> String {
        z99(value, intDigits) + (value < 0 ? "CR" : "  ")
    }
    /// -(n)9 形式 (幅 n+1、浮動マイナス)。value は整数部のみ渡す。negative は送り側の符号。
    static func minus(_ value: Int64, _ n: Int, negative: Bool? = nil) -> String {
        let v = String(abs(value) % Cobol.pow10(n))
        let t = ((negative ?? (value < 0)) ? "-" : "") + v
        return String(repeating: " ", count: n + 1 - t.count) + t
    }
    /// z(n)9 形式
    static func zz(_ value: Int64, _ digits: Int) -> String {
        let v = String(abs(value) % Cobol.pow10(digits))
        return String(repeating: " ", count: digits - v.count) + v
    }

    // MARK: - レコードレイアウト

    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static let bs = FieldType.native(bytes: 2, signed: true)
    private static func d(_ n: String, _ digits: Int = 1) -> (String, FieldType) { (n, .n9(digits: digits, scale: 0, signed: false)) }
    private static func m9(_ n: String) -> (String, FieldType) { (n, .comp3(digits: 9, scale: 2, signed: true)) }
    private static func m10(_ n: String) -> (String, FieldType) { (n, .comp3(digits: 10, scale: 2, signed: true)) }

    /// copybooks/fdsl.cob Sales-Record (300 バイト)
    static let salesLayout = Layout("sales-record", [
        ("sales-key", .x(7)), ("sales-name", .x(30)), ("sales-addr1", .x(48)), ("sales-addr2", .x(48)),
        ("sales-phone", .x(13)), ("sales-ext", .x(4)), ("sales-email", .x(30)), ("sales-fax", .x(13)),
        d("sales-status"), d("sales-late"), d("sales-dunning"), d("email-invoice"), d("email-statement"),
        d("email-letters"), d("delivery-tag"), d("notes-tag"), ("", .filler(3)), d("sales-credit", 2),
        ("sales-discount", .comp(digits: 4, scale: 2, signed: false)), ("sales-late-min", bs), ("sales-late-max", bs),
        ("sales-limit", bl), ("sales-activety", bl), ("sales-last-inv", bl), ("sales-last-pay", bl),
        ("sales-average", bl), ("sales-pay-activety", bl), ("sales-pay-average", bl), ("sales-pay-worst", bl),
        ("sales-create-date", bl), m10("sales-current"), m10("sales-last"),
        m10("turnover-q1"), m10("turnover-q2"), m10("turnover-q3"), m10("turnover-q4"),
        m10("sales-unapplied"), ("", .filler(10)),
    ])
    static func salesFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "salesled.dat", layout: salesLayout, keyOffset: 0, keyLength: 7)
    }

    /// sales/wsoi.cob OI-Header (114 バイト) = open-item-record-3
    static let oiLayout = Layout("oi-header", [
        ("oi-customer", .x(7)), ("oi-invoice", bl), ("oi-date", bl),
        ("oi-b-nos", .comp(digits: 5, scale: 0, signed: false)), ("oi-b-item", .comp(digits: 3, scale: 0, signed: false)),
        d("oi-type"), ("oi-description", .x(25)), ("oi-hold-flag", .x(1)), ("oi-unapl", .x(1)),
        m9("oi-p-c"), m9("oi-net"), m9("oi-extra"), m9("oi-carriage"), m9("oi-vat"), m9("oi-discount"),
        m9("oi-e-vat"), m9("oi-c-vat"), m9("oi-paid"), d("oi-status"),
        ("oi-deduct-days", .native(bytes: 1, signed: true)),
        ("oi-deduct-amt", .comp(digits: 5, scale: 2, signed: true)), ("oi-deduct-vat", .comp(digits: 5, scale: 2, signed: true)),
        ("oi-days", .native(bytes: 1, signed: true)), ("oi-cr", bl), ("oi-applied", .x(1)), ("oi-date-cleared", bl),
    ])
    /// open-item-file-3 (openitm3.dat、キー = 得意先 7 + 請求書番号 binary-long)
    static func oi3File(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "openitm3.dat", layout: oiLayout, keyOffset: 0, keyLength: 11)
    }

    /// copybooks/fdval.cob Value-Record
    static let valueLayout = Layout("value-record", [
        ("va-code", .x(3)), d("va-gl", 6), ("va-desc", .x(24)), ("va-print", .x(3)),
        ("va-t-this", .comp(digits: 5, scale: 0, signed: false)), ("va-t-last", .comp(digits: 5, scale: 0, signed: false)),
        ("va-t-year", .comp(digits: 5, scale: 0, signed: false)),
        m10("va-v-this"), m10("va-v-last"), m10("va-v-year"),
    ])
    static func valueFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "value.dat", layout: valueLayout, keyOffset: 0, keyLength: 3)
    }

    /// copybooks/fdbatch.cob Batch-Record
    static let batchLayout = Layout("batch-record", [
        d("ledger"), d("batch-nos", 5), d("items", 2), d("batch-status"), d("cleared-status"), d("bcycle", 2),
        ("entered", bl), ("proofed", bl), ("posted", bl), ("stored", bl),
        ("input-gross", .comp3(digits: 11, scale: 2, signed: false)), ("input-vat", .comp3(digits: 11, scale: 2, signed: false)),
        ("actual-gross", .comp3(digits: 11, scale: 2, signed: false)), ("actual-vat", .comp3(digits: 11, scale: 2, signed: false)),
        ("description", .x(24)), d("bdefault", 2), ("convention", .x(2)), d("batch-def-ac", 6), d("batch-def-pc", 2),
        ("batch-def-code", .x(2)), ("batch-def-vat", .x(1)), d("batch-start", 5),
    ])
    static func batchFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "batch.dat", layout: batchLayout, keyOffset: 0, keyLength: 6)
    }

    /// copybooks/fdpost.cob Posting-Record (相対ファイル posting.dat)
    static let postingLayout = Layout("posting-record", [
        d("batch", 5), d("post-number", 5), ("post-code", .x(2)), ("post-date", .x(8)), d("post-dr", 6), d("dr-pc", 2),
        d("post-cr", 6), d("cr-pc", 2), ("post-amount", .n9(digits: 10, scale: 2, signed: true)), ("post-legend", .x(32)),
        d("vat-ac", 6), d("vat-pc", 2), ("post-vat-side", .x(2)), ("vat-amount", .n9(digits: 10, scale: 2, signed: true)),
    ])

    /// copybooks/wssys4.cob の売掛部分 (System-Record-4 先頭)
    static let sys4Names = ["sl-os-bal-last-month", "sl-os-bal-this-month", "sl-invoices-this-month",
                            "sl-credit-notes-this-month", "sl-variance", "sl-credit-deductions",
                            "sl-cn-unappl-this-month", "sl-payments", "sl4-spare1", "sl4-spare2"]
    static let sys4Layout = Layout("system-record-4", sys4Names.map { m10($0) } + [("", .filler(964))])
    static func sys4(_ s: Session) -> Record { Record(sys4Layout, bytes: s.sysRecord4) }
    static func setSys4(_ s: Session, _ r: Record) { s.sysRecord4 = r.bytes }

    /// pic s9(7)v99 sign leading (irs-post-amount 等)
    static func signLeading(_ v: Int64, digits: Int) -> [UInt8] {
        var b = Array(Cobol.z(abs(v) % Cobol.pow10(digits), digits).utf8)
        if v < 0 { b[0] += 0x40 }
        return b
    }

    // MARK: - 請求書ファイル (invoice.dat)

    /// sales/fdinv.cob Invoice-Record (134 バイト、キー = 番号 8 + 枝番 1 + 行 1)
    static let invoiceLayout = Layout("invoice-record", [
        d("invoice-nos", 8), ("invoice-let", .x(1)), ("item-nos", .native(bytes: 1, signed: true)),
        ("invoice-customer", .x(7)), ("invoice-date", bl), ("", .filler(10)), d("invoice-type"), ("", .filler(10)),
        ("", .filler(92)),
    ])
    static func invoiceFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "invoice.dat", layout: invoiceLayout, keyOffset: 0, keyLength: 10)
    }

    /// sales/wsinv.cob sinvoice-header (作業域は 137 バイト。ファイルレコードは 134 バイトなので
    /// 書込時は末尾 3 バイトが切り捨てられ、読込時は空白で埋まる: レガシーどおり)
    static let sihLayout = Layout("sinvoice-header", [
        d("sih-invoice", 8), ("sih-letter", .x(1)), ("sih-test", .native(bytes: 1, signed: true)),
        ("sih-customer", .x(7)), ("sih-date", bl), ("sih-order", .x(10)), d("sih-type"), ("sih-ref", .x(10)),
        ("sih-description", .x(32)),
        m9("sih-p-c"), m9("sih-net"), m9("sih-extra"), m9("sih-carriage"), m9("sih-vat"), m9("sih-discount"),
        m9("sih-e-vat"), m9("sih-c-vat"),
        ("sih-status", .x(1)), ("sih-status-p", .x(1)), ("sih-status-l", .x(1)), ("sih-status-c", .x(1)),
        ("sih-status-a", .x(1)), ("sih-status-i", .x(1)),
        ("sih-lines", .native(bytes: 1, signed: true)), ("sih-deduct-days", .native(bytes: 1, signed: true)),
        ("sih-deduct-amt", .comp(digits: 5, scale: 2, signed: false)), ("sih-deduct-vat", .comp(digits: 5, scale: 2, signed: false)),
        ("sih-days", .native(bytes: 1, signed: true)), ("sih-cr", bl),
        ("sih-day-book-flag", .x(1)), ("sih-update", .x(1)),
    ])
    /// sInvoice-Bodies の 1 行 (80 バイト)
    static let silLayout = Layout("invoice-line", [
        d("sil-invoice", 8), ("sil-letter", .x(1)), ("sil-line", .native(bytes: 1, signed: true)),
        ("sil-product", .x(13)), ("sil-pa", .x(2)), ("sil-qty", bs), ("sil-type", .x(1)), ("sil-description", .x(32)),
        m9("sil-net"), m9("sil-unit"), ("sil-discount", .comp(digits: 4, scale: 2, signed: false)), m9("sil-vat"),
        d("sil-vat-code"), ("sil-update", .x(1)), ("", .filler(1)),
    ])
    /// move invoice-record to sinvoice-header
    static func sih(from rec: Record) -> Record {
        Record(sihLayout, bytes: rec.bytes + [UInt8](repeating: 0x20, count: sihLayout.size - rec.bytes.count))
    }
    /// move invoice-record to invoice-line (n)
    static func sil(from rec: Record) -> Record { Record(silLayout, bytes: Array(rec.bytes[0..<silLayout.size])) }
    /// write/rewrite invoice-record from sinvoice-header / invoice-line (n)
    static func invoiceRecord(from r: Record) -> Record {
        let n = invoiceLayout.size
        var b = Array(r.bytes.prefix(n))
        if b.count < n { b += [UInt8](repeating: 0x20, count: n - b.count) }
        return Record(invoiceLayout, bytes: b)
    }

    /// copybooks/fddel.cob Delivery-Record
    static let deliveryLayout = Layout("delivery-record", [
        ("deliv-key", .x(8)), ("deliv-name", .x(30)), ("deliv-address", .x(96)),
    ])
    static func deliveryFile(_ s: Session) -> IndexedFile {
        IndexedFile(s.store, path: s.ledgers + "delivery.dat", layout: deliveryLayout, keyOffset: 0, keyLength: 8)
    }

    /// STRING ... INTO target WITH POINTER y (桁あふれ分は転送しない)
    static func stringInto(_ target: inout [Character], _ y: inout Int, _ text: String) {
        if y < 1 || y > target.count + 1 { return }
        for ch in text {
            if y > target.count { return }
            target[y - 1] = ch
            y += 1
        }
    }

    /// sl160 / sl170 / sl180 共通の「Report Attributes」選択画面 (screen section display-03)
    final class CustSelection {
        var custIn = Cobol.x("", 6), statusIn = " "
        var creditIn: Int64 = 0, creditOp = " "
        var invoiceIn: Int64 = 0, invoiceOp = " "
        var averageIn: Int64 = 0, averageOp = " "
        var overdueIn: Int64 = 0, overdueOp = " "
        var enterDateIn = Cobol.x("", 10), enterDateOp = " "
        let withDate: Bool
        private var fields: [ScreenField] = []

        init(withDate: Bool) { self.withDate = withDate }

        /// display display-03
        func display(_ s: Session, progName: String, wsDate: String, title: String = "slb.sel.title") {
            let c = s.console
            c.eraseScreen()
            func lit(_ key: String, _ line: Int, _ col: Int) { c.display(s.t(key), at: line, col, color: 2) }
            c.display(progName, at: 1, 1, color: 2)
            lit(title, 1, 34)
            c.display(wsDate, at: 1, 71, color: 2)
            lit("slb.sel.attributes", 3, 32)
            lit("slb.sel.cust", 8, 9); c.display("]", at: 8, 34, color: 2); lit("slb.sel.cust_help", 8, 39)
            lit("slb.sel.status", 10, 9); c.display("]", at: 10, 29, color: 2); lit("slb.sel.status_help", 10, 39)
            lit("slb.sel.credit", 12, 9); c.display("]  [", at: 12, 30, color: 2); c.display("]", at: 12, 35, color: 2)
            lit("slb.sel.credit_help", 12, 39)
            lit("slb.sel.credit_l", 13, 43); lit("slb.sel.credit_g", 14, 43); lit("slb.sel.credit_e", 15, 43)
            lit("slb.sel.invoice", 17, 9); c.display("] [", at: 17, 33, color: 2); c.display("]", at: 17, 37, color: 2)
            lit("slb.sel.invoice_help", 17, 39)
            lit("slb.sel.average", 19, 9); c.display("] [", at: 19, 33, color: 2); c.display("]", at: 19, 37, color: 2)
            lit("slb.sel.average_help", 19, 39)
            lit("slb.sel.overdue", 21, 9); c.display("] [", at: 21, 33, color: 2); c.display("]", at: 21, 37, color: 2)
            lit("slb.sel.overdue_help", 21, 39)
            if withDate {
                lit("slb.sel.date", 23, 9); c.display("] [", at: 23, 33, color: 2); c.display("]", at: 23, 37, color: 2)
                lit("slb.sel.date_help", 23, 39)
            }
            func f(_ l: Int, _ col: Int, _ n: Int, _ v: String, _ k: FieldKind = .alpha) -> ScreenField {
                ScreenField(line: l, col: col, size: n, kind: k, value: v, color: 2)
            }
            fields = [f(8, 28, 6, custIn), f(10, 28, 1, statusIn),
                      f(12, 28, 2, Cobol.z(creditIn, 2), .numeric), f(12, 34, 1, creditOp),
                      f(17, 28, 5, Cobol.z(invoiceIn, 5), .numeric), f(17, 36, 1, invoiceOp),
                      f(19, 28, 5, Cobol.z(averageIn, 5), .numeric), f(19, 36, 1, averageOp),
                      f(21, 28, 5, Cobol.z(overdueIn, 5), .numeric), f(21, 36, 1, overdueOp)]
            if withDate { fields += [f(23, 23, 10, enterDateIn), f(23, 36, 1, enterDateOp)] }
            c.displayFields(fields)
        }

        /// accept display-03 (値は大文字化前のまま各項目へ戻す)
        func accept(_ s: Session) throws {
            try s.console.acceptScreen(fields)
            custIn = Cobol.x(fields[0].value, 6); statusIn = Cobol.x(fields[1].value, 1)
            creditIn = Cobol.moveNumeric(fields[2].value, digits: 2, scale: 0); creditOp = Cobol.x(fields[3].value, 1)
            invoiceIn = Cobol.moveNumeric(fields[4].value, digits: 5, scale: 0); invoiceOp = Cobol.x(fields[5].value, 1)
            averageIn = Cobol.moveNumeric(fields[6].value, digits: 5, scale: 0); averageOp = Cobol.x(fields[7].value, 1)
            overdueIn = Cobol.moveNumeric(fields[8].value, digits: 5, scale: 0); overdueOp = Cobol.x(fields[9].value, 1)
            if withDate { enterDateIn = Cobol.x(fields[10].value, 10); enterDateOp = Cobol.x(fields[11].value, 1) }
        }

        static func validOp(_ op: String) -> Bool { op == "L" || op == "G" || op == "E" || op == " " }

        /// test-num
        static func testNum(_ op: String, _ test1: Int64, _ test2: Int64) -> Bool {
            let o = op.uppercased()
            var truth = o == " "
            if o == "L" && test2 < test1 { truth = true }
            if o == "G" && test2 > test1 { truth = true }
            if o == "E" && test2 == test1 { truth = true }
            return truth
        }

        /// report-heading-setup の共通部 (l3-report への STRING)。all は「全件」判定。
        func heading(_ s: Session, size: Int, all: Bool, y startY: Int = 1) -> (buf: [Character], y: Int) {
            var buf = [Character](repeating: " ", count: size)
            var y = startY
            SLB.stringInto(&buf, &y, s.t(all ? "report.slb.sel.all" : "report.slb.sel.matched"))
            y += 1
            if statusIn == "L" { SLB.stringInto(&buf, &y, s.t("report.slb.sel.live")) }
            if statusIn == "D" { SLB.stringInto(&buf, &y, s.t("report.slb.sel.dormant")) }
            y += 1
            func operand(_ op: String) -> String { op == "L" ? "< " : (op == "G" ? "> " : (op == "E" ? "= " : "  ")) }
            if creditOp != " " {
                SLB.stringInto(&buf, &y, operand(creditOp) + SLB.zz(creditIn, 2) + Cobol.x(s.t("report.slb.sel.days_credit"), 12))
            }
            y += 1
            if invoiceOp != " " {
                SLB.stringInto(&buf, &y, operand(invoiceOp) + SLB.zz(invoiceIn, 5) + Cobol.x(s.t("report.slb.sel.invoices"), 9))
            }
            y += 1
            if averageOp != " " {
                SLB.stringInto(&buf, &y, operand(averageOp) + SLB.zz(averageIn, 5) + Cobol.x(s.t("report.slb.sel.av_value"), 10))
            }
            y += 1
            if overdueOp != " " {
                SLB.stringInto(&buf, &y, operand(overdueOp) + SLB.zz(overdueIn, 5) + Cobol.x(s.t("report.slb.sel.days_overdue"), 13))
            }
            y += 1
            return (buf, y)
        }
    }
}
