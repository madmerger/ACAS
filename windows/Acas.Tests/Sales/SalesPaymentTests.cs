using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

namespace Acas.Tests.Sales;

public sealed class SalesPaymentTests
{
    [Fact]
    public void CashPostingMatchesCobolOpenItemsCustomerAndAccountingBatch()
    {
        using var db = new Db();
        var ledger = PostedSale(db);
        ledger.RecordPaymentBatch([new("CUST011", new DateTime(2026, 11, 23), 120m, false, [new(0, 120m)])]);
        ledger.PaymentProof();
        var menu = new SalesScreens(ledger).MainMenu();
        var confirmation = Assert.IsType<ConfirmationScreen>(menu.Items.Single(i => i.Id == "SalesPaymentPost").Open!());
        var report = Assert.IsType<ReportScreen>(confirmation.Confirm());
        Assert.Contains("120.00　0.00　120.00　0.00　120.00", report.Body);
        Assert.Equal(Convert.FromHexString(
            "4355535430313100000000a35f0200000000000000324f5244455230303120202020202020202020202020202020202020" +
            "000012000c000010000c000000000c000000000c000002000c000000000c000000000c000000000c000012000c31000000000000000000000000000020a35f0200"),
            db.Read(SalesLedger.OpenItemFile, "CUST011/00000000"));
        Assert.Equal(Convert.FromHexString(
            "43555354303131e9030000a35f020000000001000135202020202020202020202020202020202020202020202020202020" +
            "000000000c000012000c000000000c000000000c000000000c000000000c000000000c000000000c000012000c31000000000000000000000000000020a35f0200"),
            db.Read(SalesLedger.OpenItemFile, "CUST011/E9030000"));
        Assert.Equal(Convert.FromHexString(
            "43555354303131414c50484120435553544f4d45522020202020202020202020202020202031205445535420524f41445c4c4f4e444f4e5c554b2020" +
            "202020202020202020202020202020202020202020202020204c4f4e444f4e2020202020202020202020202020202020202020202020202020202020" +
            "202020202020202020202020203031323334353637383930202020202020616c706861406578616d706c652e74657374202020202020202020202020" +
            "20202020202020202020202020313030303030303000000033300000000000001027000001000000a35f0200a35f0200640000000000000000000000" +
            "00000000a35f020000000000000c00000000000c00000010000c00000000000c00000000000c00000000000c00000000000c00000000000000000000"),
            db.Read(SalesLedger.CustomerFile, "CUST011"));
        Assert.Equal(Convert.FromHexString(
            "333030303032303130303031a35f020000000000000000000000000000000012000f00000000000f00000012000f00000000000f" +
            "53616c65732d4c6564676572205061796d656e7473202020303043523030303030303030534c4f3030303033"),
            db.Read(SalesLedger.Prefix + "batch.dat", "300002"));
        Assert.Equal(Convert.FromHexString(
            "30303030323030303031534c32332f31312f32363330303030313030333030303032303030303030303132303030" +
            "30303030312f30303120203a2020414c50484120435553544f4d4552202020203030303030303030435230303030303030303030"),
            db.Read(SalesLedger.Prefix + "posting.dat", "00000003"));
        Assert.Equal(0, ledger.SystemRecord().I("S-Flag-P"));
    }

    [Fact]
    public void PaymentProofSortsCobolFixedRecordsByBatchAndTypeAndEnablesPosting()
    {
        using var db = new Db();
        var ledger = PostedSale(db);
        ledger.RecordPaymentBatch([new("CUST011", new DateTime(2026, 11, 23), 120m, false, [new(0, 120m)])]);
        var menu = new SalesScreens(ledger).MainMenu();
        var report = Assert.IsType<ReportScreen>(menu.Items.Single(i => i.Id == "SalesPaymentProof").Open!());
        Assert.Contains("CUST011　ALPHA CUSTOMER　120.00　120.00　0.00", report.Body);
        Assert.Contains("請求書　0　2026年11月23日　120.00　0.00", report.Body);
        var before = db.Scan(SalesLedger.PaymentSortFile).SelectMany(row => row.Data).ToArray();
        Assert.Equal(Convert.FromHexString(
            "43555354303131e9030000a35f020000000001000135202020202020202020202020202020202020202020202020202020" +
            "000000000c000012000c000000000c000000000c000000000c000000000c000000000c000000000c000012000c30000000000000000000000000000020a35f0200" +
            "4355535430313100000000a35f0200000000010001324f5244455230303120202020202020202020202020202020202020" +
            "000012000c000010000c000000000c000000000c000002000c000000000c000000000c000000000c000012000c3100000000000000000000e02e000020a35f0200"),
            before);
        Assert.Equal(2, ledger.SystemRecord().I("S-Flag-P"));
    }

    private static SalesLedger PostedSale(Db db)
    {
        db.LoadBaseline("sl-printed");
        var ledger = new SalesLedger(db);
        ledger.ExtractSalesForPosting();
        ledger.PostSales();
        return ledger;
    }

    [Fact]
    public void PaymentCorrectionClearsBatchAndAllocationButKeepsCobolClearingDate()
    {
        using var db = new Db();
        var ledger = PostedSale(db);
        var date = new DateTime(2026, 11, 23);
        ledger.RecordPaymentBatch([new("CUST011", date, 120m, false, [new(0, 120m)])]);
        var menu = new SalesScreens(ledger).MainMenu();
        var lookup = Assert.IsType<FormScreen>(menu.Items.Single(i => i.Id == "SalesPaymentAmend").Open!());
        var payments = Assert.IsType<TableScreen>(lookup.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesPaymentAmendCustomer"] = "CUST011"
        })));
        var confirm = Assert.IsType<ConfirmationScreen>(Assert.Single(payments.Rows).Open!());
        Assert.IsType<InformationScreen>(confirm.Confirm());
        Assert.Null(db.Read(SalesLedger.OpenItemFile, "CUST011/E9030000"));
        Assert.Equal(Convert.FromHexString(
            "4355535430313100000000a35f0200000000000000324f5244455230303120202020202020202020202020202020202020" +
            "000000000c000010000c000000000c000000000c000002000c000000000c000000000c000000000c000000000c30000000000000000000000000000020a35f0200"),
            db.Read(SalesLedger.OpenItemFile, "CUST011/00000000"));
        Assert.Equal(1, ledger.SystemRecord().I("S-Flag-P"));
    }

    [Fact]
    public void PaymentEntryMatchesCobolAllocatedInvoiceAndPaymentRecords()
    {
        using var db = new Db();
        var ledger = PostedSale(db);
        var date = new DateTime(2026, 11, 23);
        var customer = db.Read(SalesLedger.CustomerFile, "CUST011");
        var menu = new SalesScreens(ledger, () => date).MainMenu();
        var lookup = Assert.IsType<FormScreen>(menu.Items.Single(i => i.Id == "SalesPaymentEntry").Open!());
        var entry = Assert.IsType<FormScreen>(lookup.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesPaymentCustomer"] = "CUST011"
        })));
        var draft = Assert.IsType<MenuScreen>(entry.Submit(new FormValues(new Dictionary<string, object?>
        {
            ["SalesPaymentDate"] = date,
            ["SalesPaymentAmount"] = "120.00",
            ["SalesPaymentAllocation0"] = "120.00"
        })));
        var confirm = Assert.IsType<ConfirmationScreen>(draft.Items.Single(i => i.Id == "SalesPaymentSave").Open!());
        Assert.IsType<InformationScreen>(confirm.Confirm());
        Assert.Equal(Convert.FromHexString(
            "4355535430313100000000a35f0200000000010001324f5244455230303120202020202020202020202020202020202020" +
            "000012000c000010000c000000000c000000000c000002000c000000000c000000000c000000000c000012000c3100000000000000000000e02e000020a35f0200"),
            db.Read(SalesLedger.OpenItemFile, "CUST011/00000000"));
        Assert.Equal(Convert.FromHexString(
            "43555354303131e9030000a35f020000000001000135202020202020202020202020202020202020202020202020202020" +
            "000000000c000012000c000000000c000000000c000000000c000000000c000000000c000000000c000012000c30000000000000000000000000000020a35f0200"),
            db.Read(SalesLedger.OpenItemFile, "CUST011/E9030000"));
        Assert.Equal(customer, db.Read(SalesLedger.CustomerFile, "CUST011"));
        Assert.Equal(2, ledger.SystemRecord().I("First-Sl-Batch"));
        Assert.Equal(1, ledger.SystemRecord().I("S-Flag-P"));
    }
}
