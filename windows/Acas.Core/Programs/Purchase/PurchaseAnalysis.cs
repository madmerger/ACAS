using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed partial class PurchaseLedger
{
    public const string AnalysisFile = "ledgers/acas/analysis.dat";
    private const string ValuesFile = "ledgers/acas/value.dat";
    private const string PaymentFile = "ledgers/acas/pay.dat";
    private static readonly Layout AnalysisLayout = new Layout().X("system", 1).X("code", 2).N9("account", 6)
        .X("description", 24).X("reference", 3);

    public bool HasInvalidAnalysisLength => database.Scan(AnalysisFile).Any(row => row.Data.Length != AnalysisLayout.Size);
    public bool AnalysisValuesAvailable => database.Exists(ValuesFile);
    public bool PaymentDataAvailable => database.Count(PaymentFile) != 0;
    public bool PaymentPending => System().I("P-Flag-P") != 0;

    private static string AnalysisKey(string code) => "P" + code.PadRight(2);
    public Rec? Analysis(string code) => database.Read(AnalysisFile, AnalysisKey(code)) is { } data && data.Length == AnalysisLayout.Size
        ? AnalysisLayout.From(data) : null;
    public IEnumerable<Rec> AnalysisRecords(bool all) => database.Scan(AnalysisFile)
        .Where(row => row.Data.Length == AnalysisLayout.Size && (all || row.Key.StartsWith('P')))
        .Select(row => AnalysisLayout.From(row.Data));

    public Rec NewAnalysis(string code)
    {
        var record = AnalysisLayout.New();
        record.Set("system", "P");
        record.Set("code", code);
        return record;
    }

    public bool SaveAnalysis(Rec record, bool create)
    {
        string key = AnalysisKey(record.S("code"));
        return !HasInvalidAnalysisLength && (create ? database.Write(AnalysisFile, key, record.B) : database.Rewrite(AnalysisFile, key, record.B));
    }

    public bool DeleteAnalysis(Rec record) => !HasInvalidAnalysisLength && database.Delete(AnalysisFile, AnalysisKey(record.S("code")));
}
