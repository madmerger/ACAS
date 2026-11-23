import Foundation

public struct PurchaseTransfer {
    public enum BookkeepingDestination: String {
        case dedicated = "ledgers/irs/"
        case shared = "ledgers/acas/"
    }

    public struct Invoice {
        public let number: Int
        public let supplier: String
        public let net: Int64
        public let tax: Int64

        public init(number: Int, supplier: String, net: Int64, tax: Int64) {
            self.number = number
            self.supplier = supplier
            self.net = net
            self.tax = tax
        }
    }

    public enum Failure: Error { case unconfigured, invalidInvoice, duplicateBatch, postingAreaInUse, noSequence }

    private let context: BusinessContext
    private let directory = "ledgers/acas/"
    private var store: FileStore { context.store }

    public init(_ context: BusinessContext) { self.context = context }

    public func write(_ invoices: [Invoice], processingDate: Date,
                      bookkeepingDestination: BookkeepingDestination = .dedicated) throws -> [String] {
        guard !invoices.isEmpty else { return [] }
        let settings = RelativeFile(store, path: directory + "system.dat", recordSize: 1024)
        guard let raw = settings.read(1) else { throw Failure.unconfigured }
        var system = Record(SystemLayout.layout, bytes: raw)
        let useIRS = system.str("irs-instead") == "Y"
        let posting = RelativeFile(store, path: directory + "posting.dat", recordSize: TransferRecords.postLayout.size)
        let batchPath = directory + "batch.dat"
        let beginning = system.int("next-batch")
        let count = invoices.count / 99 + 1
        var rowNumber = Int(system.int("postings")) + 1
        guard beginning > 0, beginning + Int64(count) <= Int64(Int16.max),
              rowNumber > 0, useIRS || rowNumber + invoices.count + count - 1 <= Int(Int16.max)
        else { throw Failure.noSequence }
        let dates = context.calendar.dateComponents([.year, .month, .day], from: processingDate)
        guard let year = dates.year, let month = dates.month, let day = dates.day,
              Maps04.validYMD(year, month, day) else { throw Failure.invalidInvoice }
        let date = Cobol.z(day, 2) + "/" + Cobol.z(month, 2) + "/" + Cobol.z(year % 100, 2)
        guard invoices.allSatisfy({
            (0...99_999_999).contains($0.number) && (-9_999_999_999...9_999_999_999).contains($0.net)
                && (-9_999_999_999...9_999_999_999).contains($0.tax)
        }) else { throw Failure.invalidInvoice }
        let keys = (0..<count).map { "2" + Cobol.z(beginning + Int64($0), 5) }
        guard keys.allSatisfy({ store.read(batchPath, key: Array($0.utf8)) == nil }) else { throw Failure.duplicateBatch }
        if !useIRS, invoices.indices.contains(where: { posting.read(rowNumber + $0 + $0 / 99) != nil }) {
            throw Failure.postingAreaInUse
        }

        var handedOff: [UInt8] = []
        var legend = [UInt8](repeating: 0x20, count: 32)
        for (index, key) in keys.enumerated() {
            let chunk = invoices[(index * 99)..<min(invoices.count, (index + 1) * 99)]
            let batchNumber = beginning + Int64(index)
            var batch = Record(TransferRecords.batchLayout)
            batch.setInt("ledger", 2)
            batch.setInt("batch-nos", batchNumber)
            batch.setInt("bcycle", system.int("scycle"))
            batch.setInt("entered", system.int("run-date"))
            batch.setInt("batch-start", Int64(rowNumber))
            batch.setInt("items", Int64(chunk.count))
            batch["description"] = "Purchase Ledger Invoices"
            batch["convention"] = "DR"
            batch["batch-def-code"] = "PL"
            batch["batch-def-vat"] = "I"
            var net: Int64 = 0
            var tax: Int64 = 0
            for (offset, invoice) in chunk.enumerated() {
                net = abs(net + invoice.net) % 100_000_000_000
                tax = abs(tax + invoice.tax) % 100_000_000_000
                let description = Array("\(invoice.number) : ".utf8) + SJIS.encode(invoice.supplier, size: 30)
                let length = min(legend.count, description.count)
                legend.replaceSubrange(0..<length, with: description.prefix(length))
                if useIRS {
                    var record = Record(BookkeepingRecords.ledgerPostLayout)
                    record.setInt("batch", batchNumber)
                    record.setInt("post-number", Int64(offset + 1))
                    record["code"] = "PL"
                    record["date"] = date
                    record.setInt("dr", system.int("bl-purch-ac"))
                    record.setInt("cr", system.int("p-creditors"))
                    BookkeepingRecords.setSigned(&record, "amount", invoice.net)
                    record.setRaw("legend", legend)
                    record.setInt("vat-ac-def", 31)
                    record["vat-side"] = "DR"
                    BookkeepingRecords.setSigned(&record, "vat-amount", invoice.tax)
                    handedOff += record.bytes
                } else {
                    var record = Record(TransferRecords.postLayout)
                    record.setInt("batch", batchNumber)
                    record.setInt("post-number", Int64(offset + 1))
                    record["post-code"] = "PL"
                    record["post-date"] = date
                    record.setInt("post-dr", system.int("bl-purch-ac"))
                    record.setInt("post-cr", system.int("p-creditors"))
                    record.setInt("post-amount", invoice.net)
                    record.setRaw("post-legend", legend)
                    record.setInt("vat-ac", system.int("vat-ac"))
                    record["post-vat-side"] = "DR"
                    record.setInt("vat-amount", invoice.tax)
                    posting.write(rowNumber, record.bytes)
                    rowNumber += 1
                }
            }
            for field in ["input-gross", "actual-gross"] { batch.setInt(field, net) }
            for field in ["input-vat", "actual-vat"] { batch.setInt(field, tax) }
            store.write(batchPath, key: batch.raw("batch-key"), data: batch.bytes)
            if !useIRS, index < keys.count - 1 { rowNumber += 1 }
        }
        if useIRS {
            store.appendRaw(bookkeepingDestination.rawValue + "postings2irs.dat", handedOff)
        } else {
            system.setInt("postings", Int64(rowNumber))
        }
        system.setInt("next-batch", beginning + Int64(count))
        settings.write(1, system.bytes)
        return keys
    }
}
