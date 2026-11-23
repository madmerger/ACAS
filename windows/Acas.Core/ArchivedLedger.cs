using Acas.Core.Engine;

namespace Acas.Core;

public sealed partial class JournalBatches
{
    public const string SortedArchiveFile = "ledgers/acas/archives/workarc.tmp";

    public bool SortArchive()
    {
        if (!database.Exists(ArchiveFile)) return false;
        database.Atomic(() =>
        {
            var records = database.Scan(ArchiveFile).Select(row => ArchivePosting.From(row.Data))
                .OrderBy(row => row.S("account"), StringComparer.Ordinal)
                .ThenBy(row => row.I("batch")).ThenBy(row => row.I("number"));
            database.Recreate(SortedArchiveFile);
            int number = 0;
            foreach (var row in records)
                database.Write(SortedArchiveFile, Cob.P9(++number, 8), row.B);
        });
        return true;
    }

    public bool ArchivedAccountExists(int account, int division) =>
        database.Read(GeneralLedger.LedgerFile, Cob.P9(account, 6) + Cob.P9(division, 2)) != null;

    public string? PrintArchivedLedger(int account = 0, int division = 0)
    {
        if (_settings.Read() is not { } system || !database.Exists(SortedArchiveFile)) return null;
        if (account != 0 && (!ArchivedAccountExists(account, 0) ||
            division != 0 && !ArchivedAccountExists(account, division))) return null;
        const string title = "保管仕訳元帳";
        var rows = database.Scan(SortedArchiveFile).Select(row => ArchivePosting.From(row.Data));
        if (account != 0)
        {
            string number = Cob.P9(account, 6);
            rows = rows.TakeWhile(row => string.CompareOrdinal(row.S("account")[..6], number) >= 0)
                .Where(row => row.S("account").StartsWith(number, StringComparison.Ordinal));
        }
        if (division != 0) rows = rows.Where(row => row.S("account")[6..] == Cob.P9(division, 2));

        var report = new LedgerReports.PagedReport(title, system, "バッチ　仕訳番号　参照　日付　摘要　相手勘定　借方　貸方");
        foreach (var group in rows.GroupBy(row => row.S("account")))
        {
            string name = database.Read(GeneralLedger.LedgerFile, group.Key) is { } data
                ? Layouts.Ledger.From(data).St("name") : "不明な勘定";
            report.Line($"勘定　{DisplayCode(group.Key)}　{name}");
            decimal debit = 0, credit = 0;
            foreach (var row in group)
            {
                decimal amount = row.N("amount");
                decimal dr = LedgerReports.Debit(amount), cr = LedgerReports.Credit(amount);
                debit += dr;
                credit += cr;
                report.Line($"{row.S("batch")}　{row.S("number")}　{row.St("code")}　{row.S("date")}　{row.St("description")}　{DisplayCode(row.S("contra"))}　{LedgerReports.Money(dr)}　{LedgerReports.Money(cr)}");
            }
            report.Line($"残高　{LedgerReports.Money(debit)}　{LedgerReports.Money(credit)}　{LedgerReports.Money(debit - credit)}");
        }
        string body = report.ToString();
        database.AddSpool(title, body);
        return body;
    }

    private static string DisplayCode(string key) => $"{key[..4]}.{key[4..6]}　{key[6..]}";
}
