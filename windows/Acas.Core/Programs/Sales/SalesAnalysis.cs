using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed record AnalysisCode(string Ledger, string Code, string Account, string Description, string PrintCode)
{
    internal string DisplayDescription => SalesLedger.AnalysisDescription(Ledger + Code, Description);
}

public sealed partial class SalesLedger
{
    private static readonly Layout AnalysisLayout = new Layout()
        .X("ledger", 1).X("code", 2).N9("account", 6).X("description", 24).X("print", 3);
    private const string AnalysisDefinition = "レコード定義/売上分析";
    private const string EmergencyAnalysisDescription = "Emergency Name";

    internal static string AnalysisDescription(string code, string description) =>
        (code.TrimEnd(), description) switch
        {
            (_, EmergencyAnalysisDescription) => "緊急用",
            ("Sv" or "Pv", "VAT Control") => "付加価値税管理",
            ("Pvi", "VAT Input Invoices/CN's") => "仕入付加価値税（請求書・貸方伝票）",
            ("Pvj", "VAT Input Receipts") => "仕入付加価値税（領収書）",
            ("Sz" or "Pz", "Computer Control") => "システム管理",
            ("Pza", "Purchase Carriage Charges") => "仕入送料",
            ("Pzb", "Purchase Late Charges") => "仕入延滞料",
            ("Szc", "Sales Carriage Charges") => "売上送料",
            ("Szd", "Sales Late Charges") => "売上延滞料",
            ("Svo", "VAT Output Invoices/CN's") => "売上付加価値税（請求書・貸方伝票）",
            ("Svp", "VAT Output Receipts") => "売上付加価値税（領収書）",
            ("Pa" or "Sa", "Default Group") => "既定グループ",
            ("Pa1", "Default Purchases") => "既定の仕入",
            ("Sa1", "Default Sales") => "既定の売上",
            _ => description
        };

    public void ImportAnalysisRecordLength(int bytes)
    {
        if (bytes <= 0) throw new ArgumentOutOfRangeException(nameof(bytes));
        db.Put(AnalysisDefinition, "1", BitConverter.GetBytes(bytes));
    }

    private void CheckAnalysisLength(IReadOnlyList<(string Key, byte[] Data)> rows)
    {
        if ((db.Read(AnalysisDefinition, "1") is { Length: 4 } definition &&
            BitConverter.ToInt32(definition) != AnalysisLayout.Size) || rows.Any(row => row.Data.Length != AnalysisLayout.Size))
            throw new SalesRuleException("売上分析ファイルのレコード長が一致しません。（状態39）");
    }

    public IReadOnlyList<AnalysisCode> AnalysisCodes(bool all = false)
    {
        var rows = db.Scan(AnalysisFile);
        CheckAnalysisLength(rows);
        return rows.Select(row => AnalysisLayout.From(row.Data)).Where(row => all || row.St("ledger") == "S")
            .Select(row => new AnalysisCode(row.St("ledger"), row.St("code"), row.S("account"),
                GetText(row, "description"), GetText(row, "print"))).ToArray();
    }

    public void SaveAnalysis(string code, string account, string description, string print, bool replace)
    {
        code = code.TrimEnd();
        if (code.Length is < 1 or > 2 || code.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-') ||
            account.Length != 6 || account.Any(c => !char.IsAsciiDigit(c)))
            throw new SalesRuleException("分析コードと6桁の勘定番号を確認してください。");
        CheckAnalysisLength(db.Scan(AnalysisFile));
        string key = "S" + code.PadRight(2);
        var row = AnalysisLayout.New();
        row.Set("ledger", "S");
        row.Set("code", code);
        row.Set("account", account);
        SetText(row, "description", description, "分析名");
        SetText(row, "print", print, "印刷分類");
        bool saved = replace ? db.Rewrite(AnalysisFile, key, row.B) : db.Write(AnalysisFile, key, row.B);
        if (!saved) throw new SalesRuleException(replace ? "分析コードが見つかりません。" : "分析コードは登録済みです。");
    }

    public void DeleteAnalysis(string code)
    {
        if (code.Length is < 1 or > 2) throw new SalesRuleException("分析コードを確認してください。");
        CheckAnalysisLength(db.Scan(AnalysisFile));
        if (!db.Delete(AnalysisFile, "S" + code.PadRight(2)))
            throw new SalesRuleException("分析コードが見つかりません。");
    }

    public string EmptyAnalysisReport()
    {
        var system = SystemRecord();
        return "売上分析コード帳票\n" + GetText(system, "Usera") + "\n" +
            ShowDate(system.I("Run-Date")) + "\nコード　勘定番号　分析名　印刷分類　種類\n";
    }

    public string AnalysisReport(bool all)
    {
        var report = new StringBuilder(EmptyAnalysisReport());
        foreach (var code in AnalysisCodes(all))
            report.AppendLine($"{code.Code}　{code.Account}　{code.DisplayDescription}　{code.PrintCode}　{(code.Code.Length == 1 ? "グループ" : "明細")}");
        return report.ToString();
    }

    public string? SalesAnalysisReport() => db.Atomic(() =>
    {
        var system = SystemRecord();
        if (system.I("S-Flag-A") != 0)
        {
            system.SetN("S-Flag-A", 0);
            SaveSystem(system);
        }
        if (!db.Exists(ValueFile)) return null;
        var report = new StringBuilder("売上分析帳票\n").AppendLine(GetText(system, "Usera"))
            .AppendLine(ShowDate(system.I("Run-Date")))
            .AppendLine("コード　分析名　区分　当期件数　前期件数　年度累計件数　件数比　当期金額　前期金額　年度累計金額　金額比");
        foreach (var (key, data) in db.Scan(ValueFile, "S").TakeWhile(row => row.Key.StartsWith('S')))
        {
            var value = ReadPostingValue(data);
            string code = value.S("code");
            bool subtotal = code[2] == ' ';
            if (!subtotal && value.N("valueCurrent") == 0 && value.N("valueYear") == 0) continue;
            string kind = subtotal && value.I("account") == 0 ? "グループ" : "明細";
            report.AppendLine($"{code[1..].TrimEnd()}　{AnalysisDescription(code, GetText(value, "description"))}　{kind}　" +
                $"{value.I("countCurrent")}　{value.I("countLast")}　{value.I("countYear")}　" +
                $"{Ratio(value.N("countCurrent"), value.N("countLast"))}　" +
                $"{Amount(value.N("valueCurrent"))}　{Amount(value.N("valueLast"))}　{Amount(value.N("valueYear"))}　" +
                $"{Ratio(value.N("valueCurrent"), value.N("valueLast"))}");
        }
        string body = report.ToString();
        db.AddSpool("prt-1", body);
        return body;

        static string Ratio(decimal current, decimal previous) =>
            Amount(previous == 0 ? 0 : decimal.Truncate(current / previous * 10_000) / 100) + "％";
    });
}
