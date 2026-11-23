import Foundation

extension SalesInvoices {
    public static let printPath = "ledgers/acas/prt-2"
    public static let deliveryPrintPath = "ledgers/acas/prt-3"
    public static let deletionReportPath = SalesProofReport.exportPath
    static let deletedNumbersPath = "ledgers/acas/delinvno.dat"

    public func openBatchPrint() throws {
        try context.store.writeRaw(Self.printPath, [])
    }

    public func openDeliveryPrint() throws -> String? {
        let system = try settings()
        guard system.int("full-invoicing") != 0, system.raw("file-statuses")[14] == 0x31 else { return nil }
        try context.store.writeRaw(Self.deliveryPrintPath, [])
        let day = system.int("run-date")
        guard (1...3_067_671).contains(day) else { return "" }
        return Maps04.format(Maps04.toDate(Int(day)), dateForm: Int(system.int("date-form")))
    }

    public func printDeletedInvoices() throws -> Int {
        let system = try settings()
        let store = context.store
        let saved = store.readRaw(Self.deletedNumbersPath)
        let records = saved ?? []
        let layout = Layout("del-inv-nos-record", [
            ("number", .n9(digits: 8, scale: 0, signed: false)),
            ("date", .native(bytes: 4, signed: true)),
            ("customer", .x(7)),
        ])
        guard records.count.isMultiple(of: layout.size) else { throw Error.invalidInput }
        let dateForm = Int(system.int("date-form"))
        func date(_ day: Int64) -> String {
            guard (1...3_067_671).contains(day) else { return Cobol.x("", 10) }
            return Maps04.format(Maps04.toDate(Int(day)), dateForm: dateForm)
        }
        var output: [UInt8] = []
        func write(_ separators: [UInt8], _ data: [UInt8]) {
            output += separators + [0, 132, 0, 0] + data
        }
        var page: Int64 = 0
        var line = 0
        func headings() {
            page += 1
            let heading = Cobol.x("SL200 (3.01.04)", 29) + Cobol.x("Invoice Deletion Report", 32)
                + Cobol.x(date(system.int("run-date")), 12) + "Page " + Pic.edit("z9", value: page, scale: 0)
            write([page == 1 ? 0x0a : 0x0c], SJIS.encode(heading, size: 132))
            write([0x0a, 0x0a], SJIS.encode("   Invoice No       Date         Cust No", size: 132))
            write([0x0a], SJIS.encode("", size: 132))
            line = 4
        }
        headings()
        if records.isEmpty {
            write(saved == nil ? [0x0a, 0x0a] : [0x0a], SJIS.encode("       None to report", size: 132))
        } else {
            for offset in stride(from: 0, to: records.count, by: layout.size) {
                let record = Record(layout, bytes: Array(records[offset..<offset + layout.size]))
                let row = "   " + Pic.edit("z(9)9", value: record.int("number"), scale: 0)
                    + "     " + date(record.int("date")) + "   "
                write([0x0a], SJIS.encode(row, size: 31) + record.raw("customer") + SJIS.encode("", size: 94))
                line += 1
                if line > 70 { headings() }
            }
        }
        try store.writeRaw(Self.deletionReportPath, output + [0x0a])
        return records.count / layout.size
    }

    public func printInvoices(_ selection: [Number]? = nil) throws -> [Invoice] {
        let system = try settings()
        let numbers = selection ?? invoices().filter { !$0.printed }.map(\.id)
        guard !numbers.isEmpty else { throw Error.empty }
        let reports = try numbers.map { id -> (Number, Record, [Record]) in
            guard let record = header(id) else { throw Error.missingInvoice }
            return (id, record, lineRecords(id, header: record))
        }
        var output = InvoicePrint(system: system, context: context)
        for (number, record, lines) in reports {
            output.append(record, lines: lines)
            var updated = record
            if !["z", "Z"].contains(updated.str("ih-status")) {
                updated["ih-status"] = "I"
                updated["ih-status-l"] = "L"
                guard context.store.rewrite(file.path, key: key(number), data: Array(updated.bytes.prefix(Self.recordSize))) else {
                    throw Error.writeFailed
                }
            }
        }
        try context.store.writeRaw(Self.printPath, output.bytes + [0x0a])
        return reports.compactMap { header($0.0).map(summary) }
    }
}

private struct InvoicePrint {
    let system: Record
    let context: BusinessContext
    var bytes: [UInt8] = []
    private let width = 102
    private var first = true
    private var discountTitle = "  Disc "

    init(system: Record, context: BusinessContext) {
        self.system = system
        self.context = context
    }

    private func pad(_ value: String, _ size: Int) -> String { Cobol.x(value, size) }
    private func spaces(_ size: Int) -> String { pad("", size) }

    private func digits(_ value: Int64, _ size: Int, blank: Bool = true) -> String {
        if value == 0 && blank { return spaces(size) }
        let str = String(abs(value) % Cobol.pow10(size))
        return spaces(size - str.count) + str
    }

    private func money(_ value: Int64, _ size: Int, signed: Bool = false, blank: Bool = true) -> String {
        let width = size + (signed ? 4 : 3)
        if value == 0 && blank { return spaces(width) }
        let magnitude = abs(value) % Cobol.pow10(size + 2)
        let amount = (signed && value < 0 ? "-" : "") + String(magnitude / 100) + "." + Cobol.z(magnitude % 100, 2)
        return spaces(width - amount.count) + amount
    }

    private mutating func emit(_ line: String = "", after count: Int = 1, page: Bool = false) {
        bytes += page ? [0x0c] : [UInt8](repeating: 0x0a, count: count)
        bytes += SJIS.encode(line, size: width)
    }

    mutating func append(_ header: Record, lines: [Record]) {
        let headings = system.str("sl-comp-head-pick") == "Y"
        let h = header.int("ih-type")
        let title = [1: "  Receipt", 2: "  Invoice", 3: "Credit Note"][h] ?? "  Pro-Forma"
        let underline = [3: "===========", 4: "  ========="][h] ?? "  ======="
        let addressDelimiter = system.str("sl-delim").first ?? "\\"
        let key = header.raw("ih-customer")
        let store = context.store
        let sale = SalesProofRecords.salesFile(store).read(key: key) ?? Record(SalesProofRecords.salesLayout)
        let address = addressLines(sale.str("sales-addr1") + sale.str("sales-addr2"), splitOn: addressDelimiter, width: 31)
        var deliveryName = spaces(30)
        var deliveryAddress = [String](repeating: deliveryName, count: 5)
        if sale.int("delivery-tag") != 0, let record = store.read("ledgers/acas/delivery.dat", key: [0x44] + key), record.count >= 134 {
            deliveryName = SJIS.decode(record[8..<38])
            deliveryAddress = addressLines(SJIS.decode(record[38..<134]), splitOn: addressDelimiter, width: 30)
        }
        let day = Int(header.int("ih-date"))
        let date = day > 0 ? Maps04.format(Maps04.toDate(day), dateForm: Int(system.int("date-form"))) : spaces(10)
        let time = context.calendar.dateComponents([.hour, .minute], from: context.now())
        let clock = String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0)
        let count = max(1, lines.count)
        let pages = (max(1, count - 1) / 15 + 1) % 10
        func total(_ terms: String = "", _ days: Int64 = 0, _ description: String = "", _ net: Int64 = 0, _ tax: Int64 = 0) -> String {
            pad(terms, 14) + digits(days, 3) + spaces(24) + pad(description, 24) + money(net, 7, signed: true) + money(tax, 7, signed: true)
        }
        func align(_ string: String) -> String {
            let name = Cobol.rtrim(string)
            return spaces(43 - max(1, name.count) / 2) + name
        }
        func addressLine(_ i: Int) -> String { address[i] + spaces(4) + deliveryAddress[i] }
        func nameLine(_ name: String) -> String { pad(name, 31) + spaces(4) + deliveryName }
        let dateLinePrefix = spaces(25) + "INVOICE" + spaces(25) + "Page "
        let dateLineSuffix = " of \(pages) \(date) \(clock)"
        let invoiceLine = spaces(72) + "Inv: " + digits(header.int("ih-invoice"), 8, blank: false)
        let headingText = pad("Product Code", 14) + pad("Item Description", 30) + "   Qty      Cost"
        let reportOrder = pad("Order:", 7) + pad(header.str("ih-order"), 11)
        let reportRef = pad(" Ref :", 7) + pad(header.str("ih-ref"), 11)
        let reportAccount = pad(" A/C :", 7) + header.str("ih-customer")
        var page = 1
        let company = ["usera", "address-1", "address-2", "address-3", "address-4", "post-code", "country"]
            .map { align(system.str($0)) }
        let description = spaces(37) + (h == 4 ? "This is not a VAT Invoice" : "")
        let addresses = [nameLine(sale.str("sales-name")), addressLine(0),
                         addressLine(1) + spaces(5) + reportOrder, addressLine(2) + spaces(5) + reportRef,
                         addressLine(3) + spaces(5) + reportAccount, addressLine(4)]
        func writeHeading(_ report: inout Self) {
            if headings {
                report.emit(company[0], page: !report.first)
                for line in company.dropFirst() { report.emit(line) }
                report.emit(title)
            } else {
                if !report.first { report.emit(page: true) }
                report.emit(title, after: 4)
            }
            report.emit(underline)
            report.emit(description, after: 2)
            report.emit(dateLinePrefix + String(page % 10) + dateLineSuffix)
            report.emit(invoiceLine, after: 2)
            for line in addresses { report.emit(line) }
            report.emit(after: 2)
            report.emit(headingText + Cobol.x(report.discountTitle, 7) + "      Net       Vat")
            report.first = false
        }
        writeHeading(&self)
        var workNet: Int64 = 0, workTax: Int64 = 0
        for (index, line) in lines.enumerated() {
            if index > 0 && index % 25 == 0 {
                emit(total("Credit Terms:", abs(header.int("ih-days")), "", workNet, workTax), after: 2)
                emit(after: 13)
                page += 1
                writeHeading(&self)
            }
            let net = line.int("il-net"), tax = line.int("il-vat")
            let comment = line.str("il-product").hasPrefix("/")
            let detailed = system.int("invoicer") == 2
            let discount = line.int("il-discount")
            let showDiscount = detailed && discount != 0 && !comment
            discountTitle = showDiscount ? "  Disc " : ""
            let product = detailed && !comment ? pad(line.str("il-product"), 14) : spaces(14)
            let name = detailed ? pad(line.str("il-description"), 30) : spaces(30)
            let quantity = detailed && !comment ? digits(line.int("il-qty"), 6) : spaces(6)
            let unit = detailed && !comment ? money(line.int("il-unit"), 7) : spaces(10)
            let rebate = showDiscount ? money(discount, 3) + "%" : spaces(7)
            emit(product + name + quantity + unit + rebate + money(net, 7) + money(tax, 7))
            workNet = abs(workNet + net) % 100_000_000
            workTax = abs(workTax + tax) % 100_000_000
        }
        emit(total("Credit Terms:", abs(header.int("ih-days")), "", workNet, workTax),
             after: abs(pages * 25 - count + 2) % 100)
        let extra = header.int("ih-extra"), extraTax = header.int("ih-e-vat")
        let carriage = header.int("ih-carriage"), carriageTax = header.int("ih-c-vat")
        let deduct = header.int("ih-deduct-amt"), deductTax = header.int("ih-deduct-vat")
        emit(deduct == 0 && deductTax == 0 ? "" : total("", 0, "Late Payment Surcharge", deduct, deductTax))
        emit(system.str("extra-print") == "N" || (extra == 0 && extraTax == 0) ? "" :
             total("", 0, system.str("extra-desc"), extra, extraTax))
        emit(total("", 0, "", carriage, carriageTax), after: 2)
        emit(spaces(14) + pad(deduct == 0 ? "" : "Prompt pay time:", 16) + digits(deduct == 0 ? 0 : header.int("ih-deduct-days"), 3))
        let net = header.int("ih-net") + extra + carriage + deduct
        let tax = header.int("ih-vat") + extraTax + carriageTax + deductTax
        emit(spaces(13) + money(deduct + deductTax, 4) + spaces(45) + money(net, 8) + money(tax, 8))
        emit(spaces(65) + "Total Due: " + money(net + tax, 8, blank: false), after: 2)
        emit(after: 5)
    }

    private func addressLines(_ value: String, splitOn delimiter: Character, width: Int) -> [String] {
        let segments = value.split(separator: delimiter, omittingEmptySubsequences: false)
        return (0..<5).map { index in pad(index < segments.count ? String(segments[index]) : "", width) }
    }
}
