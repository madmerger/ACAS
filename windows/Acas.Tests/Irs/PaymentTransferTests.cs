using System.Text;
using Acas.Core.Engine;
using Acas.Core.Programs.Integration;
using Acas.Core.Programs.Irs;

namespace Acas.Tests.Irs;

public class PaymentTransferTests
{
    private const string Directory = "ledgers/acas/";
    private const string SystemFile = Directory + "system.dat";
    private static readonly DateTime Date = new(2026, 11, 23);
    private static readonly int Day = (Date - new DateTime(1600, 12, 31)).Days;

    [Fact]
    public void 売掛貸方票の延滞加算免除を帳票と集計に反映する()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        const string invoices = Directory + "invoice.dat";
        var (key, invoice) = db.Scan(invoices).First(x => x.Key.EndsWith("/00", StringComparison.Ordinal));
        var credit = (byte[])invoice.Clone();
        invoice[125] = 100;
        credit[7] = (byte)'1';
        credit[31] = (byte)'3';
        db.Put(invoices, key, invoice);
        db.Put(invoices, "00000001/ /00", credit);
        var balanceLayout = new Layout().Fill(30).C3("deductions", 8, 2);
        var before = balanceLayout.From(db.Read(SystemFile, "00000004")!).N("deductions");

        var report = new LedgerTransfer(db).TransferInvoices(TransferLedger.Sales, Date, TransferDestination.Dedicated);

        Assert.Contains("延滞加算免除合計　1.00", report.Body);
        Assert.Equal(before + 1, balanceLayout.From(db.Read(SystemFile, "00000004")!).N("deductions"));
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(true, true)]
    [InlineData(false, false)]
    [InlineData(false, true)]
    public void 照合済み入出金の消込額を総勘定元帳または簡易記帳に転記する(bool sales, bool irs)
    {
        using var db = new Db();
        db.LoadBaseline("biz");
        var system = Prepare(db, irs, sales);
        string party = sales ? "CUST011" : "SUPP018";
        string file = Directory + (sales ? "openitm3.dat" : "openitm5.dat");
        var item = OpenItem(sales, party, 7, 5, 80m, 100m);
        db.Put(file, party + "/00000007", item.B);

        var result = new LedgerTransfer(db).TransferPayments(sales ? TransferLedger.Sales : TransferLedger.Purchases,
            Date.AddDays(1), TransferDestination.Shared);

        var saved = item.L.From(db.Read(file, party + "/00000007")!);
        Assert.Equal(1, saved.I("status"));
        Assert.Equal(80m, saved.N("paid"));
        string batchKey = sales ? "300010" : "200010";
        var batch = Layouts.Batch.From(db.Read(Directory + "batch.dat", batchKey)!);
        Assert.Equal(80m, batch.N("actual-gross"));
        Assert.Equal(1, batch.I("items"));
        system = Layouts.System.From(db.Read(SystemFile, "00000001")!);
        Assert.Equal(0, system.I(sales ? "S-Flag-P" : "P-Flag-P"));
        Assert.Equal(11, system.I(sales ? "Next-Batch" : "BL-Next-Batch"));
        Assert.Contains("80.00", result.Body);
        if (irs)
        {
            var entry = Assert.Single(db.Scan(Directory + "postings2irs.dat"));
            string legend = sales ? "00006/009  :  ALPHA CUSTOMER" : "7 : ALPHA SUPPLIER";
            string expected = "0001000001" + (sales ? "SL" : "PL") + "23/11/26" + (sales ? "3000130002" : "3000330001") +
                "000008000" + legend.PadRight(32) + (sales ? "32CR" : "31DR") + "000000000";
            Assert.Equal(Encoding.ASCII.GetBytes(expected), entry.Data);
            Assert.Empty(db.Scan(Directory + "posting.dat"));
        }
        else
        {
            var entry = Layouts.Posting.From(db.Read(Directory + "posting.dat", "00000001")!);
            Assert.Equal(80m, entry.N("post-amount"));
            Assert.Equal(0m, entry.N("vat-amount"));
            Assert.Equal(sales ? 30001 : 30003, entry.I("post-dr"));
            Assert.Equal(sales ? 30002 : 30001, entry.I("post-cr"));
            Assert.Equal("23/11/26", entry.S("post-date"));
            Assert.Equal(2, system.I("Postings"));
        }
    }

    [Fact]
    public void 請求書の後に売掛入金と買掛支払を総勘定元帳へ連続転記できる()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var system = Prepare(db, false, true);
        system.SetN("P-Flag-P", 2);
        db.Put(SystemFile, "00000001", system.B);
        db.Put(Directory + "openitm3.dat", "CUST011/00000007", OpenItem(true, "CUST011", 7, 5, 80m, 100m).B);
        db.Put(Directory + "openitm5.dat", "SUPP018/00000007", OpenItem(false, "SUPP018", 7, 5, 80m, 100m).B);

        var transfer = new LedgerTransfer(db);
        transfer.TransferInvoices(TransferLedger.Sales, Date, TransferDestination.Dedicated);
        transfer.TransferPayments(TransferLedger.Sales, Date, TransferDestination.Dedicated);
        transfer.TransferPayments(TransferLedger.Purchases, Date, TransferDestination.Dedicated);

        Assert.Equal(new[] { "00000001", "00000003", "00000005" }, db.Scan(Directory + "posting.dat").Select(x => x.Key));
        Assert.Equal(6, Layouts.System.From(db.Read(SystemFile, "00000001")!).I("Postings"));
    }

    [Fact]
    public void 同じ伝票番号の売掛入金と買掛支払を簡易記帳へ順番に転記できる()
    {
        using var db = new Db();
        db.LoadBaseline("biz");
        var system = Prepare(db, true, true);
        system.SetN("P-Flag-P", 2);
        db.Put(SystemFile, "00000001", system.B);
        db.Put(Directory + "openitm3.dat", "CUST011/00000007", OpenItem(true, "CUST011", 7, 5, 80m, 100m).B);
        db.Put(Directory + "openitm5.dat", "SUPP018/00000007", OpenItem(false, "SUPP018", 7, 5, 80m, 100m).B);

        var transfer = new LedgerTransfer(db);
        transfer.TransferPayments(TransferLedger.Sales, Date, TransferDestination.Dedicated);
        transfer.TransferPayments(TransferLedger.Purchases, Date, TransferDestination.Dedicated);

        Assert.Equal(new[] { "0001000001SL", "0001000001PL" },
            db.Scan(IrsBookkeeping.Directory + "postings2irs.dat").Select(row => Encoding.ASCII.GetString(row.Data, 0, 12)));
    }

    [Fact]
    public void 小切手台帳から支払総額を転記して請求書を消し込む()
    {
        using var db = new Db();
        db.LoadBaseline("biz");
        Prepare(db, false, false);
        const string items = Directory + "openitm5.dat";
        var invoice = OpenItem(false, "SUPP018", 7, 2, 100m, 0m);
        db.Put(items, "SUPP018/00000007", invoice.B);
        var queue = new Layout().X("supplier", 7).BChar("sequence").Fill(1).BLong("date").BLong("cheque")
            .Fill(8).C3("gross", 7, 2).BLong("folio").Fill(1).C3("amount", 7, 2).C3("deduction", 3, 2).Fill(194).New();
        queue.Set("supplier", "SUPP018");
        queue.SetN("date", Day);
        queue.SetN("cheque", 1234);
        queue.SetN("gross", 90);
        queue.SetN("folio", 7);
        queue.SetN("amount", 90);
        queue.SetN("deduction", 10);
        db.Put(Directory + "pay.dat", "SUPP018/1", queue.B);

        var report = new LedgerTransfer(db).TransferChequeRegister(Date, TransferDestination.Dedicated);

        Assert.Contains("小切手 1234", report.Body);
        Assert.Empty(db.Scan(Directory + "pay.dat"));
        var settled = invoice.L.From(db.Read(items, "SUPP018/00000007")!);
        Assert.Equal((90m, 90m, 1, Day), (settled.N("paid"), settled.N("amount"), settled.I("status"), settled.I("cleared")));
        var payment = invoice.L.From(db.Read(items, "SUPP018/00011001")!);
        Assert.Equal((5, 90m, 10m), (payment.I("type"), payment.N("paid"), payment.N("deduction")));
        var posting = Layouts.Posting.From(db.Read(Directory + "posting.dat", "00000001")!);
        Assert.Equal(90m, posting.N("post-amount"));
    }

    [Fact]
    public void 在庫連動の売上も売掛の科目で簡易記帳へ転記する()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var system = Prepare(db, true, true);
        system.Set("SL-Stock-Link", "Y");
        system.SetN("SL-Sales-Ac", 40001);
        db.Put(SystemFile, "00000001", system.B);

        var report = new LedgerTransfer(db).TransferInvoices(TransferLedger.Sales, Date, TransferDestination.Dedicated);

        var record = Assert.Single(db.Scan(IrsBookkeeping.Directory + "postings2irs.dat")).Data;
        Assert.Equal(84, record.Length);
        Assert.Equal("3000240001", Encoding.ASCII.GetString(record, 20, 10));
        Assert.Contains("CUST011", report.Body);
    }

    private static Rec Prepare(Db db, bool irs, bool sales)
    {
        var sys = Layouts.System.From(db.Read(SystemFile, "00000001")!);
        sys.SetN("Level-1", 1);
        sys.Set("Irs-Instead", irs ? "Y" : "N");
        sys.SetN("Next-Batch", 10);
        sys.SetN("BL-Next-Batch", 10);
        sys.SetN("Postings", 0);
        sys.SetN(sales ? "S-Flag-P" : "P-Flag-P", 2);
        sys.SetN("SL-Pay-Ac", 30001);
        sys.SetN("S-Debtors", 30002);
        sys.SetN("P-Creditors", 30003);
        sys.SetN("BL-Pay-Ac", 30001);
        db.Put(SystemFile, "00000001", sys.B);
        return sys;
    }

    private static Rec OpenItem(bool sales, string party, int invoice, int type, decimal amount, decimal paid)
    {
        var item = new Layout().X("party", 7).BLong("invoice").BLong("date").Comp("batch", 5).Comp("item", 3)
            .N9("type", 1).Fill(sales ? 27 : 22).C3("current", 7, 2).C3("amount", 7, 2).Fill(30).C3("paid", 7, 2)
            .N9("status", 1).BChar("deductDays").Comp("deduction", 3, 2, true).Fill(10).BLong("cleared").New();
        item.Set("party", party);
        item.SetN("invoice", invoice);
        item.SetN("date", Day);
        item.SetN("batch", type == 2 ? 0 : 6);
        item.SetN("item", type == 2 ? 0 : 9);
        item.SetN("type", type);
        item.SetN("amount", amount);
        item.SetN("paid", paid);
        return item;
    }
}
