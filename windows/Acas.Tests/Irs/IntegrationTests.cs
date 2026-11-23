using System.Text;
using Acas.Core.Engine;
using Acas.Core.Programs.Integration;
using Acas.Core.Programs.Irs;

namespace Acas.Tests.Irs;

public class IntegrationTests
{
    [Fact]
    public void 買掛請求を総勘定元帳へ転記する()
    {
        using var db = new Db();
        db.LoadBaseline("pl-invoice");
        var service = new LedgerTransfer(db);

        var report = service.TransferInvoices(TransferLedger.Purchases, new DateTime(2026, 11, 23), TransferDestination.Dedicated);

        Assert.Equal(96, db.Read("ledgers/acas/batch.dat", "200001")!.Length);
        var posting = Layouts.Posting.From(db.Read("ledgers/acas/posting.dat", "00000001")!);
        Assert.Equal(100.00m, posting.N("post-amount"));
        Assert.Equal(20.00m, posting.N("vat-amount"));
        Assert.Equal("PL", posting.S("post-code"));
        Assert.Contains("買掛請求の転記", report.Body);
    }

    [Fact]
    public void 連携仕訳の取込は八十四バイトのレコードを使用する()
    {
        using var db = new Db();
        db.LoadBaseline("irs-biz");
        const string file = "ledgers/acas/postings2irs.dat";
        string raw = "0000100001BK23/11/264000130001000010000" + "連携".PadRight(30) + "00DR000000000";
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        byte[] bytes = Encoding.GetEncoding(932).GetBytes(raw);
        Assert.Equal(84, bytes.Length);
        db.Put(file, "0000100001", bytes);

        var books = new IrsBookkeeping(db);
        Assert.Equal(1, books.ImportPostings(clear: true, shared: true));
        var entry = Assert.Single(books.Journal());
        Assert.Equal(100m, entry.Amount);
        Assert.Equal((40001, 30001, "連携"), (entry.Debit, entry.Credit, entry.Legend));
        Assert.Empty(db.Scan(file));
    }

    [Fact]
    public void 分析レコード長の不一致は状態番号三十九になる()
    {
        using var db = new Db();
        db.Put("ledgers/irs/analysis.dat", "1", new byte[66]);
        var error = Assert.Throws<IrsException>(() => new IrsBookkeeping(db).Analysis());
        Assert.Contains("状態番号39", error.Message);
    }

    [Fact]
    public void 売掛期末処理は請求書の百二十九バイト以降を消去する()
    {
        using var db = new Db();
        var system = Layouts.System.New();
        foreach (string field in new[] { "Level-3", "File-Status-15", "File-Status-19", "Cyclea", "Current-Quarter" })
            system.SetN(field, 1);
        db.Put("ledgers/acas/system.dat", "00000001", system.B);
        var invoice = Enumerable.Repeat((byte)' ', 134).ToArray();
        invoice[9] = 1;
        invoice[128] = (byte)'A';
        invoice[129] = (byte)'B';
        db.Put("ledgers/acas/invoice.dat", "00000001/ /00", invoice);

        new LedgerTransfer(db).ClosePeriod(TransferLedger.Sales, new DateTime(2026, 11, 30), "", true, false);

        var saved = db.Read("ledgers/acas/invoice.dat", "00000001/ /00")!;
        Assert.Equal(invoice[..129], saved[..129]);
        Assert.All(saved[129..], value => Assert.Equal((byte)' ', value));
    }
}
