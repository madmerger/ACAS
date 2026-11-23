using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

namespace Acas.Tests.Sales;

public sealed class SalesPostingTests
{
    [Fact]
    public void AnalysisRegistrationAndLookupKeepCobolCaseSensitiveKeys()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        sales.SaveAnalysis("a1", "410000", "小文字の分析", "", false);
        sales.SaveAnalysis("A1", "420000", "大文字の分析", "", false);

        var menu = new SalesScreens(sales).MainMenu();
        var analysis = Assert.IsType<MenuScreen>(menu.Items.Single(i => i.Id == "SalesAnalysis").Open!());
        var lookup = Assert.IsType<FormScreen>(analysis.Items.Single(i => i.Id == "SalesAnalysisDisplay").Open!());
        var result = Assert.IsType<TableScreen>(lookup.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesFindAnalysisCode"] = "a1"
        })));
        Assert.Equal("小文字の分析", Assert.Single(result.Rows).Cells[2]);
        Assert.NotNull(db.Read(SalesLedger.AnalysisFile, "Sa1"));
        Assert.NotNull(db.Read(SalesLedger.AnalysisFile, "SA1"));
    }

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
        Assert.Contains("a1　緊急用　明細　1　0　1　0.00％　100.00　0.00　100.00", report.Body);
        Assert.DoesNotContain("Emergency Name", report.Body);
        Assert.Equal(report.Body, db.Spool().Last().Body);
        Assert.Equal("Sa1000000Emergency Name             ",
            System.Text.Encoding.ASCII.GetString(db.Read(SalesLedger.AnalysisFile, "Sa1")!));
        Assert.Equal(db.Read(SalesLedger.AnalysisFile, "Sa1")!,
            db.Read(SalesLedger.Prefix + "value.dat", "Sa1")![..36]);
        Assert.Equal(0, sales.SystemRecord().I("S-Flag-A"));
    }

    [Fact]
    public void AnalysisEditorDisplaysGeneratedNamesWithoutReplacingTheirStoredValues()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        sales.ExtractSalesForPosting();
        sales.SaveAnalysis("v", "000000", "VAT Control", "", true);
        sales.SaveAnalysis("U1", "420000", "Default Sales", "", false);
        Assert.Contains("v　000000　付加価値税管理", sales.AnalysisReport(false));
        Assert.Contains("U1　420000　Default Sales", sales.AnalysisReport(false));
        var menu = new SalesScreens(sales).MainMenu();
        var analysis = Assert.IsType<MenuScreen>(menu.Items.Single(i => i.Id == "SalesAnalysis").Open!());
        var values = new FormValues(new Dictionary<string, object?> { ["SalesFindAnalysisCode"] = "a1" });
        var lookup = Assert.IsType<FormScreen>(analysis.Items.Single(i => i.Id == "SalesAnalysisDisplay").Open!());
        var result = Assert.IsType<TableScreen>(lookup.Submit(values));
        Assert.Equal("緊急用", Assert.Single(result.Rows).Cells[2]);
        var change = Assert.IsType<FormScreen>(analysis.Items.Single(i => i.Id == "SalesAnalysisChange").Open!());
        var selected = Assert.IsType<MenuScreen>(change.Submit(values));
        var editor = Assert.IsType<FormScreen>(selected.Items.Single(i => i.Id == "SalesAnalysisEditSelected").Open!());
        var action = Assert.IsType<ChoiceField>(editor.Fields.Single(f => f.Id == "SalesAnalysisDescriptionAction"));
        Assert.Equal("現在の分析名：緊急用", action.Label);
        Assert.Equal("", Assert.IsType<TextField>(editor.Fields.Single(f => f.Id == "SalesAnalysisDescription")).Value);
        var fields = EditorFields(editor);
        byte[] before = db.Read(SalesLedger.AnalysisFile, "Sa1")!;
        before[32] = 0; // Preserve even the original padding byte.
        db.Put(SalesLedger.AnalysisFile, "Sa1", before);
        Assert.IsType<ConfirmationScreen>(editor.Submit(new FormValues(fields))).Confirm();
        Assert.Equal(before, db.Read(SalesLedger.AnalysisFile, "Sa1"));
    }

    [Fact]
    public void AnalysisEditorAcceptsOnlyNewNamesThatFitTheFixedByteField()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        sales.SaveAnalysis("vo", "000000", "VAT Output Invoices/CN's", "", false);
        var menu = new SalesScreens(sales).MainMenu();
        var analysis = Assert.IsType<MenuScreen>(menu.Items.Single(i => i.Id == "SalesAnalysis").Open!());
        var change = Assert.IsType<FormScreen>(analysis.Items.Single(i => i.Id == "SalesAnalysisChange").Open!());
        var selected = Assert.IsType<MenuScreen>(change.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesFindAnalysisCode"] = "vo"
        })));
        var editor = Assert.IsType<FormScreen>(selected.Items.Single(i => i.Id == "SalesAnalysisEditSelected").Open!());
        var action = Assert.IsType<ChoiceField>(editor.Fields.Single(f => f.Id == "SalesAnalysisDescriptionAction"));
        Assert.Equal("現在の分析名：売上付加価値税（請求書・貸方伝票）", action.Label);
        var fields = EditorFields(editor);
        byte[] before = db.Read(SalesLedger.AnalysisFile, "Svo")!;
        Assert.Equal("0", fields["SalesAnalysisDescriptionAction"]);
        fields["SalesAnalysisDescription"] = "新しい分析名";
        var conflict = Assert.IsType<InformationScreen>(editor.Submit(new FormValues(fields)));
        Assert.Contains("新しい分析名が入力されています", conflict.Message);
        Assert.Equal(before, db.Read(SalesLedger.AnalysisFile, "Svo"));
        fields["SalesAnalysisDescriptionAction"] = "1";
        fields["SalesAnalysisDescription"] = new string('税', 13);
        var rejected = Assert.IsType<InformationScreen>(Assert.IsType<ConfirmationScreen>(editor.Submit(new FormValues(fields))).Confirm());
        Assert.Contains("固定長レコード", rejected.Message);
        Assert.Equal(before, db.Read(SalesLedger.AnalysisFile, "Svo"));
        fields["SalesAnalysisDescription"] = new string('税', 12);
        Assert.IsType<MenuScreen>(Assert.IsType<ConfirmationScreen>(editor.Submit(new FormValues(fields))).Confirm());
        Assert.Equal(fields["SalesAnalysisDescription"], sales.AnalysisCodes().Single(c => c.Code == "vo").Description);
    }

    private static Dictionary<string, object?> EditorFields(FormScreen editor) => editor.Fields.ToDictionary(
        f => f.Id, f => f is TextField text ? (object?)text.Value : ((ChoiceField)f).Value);

    [Fact]
    public void MissingCustomerNameIsLocalizedInReportsWithoutChangingTheLegacyRecord()
    {
        using var db = new Db();
        db.LoadBaseline("sl-printed");
        var sales = new SalesLedger(db);
        sales.ExtractSalesForPosting();
        Assert.True(db.Delete(SalesLedger.CustomerFile, "CUST011"));
        Assert.Contains("CUST011　得意先不明", sales.PostSales());
        var menu = new SalesScreens(sales).MainMenu();
        var customers = Assert.IsType<MenuScreen>(menu.Items.Single(i => i.Id == "SalesCustomers").Open!());
        var lookup = Assert.IsType<FormScreen>(customers.Items.Single(i => i.Id == "SalesCustomerDisplay").Open!());
        var result = Assert.IsType<TableScreen>(lookup.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesDisplayCustomerCode"] = "CUST011"
        })));
        Assert.Equal("得意先不明", result.Rows.Single(r => r.Cells[0] == "得意先名").Cells[1]);
        Assert.Equal("*** Customer Unknown ***", sales.GetCustomer("CUST011").Details.Name);
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
