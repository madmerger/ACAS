using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

namespace Acas.Tests.Sales;

public sealed class SalesPostingTests
{
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
