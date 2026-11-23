using Acas.Core;
using Acas.Core.Engine;

namespace Acas.Tests;

public class LedgerReportTests
{
    private static readonly DateTime RunDate = new(2025, 4, 1);

    [Fact]
    public void 勘定科目一覧は見出しと明細を印刷し予約科目を除外する()
    {
        using var db = OpenCompany();
        Account(db, 300000, 0, 1, "Revenue", "A");
        Account(db, 300001, 0, 0, "Sales", "A");
        Account(db, 999900, 0, 0, "Sentinel", "Z");

        var body = new LedgerReports(db).PrintChart();
        Assert.NotNull(body);
        Assert.Contains("3000.00　00　第1階層　Revenue", body);
        Assert.Contains("3000.01　00　明細　Sales", body);
        Assert.DoesNotContain("Sentinel", body);
        Assert.Equal(body, Assert.Single(db.Spool()).Body);
    }

    [Fact]
    public void データがない会社でも仕訳とバッチ状況の帳票を作成する()
    {
        using var db = OpenCompany();
        var batches = new JournalBatches(db);

        Assert.Contains("仕訳がありません", batches.PrintTransactions());
        Assert.Contains("バッチ状況帳票", batches.PrintStatus());
        Assert.Equal(2, db.Spool().Count);
    }

    [Fact]
    public void 試算表は借方と貸方を分け前期と直近の四半期を表示する()
    {
        using var db = OpenCompany();
        Account(db, 300000, 0, 1, "Revenue", "A");
        Account(db, 300001, 0, 0, "Sales", "A", -120m, -70m, -31m, -22m);
        Account(db, 400000, 0, 1, "Assets", "S");
        Account(db, 400001, 0, 0, "Cash", "S", 120m, 70m, 31m, 22m);
        Account(db, 999900, 0, 0, "Sentinel", "Z", 555m);

        var reports = new LedgerReports(db);
        var detailed = reports.TrialBalance(false);
        Assert.NotNull(detailed);
        Assert.Contains("Sales　0.00　120.00　0.00　70.00　-31.00　-22.00", detailed);
        Assert.Contains("合計　120.00　120.00　70.00　70.00", detailed);
        Assert.DoesNotContain("Sentinel", detailed);
        var structured = reports.TrialBalance(true);
        Assert.NotNull(structured);
        Assert.Contains("部門別試算表", structured);
        Assert.Contains("3000.00　第1階層　0.00　120.00", structured);
        Assert.Contains("合計　120.00　120.00", structured);
        Assert.Equal(2, db.Spool().Count);
    }

    [Fact]
    public void 決算書は見出し別の集計レコードを作成して処理日を表示する()
    {
        using var db = OpenCompany();
        Account(db, 300000, 0, 1, "Revenue", "A");
        Account(db, 300001, 0, 0, "Sales", "A", -200m);
        Account(db, 300001, 1, 0, "Sales", "A", -100m);
        Account(db, 400000, 0, 1, "Cost", "E");
        Account(db, 400001, 0, 0, "Expenses", "E", 45m);
        Account(db, 500000, 0, 1, "Other income", "I");
        Account(db, 500001, 0, 0, "Other income item", "I", -5m);
        Account(db, 600000, 0, 1, "Equipment", "O");
        Account(db, 600001, 0, 0, "Equipment item", "O", 260m);

        var body = new LedgerReports(db).FinancialStatements();
        Assert.NotNull(body);
        Assert.Contains("損益計算書　2025年4月1日", body);
        Assert.Contains("Revenue　300.00　0.00", body);
        Assert.Contains("売上総利益　255.00　0.00", body);
        Assert.Contains("当期純利益　260.00　0.00", body);
        Assert.Contains("貸借対照表", body);
        Assert.Equal(new[] { "A30000000", "E40000000", "I50000000", "O60000000" },
            db.Scan(LedgerReports.FinalFile).Select(row => row.Key));
        Assert.Equal(body, Assert.Single(db.Spool()).Body);
    }

    [Fact]
    public void 元帳印刷は保管順を変更せず並べ替え結果から勘定別残高を出力する()
    {
        using var db = OpenCompany();
        Account(db, 300000, 0, 1, "Sales", "A");
        Account(db, 400000, 0, 1, "Cash", "S");
        var archive = new JournalBatches(db);
        Assert.False(archive.SortArchive());
        Assert.Null(archive.PrintArchivedLedger());
        var layout = new Layout().N9("batch", 5).N9("number", 5).X("code", 2).X("date", 8)
            .X("account", 8).N9("amount", 8, 2, true).X("description", 32).X("contra", 8);
        void Add(string key, int batch, string account, decimal amount, string description, string contra)
        {
            var row = layout.New();
            row.SetN("batch", batch);
            row.SetN("number", 1);
            row.Set("account", account);
            row.SetN("amount", amount);
            row.Set("description", description);
            row.Set("contra", contra);
            db.Write(JournalBatches.ArchiveFile, key, row.B);
        }
        Add("00000001", 2, "40000000", 20m, "Second", "30000000");
        Add("00000002", 2, "30000000", -20m, "Second", "40000000");
        Add("00000003", 1, "40000000", 10m, "First", "30000000");
        Add("00000004", 1, "30000000", -10m, "First", "40000000");

        Assert.True(archive.SortArchive());
        var sorted = db.Scan(JournalBatches.SortedArchiveFile).Select(row => layout.From(row.Data)).ToArray();
        Assert.Equal(new[] { "30000000", "30000000", "40000000", "40000000" }, sorted.Select(row => row.S("account")));
        Assert.Equal(new[] { 1, 2, 1, 2 }, sorted.Select(row => row.I("batch")));
        Assert.Equal(2, layout.From(db.Scan(JournalBatches.ArchiveFile)[0].Data).I("batch"));
        var body = archive.PrintArchivedLedger();
        Assert.NotNull(body);
        Assert.Contains("Sales", body);
        Assert.Contains("残高　0.00　30.00　-30.00", body);
        Assert.Contains("残高　30.00　0.00　30.00", body);
        Assert.DoesNotContain("Cash", archive.PrintArchivedLedger(300000)!);
    }

    private static Db OpenCompany()
    {
        var db = new Db();
        var settings = new SystemSettings(db);
        Assert.True(settings.Initialize(new("Example", "ABCD", true, false, false, false, false, false), RunDate));
        var system = settings.Read()!;
        system.SetN("Current-Quarter", 2);
        db.Put(SystemSettings.SystemFile, "00000001", system.B);
        var parameters = settings.ReadGeneralLedgerParameters()!;
        Assert.True(settings.SaveGeneralLedgerParameters(parameters with { Division = "P" }));
        return db;
    }

    private static void Account(Db db, int number, int division, int level, string name, string place,
        decimal balance = 0, decimal last = 0, decimal q1 = 0, decimal q4 = 0)
    {
        var row = Layouts.Ledger.New();
        row.SetN("nos", number);
        row.SetN("pc", division);
        row.SetN("level", level);
        row.Set("name", name);
        row.Set("place", place);
        row.SetN("balance", balance);
        row.SetN("last", last);
        row.SetN("q1", q1);
        row.SetN("q4", q4);
        db.Write(GeneralLedger.LedgerFile, row.S("nos") + row.S("pc"), row.B);
    }
}
