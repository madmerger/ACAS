public struct SalesCommonSettings {
    public struct Field: Identifiable {
        public let id: String
        public let value: String
    }

    public let fields: [Field]

    public init(_ context: BusinessContext) throws {
        let system = try SalesLedger(context).systemRecord()
        let format = Int(system.int("date-form"))
        func text(_ key: String) -> Field {
            Field(id: key, value: Cobol.rtrim(system.str(key)))
        }
        func digits(_ key: String, _ width: Int = 1) -> Field {
            Field(id: key, value: Cobol.z(system.int(key), width))
        }
        func date(_ key: String) -> Field {
            let day = system.int(key)
            let value = (1...3_067_671).contains(day)
                ? Maps04.format(Maps04.toDate(Int(day)), dateForm: format) : ""
            return Field(id: key, value: value)
        }
        func rate(_ index: Int) -> Field {
            let key = "vat-rate-\(index)"
            let cents = system.int(key)
            return Field(id: key, value: Cobol.z(cents / 100, 2) + "." + Cobol.z(cents % 100, 2))
        }
        fields = [
            text("usera"), text("address-1"), text("address-2"), text("address-3"), text("address-4"),
            text("post-code"), text("country"), digits("date-form"), date("start-date"), date("end-date"),
            digits("page-lines", 3), rate(1), rate(2), rate(3), rate(4), rate(5), text("vat-reg-number"),
            text("sl-vat-printed"), Field(id: "password", value: ""), digits("scycle", 2),
            digits("current-quarter", 2), digits("period", 2), digits("file-system-used"), digits("file-duplicates-in-use"),
        ]
    }
}
