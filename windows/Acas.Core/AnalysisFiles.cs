using Acas.Core.Engine;

namespace Acas.Core;

internal static class AnalysisFiles
{
    internal const string Analysis = "ledgers/acas/analysis.dat";
    internal const string Values = "ledgers/acas/value.dat";
    internal const string Definition = "レコード定義/売上分析";

    internal static readonly Layout AnalysisLayout = new Layout()
        .X("ledger", 1).X("code", 2).N9("account", 6).X("description", 24).X("print", 3);
    internal static readonly Layout ValueLayout = new Layout().X("code", 3).N9("account", 6)
        .X("description", 24).X("print", 3).Comp("countCurrent", 5).Comp("countLast", 5).Comp("countYear", 5)
        .C3("valueCurrent", 8, 2).C3("valueLast", 8, 2).C3("valueYear", 8, 2);

    internal static void Initialize(Db db, Rec system)
    {
        if (system.I("File-Status-15") == 1) return;
        if (!db.Exists(Values))
        {
            db.Create(Values);
            system.SetN("File-Status-13", 1);
        }
        db.Recreate(Analysis);
        db.Delete(Definition, "1");
        (string Key, string Name, string Print)[] defaults =
        [
            ("Sv ", "VAT Control", ""), ("Pv ", "VAT Control", ""),
            ("Pvi", "VAT Input Invoices/CN's", ""), ("Pvj", "VAT Input Receipts", ""),
            ("Sz ", "Computer Control", ""), ("Pz ", "Computer Control", ""),
            ("Pza", "Purchase Carriage Charge", "P&P"), ("Pzb", "Purchase Late Charges", "LCG"),
            ("Szc", "Sales Carriage Charges", "P&P"), ("Szd", "Sales Late Charges", "LCG"),
            ("Svo", "VAT Output Invoices/CN's", ""), ("Svp", "VAT Output Receipts", ""),
            ("Pa ", "Default Group", ""), ("Pa1", "Default Purchases", ""),
            ("Sa ", "Default Group", ""), ("Sa1", "Default Sales", "")
        ];
        foreach (var (key, name, print) in defaults)
        {
            var analysis = AnalysisLayout.New();
            analysis.Set("ledger", key[..1]);
            analysis.Set("code", key[1..]);
            analysis.Set("description", name);
            analysis.Set("print", print);
            var value = ValueLayout.New();
            analysis.B.CopyTo(value.B, 0);
            db.Write(Values, key, value.B);
            db.Write(Analysis, key, analysis.B);
        }
        system.SetN("File-Status-15", 1);
    }
}
