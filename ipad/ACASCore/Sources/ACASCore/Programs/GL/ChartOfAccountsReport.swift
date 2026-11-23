import Foundation

public struct ChartOfAccountsReport {
    public static let path = "ledgers/acas/prt-1"
    private let context: BusinessContext

    public init(_ context: BusinessContext) { self.context = context }

    public func generate() throws {
        let settings = CompanySetup(context).settings
        let date = Maps04.toDate(Int(settings.number("run-date")))
        let pageLines = Int(settings.number("page-lines"))
        let branchHeading: String
        switch settings.text("p-c") {
        case "P": branchHeading = "Profit Centre"
        case "B": branchHeading = "   Branch"
        default: branchHeading = ""
        }
        var output: [UInt8] = []
        var page: Int64 = 0
        var lines = 0

        func append(_ text: String, advance: [UInt8] = [10]) {
            output += advance + SJIS.encode(text, size: 132)
        }

        func headings() {
            page += 1
            append("GL030 (3.00.04" + Cobol.x("", 28) + "Chart of Accounts" + Cobol.x("", 31) + date,
                   advance: page == 1 ? [10] : [12])
            output += [10] + SJIS.encode(settings.text("usera"), size: 32)
                + SJIS.encode(Cobol.x("", 60) + "Page -" + Pic.edit("z9", value: page, scale: 0), size: 100)
            append(Cobol.x("---Level---   Header       Detail", 40)
                   + Cobol.x(branchHeading, 17) + "--Placement--      ----------Name----------", advance: [10, 10])
            append("")
            lines = 5
        }

        headings()
        for account in ChartOfAccounts(context).accounts.prefix(while: { !$0.code.hasPrefix("9999") }) {
            var level = Array(repeating: Character(" "), count: 10)
            if (1...4).contains(account.level) { level[account.level * 2] = Character(String(account.level)) }
            let code = Int64(account.code) ?? 0
            let number = code == 0 ? Cobol.x("", 7) : Pic.edit("zzz9.99", value: code, scale: 2)
            let header = account.level == 0 ? "" : number
            let detail = account.level == 0 ? number : ""
            let branch = Int64(account.branch) ?? 0
            let branchCode = branch == 0 ? "" : Pic.edit("b(5)z9", value: branch, scale: 0)
            let placement = account.level == 0 ? "" : Self.placement(account.placement)
            let columns = String(level) + Cobol.x("", 3) + Cobol.x(header, 7) + Cobol.x("", 7)
                + Cobol.x(detail, 7) + Cobol.x("", 6) + Cobol.x(branchCode, 7) + Cobol.x("", 10)
                + Cobol.x(placement, 13) + Cobol.x("", 6)
            append(columns + account.name)
            lines += 1
            if lines > pageLines { headings() }
        }
        output.append(10)
        try context.store.writeRaw(Self.path, output)
    }

    private static func placement(_ code: String) -> String {
        switch code {
        case ..<"E": return "Direct Income"
        case ..<"I": return "Direct Costs"
        case ..<"K": return "Sundry Income"
        case ..<"O": return "Indirect Cost"
        case ..<"R": return "Fixed Assets"
        case ..<"U": return "Current Asset"
        case ..<"W": return "Current Liab."
        default: return "Capital A/Cs"
        }
    }
}
