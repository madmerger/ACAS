import Foundation

extension PurchaseRecords {
    /// wssys4.cob System-Record-4 の買掛部分 (先頭 120 バイト)
    static let sys4Layout: Layout = {
        var f: [(String, FieldType)] = []
        for n in ["sl-os-bal-last-month", "sl-os-bal-this-month", "sl-invoices-this-month", "sl-credit-notes-this-month", "sl-variance",
                  "sl-credit-deductions", "sl-cn-unappl-this-month", "sl-payments", "sl4-spare1", "sl4-spare2",
                  "pl-os-bal-last-month", "pl-os-bal-this-month", "pl-invoices-this-month", "pl-credit-notes-this-month", "pl-variance",
                  "pl-credit-deductions", "pl-cn-unappl-this-month", "pl-payments", "sl4-spare3", "sl4-spare4"] {
            f.append((n, money(10)))
        }
        return Layout("system-record-4", f)
    }()
    /// fdbatch.cob batch-record (96 バイト)
    static let batchLayout: Layout = {
        let amt = FieldType.comp3(digits: 11, scale: 2, signed: false)
        let l = Layout("batch-record", [
            ("ledger", d(1)), ("batch-nos", d(5)), ("items", d(2)), ("batch-status", d(1)), ("cleared-status", d(1)), ("bcycle", d(2)),
            ("entered", bl), ("proofed", bl), ("posted", bl), ("stored", bl),
            ("input-gross", amt), ("input-vat", amt), ("actual-gross", amt), ("actual-vat", amt),
            ("description", .x(24)), ("bdefault", d(2)), ("convention", .x(2)), ("batch-def-ac", d(6)), ("batch-def-pc", d(2)),
            ("batch-def-code", .x(2)), ("batch-def-vat", .x(1)), ("batch-start", d(5)),
        ])
        l.redefine("batch-key", .x(6), at: 0)
        return l
    }()

    /// fdpost.cob posting-record (98 バイト)
    static let postLayout = Layout("posting-record", [
        ("batch", d(5)), ("post-number", d(5)), ("post-code", .x(2)), ("post-date", .x(8)), ("post-dr", d(6)), ("dr-pc", d(2)),
        ("post-cr", d(6)), ("cr-pc", d(2)), ("post-amount", .n9(digits: 10, scale: 2, signed: true)), ("post-legend", .x(32)),
        ("vat-ac", d(6)), ("vat-pc", d(2)), ("post-vat-side", .x(2)), ("vat-amount", .n9(digits: 10, scale: 2, signed: true)),
    ])

    /// pic s9(7)v99 sign leading (符号は先頭桁へのオーバーパンチ)
    static func signLeading(_ v: Int64, digits: Int) -> [UInt8] {
        var a = Array(Cobol.z(abs(v) % Cobol.pow10(digits), digits).utf8)
        if v < 0 { a[0] = a[0] + 0x40 }
        return a
    }
    /// z(n)9.99cr 形式の編集 (上位桁切り捨て)
    static func cr(_ pic: String, _ v: Int64, int: Int) -> String {
        Pic.edit(pic, value: (v < 0 ? -1 : 1) * (abs(v) % Cobol.pow10(int + 2)), scale: 2)
    }

}
