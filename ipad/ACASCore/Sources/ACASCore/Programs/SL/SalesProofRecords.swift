import Foundation

enum SalesProofRecords {
    private static let bl = FieldType.native(bytes: 4, signed: true)
    private static let bs = FieldType.native(bytes: 2, signed: true)
    private static let amt = FieldType.comp3(digits: 10, scale: 2, signed: true)
    private static func d(_ n: String, _ digits: Int = 1) -> (String, FieldType) { (n, .n9(digits: digits, scale: 0, signed: false)) }

    static let salesLayout = Layout("sales-record", [
        ("sales-key", .x(7)), ("sales-name", .x(30)), ("sales-addr1", .x(48)), ("sales-addr2", .x(48)),
        ("sales-phone", .x(13)), ("sales-ext", .x(4)), ("sales-email", .x(30)), ("sales-fax", .x(13)),
        d("sales-status"), d("sales-late"), d("sales-dunning"), d("email-invoice"), d("email-statement"),
        d("email-letters"), d("delivery-tag"), d("notes-tag"), ("", .filler(3)), d("sales-credit", 2),
        ("sales-discount", .comp(digits: 4, scale: 2, signed: false)),
        ("sales-late-min", bs), ("sales-late-max", bs), ("sales-limit", bl), ("sales-activety", bl),
        ("sales-last-inv", bl), ("sales-last-pay", bl), ("sales-average", bl), ("sales-pay-activety", bl),
        ("sales-pay-average", bl), ("sales-pay-worst", bl), ("sales-create-date", bl),
        ("sales-current", amt), ("sales-last", amt), ("turnover-q1", amt), ("turnover-q2", amt),
        ("turnover-q3", amt), ("turnover-q4", amt), ("sales-unapplied", amt), ("", .filler(10)),
    ])
    private static let fig = FieldType.comp3(digits: 9, scale: 2, signed: true)

    /// fdinv2.cob invoice-header
    static let ihLayout = Layout("invoice-header", [
        ("ih-invoice", .n9(digits: 8, scale: 0, signed: false)), ("ih-letter", .x(1)), ("ih-test", .native(bytes: 1, signed: true)),
        ("ih-customer", .x(7)), ("ih-date", bl), ("ih-order", .x(10)), d("ih-type"), ("ih-ref", .x(10)),
        ("ih-description", .x(32)),
        ("ih-p-c", fig), ("ih-net", fig), ("ih-extra", fig), ("ih-carriage", fig), ("ih-vat", fig),
        ("ih-discount", fig), ("ih-e-vat", fig), ("ih-c-vat", fig),
        ("ih-status", .x(1)), ("ih-status-p", .x(1)), ("ih-status-l", .x(1)), ("ih-status-c", .x(1)),
        ("ih-status-a", .x(1)), ("ih-status-i", .x(1)),
        ("ih-lines", .native(bytes: 1, signed: true)), ("ih-deduct-days", .native(bytes: 1, signed: true)),
        ("ih-deduct-amt", .comp(digits: 5, scale: 2, signed: false)), ("ih-deduct-vat", .comp(digits: 5, scale: 2, signed: false)),
        ("ih-days", .native(bytes: 1, signed: true)), ("ih-cr", bl), ("ih-day-book-flag", .x(1)), ("ih-update", .x(1)),
    ])
    /// fdinv2.cob / wsinv.cob invoice-line (80 バイト)
    static let ilLayout = Layout("invoice-line", [
        ("il-invoice", .n9(digits: 8, scale: 0, signed: false)), ("il-letter", .x(1)), ("il-line", .native(bytes: 1, signed: true)),
        ("il-product", .x(13)), ("il-pa", .x(2)), ("il-qty", bs), ("il-type", .x(1)), ("il-description", .x(32)),
        ("il-net", fig), ("il-unit", fig), ("il-discount", .comp(digits: 4, scale: 2, signed: false)), ("il-vat", fig),
        d("il-vat-code"), ("il-update", .x(1)), ("", .filler(1)),
    ])

    static func salesFile(_ store: FileStore) -> IndexedFile {
        IndexedFile(store, path: "ledgers/acas/salesled.dat", layout: salesLayout, keyLength: 7)
    }

    static func invoiceFile(_ store: FileStore) -> IndexedFile {
        IndexedFile(store, path: "ledgers/acas/invoice.dat", layout: ihLayout, keyLength: 10)
    }

    static func spaces(_ n: Int) -> String { String(repeating: " ", count: n) }

    final class Printer {
        private let store: FileStore
        private let path = SalesProofReport.exportPath
        private var output: [UInt8] = []

        init(_ store: FileStore) { self.store = store }
        func open() { output.removeAll() }
        func after(_ n: Int, _ line: String) {
            output += [UInt8](repeating: 0x0a, count: n) + SJIS.encode(line, size: 132)
        }
        func afterPage(_ line: String) { output += [0x0c] + SJIS.encode(line, size: 132) }
        func close() throws { try store.writeRaw(path, output + [0x0a]) }
    }
}
