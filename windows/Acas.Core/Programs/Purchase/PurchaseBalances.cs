using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed record PurchaseAnalysisTotal(string Code, string Description, bool Group, int CurrentCount, int PreviousCount,
    int YearCount, decimal Current, decimal Previous, decimal Year)
{
    internal const string EmergencyDescription = "Emergency Name";
    public string DisplayDescription => Description == EmergencyDescription ? "緊急作成" : Description;
}

public sealed record AgedPurchaseItem(string Supplier, int Folio, DateTime? Date, int Type, bool Held, int Bucket,
    decimal Balance, decimal Paid, decimal ExpiredDiscount);

public sealed partial class PurchaseLedger
{
    private static readonly Layout AnalysisValue = new Layout().X("system", 1).X("first", 1).X("second", 1)
        .N9("account", 6).X("description", 24).X("print", 3).Comp("count", 5).Comp("priorCount", 5).Comp("yearCount", 5)
        .C3("amount", 8, 2).C3("priorAmount", 8, 2).C3("yearAmount", 8, 2);

    private bool AccumulatePurchaseAnalysis(PurchaseInvoice[] invoices)
    {
        bool legacyAnalysisUnavailable = HasInvalidAnalysisLength;
        var specials = new (string Code, Func<PurchaseInvoice, decimal> Amount)[]
        {
            ("vi", invoice => invoice.Type == 1 ? 0 : (invoice.Tax + invoice.CarriageTax) * (invoice.Type == 3 ? -1 : 1)),
            ("vj", invoice => invoice.Type == 1 ? invoice.Tax + invoice.CarriageTax : 0),
            ("za", invoice => invoice.Carriage * (invoice.Type == 3 ? -1 : 1)),
            ("zb", invoice => invoice.Discount)
        };
        foreach (var invoice in invoices)
            foreach (var line in invoice.Lines)
                if (!AddPurchaseAnalysis(line.Code, 1, invoice.Type == 3 ? -line.Net : line.Net, legacyAnalysisUnavailable)) return false;
        foreach (var (code, amount) in specials)
        {
            var values = invoices.Select(amount).Where(value => value != 0).ToArray();
            if (!AddPurchaseAnalysis(code, values.Length, values.Sum(), legacyAnalysisUnavailable, ensureGroup: true)) return false;
        }
        return true;
    }

    private bool AddPurchaseAnalysis(string code, int count, decimal amount, bool legacyAnalysisUnavailable, bool ensureGroup = false)
    {
        var group = code[..1];
        var detailKey = AnalysisKey(code);
        var groupKey = AnalysisKey(group);
        if (detailKey != groupKey)
        {
            if (!AddValue(detailKey, code)) return false;
            if (!ensureGroup && database.Read(ValuesFile, groupKey) is null && Analysis(group) is null) return true;
        }
        return AddValue(groupKey, group);

        bool AddValue(string key, string analysisCode)
        {
            var bytes = database.Read(ValuesFile, key);
            if (bytes != null && bytes.Length != AnalysisValue.Size) return false;
            var value = bytes is null ? AnalysisValue.New() : AnalysisValue.From(bytes);
            if (bytes is null)
            {
                var analysis = Analysis(analysisCode);
                value.Set("system", "P");
                value.Set("first", analysisCode[..1]);
                value.Set("second", analysisCode.PadRight(2)[1..]);
                if (legacyAnalysisUnavailable)
                    value.B.AsSpan(AnalysisValue.F["account"].Off, 33).Clear();
                else
                {
                    value.SetN("account", analysis?.N("account") ?? 0);
                    value.Set("description", analysis?.S("description") ?? PurchaseAnalysisTotal.EmergencyDescription);
                    value.Set("print", analysis?.S("reference") ?? "");
                }
            }
            if (!AdjustAnalysisValue(value, count, amount)) return false;
            database.Put(ValuesFile, key, value.B);
            return true;
        }
    }

    private bool DeductPaidDiscounts(int count, decimal amount)
    {
        if (amount == 0) return true;
        foreach (var key in new[] { AnalysisKey("zb"), AnalysisKey("z") })
        {
            if (database.Read(ValuesFile, key) is not { } bytes) return true;
            if (bytes.Length != AnalysisValue.Size) return false;
            var value = AnalysisValue.From(bytes);
            if (!AdjustAnalysisValue(value, -count, -amount) || !database.Rewrite(ValuesFile, key, value.B)) return false;
        }
        return true;
    }

    private static bool AdjustAnalysisValue(Rec value, int count, decimal amount)
    {
        decimal period = value.N("amount") + amount, year = value.N("yearAmount") + amount;
        if (Math.Abs(period) > 99999999.99m || Math.Abs(year) > 99999999.99m) return false;
        value.SetN("count", value.N("count") + count);
        value.SetN("yearCount", value.N("yearCount") + count);
        value.SetN("amount", period);
        value.SetN("yearAmount", year);
        return true;
    }

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
