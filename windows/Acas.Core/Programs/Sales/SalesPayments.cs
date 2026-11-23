using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed record PaymentAllocation(int Invoice, decimal Amount, bool WaiveLateCharge = false);
public sealed record SalesPaymentInput(string Customer, DateTime Date, decimal Amount, bool FromUnapplied,
    IReadOnlyList<PaymentAllocation> Allocations);
public sealed record SalesPaymentItem(int Number, int Date, decimal Outstanding, decimal LateCharge);

public sealed partial class SalesLedger
{
    public IReadOnlyList<SalesPaymentItem> PaymentInvoices(string customer) => ReadOpenItems(customer)
        .Where(item => item.I("type") == 2 && item.I("batchNumber") == 0 && InvoiceAmounts.Sum(item.N) > item.N("paid"))
        .Select(item => new SalesPaymentItem(item.I("number"), item.I("date"),
            InvoiceAmounts.Sum(item.N) - item.N("paid"), item.N("deductAmount") + item.N("deductVat"))).ToArray();

    public int RecordPaymentBatch(IReadOnlyList<SalesPaymentInput> payments) => db.Atomic(() =>
    {
        var system = SystemRecord();
        if (!HasOpenItems()) throw new SalesRuleException("売掛明細ファイルがありません。");
        if (system.I("S-Flag-I") == 1) throw new SalesRuleException("売上取引を転記してから入金してください。");
        int batch = Math.Max(1, system.I("First-Sl-Batch"));
        if (payments.Count is < 1 or > 999 || batch == short.MaxValue)
            throw new SalesRuleException("入金バッチに登録できる件数または番号の上限に達しました。");
        for (int i = 0; i < payments.Count; i++)
        {
            SavePayment(payments[i], batch, i + 1);
            if (!payments[i].FromUnapplied) system.SetN("S-Flag-P", 1);
        }
        system.SetN("First-Sl-Batch", batch + 1);
        system.Set("Oi-3-Flag", "Y");
        SaveSystem(system);
        return batch;
    });

    private void SavePayment(SalesPaymentInput input, int batch, int sequence)
    {
        int date = EncodeDate(input.Date);
        if (date <= 0 || !ValidPaymentAmount(input.Amount) || input.Amount == 0)
            throw new SalesRuleException("入金日と入金額を確認してください。");
        var customer = CustomerRecord(input.Customer);
        string code = customer.S("key");
        if (input.FromUnapplied)
        {
            if (input.Amount > customer.N("unapplied")) throw new SalesRuleException("未消込残高を超える金額を振り替えられません。");
            customer.SetN("unapplied", customer.N("unapplied") - input.Amount);
            db.Rewrite(CustomerFile, code, customer.B);
        }
        Dictionary<int, PaymentAllocation> allocations = [];
        foreach (var entry in input.Allocations)
            if (!ValidPaymentAmount(entry.Amount) || !allocations.TryAdd(entry.Invoice, entry))
                throw new SalesRuleException("請求番号または消込額が無効です。");
        decimal allocated = 0, deductions = 0;
        int lastClearedDate = 0;
        foreach (var (key, data) in db.Scan(OpenItemFile, code))
        {
            var item = DecodePostingItem(data);
            lastClearedDate = item.I("closedDate");
            if (item.I("type") != 2) continue;
            if (item.S("customer") != code) break;
            if (item.I("batchNumber") != 0) continue;
            decimal outstanding = InvoiceAmounts.Sum(item.N) - item.N("paid");
            decimal lateCharge = item.N("deductAmount") + item.N("deductVat");
            if (outstanding == 0 && item.I("closed") == 0)
            {
                lastClearedDate = date;
                item.SetN("closedDate", date);
                item.SetN("closed", 1);
                db.Rewrite(OpenItemFile, key, item.B);
                continue;
            }
            if (!allocations.Remove(item.I("number"), out var entry) || entry.Amount == 0) continue;
            if (outstanding <= 0 || entry.Amount > outstanding || allocated + entry.Amount > input.Amount)
                throw new SalesRuleException("消込額が請求残高または入金額を超えています。");
            bool withinTerm = item.I("date") + item.I("deductDays") + 1 > date;
            bool waive = lateCharge != 0 && entry.Amount == outstanding - lateCharge && (withinTerm || entry.WaiveLateCharge);
            if (waive)
            {
                deductions += lateCharge;
                item.SetN("deductAmount", 0);
                item.SetN("deductVat", 0);
            }
            item.SetN("batchNumber", batch);
            item.SetN("batchItem", sequence);
            item.SetN("paid", item.N("paid") + entry.Amount);
            item.SetN("pc", item.N("pc") + entry.Amount);
            item.SetN("creditFor", entry.Amount * 100);
            if (waive || entry.Amount == outstanding)
            {
                lastClearedDate = date;
                item.SetN("closedDate", date);
                item.SetN("closed", 1);
            }
            db.Rewrite(OpenItemFile, key, item.B);
            allocated += entry.Amount;
            if (allocated == input.Amount) break;
        }
        if (allocations.Values.Any(a => a.Amount != 0))
            throw new SalesRuleException("消込を指定した請求書が見つからないか、既に消込済みです。");
        var payment = OpenItemLayout.New();
        int number = batch * 1000 + sequence;
        payment.Set("customer", code);
        payment.SetN("number", number);
        payment.SetN("date", date);
        payment.SetN("type", input.FromUnapplied ? 6 : 5);
        payment.SetN("batchNumber", batch);
        payment.SetN("batchItem", sequence);
        payment.SetN("closedDate", lastClearedDate);
        payment.SetN("paid", input.Amount);
        payment.SetN("net", allocated);
        payment.SetN("deductAmount", deductions);
        if (!db.Write(OpenItemFile, OpenItemKey(code, number), payment.B))
            throw new SalesRuleException("同じ得意先と番号の入金明細が既にあります。");
    }

    private static bool ValidPaymentAmount(decimal amount) =>
        amount is >= 0 and <= 999_999.99m && decimal.Round(amount, 2) == amount;
}
