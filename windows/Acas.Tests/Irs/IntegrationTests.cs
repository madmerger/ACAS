using System.Text;
using Acas.Core.Engine;
using Acas.Core.Programs.Integration;
using Acas.Core.Programs.Irs;

namespace Acas.Tests.Irs;

public class IntegrationTests
{
    [Fact]
    public void 付加価値税日計帳は期間内の返品を仕入と売上から差し引く()
    {
        using var db = new Db();
        void Write(int number, string date, string code, string tax, string side)
        {
            string raw = $"{number:D5}BK{date}4000130001000010000{code.PadRight(32)}{tax}{side}000002000";
            db.Put("ledgers/irs/post.dat", $"{number:D5}", Encoding.ASCII.GetBytes(raw));
        }
        Write(1, "01/11/26", "INPUT", "31", "DR");
        Write(2, "30/11/26", "INPUT RETURN", "31", "CR");
        Write(3, "30/11/26", "OUTPUT RETURN", "32", "DR");
        Write(4, "01/12/26", "OUTSIDE", "32", "CR");

        var report = new IrsBookkeeping(db).AuditReport("D", "3", new DateTime(2026, 11, 1), new DateTime(2026, 11, 30));

        Assert.Contains("INPUT RETURN　-100.00　-20.00", report.Body);
        Assert.Contains("OUTPUT RETURN　　　-100.00　-20.00", report.Body);
        Assert.Contains("合計　0.00　0.00　-100.00　-20.00", report.Body);
        Assert.DoesNotContain("OUTSIDE", report.Body);
    }

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
    public void 科目表の補助勘定を復元し書き出し時は数式を無効化する()
    {
        using var db = new Db();
        var books = new IrsBookkeeping(db);
        books.SaveAccount(30001, 0, "預金", "R", amend: false);
        books.SaveAccount(30001, 30002, "=1+1", "R", amend: false);
        byte[] archive = books.ExportAccounts(csv: false);
        Assert.Contains("T3000130002S=1+1", Encoding.ASCII.GetString(archive));
        Assert.DoesNotContain("T3000200000", Encoding.ASCII.GetString(archive));
        Assert.Contains("\"'=1+1\"", Encoding.ASCII.GetString(books.ExportAccounts(csv: true)));

        books.ImportAccounts(archive);

        Assert.Contains(books.Accounts(), account => account.Code == 30001 && account.SubAccount == 30002);
        Assert.Equal(archive, books.ExportAccounts(csv: false));
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
    public void 両元帳を同時に締めても会計期間と四半期は一度しか進まない()
    {
        using var db = new Db();
        const string file = "ledgers/acas/system.dat";
        var system = Layouts.System.New();
        foreach (string field in new[] { "Level-2", "Level-3", "File-Status-15", "File-Status-19", "File-Status-29", "Current-Quarter" })
            system.SetN(field, 1);
        system.SetN("Period", 3);
        system.SetN("Cyclea", 3);
        db.Put(file, "00000001", system.B);
        var date = new DateTime(2026, 11, 30);

        new LedgerTransfer(db).ClosePeriod([TransferLedger.Sales, TransferLedger.Purchases], date, "", true, false);

        var result = Layouts.System.From(db.Read(file, "00000001")!);
        int day = (date - new DateTime(1600, 12, 31)).Days;
        Assert.Equal((4, 2, day, day, "Y", "Y"), (result.I("Cyclea"), result.I("Current-Quarter"),
            result.I("S-End-Cycle-Date"), result.I("BL-End-Cycle-Date"), result.S("Oi-3-Flag"), result.S("Oi-5-Flag")));
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
