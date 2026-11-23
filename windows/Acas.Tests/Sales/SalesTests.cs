using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

namespace Acas.Tests.Sales;

public sealed class SalesTests
{
    [Fact]
    public void NavigationPreservesLegacyKeysAndNumberedGroups()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var screens = new SalesScreens(new SalesLedger(db), () => new DateTime(2026, 11, 23));
        var route = screens.Navigation();
        Assert.Equal("Ｂ　売掛元帳", route.Caption);
        var date = Assert.IsType<FormScreen>(route.Open!());
        Assert.Equal(new DateTime(2026, 11, 23), Assert.IsType<DateField>(Assert.Single(date.Fields)).Value);
        var root = Assert.IsType<MenuScreen>(date.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesStartDate"] = new DateTime(2026, 11, 24)
        })));
        Assert.Equal("ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＸＺ", new string(root.Items.Select(i => i.Label[0]).ToArray()));
        var customer = Assert.IsType<MenuScreen>(root.Items.Single(i => i.Id == "SalesCustomers").Open!());
        Assert.Equal(new int?[] { 1, 2, 3, 4, 5, 9 }, customer.Items.Select(i => i.Number).ToArray());
        Assert.Equal("2026年11月24日", SalesLedger.ShowDate(new SalesLedger(db).SystemRecord().I("Run-Date")));
    }

    [Fact]
    public void CustomerModificationChangesOnlyTheFixedNameField()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        byte[] expected = db.Read(SalesLedger.CustomerFile, "CUST011")!;
        "EQUIV UPDATED CUSTOMER".PadRight(30).Select(c => (byte)c).ToArray().CopyTo(expected, 7);
        var details = sales.GetCustomer("CUST011").Details;
        Assert.Equal("EQUIV UPDATED CUSTOMER", sales.UpdateCustomer("CUST011", details with { Name = "EQUIV UPDATED CUSTOMER" }).Details.Name);
        Assert.Equal(expected, db.Read(SalesLedger.CustomerFile, "CUST011"));
    }

    [Fact]
    public void CustomerCreationKeepsTheFixedLengthAndRejectsUnencodableInput()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        var details = sales.CustomerDefaults() with { Name = "得意先", Address1 = "1 TEST ROAD\\LONDON\\UK" };
        var added = sales.CreateCustomer("TEST01", details);
        Assert.Equal("TEST011", added.Code);
        Assert.Equal("得意先", added.Details.Name);
        Assert.Equal(300, db.Read(SalesLedger.CustomerFile, added.Code)!.Length);
        var before = db.Snapshot()[SalesLedger.CustomerFile][added.Code];
        Assert.Throws<SalesRuleException>(() => sales.UpdateCustomer(added.Code, details with { Name = new string('先', 16) }));
        Assert.Equal(before, db.Snapshot()[SalesLedger.CustomerFile][added.Code]);
        sales.CloseCustomer(added.Code, true);
        Assert.Null(db.Read(SalesLedger.CustomerFile, added.Code));
    }

    [Fact]
    public void InvoiceMatchesRecordLayoutAndSetsPrintFlags()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        var invoice = new InvoiceInput(new DateTime(2026, 11, 23), "CUST011", "EQUIVREF", "ORDER001",
            InvoiceKind.Account, null, 0, "", 0m, null);
        Assert.Equal(0, sales.SaveInvoice(invoice, [new("INVTEST", "a1", "TEST SERVICE", 1, 100m, 0m, 1)]));
        var h = db.Read(SalesLedger.InvoiceFile, "00000000/ /00")!;
        Assert.Equal(134, h.Length);
        Assert.Equal("000002000C", Convert.ToHexString(h.AsSpan(94, 5)));
        Assert.Equal((byte)'P', h[114]);
        var printed = sales.PrintInvoices(false, false);
        Assert.Contains("請求合計　120.00", printed);
        Assert.Contains("TEST SERVICE", printed);
        Assert.Equal([(byte)'I', (byte)' ', (byte)'L'], db.Read(SalesLedger.InvoiceFile, "00000000/ /00")![114..117]);
        Assert.Contains("未転記売上取引検証帳票", sales.InvoiceProof());
    }

    [Fact]
    public void InvoiceWithTaxCodeZeroDoesNotChargeStandardTax()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        var invoice = new InvoiceInput(new DateTime(2026, 11, 23), "CUST011", "", "",
            InvoiceKind.Account, null, 0, "", 0m, null);
        sales.SaveInvoice(invoice, [new("INVTEST", "a1", "非課税の品目", 1, 100m, 0m, 0)]);
        var saved = Assert.Single(sales.Invoices());
        Assert.Equal(0, Assert.Single(saved.Lines).VatCode);
        Assert.Equal(0m, saved.Vat);
    }

    [Fact]
    public void InvoiceProofIncludesPendingCreditWithNegativeAmounts()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        var invoice = new InvoiceInput(new DateTime(2026, 11, 23), "CUST011", "", "", InvoiceKind.Credit,
            null, 0, "", 0m, null);
        sales.SaveInvoice(invoice, [new("INVTEST", "a1", "TEST SERVICE", 1, 50m, 0m, 1)]);
        var proof = sales.InvoiceProof();
        Assert.Contains("貸方伝票　-50.00　-50.00　-10.00　-60.00", proof);
        Assert.Contains("分析コード　a1　金額　-50.00　税区分　1", proof);
    }

    [Fact]
    public void DayBookIncludesPostedInvoicesOnlyWithoutChangingRecords()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        var date = new DateTime(2026, 11, 23);
        var input = new InvoiceInput(date, "CUST011", "", "", InvoiceKind.Account, null, 0, "", 0m, null);
        sales.SaveInvoice(input, [new("POSTED", "a1", "記帳済み", 1, 100m, 0m, 1)]);
        sales.SaveInvoice(input, [new("PENDING", "a1", "未記帳", 1, 50m, 0m, 1)]);
        byte[] posted = db.Read(SalesLedger.InvoiceFile, "00000000/ /00")!;
        posted[114] = (byte)'z';
        db.Put(SalesLedger.InvoiceFile, "00000000/ /00", posted);
        var book = sales.InvoiceDayBook(date);
        Assert.Contains("掛売請求書　100.00　20.00　120.00", book);
        Assert.DoesNotContain("50.00", book);
        Assert.Equal(posted, db.Read(SalesLedger.InvoiceFile, "00000000/ /00"));
    }

    [Fact]
    public void DayBookScreenUsesTheEnteredProcessingDate()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        var wallClock = new DateTime(2026, 11, 23);
        sales.SaveInvoice(new InvoiceInput(wallClock, "CUST011", "", "", InvoiceKind.Account, null, 0, "", 0m, null),
            [new("PENDING", "a1", "未記帳", 1, 50m, 0m, 1)]);
        var start = Assert.IsType<FormScreen>(new SalesScreens(sales, () => wallClock).Navigation().Open!());
        var menu = Assert.IsType<MenuScreen>(start.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesStartDate"] = wallClock.AddDays(1)
        })));
        Assert.IsType<ReportScreen>(menu.Items.Single(i => i.Id == "SalesDayBook").Open!());
        var spool = Assert.Single(db.Spool());
        Assert.Equal("prt-1", spool.Name);
        Assert.Contains("2026年11月24日", spool.Body);
        Assert.DoesNotContain("2026年11月23日", spool.Body);
    }

    [Fact]
    public void AllAnalysisCodesDisplayTruncatedLegacyPurchaseCarriageDescriptionInJapanese()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        var system = sales.SystemRecord();
        system.SetN("File-Status-15", 0);
        db.Put(SalesLedger.SystemFile, "00000001", system.B);
        sales.ExtractSalesForPosting();

        byte[] stored = db.Read(SalesLedger.AnalysisFile, "Pza")!;
        Assert.Equal("Purchase Carriage Charge", System.Text.Encoding.ASCII.GetString(stored, 9, 24));
        Assert.Contains("za　000000　仕入送料　P&P", sales.AnalysisReport(true));
        Assert.DoesNotContain("Purchase Carriage Charge", sales.AnalysisReport(true));
        Assert.Equal(stored, db.Read(SalesLedger.AnalysisFile, "Pza"));
    }

    [Fact]
    public void EmptyAnalysisReportComparisonChecksHeadingValuesAndNoDetails()
    {
        var legacy = "SL070                              Product Analysis Codes        Page   1\n\n" +
            "事業者".PadRight(70) + "23/11/2026\n\n    Code    Gl.Nos.      <-----Description------>   Print      -Type-";
        const string localized = "売上分析コード帳票\n事業者\n2026年11月23日\nコード　勘定番号　分析名　印刷分類　種類\n" +
            "売上分析ファイルのレコード長が一致しません。（状態39）";
        Assert.Null(SalesReportValues.Difference(legacy, localized));
        Assert.NotNull(SalesReportValues.Difference(legacy, localized.Replace("11月23日", "11月24日")));
        Assert.NotNull(SalesReportValues.Difference(legacy, localized.Replace("事業者", "別の事業者")));
        Assert.NotNull(SalesReportValues.Difference(legacy, localized + "\nAB　000001　明細"));
    }

    [Fact]
    public void ProofComparisonRequiresSameOrderedTaxValues()
    {
        var header = "SL050".PadRight(49) + "Unapplied Sales Transaction Report".PadRight(75) + "Page 1";
        var legacy = header + "\n" + "事業者".PadRight(122) + "23/11/2026\n" +
            "Vat Code 1   20.00%           0.00          20.00           0.00\n" +
            "Vat Code 2    5.00%           0.00           0.00           0.00\n";
        const string heading = "未転記売上取引検証帳票\n事業者\n2026年11月23日\n税区分別集計　現金売上　掛売請求書　貸方伝票\n";
        const string first = "税区分1　税率20.00％　0.00　20.00　0.00\n";
        const string second = "税区分2　税率5.00％　0.00　0.00　0.00\n";
        Assert.Null(SalesReportValues.Difference(legacy, heading + first + second));
        Assert.NotNull(SalesReportValues.Difference(legacy, heading + second + first));
        Assert.NotNull(SalesReportValues.Difference(legacy, heading + first + second + second));
        Assert.NotNull(SalesReportValues.Difference(legacy, heading + first.Replace("20.00　0.00", "21.00　0.00") + second));
    }

    [Fact]
    public void CycleClosePadsInvoiceAtTheLegacyTemporaryRecordBoundary()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        var date = new DateTime(2026, 11, 23);
        var invoice = new InvoiceInput(date, "CUST011", "", "", InvoiceKind.Account, null, 0, "", 0m, null);
        sales.SaveInvoice(invoice, [new("INVTEST", "a1", "TEST SERVICE", 1, 100m, 0m, 1)]);
        var system = sales.SystemRecord();
        system.SetN("File-Status-15", 1);
        system.SetN("File-Status-19", 1);
        system.SetN("Current-Quarter", 1);
        system.Set("Pass-Word", "");
        db.Put(SalesLedger.SystemFile, "00000001", system.B);
        db.Create(SalesLedger.OpenItemFile);
        const string key = "00000000/ /00";
        byte[] before = db.Read(SalesLedger.InvoiceFile, key)!;
        before.AsSpan(129).Fill(0x41);
        db.Put(SalesLedger.InvoiceFile, key, before);
        Assert.Throws<SalesRuleException>(() => sales.CloseCycle("A", false, true, date));
        Assert.Equal(before, db.Read(SalesLedger.InvoiceFile, key));
        sales.CloseCycle("", false, true, date);
        byte[] after = db.Read(SalesLedger.InvoiceFile, key)!;
        Assert.Equal(before[..129], after[..129]);
        Assert.Equal(new byte[] { 32, 32, 32, 32, 32 }, after[129..]);
    }

    [Fact]
    public void IncompatibleAnalysisRecordLengthPreventsUpdates()
    {
        using var db = new Db();
        db.LoadBaseline("sl-ready");
        var sales = new SalesLedger(db);
        sales.ImportAnalysisRecordLength(66);
        var failure = Assert.Throws<SalesRuleException>(() => sales.SaveAnalysis("A", "400001", "売上", "A", false));
        Assert.Contains("状態39", failure.Message);
        Assert.Empty(db.Scan(SalesLedger.AnalysisFile));
    }
}
