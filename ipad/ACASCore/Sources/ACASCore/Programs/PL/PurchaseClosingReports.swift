import Foundation

extension PurchaseLedger {
    public func purchaseDayBook() throws -> Data? {
        let settings = system
        guard store.kind(invoicePath) == "indexed", store.kind(suppliersPath) == "indexed" else { return nil }
        let printer = PurchasePrinter(self)
        let date = reportDate(try legacyDate(processingDate))
        var page: Int64 = 0
        var line: Int64 = 0
        func headings(totals: Bool = false) {
            page += 1
            let title = Cobol.x("PL140 (3.01.07)", 54) + Cobol.x("Purchase Ledger Day Book", 70)
                + "Page " + Pic.edit("zz9", value: page, scale: 0)
            let company = Cobol.x(settings.str("usera"), 122) + date
            if page == 1 {
                printer.writeBefore(title, before: 1)
                printer.writeBefore(company, before: 1)
            } else {
                printer.writePage(title)
                printer.write(company, after: 1)
                printer.write("", after: 1)
            }
            line = 2
            if !totals {
                printer.write(Cobol.x(" Number  ---Date--- <------------Supplier------------>", 74)
                              + "<---Net-->  <---Vat-->  <--Gross->       Prompt Pay", after: 2)
                printer.write("", after: 1)
                line += 3
            }
        }
        headings()
        var totals = Array(repeating: Array(repeating: Int64(0), count: 6), count: 4)
        var name = ""
        for header in headers() {
            let type = Int(header.int("ih-type"))
            guard (1...3).contains(type), ["z", "Z"].contains(header.str("ih-status")),
                  !["b", "B"].contains(header.str("ih-day-book-flag")) else { continue }
            if line > settings.int("page-lines") { headings() }
            let code = header.str("ih-supplier")
            if let supplier = supplierRecord(code) { name = supplier.str("purch-name") }
            let sign: Int64 = type == 3 ? -1 : 1
            let goods = sign * header.int("ih-net")
            let carriage = sign * header.int("ih-carriage")
            let tax = sign * (header.int("ih-vat") + header.int("ih-c-vat"))
            let net = goods + carriage
            let discount = header.int("ih-deduct-amt")
            let values = [goods, carriage, net, tax, net + tax, discount]
            for i in values.indices {
                totals[type - 1][i] = Cobol.truncate(totals[type - 1][i] + values[i], digits: 10)
                totals[3][i] = Cobol.truncate(totals[3][i] + values[i], digits: 10)
            }
            let folio = Pic.edit("z(7)9b", value: header.int("ih-invoice"), scale: 0)
            let when = reportDate(header.int("ih-date")) + " "
            let kind = ["Receipt", "Invoice", "Cr. Note"][type - 1]
            let amounts = values[2...4].map { PurchaseRecords.cr("z(6)9.99cr", $0, int: 7) }.joined()
            let prompt = discount == 0 ? Cobol.x("", 12) : PurchaseRecords.cr("z(6)9.99cr", discount, int: 7)
            printer.write(folio + when + Cobol.x(code, 8) + Cobol.x(name, 28) + Cobol.x(kind, 17)
                          + amounts + Cobol.x("", 5) + prompt, after: 1)
            line += 1
        }
        headings(totals: true)
        printer.write(Cobol.x("", 23) + "Goods     Carriage          Net          Vat        Gross   Prompt Pay", after: 2)
        printer.write("", after: 1)
        for (label, values) in zip(["Receipts", "Invoices", "Credit Notes", "      Total"], totals) {
            printer.write(Cobol.x(label, 17) + values.map { PurchaseRecords.cr("z(7)9.99cr", $0, int: 8) }.joined(), after: 1)
        }
        try printer.close()
        return store.readRaw(Self.reportPath).map { Data($0) }
    }

    public func purchaseAnalysisReport() throws -> Data? {
        try store.withTransaction {
            var settings = system
            let path = base + "value.dat"
            var report: Data?
            if store.kind(path) == "indexed" {
                let printer = PurchasePrinter(self)
                let date = reportDate(try legacyDate(processingDate))
                var page: Int64 = 0
                var line: Int64 = 0
                var ratio: Int64 = 0
                func headings() {
                    guard page == 0 || line >= settings.int("page-lines") - 8 else { return }
                    page += 1
                    line = 0
                    let title = Cobol.x("PL130 (3.01.04)", 49) + Cobol.x("              Purchase  Analysis", 75)
                        + " Page " + Pic.edit("z9", value: page, scale: 0)
                    let company = Cobol.x(settings.str("usera"), 122) + date
                    if page == 1 {
                        printer.writeBefore(title, before: 1)
                        printer.writeBefore(company, before: 1)
                    } else {
                        printer.writePage(title)
                        printer.write(company, after: 1)
                        printer.write("", after: 1)
                    }
                    printer.write("Analysis  Type    <-----Description------>   <-------Transactions------->   <----------------Amount----------------->  % Period Mvmt", after: 1)
                    printer.write(Cobol.x("  Code", 45) + "Current   Previous   Y. to D      Current      Previous     Year to Date  Trans. Amount", after: 1)
                    printer.write("", after: 1)
                }
                func movement(_ current: Int64, _ last: Int64, picture: String) -> String {
                    if last != 0 { ratio = Cobol.truncate(current * 10_000 / last, digits: 8, signed: false) }
                    return ratio == 0 ? Cobol.x("", picture == "z(4)9.99" ? 8 : 7)
                        : Pic.edit(picture, value: ratio, scale: 2)
                }
                headings()
                for entry in store.all(path) where entry.data.first == 0x50 && entry.data.count == PurchaseRecords.valueLayout.size {
                    let value = Record(PurchaseRecords.valueLayout, bytes: entry.data)
                    let secondIsSpace = entry.data[2] == 0x20
                    guard secondIsSpace || value.int("this-net") != 0 || value.int("year-net") != 0 else { continue }
                    let isGroup = secondIsSpace && value.int("account") == 0
                    if isGroup {
                        headings()
                        printer.write("", after: 1)
                        line += 1
                    }
                    let code = Cobol.x(String(value.str("code").dropFirst()), 6)
                    let kind = Cobol.x(isGroup ? "Group" : " Detail", 9)
                    let counts = ["this-count", "last-count", "year-count"].map { field in
                        let count = value.int(field)
                        return count == 0 ? Cobol.x("", 5) : Pic.edit("zzzz9", value: count, scale: 0)
                    }
                    let nets = zip(["this-net", "last-net", "year-net"], [8, 9, 9]).map { field, digits in
                        let net = value.int(field)
                        return net == 0 ? Cobol.x("", digits + 5) : PurchaseRecords.cr("z(\(digits - 1))9.99cr", net, int: digits)
                    }
                    let countChange = movement(value.int("this-count"), value.int("last-count"), picture: "z(4)9.99")
                    let netChange = movement(value.int("this-net"), value.int("last-net"), picture: "zzz9.99")
                    let countColumns = counts[0] + Cobol.x("", 5) + counts[1] + Cobol.x("", 6) + counts[2]
                    let netColumns = nets.joined() + countChange + netChange
                    printer.write("   " + code + kind + Cobol.x(value.str("description"), 28)
                                  + countColumns + Cobol.x("", 4) + netColumns, after: 1)
                    line += 1
                    if line > settings.int("page-lines") { headings() }
                }
                try printer.close()
                report = store.readRaw(Self.reportPath).map { Data($0) }
            }
            settings.setInt("p-flag-a", 0)
            try systemFile.write(1, settings.bytes)
            return report
        }
    }
}
