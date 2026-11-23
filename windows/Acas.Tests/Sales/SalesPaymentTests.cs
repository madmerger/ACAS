using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

namespace Acas.Tests.Sales;

public sealed class SalesPaymentTests
{
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
