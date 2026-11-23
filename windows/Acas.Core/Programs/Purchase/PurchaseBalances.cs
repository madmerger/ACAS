using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed record PurchaseAnalysisTotal(string Code, string Description, bool Group, int CurrentCount, int PreviousCount,
    int YearCount, decimal Current, decimal Previous, decimal Year);

public sealed record AgedPurchaseItem(string Supplier, int Folio, DateTime? Date, int Type, bool Held, int Bucket,
    decimal Balance, decimal Paid, decimal ExpiredDiscount);

public sealed partial class PurchaseLedger
{
    private static readonly Layout AnalysisValue = new Layout().X("system", 1).X("first", 1).X("second", 1)
        .N9("account", 6).X("description", 24).X("print", 3).Comp("count", 5).Comp("priorCount", 5).Comp("yearCount", 5)
        .C3("amount", 8, 2).C3("priorAmount", 8, 2).C3("yearAmount", 8, 2);

    public IReadOnlyList<PurchaseAnalysisTotal>? PurchaseAnalysisTotals()
    {
        var rows = database.Scan(ValuesFile);
        if (rows.Any(row => row.Data.Length != AnalysisValue.Size)) return null;
        return rows.Select(row => AnalysisValue.From(row.Data)).Where(row => row.S("system") == "P" &&
                (row.S("second") == " " || row.N("amount") != 0 || row.N("yearAmount") != 0))
            .Select(row => new PurchaseAnalysisTotal((row.S("first") + row.S("second")).TrimEnd(), row.St("description"),
                row.S("second") == " " && row.I("account") == 0, row.I("count"), row.I("priorCount"), row.I("yearCount"),
                row.N("amount"), row.N("priorAmount"), row.N("yearAmount"))).ToArray();
    }

    public bool FinishPurchaseAnalysis()
    {
        var system = System();
        if (system.I("P-Flag-A") == 0) return true;
        system.SetN("P-Flag-A", 0);
        return SaveSystem(system);
    }

    public IReadOnlyList<AgedPurchaseItem>? AgedPurchaseItems(DateTime reportDate)
    {
        int date = EncodeDate(reportDate);
        return PaymentItems()?.Select(row => row.Record).Where(item => item.I("type") is 2 or 3 or 5 or 6 &&
                (item.I("closed") == 0 || item.S("applied") != "z"))
            .Select(item =>
            {
                int type = item.I("type"), age = date - item.I("date");
                decimal outstanding = type == 2 ? OpenItemGross(item) - item.N("paid") :
                    type == 3 ? OpenItemGross(item) + item.N("paid") : 0;
                int bucket = type == 2 && outstanding > 0 ? Math.Clamp(age / 30, 0, 3) : 0;
                return new AgedPurchaseItem(item.St("supplier"), item.I("folio"), DecodeDate(item.I("date")), type,
                    item.S("hold") == "H", bucket, outstanding, type is 5 or 6 ? item.N("paid") : 0,
                    type == 2 && age > item.I("discountDays") ? item.N("discountAmount") : 0);
            }).ToArray();
    }
}
