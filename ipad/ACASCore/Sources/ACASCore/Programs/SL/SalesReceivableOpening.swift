public enum SalesReceivableOpening {
    public enum Refusal: Equatable { case missingOpenItems, pendingPayments }

    case enquiry, ageing

    public func refusal(in context: BusinessContext) throws -> Refusal? {
        let system = try SalesLedger(context).systemRecord()
        let missing = system.raw("file-statuses")[18] != 0x31
        if self == .ageing {
            if system["oi-3-flag"] != "N", missing { return .missingOpenItems }
            if system.int("s-flag-p") == 1 { return .pendingPayments }
        }
        return missing ? .missingOpenItems : nil
    }
}
