import Foundation

extension StockService {
    public func importItems(_ text: String) throws -> Int {
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { throw Failure.invalidInput }
        return try store.transaction {
            var abbreviations = Set(records.map { $0.raw("stock-abrev-key") })
            var sequence = 0
            for line in lines {
                let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard fields.count == 13 else { throw Failure.invalidInput }
                let code = try key(fields[0], 13)
                let abbreviation: [UInt8]
                if fields[0].utf8.count <= 7 {
                    abbreviation = try key(fields[0], 7)
                } else {
                    sequence += 1
                    guard sequence <= 9_999_999 else { throw Failure.invalidInput }
                    abbreviation = Array(Cobol.z(sequence, 7).utf8)
                }
                guard abbreviations.insert(abbreviation).inserted else { throw Failure.duplicate }
                var row = Record(StockLayout.layout)
                row.setRaw("stock-key", code)
                row.setRaw("stock-abrev-key", abbreviation)
                row["stock-supplier-p1"] = "A000011"
                row["stock-pa-code"] = "Pa1"
                row["stock-sa-code"] = "Sa1"
                row["stock-services-flag"] = "N"
                row.setRaw("filler-1", Array(repeating: 0, count: 8))
                row.setRaw("filler-2", Array(repeating: 0, count: 15))
                var name = fields[1]
                if let quote = name.first, ["'", "\""].contains(quote), name.count >= 2, name.last == quote {
                    name = String(name.dropFirst().dropLast())
                }
                row.setRaw("stock-desc", try key(name, 32))
                for (index, name) in ["reorder-pnt", "std-reorder", "back-ordered", "on-order", "held", "pre-sales"].enumerated() {
                    let field = fields[index + 2]
                    guard let quantity = Int64(field.isEmpty ? "0" : field), (-999_999...999_999).contains(quantity)
                    else { throw Failure.invalidInput }
                    row.setInt("stock-" + name, quantity)
                }
                for (index, name) in ["retail", "cost", "value"].enumerated() {
                    let field = fields[index + 8]
                    let scale: Decimal = name == "cost" ? 10_000 : 100
                    guard field.allSatisfy({ "0123456789.".contains($0) }),
                          let amount = Decimal(string: field.isEmpty ? "0" : field, locale: Locale(identifier: "en_US_POSIX")),
                          amount * scale < (name == "retail" ? 1_000_000_000 : 100_000_000_000)
                    else { throw Failure.invalidInput }
                    row.setInt("stock-" + name, NSDecimalNumber(decimal: amount * scale).int64Value)
                }
                for (index, name) in ["order-date", "order-due"].enumerated() {
                    let field = fields[index + 11]
                    let date = Maps04.toBinary(field)
                    guard field.isEmpty || date != 0 else { throw Failure.invalidInput }
                    row.setInt("stock-" + name, Int64(date))
                }
                guard store.write(path, key: code, data: row.bytes) else { throw Failure.duplicate }
            }
            return lines.count
        }
    }
}
