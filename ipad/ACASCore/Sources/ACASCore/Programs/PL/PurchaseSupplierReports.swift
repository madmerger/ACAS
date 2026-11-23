import Foundation

extension PurchaseLedger {
    public enum SupplierReport: CaseIterable, Hashable {
        case alphabetical, turnover, listing, file
    }

    public struct SupplierReportFilter {
        public enum Status: CaseIterable, Hashable { case all, active, dormant }
        public enum Comparison: CaseIterable, Hashable { case any, less, greater, equal }
        public struct Criterion {
            public var comparison: Comparison = .any
            public var value: Int64 = 0
            public init() {}
            func matches(_ actual: Int64) -> Bool {
                switch comparison {
                case .any: true
                case .less: actual < value
                case .greater: actual > value
                case .equal: actual == value
                }
            }
        }

        public var supplier = ""
        public var status: Status = .all
        public var credit = Criterion()
        public var activity = Criterion()
        public var average = Criterion()
        public var overdue = Criterion()
        public var created = Criterion()
        public var creationDate: Date?
        public init() {}
    }

    public func supplierReport(_ kind: SupplierReport, filter: SupplierReportFilter = .init()) throws -> Data? {
        let settings = system
        let runDay = settings.int("run-date")
        var created = filter.created
        if let date = filter.creationDate { created.value = try legacyDate(date) }
        return try store.withTransaction {
            let records = try kind == .alphabetical ? sortReportSuppliers() : reportSupplierRecords()
            let supplier = kind == .listing ? Cobol.x(filter.supplier.uppercased(), 6) : filter.supplier
            let range = SupplierReportRange(supplier, upperSpace: kind == .file ? 0xff : 0x5a)
            let printer = PurchasePrinter(self)
            var page: Int64 = 0, line: Int64 = 0, printed = 0
            let title: String
            let version: String
            switch kind {
            case .alphabetical: (title, version) = ("Supplier Alphabetical Listing", "PL160 (3.01.05)")
            case .turnover: (title, version) = ("Purchase Ledger Turnover Report", "PL170 (3.01.06)")
            case .listing: (title, version) = ("Supplier Listing", "PL010 (3.01.13)")
            case .file: (title, version) = ("Purchase Ledger Dump", "PL190 (3.01.04)")
            }
            func headings() {
                page += 1
                let width = kind == .file || kind == .listing ? 57 : 51
                let heading = Cobol.x(version, width) + Cobol.x(title, 124 - width) + "Page " + Pic.edit("zz9", value: page, scale: 0)
                if page == 1 { printer.writeBefore(heading, before: 1) } else { printer.writePage(heading) }
                if kind == .listing {
                    let second = supplierListingHeading(filter, created: created, range: range, settings: settings)
                    if page == 1 { printer.writeBefore(second, before: 1) }
                    else { printer.write(second, after: 1); printer.write("", after: 1) }
                    printer.write(Cobol.x("Supplier  Status    <----------------Name & Address", 51)
                                  + Cobol.x("---------------->   ----Telephone---- -----Fax-----", 51)
                                  + "    ----Credit----   Discount ", after: 1)
                    printer.write(Cobol.x(" Number   ------", 87) + "                   Limit   Period       %", after: 1)
                    printer.write("", after: 1)
                    line = 6
                } else if kind == .turnover {
                    let second = Cobol.x(settings.str("usera"), 122) + reportDate(runDay)
                    if page == 1 { printer.writeBefore(second, before: 1) }
                    else { printer.write(second, after: 1); printer.write("", after: 1) }
                    printer.write(Cobol.x("", 38) + "Credit Terms  <------------- T u r n o v e r ------------> <--Purchases-->  <--Date of Last-->", after: 1)
                    printer.write(Cobol.x("Acct No          Name", 38) + "Days   Limit  Mvmt Average   Qtr 1   Qtr 2   Qtr 3   Qtr 4 Current    Last  Invoice    Payment", after: 1)
                    printer.write("", after: 1)
                    line = 6
                } else {
                    if page != 1 { printer.write("", after: 1) }
                    let filtered = !range.isEmpty || filter.status != .all ||
                        [filter.credit, filter.activity, filter.average, filter.overdue, created].contains { $0.comparison != .any }
                    let status = filter.status == .active ? " Live" : filter.status == .dormant ? " Dormant" : ""
                    let selection = (filtered ? "Matched" : "All") + status
                        + (range.isEmpty ? "" : " Keys Matching - " + Cobol.rtrim(SJIS.decode(range.lower[...])))
                    printer.write(Cobol.x(settings.str("usera"), 40) + (kind == .file ? "Report On : " : "Report on : ")
                                  + Cobol.x(selection, 70) + reportDate(runDay), after: 1)
                    if kind == .alphabetical {
                        printer.write("Supplier  Status    <----------------Name & Address---------------->   ----Telephone----    ----Fax---    ----Credit----   Discount ", after: 2)
                        printer.write(Cobol.x(" Number   ------", 87) + "                   Limit   Period", after: 1)
                    }
                    if kind == .alphabetical { printer.write("", after: 1) }
                    line = 6
                }
            }
            headings()
            for value in records {
                let key = value.raw("purch-key")
                guard range.contains(key) else { continue }
                if kind == .file && !range.isEmpty &&
                    zip(range.lower.prefix(6), key).contains(where: { $0 != 0x20 && $0 != $1 }) { continue }
                let status = value.int("purch-status")
                let current = value.int("purch-current")
                guard !(filter.status == .active && status == 0), !(filter.status == .dormant && status == 1),
                      filter.credit.matches(value.int("purch-credit")), filter.activity.matches(value.int("purch-activety")),
                      filter.average.matches(value.int("purch-average")),
                      current <= 0 || filter.overdue.matches(runDay - value.int("purch-last-inv")),
                      kind == .file || created.matches(value.int("purch-create-date")) else { continue }
                func number(_ field: String, _ picture: String, scale: Int = 0) -> String {
                    Pic.edit(picture, value: value.int(field), scale: scale)
                }
                func date(_ field: String, short: Bool = false) -> String {
                    let day = value.int(field)
                    let full = day == 0 ? "" : reportDate(day)
                    guard short, full.count == 10 else { return full }
                    return settings.int("date-form") == 3 ? String(full.dropFirst(2)) : String(full.prefix(6) + full.suffix(2))
                }
                let balance = current - value.int("purch-unapplied")
                switch kind {
                case .listing:
                    if line > settings.int("page-lines") - 3 { headings() }
                    line += supplierListingRow(value, settings: settings, printer: printer)
                case .alphabetical:
                    if line > settings.int("page-lines") - 3 { headings() }
                    let ext = Cobol.rtrim(value.str("purch-ext"))
                    let telephone = value.str("purch-phone")
                    let phone = ext.isEmpty ? telephone : (telephone.components(separatedBy: "  ").first ?? "") + "x" + ext
                    let limit = value.int("purch-limit") == 0 ? Cobol.x("", 14) : number("purch-limit", "z(9)9bbbb")
                    let credit = value.int("purch-credit") == 0 ? Cobol.x("", 8) : number("purch-credit", "z9bbbbbb")
                    let discount = value.int("purch-discount") == 0 ? Cobol.x("", 5) : number("purch-discount", "z9.99", scale: 2)
                    printer.write(Cobol.x(value.str("purch-key"), 10) + Cobol.x(status == 1 ? "Active" : "Dormant", 10)
                                  + Cobol.x(value.str("purch-name"), 51) + Cobol.x(phone, 17)
                                  + Cobol.x(value.str("purch-fax"), 14) + limit + credit + discount, after: 1)
                    let delim = settings.str("pl-delim")
                    let address = value.str("purch-address")
                    printer.write(Cobol.x("", 20) + (delim.isEmpty ? address : address.replacingOccurrences(of: delim, with: ",")), after: 1)
                    printer.write("", after: 1)
                    line += 3
                case .turnover:
                    if line > settings.int("page-lines") - 3 { headings() }
                    let credit = number("purch-credit", "zzz9") + number("purch-limit", "z(7)9")
                    let movement = number("purch-activety", "-(5)9") + number("purch-average", "-(7)9")
                    let quarters = (1...4).map { Pic.edit("-(7)9", value: value.int("turnover-q\($0)") / 100, scale: 0) }.joined()
                    let balances = Pic.edit("-(7)9", value: balance / 100, scale: 0)
                        + Pic.edit("-(7)9", value: value.int("purch-last") / 100, scale: 0)
                    let dates = "  " + Cobol.x(date("purch-last-inv", short: true), 10) + "  " + Cobol.x(date("purch-last-pay", short: true), 8)
                    printer.write(Cobol.x(value.str("purch-key"), 8) + value.str("purch-name") + credit + movement + quarters + balances + dates, after: 1)
                    line += 1
                case .file:
                    func row(_ label: String, _ text: String, _ other: String, _ detail: String,
                             _ totalLabel: String = "", _ total: Int64? = nil, after: Int = 1) {
                        let amount = total.map { Pic.edit("z(7)9.99cr", value: $0, scale: 2) } ?? ""
                        printer.write(Cobol.x(label, 14) + Cobol.x(text, 56) + Cobol.x(other, 16)
                                      + Cobol.x(detail, 14) + Cobol.x(totalLabel, 18) + amount, after: after)
                    }
                    row("Purch-Key", value.str("purch-key"), "Purch-Credit", number("purch-credit", "z(7)9.99bbb"),
                        "Purch-Current", balance, after: 2)
                    row("Purch-Name", value.str("purch-name"), "Purch-Discount", number("purch-discount", "z(7)9.99bbb", scale: 2),
                        "Purch-Last", value.int("purch-last"))
                    row("Purch-Addr1", value.str("purch-addr1"), "Purch-Notes", number("purch-notes-tag", "z(6)99"),
                        "Turnover-Q1", value.int("turnover-q1"))
                    row("Purch-Addr2", value.str("purch-addr2"), "Purch-Average", number("purch-average", "z(7)9.99bbb"),
                        "Turnover-Q2", value.int("turnover-q2"))
                    row("Purch-Phone", value.str("purch-phone"), "Purch-Limit", number("purch-limit", "z(7)9.99bbb"),
                        "Turnover-Q3", value.int("turnover-q3"))
                    row("Purch-Fax", value.str("purch-fax"), "Purch-Activety", number("purch-activety", "z(7)9.99bbb"),
                        "Turnover-Q4", value.int("turnover-q4"))
                    row("Purch-Status", status == 1 ? "Live" : "Dead", "Purch-Last-Inv", "   " + date("purch-last-inv"))
                    row("Purch-Email", value.str("purch-email"), "Purch-Last-Pay", "   " + date("purch-last-pay"))
                    if (printed + 1).isMultiple(of: 4) { headings() } else { printer.write("", after: 1) }
                }
                printed += 1
            }
            if kind == .alphabetical { try store.writeRaw(supplierSortPath, []) }
            try printer.close()
            guard (kind != .file && kind != .listing) || printed > 0 else { return nil }
            return Data(store.readRaw(Self.reportPath) ?? [])
        }
    }

    private func supplierListingHeading(_ filter: SupplierReportFilter, created: SupplierReportFilter.Criterion,
                                        range: SupplierReportRange, settings: Record) -> String {
        let criteria = [filter.credit, filter.activity, filter.average, filter.overdue]
        let all = range.isEmpty && filter.status == .all && criteria.allSatisfy { $0.comparison == .any }
        func operand(_ criterion: SupplierReportFilter.Criterion) -> String {
            switch criterion.comparison {
            case .any: ""
            case .less: "< "
            case .greater: "> "
            case .equal: "= "
            }
        }
        let status = filter.status == .active ? "Live" : filter.status == .dormant ? "Dormant" : ""
        var selection = (all ? "All" : "Matched") + " " + status + " "
        let columns = [("z9", " Days Credit"), ("zzzz9", " Invoices"),
                       ("zzzz9", " Av. Value"), ("zzzz9", " Days Overdue")]
        for (criterion, column) in zip(criteria, columns) {
            if criterion.comparison != .any {
                selection += operand(criterion) + Pic.edit(column.0, value: criterion.value, scale: 0) + column.1
            }
            selection += " "
        }
        if created.comparison != .any {
            let entered = created.value == 0 ? "" : reportDate(created.value)
            selection += operand(created) + Cobol.x(entered, 8) + " Entry Date"
        }
        selection += " "
        if !range.isEmpty { selection += " Keys Matching - " + SJIS.decode(range.lower[...]) }
        return Cobol.x(settings.str("usera"), 40) + "Report On : " + Cobol.x(selection, 70) + reportDate(settings.int("run-date"))
    }

    private func supplierListingRow(_ value: Record, settings: Record, printer: PurchasePrinter) -> Int64 {
        func field(_ name: String, _ width: Int) -> String { Cobol.x(value.str(name), width) }
        func number(_ name: String, _ picture: String, _ width: Int, scale: Int = 0) -> String {
            let amount = value.int(name)
            return Cobol.x(amount == 0 ? "" : Pic.edit(picture, value: amount, scale: scale), width)
        }
        let telephone = value.str("purch-phone")
        let ext = value.str("purch-ext")
        let phonePart = telephone.components(separatedBy: "  ").first ?? ""
        let phone = Cobol.rtrim(ext).isEmpty ? telephone :
            (phonePart.isEmpty ? "" : String(phonePart.dropLast()) + "x" + ext)
        printer.write(field("purch-key", 10) + Cobol.x(value.int("purch-status") == 1 ? "Active" : "Dormant", 10)
                      + field("purch-name", 51) + Cobol.x(phone, 18) + field("purch-fax", 13)
                      + number("purch-limit", "z(8)9", 9) + number("purch-credit", "z(7)9", 8)
                      + number("purch-discount", "z(7)9.99", 11, scale: 2), after: 1)
        let delim = settings.str("sl-delim")
        let address = value.str("purch-address")
        let indent = Cobol.x("", 20)
        printer.write(indent + (delim.isEmpty ? address : address.replacingOccurrences(of: delim, with: ",")), after: 1)
        let hasNotes = value.int("purch-notes-tag") > 0
        if hasNotes {
            let key = [UInt8(0x4e)] + value.raw("purch-key")
            let address = store.read(notesPath, key: key).flatMap { $0.count == 134 ? SJIS.decode($0[38..<134]) : nil } ?? "Record Not Found"
            printer.write(indent + "Notes: " + (address.components(separatedBy: "  ").first ?? ""), after: 1)
        }
        printer.write("", after: 1)
        return hasNotes ? 4 : 3
    }

    public func analysisCodeReport(allLedgers: Bool = false) throws -> Data {
        guard !hasIncompatibleAnalysis else { throw Error.analysisFileIncompatible }
        let settings = system
        let printer = PurchasePrinter(self)
        var page: Int64 = 0, line = 0
        func headings() {
            page += 1
            let title = Cobol.x("PL070 (3.01.11)", 33) + Cobol.x("Product Analysis Codes", 39)
                + "Page " + Pic.edit("zz9", value: page, scale: 0)
            if page == 1 { printer.writeBefore(title, before: 1) } else { printer.writePage(title); printer.write("", after: 1) }
            printer.write(Cobol.x(settings.str("usera"), 70) + reportDate(settings.int("run-date")), after: 1)
            printer.write(Cobol.x(allLedgers ? "Lgr" : "", 4)
                          + Cobol.x("Code    GL.No.      <-----Description------>   Print", 59) + "-Type-", after: 2)
            line = 5
        }
        headings()
        var missingAccount = false
        for entry in store.all(analysisPath) where entry.data.count == Self.analysisLayout.size {
            if !allLedgers && entry.key.first != 0x50 { break }
            let value = Record(Self.analysisLayout, bytes: entry.data)
            let header = value.raw("code").last == 0x20
            let account = value.int("account")
            let group = header && account == 0
            if group { printer.write("", after: 1); line += 1 }
            if line > 70 { headings() }
            if !header && account == 0 { missingAccount = true }
            let printedAccount = settings.str("irs-instead") == "Y" ? account : account / 100
            let accountText = printedAccount == 0 ? Cobol.x("", 6) : Pic.edit("9(6)", value: printedAccount, scale: 0)
            printer.write(" " + (allLedgers && group ? value.str("system") : " ") + "   " + Cobol.x(value.str("code"), 7)
                          + accountText + Cobol.x("", 7) + value.str("description") + Cobol.x("", 4)
                          + value.str("print") + Cobol.x("", 7) + Cobol.x(group ? "Group" : "Detail", 6), after: 1)
            line += 1
            if line > 70 { headings() }
        }
        if missingAccount { printer.write("Warning: One or more P.A. codes contain a zero value for General Ledger numbers", after: 2) }
        try printer.close()
        return Data(store.readRaw(Self.reportPath) ?? [])
    }
}
