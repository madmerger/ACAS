using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed record ScheduledPurchaseLine(int Folio, int Period, decimal Amount, string Reference);

public sealed record ScheduledPurchasePayment(string Supplier, int Number, DateTime? Date,
    bool BankTransfer, bool Continues, IReadOnlyList<ScheduledPurchaseLine> Lines);

public sealed partial class PurchaseLedger
{
    private static readonly Layout PaymentScheduleLayout = new Layout()
        .X("supplier", 7).BChar("number").X("continuation", 1).BLong("date").BLong("cheque")
        .BLong("sort").BLong("account").C3("gross", 7, 2)
        .Group(9, (layout, i) => layout.BLong("folio" + i).BChar("period" + i)
            .C3("amount" + i, 7, 2).C3("deduction" + i, 3, 2).X("reference" + i, 10));

    public IReadOnlyList<ScheduledPurchasePayment>? ScheduledPayments()
    {
        var rows = database.Scan(PaymentFile);
        if (rows.Any(row => row.Data.Length != PaymentScheduleLayout.Size)) return null;
        return rows.Select(row =>
        {
            var record = PaymentScheduleLayout.From(row.Data);
            return new ScheduledPurchasePayment(record.St("supplier"), record.I("number"), DecodeDate(record.I("date")),
                record.I("sort") != 0, record.S("continuation") == "C",
                Enumerable.Range(1, 9).Where(i => record.N("amount" + i) != 0)
                    .Select(i => new ScheduledPurchaseLine(record.I("folio" + i), record.I("period" + i),
                        record.N("amount" + i), record.St("reference" + i))).ToArray());
        }).ToArray();
    }
}
