using System.Buffers.Binary;
using Acas.Core.Engine;
using Acas.Core.Programs.Purchase;

namespace Acas.Tests.Purchase;

public sealed class PurchaseLedgerTests
{
    [Fact]
    public void 支払予定は二百三十七バイトの明細と継続フラグを読み取る()
    {
        using var db = new Db();
        var ledger = new PurchaseLedger(db);
        Assert.Empty(ledger.ScheduledPayments()!);
        var raw = new byte[237];
        "SUPP018"u8.CopyTo(raw);
        raw[7] = 2;
        raw[8] = (byte)'C';
        BinaryPrimitives.WriteInt32LittleEndian(raw.AsSpan(9), 155555);
        BinaryPrimitives.WriteInt32LittleEndian(raw.AsSpan(17), 123456);
        BinaryPrimitives.WriteInt32LittleEndian(raw.AsSpan(30), 10);
        raw[34] = 60;
        Convert.FromHexString("000010050C").CopyTo(raw, 35);
        "REF-10    "u8.CopyTo(raw.AsSpan(43));
        db.Put("ledgers/acas/pay.dat", "SUPP018/02", raw);
        var payment = Assert.Single(ledger.ScheduledPayments()!);
        Assert.Equal(("SUPP018", 2, new DateTime(2026, 11, 23), true, true),
            (payment.Supplier, payment.Number, payment.Date!.Value, payment.BankTransfer, payment.Continues));
        Assert.Equal(new ScheduledPurchaseLine(10, 60, 100.50m, "REF-10"), Assert.Single(payment.Lines));
        db.Put("ledgers/acas/pay.dat", "SUPP018/03", new byte[236]);
        Assert.Null(ledger.ScheduledPayments());
    }

    [Theory]
    [InlineData("test01", "TEST011")]
    [InlineData("SUPP01", "SUPP018")]
    [InlineData("SUPP02", "SUPP026")]
    [InlineData("短い", null)]
    [InlineData("ABC 12", null)]
    public void 仕入先コードは旧式の検査数字を付ける(string input, string? expected) =>
        Assert.Equal(expected, PurchaseLedger.SupplierKey(input));

    [Fact]
    public void 日付は西暦千六百年の末日からの通算日数で格納する()
    {
        var date = new DateTime(2026, 11, 23);
        Assert.Equal(155555, PurchaseLedger.EncodeDate(date));
        Assert.Equal(date, PurchaseLedger.DecodeDate(155555));
        Assert.Null(PurchaseLedger.DecodeDate(0));
    }

    [Fact]
    public void 仕入先の変更では名称以外のバイトを変えない()
    {
        using var db = Fixture("biz");
        var ledger = new PurchaseLedger(db);
        var original = db.Read(PurchaseLedger.SupplierFile, "SUPP018")!;
        var supplier = ledger.GetSupplier("SUPP018")!;
        supplier.Set("name", "EQUIV UPDATED SUPPLIER");
        Assert.True(ledger.SaveSupplier(supplier, false, "", ""));
        var updated = db.Read(PurchaseLedger.SupplierFile, "SUPP018")!;
        Assert.Equal(original[..9], updated[..9]);
        Assert.Equal(original[39..], updated[39..]);
        Assert.Equal("EQUIV UPDATED SUPPLIER", ledger.GetSupplier("SUPP018")!.St("name"));
    }

    [Fact]
    public void 残高がある仕入先は休止も削除もできない()
    {
        using var db = Fixture("biz");
        var ledger = new PurchaseLedger(db);
        var supplier = ledger.GetSupplier("SUPP018")!;
        supplier.SetN("current", 10);
        Assert.True(ledger.SaveSupplier(supplier, false, "", ""));
        Assert.False(ledger.RemoveSupplier("SUPP018", true));
        Assert.False(ledger.RemoveSupplier("SUPP018", false));
        Assert.True(ledger.RemoveSupplier("SUPP026", false));
        Assert.Null(ledger.GetSupplier("SUPP026"));
    }

    [Fact]
    public void 仕入伝票のヘッダと明細は旧レコードと一致する()
    {
        using var db = Fixture("sl-ready");
        var ledger = new PurchaseLedger(db);
        db.Put(PurchaseLedger.AnalysisFile, "Pa1", new byte[66]);
        var invoice = Sample(ledger);
        Assert.True(ledger.SaveInvoice(invoice, true));
        using var expected = Fixture("pl-invoice");
        foreach (string key in new[] { "00000001/00", "00000001/01" })
            Assert.Equal(expected.Read(PurchaseLedger.InvoiceFile, key), db.Read(PurchaseLedger.InvoiceFile, key));
        Assert.Equal(120m, ledger.Invoice(invoice.Folio)!.Total);
    }

    [Fact]
    public void 仕入伝票保存は不存在仕入先の台帳を変更しない()
    {
        using var db = Fixture("sl-ready");
        var ledger = new PurchaseLedger(db);
        var before = db.Snapshot().SelectMany(file => file.Value).ToArray();
        Assert.False(ledger.SaveInvoice(Sample(ledger) with { Supplier = "MISS001" }, true));
        Assert.Equal(before, db.Snapshot().SelectMany(file => file.Value).ToArray());
    }

    [Fact]
    public void 八桁の最大伝票番号は保存できるが次の九桁は保存しない()
    {
        using var db = Fixture("sl-ready");
        var ledger = new PurchaseLedger(db);
        Assert.True(ledger.SaveAnalysis(ledger.NewAnalysis("a1"), true));
        Assert.True(ledger.SaveInvoiceSettings(99999999, null));
        Assert.True(ledger.SaveInvoice(Sample(ledger), true));
        Assert.Equal("99999999", Assert.Single(ledger.Invoices()).Folio);
        Assert.Equal("100000000", ledger.NextFolio);
        Assert.False(ledger.SaveInvoice(Sample(ledger), true));
        Assert.Null(db.Read(PurchaseLedger.InvoiceFile, "100000000/00"));
    }

    [Fact]
    public void 仕入転記は削除された仕入先を旧版と同様に再作成する()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.True(db.Delete(PurchaseLedger.SupplierFile, "SUPP018"));
        Assert.Single(ledger.PostInvoices()!);
        var supplier = ledger.GetSupplier("SUPP018")!;
        Assert.Equal("Supplier Unknown", supplier.St("name"));
        Assert.Equal(120m, supplier.N("current"));
        Assert.True(ledger.Invoice("00000001")!.Posted);
    }

    [Fact]
    public void 仕入転記は明細の当期と年累計を分析帳票に追加する()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        db.Remove(PurchaseLedger.AnalysisFile);
        var group = ledger.NewAnalysis("a");
        group.Set("description", "GROUP");
        Assert.True(ledger.SaveAnalysis(group, true));
        var detail = ledger.NewAnalysis("a1");
        detail.Set("description", "DETAIL");
        Assert.True(ledger.SaveAnalysis(detail, true));
        Assert.Single(ledger.PostInvoices()!);
        var totals = ledger.PurchaseAnalysisTotals()!;
        Assert.Contains(new PurchaseAnalysisTotal("a1", "DETAIL", false, 1, 0, 1, 100m, 0m, 100m), totals);
        Assert.Contains(new PurchaseAnalysisTotal("a", "GROUP", true, 1, 0, 1, 100m, 0m, 100m), totals);
        Assert.Contains(totals, row => row is { Code: "vi", Current: 20m });
    }

    [Fact]
    public void 最後の未転記伝票を削除した後に空の仕入転記で支払入力の制限を解除できる()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.True(ledger.DeleteInvoice("00000001"));
        Assert.True(ledger.InvoicesPending);
        Assert.Empty(ledger.PostInvoices()!);
        Assert.False(ledger.InvoicesPending);
        Assert.Equal(1, ledger.System().I("File-Status-29"));
        Assert.True(db.Exists("ledgers/acas/openitm5.dat"));
    }

    [Fact]
    public void 投稿済みの掛仕入の未決済レコードは旧バイト列と一致する()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.Single(ledger.PostInvoices()!);
        byte[] expected = Convert.FromHexString(
            "5355505030313801000000a35f020000000000000032504c2d52454620202020504c2d4f5244455220202000000000000c000010000c000000000c000000000c000002000c000000000c000000000c000000000c000000000c3000000000000000000000000000002000000000");
        Assert.Equal(expected, db.Read("ledgers/acas/openitm5.dat", "SUPP018/00000001"));
    }

    [Fact]
    public void 仕入転記のフラグは買掛終了までシステムファイルに書き込まない()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        const string key = "00000001";
        var before = db.Read(PurchaseLedger.SystemFile, key);
        Assert.Single(ledger.PostInvoices()!);
        Assert.Equal(before, db.Read(PurchaseLedger.SystemFile, key));
        Assert.False(ledger.InvoicesPending);
        Assert.Equal(1, ledger.System().I("File-Status-29"));
        var next = ledger.System();
        next.Set("Usera", "UPDATED BUSINESS");
        Assert.True(ledger.SaveSystem(next));
        var onDisk = new PurchaseLedger(db).System();
        Assert.Equal("UPDATED BUSINESS", onDisk.St("Usera"));
        Assert.Equal(1, onDisk.I("P-Flag-I"));
        Assert.True(ledger.FlushPostingFlags());
        Assert.Equal(next.B, db.Read(PurchaseLedger.SystemFile, key));
        Assert.Equal(2, new PurchaseLedger(db).System().I("P-Flag-I"));
    }

    [Fact]
    public void 分析ファイルの旧形式を誤って上書きしない()
    {
        using var db = Fixture("biz");
        var ledger = new PurchaseLedger(db);
        db.Put(PurchaseLedger.AnalysisFile, "Pa1", new byte[66]);
        Assert.True(ledger.HasInvalidAnalysisLength);
        Assert.False(ledger.SaveAnalysis(ledger.NewAnalysis("Z"), true));
        Assert.Equal(1, db.Count(PurchaseLedger.AnalysisFile));
    }

    [Fact]
    public void 貸方票は対象伝票の残高と仕入先の残高を減らす()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.Single(ledger.PostInvoices()!);
        db.Put(PurchaseLedger.AnalysisFile, "Pa1", new byte[66]);
        var note = Sample(ledger) with { Type = 3, CreditFolio = 1, Lines = [new("a1", 25m, 1, 5m, "")] };
        Assert.False(ledger.SaveInvoice(note with { Supplier = "SUPP026" }, true));
        Assert.False(ledger.SaveInvoice(note with { CreditFolio = 99 }, true));
        Assert.True(ledger.SaveInvoice(note, true));
        Assert.Equal(1, ledger.Invoice(note.Folio)!.CreditFolio);
        Assert.Single(ledger.PostInvoices()!);
        Assert.Equal(90m, ledger.GetSupplier("SUPP018")!.N("current"));
        const string file = "ledgers/acas/openitm5.dat";
        Assert.Equal("000003000c", Convert.ToHexString(db.Read(file, "SUPP018/00000001")!.AsSpan(84, 5)).ToLowerInvariant());
        var item = db.Read(file, $"SUPP018/{note.Folio}")!;
        Assert.Equal(1, BinaryPrimitives.ReadInt32LittleEndian(item.AsSpan(100, 4)));
        Assert.Equal((byte)'1', item[89]);
    }

    [Fact]
    public void 支払は消込の取消と再入力ができ検証後に残高へ転記される()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.Single(ledger.PostInvoices()!);
        var date = new DateTime(2026, 11, 23);
        const string supplier = "SUPP018";
        const string file = "ledgers/acas/openitm5.dat";
        const string invoice = "SUPP018/00000001";
        var before = db.Read(file, invoice);
        var allocations = new Dictionary<int, decimal> { [1] = 50m };
        Assert.False(ledger.SavePayment(supplier, date, 40m, false, allocations));
        Assert.Equal(before, db.Read(file, invoice));
        Assert.True(ledger.SavePayment(supplier, date, 60m, false, allocations));
        Assert.Equal("000005000C", Convert.ToHexString(db.Read(file, invoice)!.AsSpan(84, 5)));
        Assert.Equal(120m, ledger.GetSupplier(supplier)!.N("current"));
        Assert.Null(ledger.PostPayments());
        var first = Assert.Single(ledger.Payments()!);
        Assert.True(ledger.CancelPayment(supplier, first.Folio, new Dictionary<int, decimal>()));
        Assert.Equal(before, db.Read(file, invoice));
        Assert.True(ledger.SavePayment(supplier, date, 60m, false, allocations));
        var proof = Assert.Single(ledger.ProvePayments()!);
        Assert.Equal(50m, Assert.Single(proof.Lines).Applied);
        Assert.Equal(2, db.Count("ledgers/acas/poisort.wrk"));
        var posted = Assert.Single(ledger.PostPayments()!);
        Assert.Equal((120m, 60m), (posted.OldBalance!.Value, posted.NewBalance!.Value));
        var account = ledger.GetSupplier(supplier)!;
        Assert.Equal(70m, account.N("current"));
        Assert.Equal(10m, account.N("unapplied"));
        Assert.False(ledger.PaymentPending);
        Assert.Empty(ledger.Payments()!);
    }

    [Fact]
    public void アイアールエスの仕入と支払は同じ採番でも別バッチになる()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        var system = ledger.System();
        system.Set("Irs-Instead", "Y");
        system.SetN("Next-Batch", 1);
        system.SetN("BL-Next-Batch", 1);
        Assert.True(ledger.SaveSystem(system));
        Assert.Single(ledger.PostInvoices()!);
        Assert.True(ledger.SavePayment("SUPP018", new DateTime(2026, 11, 23), 50m, false,
            new Dictionary<int, decimal> { [1] = 50m }));
        Assert.Single(ledger.ProvePayments()!);
        Assert.Single(ledger.PostPayments()!);
        Assert.Equal(new[] { "0000100001", "0000200001" },
            db.Scan("ledgers/acas/postings2irs.dat").Select(row => row.Key));
        Assert.NotNull(db.Read("ledgers/acas/batch.dat", "200001"));
        Assert.NotNull(db.Read("ledgers/acas/batch.dat", "200002"));
    }

    [Fact]
    public void アイアールエス仕入転記は固定長仕訳とバッチだけを作る()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        var system = ledger.System();
        system.Set("Irs-Instead", "Y");
        system.SetN("BL-Purch-Ac", 12345);
        system.SetN("P-Creditors", 23456);
        Assert.True(ledger.SaveSystem(system));
        int postings = system.I("Postings");
        int batch = system.I("Next-Batch");
        int prior = db.Count("ledgers/acas/posting.dat");
        Assert.Single(ledger.PostInvoices()!);
        var (key, bytes) = Assert.Single(db.Scan("ledgers/acas/postings2irs.dat"));
        string expected = $"{batch:00000}00001PL23/11/261234523456000010000" +
            "1 : ALPHA SUPPLIER".PadRight(32) + "31DR000002000";
        Assert.Equal(expected[..10], key);
        Assert.Equal(System.Text.Encoding.ASCII.GetBytes(expected), bytes);
        Assert.NotNull(db.Read("ledgers/acas/batch.dat", $"2{batch:00000}"));
        Assert.Equal(batch + 1, ledger.System().I("Next-Batch"));
        Assert.Equal(postings, ledger.System().I("Postings"));
        Assert.Equal(prior, db.Count("ledgers/acas/posting.dat"));
    }

    [Fact]
    public void アイアールエスには専用の固定長支払仕訳を出力する()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.Single(ledger.PostInvoices()!);
        var system = ledger.System();
        system.Set("Irs-Instead", "Y");
        system.SetN("P-Creditors", 12345);
        system.SetN("BL-Pay-Ac", 23456);
        Assert.True(ledger.SaveSystem(system));
        int postings = ledger.System().I("Postings");
        int prior = db.Count("ledgers/acas/posting.dat");
        Assert.True(ledger.SavePayment("SUPP018", new DateTime(2026, 11, 23), 50m, false,
            new Dictionary<int, decimal> { [1] = 50m }));
        Assert.Single(ledger.ProvePayments()!);
        var payment = Assert.Single(ledger.PostPayments()!);
        var (key, bytes) = Assert.Single(db.Scan("ledgers/acas/postings2irs.dat"));
        string expected = $"{payment.Batch + 1:00000}00001PL23/11/261234523456000005000" +
            $"{payment.Folio} : ALPHA SUPPLIER".PadRight(32) + "31DR000000000";
        Assert.Equal(expected[..10], key);
        Assert.Equal(System.Text.Encoding.ASCII.GetBytes(expected), bytes);
        Assert.Equal(postings, ledger.System().I("Postings"));
        Assert.Equal(prior, db.Count("ledgers/acas/posting.dat"));
    }

    [Fact]
    public void 小切手の生成と台帳更新後も送金案内を取得できる()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.Single(ledger.PostInvoices()!);
        Assert.True(ledger.CreatePaymentSchedule(0));
        var payment = Assert.Single(ledger.ScheduledPayments()!);
        Assert.Equal(120m, payment.Gross);
        Assert.True(ledger.AmendPaymentSchedule(payment.Supplier, payment.Number, new Dictionary<int, decimal> { [1] = 100m }));
        Assert.True(ledger.GenerateChequeData(4321, new DateTime(2026, 11, 24)));
        var export = Assert.Single(db.Scan("ledgers/acas/cheque.dat")).Data;
        Assert.Equal(645, export.Length);
        Assert.Equal("     4321,24/11/2026", System.Text.Encoding.ASCII.GetString(export.AsSpan(345, 20)));
        var register = Assert.Single(ledger.ApplyChequeRegister()!);
        Assert.Equal((4321, 100m), (register.Cheque, register.Gross));
        Assert.Empty(ledger.ScheduledPayments()!);
        var remittance = Assert.Single(ledger.Remittances()!);
        Assert.Equal(("4321", 100m), (remittance.Method, remittance.Amount));
        Assert.Equal(1, Assert.Single(remittance.Lines).Folio);
        Assert.Equal("000010000C", Convert.ToHexString(db.Read("ledgers/acas/openitm5.dat", "SUPP018/00000001")!.AsSpan(84, 5)));
    }

    [Fact]
    public void 買掛締めは未決済伝票を残し仕入先残高を翌期に繰り越す()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        Assert.Single(ledger.PostInvoices()!);
        var system = ledger.System();
        system.SetN("File-Status-15", 1);
        system.SetN("Level-2", 1);
        Assert.True(ledger.SaveSystem(system));
        var date = new DateTime(2026, 11, 30);
        Assert.False(ledger.ClosePeriod(date, purchase: true, sales: false, quarter: false, allowUnposted: false));
        Assert.True(ledger.FinishPurchaseAnalysis());
        Assert.True(ledger.ClosePeriod(date, purchase: true, sales: false, quarter: false, allowUnposted: false));
        Assert.Equal(120m, ledger.GetSupplier("SUPP018")!.N("last"));
        Assert.Equal(PurchaseLedger.EncodeDate(date), ledger.System().I("BL-End-Cycle-Date"));
        var invoice = Assert.Single(ledger.AgedPurchaseItems(date)!);
        Assert.Equal(120m, invoice.Balance);
        Assert.Empty(ledger.Invoice("00000001")!.Lines);
    }

    [Fact]
    public void 期間締めは初期設定の暗証文字を拒否し設定済みの暗証文字だけを照合する()
    {
        using var db = Fixture("pl-invoice");
        var ledger = new PurchaseLedger(db);
        var system = ledger.System();
        system.Set("Pass-Word", "CEJE");
        Assert.True(ledger.SaveSystem(system));
        Assert.False(ledger.HasConfiguredCyclePassword);
        Assert.False(ledger.MatchesCyclePassword(""));
        system.Set("Pass-Word", "CCPI");
        Assert.True(ledger.SaveSystem(system));
        Assert.True(ledger.HasConfiguredCyclePassword);
        Assert.True(ledger.MatchesCyclePassword("WQZE"));
        Assert.False(ledger.MatchesCyclePassword("WQZA"));
    }

    [Fact]
    public void 途中で失敗した複数台帳の変更はロールバックする()
    {
        using var db = new Db();
        Assert.False(db.ExecuteAtomically(() =>
        {
            db.Put(PurchaseLedger.SupplierFile, "SUPP018", [42]);
            return false;
        }));
        Assert.False(db.Exists(PurchaseLedger.SupplierFile));
    }

    private static Db Fixture(string name)
    {
        var db = new Db();
        db.LoadBaseline(name);
        return db;
    }

    private static PurchaseInvoice Sample(PurchaseLedger ledger) =>
        new(ledger.NextFolio, "SUPP018", new DateTime(2026, 11, 23), "PL-ORDER", "PL-REF", 2,
            [new("a1", 100m, 1, 20m, "")], 0, 0m, 0, 0m, 0m);
}
