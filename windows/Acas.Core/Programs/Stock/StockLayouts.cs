namespace Acas.Core.Engine;

public static partial class Layouts
{
    /// <summary>stock/fdstock.cob (stockctl.dat, 400 バイト, キー = Stock-Key, 代替キー = Stock-Abrev-Key)。</summary>
    public static readonly Layout Stock = BuildStock();

    /// <summary>copybooks/fdaudit.cob (staudit.dat, 104 バイト, 順編成)。</summary>
    public static readonly Layout StockAudit = new Layout()
        .N9("Audit-Type", 1).N9("Audit-Invoice-PO", 8).N9("Audit-Cr-for-Invoice", 8).X("Audit-Stock-Key", 13)
        .X("Audit-Desc", 32).X("Audit-Process-Date", 10).N9("Audit-Reverse-Transaction", 1)
        .N9("Audit-Transaction-Qty", 6, 0, true).N9("Audit-Unit-Cost", 6, 4, true)
        .N9("Audit-Stock-Value-Change", 8, 2, true).N9("Audit-No", 5);

    private static Layout BuildStock()
    {
        var l = new Layout()
            .X("Stock-Key", 13).X("Stock-Abrev-Key", 7)
            .X("Stock-Supplier-P1", 7).X("Stock-Supplier-P2", 7).X("Stock-Supplier-P3", 7)
            .X("Stock-Desc", 32).X("Stock-Construct-Item", 13).X("Stock-Location", 10)
            .X("Stock-PA-Code", 3).X("Stock-SA-Code", 3).X("Stock-Services-Flag", 1)
            .C3("Stock-Last-Actual-Cost", 7, 2, false).Fill(8)
            .Comp("Stock-Construct-Bundle", 6, 0, true).Comp("Stock-Under-Construction", 6, 0, true)
            .Comp("Stock-Work-in-Progress", 6, 0, true).Comp("Stock-ReOrder-Pnt", 6, 0, true)
            .Comp("Stock-Std-ReOrder", 6, 0, true).Comp("Stock-Back-Ordered", 6, 0, true)
            .Comp("Stock-On-Order", 6, 0, true).Comp("Stock-Held", 6, 0, true).Comp("Stock-Pre-Sales", 6, 0, true)
            .C3("Stock-Retail", 7, 2, false).C3("Stock-Cost", 7, 4, false).C3("Stock-Value", 9, 2, false)
            .Comp("Stock-Order-Due", 8).Comp("Stock-Order-Date", 8)
            .Comp("Stock-Adds", 8).Comp("Stock-Deducts", 8).Comp("Stock-Wip-Adds", 8).Comp("Stock-Wip-Deds", 8);
        for (int m = 1; m <= 12; m++)
            l.Comp("Stock-TD-Adds-" + m, 8).Comp("Stock-TD-Deds-" + m, 8).Comp("Stock-TD-Wip-Adds-" + m, 8).Comp("Stock-TD-Wip-Deds-" + m, 8);
        l.Fill(15);
        l.Alias("Stock-PA-Group", "Stock-PA-Code", 1, 2).Alias("Stock-SA-Group", "Stock-SA-Code", 1, 2);
        return l;
    }
}
