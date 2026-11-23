using Acas.Core.Engine;
using Acas.Core.Programs.Purchase;

namespace Acas.Tests.Purchase;

public sealed class PurchaseLedgerTests
{
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
