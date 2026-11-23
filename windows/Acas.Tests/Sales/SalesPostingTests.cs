using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

namespace Acas.Tests.Sales;

public sealed class SalesPostingTests
{
    [Fact]
    public void AnalysisReportUsesPostedCountsAndAmountsAndClearsFlag()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        sales.ExtractSalesForPosting();
        sales.PostSales();
        var menu = new SalesScreens(sales).MainMenu();
        var report = Assert.IsType<ReportScreen>(menu.Items.Single(i => i.Id == "SalesAnalysisReport").Open!());
        Assert.Contains("a1　Emergency Name　明細　1　0　1　0.00％　100.00　0.00　100.00", report.Body);
        Assert.Equal(0, sales.SystemRecord().I("S-Flag-A"));
    }

    [Fact]
    public void ConfirmedSaleMatchesCobolCustomerOpenItemAndNominalPosting()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        var screen = new SalesScreens(sales).MainMenu().Items.Single(item => item.Id == "SalesSalesPost");
        var confirmation = Assert.IsType<ConfirmationScreen>(screen.Open!());
        var staged = Assert.Single(db.Scan(SalesLedger.PostingStageFile)).Data;
        var result = Assert.IsType<ReportScreen>(confirmation.Confirm());
        Assert.Contains("0　2026年11月23日　CUST011　ALPHA CUSTOMER　掛売請求書　0.00　120.00　0.00　100.00　20.00　120.00", result.Body);
        Assert.Equal(staged, db.Read(SalesLedger.OpenItemFile, "CUST011/00000000"));
        Assert.Empty(db.Scan(SalesLedger.PostingStageFile));
        Assert.Equal(Convert.FromHexString(
            "43555354303131414c50484120435553544f4d45522020202020202020202020202020202031205445535420524f41445c4c4f4e444f4e5c554b2020" +
            "202020202020202020202020202020202020202020202020204c4f4e444f4e2020202020202020202020202020202020202020202020202020202020" +
            "202020202020202020202020203031323334353637383930202020202020616c706861406578616d706c652e74657374202020202020202020202020" +
            "20202020202020202020202020313030303030303000000033300000000000001027000001000000a35f020000000000640000000000000000000000" +
            "00000000a35f020000000012000c00000000000c00000010000c00000000000c00000000000c00000000000c00000000000c00000000000000000000"),
            db.Read(SalesLedger.CustomerFile, "CUST011"));
        Assert.Equal(Convert.FromHexString(
            "333030303031303130303031a35f020000000000000000000000000000000010000f00000002000f00000010000f00000002000f" +
            "53616c6573204c656467657220496e766f69636573202020303043523030303030303030534c4f3030303031"),
            db.Read(SalesLedger.Prefix + "batch.dat", "300001"));
        Assert.Equal(Convert.FromHexString(
            "30303030313030303031534c32332f31312f3236333030303032303034303030303130303030303030313030303030203a20" +
            "414c50484120435553544f4d455220202020202020202020202020203030303030303030435230303030303032303030"),
            db.Read(SalesLedger.Prefix + "posting.dat", "00000001"));
        Assert.Equal(2, sales.SystemRecord().I("S-Flag-I"));
        Assert.Equal(0, sales.SystemRecord().I("File-Status-18"));
    }

    [Fact]
    public void ExtractMatchesCobolWorkAndValueRecords()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        const string headerKey = "00000000/ /00";
        const string detailKey = "00000000/ /01";
        byte[] header = db.Read(SalesLedger.InvoiceFile, headerKey)!;
        byte[] detail = db.Read(SalesLedger.InvoiceFile, detailKey)!;
        header[114] = (byte)'Z';
        header[118] = (byte)'A';
        detail[78] = (byte)'Z';

        Assert.False(sales.ExtractSalesForPosting());

        var staged = Assert.Single(db.Scan(SalesLedger.PostingStageFile));
        Assert.Equal(Convert.FromHexString(
            "4355535430313100000000a35f0200000000000000324f5244455230303120202020202020202020202020202020202020" +
            "000000000c000010000c000000000c000000000c000002000c000000000c000000000c000000000c000000000c3000000000000000000000000000002000000000"),
            staged.Data);
        const string value = SalesLedger.Prefix + "value.dat";
        Assert.Equal(Convert.FromHexString(
            "536131303030303030456d657267656e6379204e616d652020202020202020202020202000000001000000000000000100000010000c00000000000c00000010000c"),
            db.Read(value, "Sa1"));
        Assert.Equal(Convert.FromHexString(
            "537620303030303030456d657267656e6379204e616d652020202020202020202020202000000001000000000000000100000002000c00000000000c00000002000c"),
            db.Read(value, "Sv "));
        Assert.Equal(header, db.Read(SalesLedger.InvoiceFile, headerKey));
        Assert.Equal(detail, db.Read(SalesLedger.InvoiceFile, detailKey));
        Assert.Equal(1, sales.SystemRecord().I("File-Status-18"));

        byte[] detailValue = db.Read(value, "Sa1")!;
        Assert.False(sales.ExtractSalesForPosting());
        Assert.Single(db.Scan(SalesLedger.PostingStageFile));
        Assert.Equal(detailValue, db.Read(value, "Sa1"));
    }
}
