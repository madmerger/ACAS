extension PurchaseLedger {
    public struct InvoiceSettings {
        public var nextFolio: Int64
        public var vatAccount: Int64?
    }

    public func invoiceSettings() -> InvoiceSettings {
        let configuration = system
        return InvoiceSettings(
            nextFolio: configuration.int("next-folio"),
            vatAccount: configuration.int("level-1") == 1 ? configuration.int("vat-ac") : nil
        )
    }

    public func saveInvoiceSettings(_ settings: InvoiceSettings) throws {
        guard (1...99_999_999).contains(settings.nextFolio) else { throw Error.invalidInvoiceSettings }
        var configuration = system
        configuration.setInt("next-folio", settings.nextFolio)
        if configuration.int("level-1") == 1 {
            guard let account = settings.vatAccount, (0...999_999).contains(account) else {
                throw Error.invalidInvoiceSettings
            }
            configuration.setInt("vat-ac", account)
        }
        try systemFile.write(1, configuration.bytes)
    }
}
