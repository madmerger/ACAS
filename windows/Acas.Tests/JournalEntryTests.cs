using Acas.Core;
using Acas.Core.Engine;

namespace Acas.Tests;

public class JournalEntryTests
{
    private static readonly DateTime Date = new(2025, 4, 1);
    private static readonly DefaultAccount Contra = new(33, 3000m, "BK", "N");
    private static readonly JournalHeader Batch = new(1, Contra, 0, true, Date, 1, 1, 100m, 0m, "Batch");
    private static readonly JournalLine Line = new(Date, new(4000, 0), 100m, "Journal");

    [Fact]
    public void 仕訳入力を開いた時の管理レコードがレガシー証跡と一致する()
    {
        using var db = new Db();
        var journal = new JournalEntry(db);
        journal.Open();
        journal.Open();

        var (key, data) = Assert.Single(db.Scan(JournalEntry.BatchFile));
        Assert.Equal("999999", key);
        Assert.Equal(Convert.FromHexString(
            "3939393939393030303039390000000000000000000000000000000000000000" +
            "000f00000000000f00000000000f00000000000f202020202020202020202020" +
            "2020202020202020202020203030202030303030303030302020203030303030"), data);
        Assert.Empty(db.Scan(JournalEntry.PostingFile));
    }

    [Fact]
    public void 仕訳を正しい借方と貸方で固定長レコードへ保存する()
    {
        using var db = OpenCompany();
        var journal = new JournalEntry(db);

        Assert.Equal(JournalError.Cycle, journal.Save(Batch with { Cycle = 3 }, [Line]));
        Assert.Equal(JournalError.Line, journal.Save(Batch, [Line, Line with { Amount = 0 }]));
        Assert.Single(db.Scan(JournalEntry.BatchFile));
        Assert.Empty(db.Scan(JournalEntry.PostingFile));

        Assert.Equal(JournalError.None, journal.Save(Batch, [Line]));
        var batch = Layouts.Batch.From(db.Read(JournalEntry.BatchFile, "100001")!);
        Assert.Equal(1, batch.I("batch-start"));
        Assert.Equal(100m, batch.N("input-gross"));
        Assert.Equal("DR", batch.S("convention"));
        var (key, data) = Assert.Single(db.Scan(JournalEntry.PostingFile));
        Assert.Equal("00000002", key);
        var posting = Layouts.Posting.From(data);
        Assert.Equal(400000, posting.I("post-dr"));
        Assert.Equal(300000, posting.I("post-cr"));
        Assert.Equal("BK", posting.S("post-code"));
        Assert.Equal("01/04/20", posting.S("post-date"));
        Assert.Equal(100m, posting.N("post-amount"));
        var system = new SystemSettings(db).Read()!;
        Assert.Equal(2, system.I("Next-Batch"));
        Assert.Equal(1, system.I("Postings"));
        Assert.Equal(JournalError.Number, journal.Save(Batch, [Line]));
    }

    [Fact]
    public void バッチ設定の中止と明細の破棄は異なる更新を行う()
    {
        using var db = OpenCompany();
        var journal = new JournalEntry(db);
        var settings = new SystemSettings(db);

        journal.Discard(Batch);
        Assert.Equal(1, settings.Read()!.I("Next-Batch"));
        var defaults = Layouts.Default.From(db.Read(SystemSettings.SystemFile, "00000002")!);
        Assert.Equal(3000m, defaults.N("acs33"));
        Assert.Equal(JournalError.None, journal.CancelSetup(Batch.Number));
        Assert.Equal(2, settings.Read()!.I("Next-Batch"));
        Assert.Single(db.Scan(JournalEntry.BatchFile));
        Assert.Empty(db.Scan(JournalEntry.PostingFile));
    }

    [Fact]
    public void 仕訳の照合は差額を検出し修正後にバッチを閉じる()
    {
        using var db = OpenCompany();
        var journal = new JournalEntry(db);
        var batches = new JournalBatches(db);
        Assert.Equal(JournalError.None, journal.Save(Batch, [Line with { Amount = 90m }]));

        Assert.Contains("照合結果：不一致", batches.Proof(1));
        var before = Assert.Single(batches.Current());
        Assert.Equal(90m, before.ActualGross);
        Assert.Equal(0, before.Status);

        var entry = Assert.Single(batches.Entries(1));
        Assert.Equal(JournalError.None, batches.AmendEntry(1, entry, null, Line.Account, 100m, 0m, 1, "", "Amended"));
        Assert.Equal(JournalError.None, batches.Amend(1, 1, 1, 100m, 0m, "Revised batch"));
        Assert.Equal("Amended", Assert.Single(batches.Entries(1)).Description);
        Assert.Contains("照合結果：一致", batches.Proof(1));

        var after = Assert.Single(batches.Current());
        Assert.Equal(100m, after.ActualGross);
        Assert.Equal(1, after.Status);
        Assert.Equal("転記待ち", JournalBatches.StatusName(after));
        Assert.Contains("Revised batch", batches.PrintTransactions());
        Assert.Contains("転記待ち", batches.PrintStatus());
        Assert.Equal(4, db.Spool().Count);
    }

    [Fact]
    public void 転記では未照合を拒否し照合済み仕訳の借方貸方を一度だけ更新する()
    {
        using var db = OpenCompany();
        var journal = new JournalEntry(db);
        var batches = new JournalBatches(db);
        Assert.Equal(JournalError.None, journal.Save(Batch, [Line]));
        Assert.Equal(PostingStatus.OpenBatches, batches.Post().Status);
        Assert.Empty(db.Spool());
        Assert.NotNull(batches.Proof(1));
        var result = batches.Post();
        Assert.Equal(PostingStatus.Posted, result.Status);
        Assert.Contains("繰越残高", result.Report);
        Assert.Contains("Journal", result.Report);
        Assert.Equal(1, batches.Find(1)!.Cleared);
        Assert.Equal(-100m, Layouts.Ledger.From(db.Read(GeneralLedger.LedgerFile, "30000000")!).N("balance"));
        Assert.Equal(100m, Layouts.Ledger.From(db.Read(GeneralLedger.LedgerFile, "40000000")!).N("balance"));
        Assert.Equal(PostingStatus.NothingToPost, batches.Post().Status);
        Assert.Equal(2, db.Spool().Count);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void 期間締めは現期間だけ更新して圧縮前で止まる(bool archive)
    {
        using var db = OpenCompany();
        var journal = new JournalEntry(db);
        var batches = new JournalBatches(db);
        var settings = new SystemSettings(db);
        Assert.True(settings.SetRunDate(Date));
        var system = settings.Read()!;
        system.Set("Arch", archive ? "Y" : "N");
        db.Rewrite(SystemSettings.SystemFile, "00000001", system.B);

        Assert.Equal(JournalError.None, journal.Save(Batch, [Line]));
        Assert.Equal(JournalError.None, journal.Save(Batch with { Number = 2, Cycle = 2 }, [Line]));
        Assert.Equal(ClosingStatus.OpenBatches, batches.CloseCycle());
        Assert.Equal(2, db.Count(JournalEntry.PostingFile));
        Assert.NotNull(batches.Proof(1));
        Assert.Equal(PostingStatus.Posted, batches.Post().Status);
        var before = settings.Read()!.B;

        Assert.Equal(ClosingStatus.PostingLayoutMismatch, batches.CloseCycle());

        var batch = Layouts.Batch.From(db.Read(JournalEntry.BatchFile, "100001")!);
        Assert.Equal(2, batch.I("cleared-status"));
        Assert.Equal(system.I("Run-Date"), batch.I("stored"));
        Assert.Equal(0, batch.I("batch-start"));
        Assert.Equal("00000003", Assert.Single(db.Scan(JournalEntry.PostingFile)).Key);
        Assert.Equal(0, batches.Find(2)!.Cleared);
        Assert.Equal(before, settings.Read()!.B);
        Assert.Equal(100m, Layouts.Ledger.From(db.Read(GeneralLedger.LedgerFile, "40000000")!).N("balance"));
        Assert.Equal(archive, db.Exists(JournalBatches.ArchiveFile));
        var records = db.Scan(JournalBatches.ArchiveFile);
        Assert.Equal(archive ? 2 : 0, records.Count);
        if (archive)
        {
            Assert.All(records, row => Assert.Equal(78, row.Data.Length));
            Assert.Equal("40000000", System.Text.Encoding.ASCII.GetString(records[0].Data, 20, 8));
            Assert.Equal("30000000", System.Text.Encoding.ASCII.GetString(records[1].Data, 20, 8));
        }
    }

    private static Db OpenCompany()
    {
        var db = new Db();
        var settings = new SystemSettings(db);
        Assert.True(settings.Initialize(new("Example", "ABCD", true, false, false, false, false, false), Date));
        Assert.True(settings.SaveParameters(new("Example", Date, Date.AddMonths(12), 1, 3, 48, 1, false)));
        var ledger = new GeneralLedger(db);
        var system = settings.Read()!;
        Assert.Equal(AccountError.None, ledger.Register(system, new(new(3000, 0), "Contra", 0, 'A', 1)));
        Assert.Equal(AccountError.None, ledger.Register(system, new(new(4000, 0), "Account", 0, 'A', 1)));
        new JournalEntry(db).Open();
        return db;
    }
}
