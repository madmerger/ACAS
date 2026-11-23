using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed record AnalysisCode(string Ledger, string Code, string Account, string Description, string PrintCode);

public sealed partial class SalesLedger
{
    private static readonly Layout AnalysisLayout = new Layout()
        .X("ledger", 1).X("code", 2).N9("account", 6).X("description", 24).X("print", 3);
    private const string AnalysisDefinition = "レコード定義/売上分析";

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
        code = code.TrimEnd().ToUpperInvariant();
        if (code.Length is < 1 or > 2 || code.Any(c => !CodeAlphabet.Contains(c)) ||
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
            report.AppendLine($"{code.Code}　{code.Account}　{code.Description}　{code.PrintCode}　{(code.Code.Length == 1 ? "グループ" : "明細")}");
        return report.ToString();
    }
}
