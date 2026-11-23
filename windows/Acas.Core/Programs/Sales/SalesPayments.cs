using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed record PaymentAllocation(int Invoice, decimal Amount, bool WaiveLateCharge = false);
public sealed record SalesPaymentInput(string Customer, DateTime Date, decimal Amount, bool FromUnapplied,
    IReadOnlyList<PaymentAllocation> Allocations);
public sealed record SalesPaymentItem(int Number, int Date, decimal Outstanding, decimal LateCharge);
public sealed record PendingSalesPayment(int Number, int Batch, int Item, decimal Amount, decimal Deducted,
    IReadOnlyList<int> InvoicesWithoutLateCharge);

public sealed partial class SalesLedger
{
    public const string PaymentSortFile = Prefix + "oisort.wrk";

    public string PaymentProof() => db.Atomic(() =>
    {
        var system = SystemRecord();
        if (system.I("S-Flag-P") == 0) throw new SalesRuleException("未転記の入金がありません。");
        var items = db.Scan(OpenItemFile).Select(row => DecodePostingItem(row.Data))
            .Where(item => item.I("type") is not (1 or 3) &&
                (item.I("batchNumber") != 0 || item.I("batchItem") != 0))
            .OrderBy(item => item.I("batchNumber")).ThenBy(item => item.I("batchItem"))
            .ThenByDescending(item => item.I("type")).ThenBy(item => item.I("date"))
            .ThenBy(item => item.I("number")).ToArray();
        db.Recreate(PaymentSortFile);
        var report = new StringBuilder("入金検証帳票\n").AppendLine(GetText(system, "Usera"))
            .AppendLine(ShowDate(system.I("Run-Date")))
            .AppendLine("バッチ／明細　区分　日付　得意先　入金額　消込額　値引額　請求番号　請求日　明細消込額　請求残高");
        var totals = new (decimal Paid, decimal Allocated, decimal Discount)[2];
        string customer = "";
        decimal allocated = 0;
        for (int i = 0; i < items.Length; i++)
        {
            var item = items[i];
            db.Put(PaymentSortFile, (i + 1).ToString("D10", CultureInfo.InvariantCulture), item.B);
            int type = item.I("type");
            if (type == 2 && item.N("paid") != 0 && customer == item.S("customer"))
                report.AppendLine($"　請求書　{item.I("number")}　{ShowDate(item.I("date"))}　{Amount(Math.Min(item.N("paid"), allocated))}　" +
                    $"{Amount(InvoiceAmounts.Sum(item.N) - item.N("paid"))}");
            if (type is not (5 or 6) || item.I("closed") != 0) continue;
            customer = item.S("customer");
            string name = db.Read(CustomerFile, customer) is { } data && data.Length == CustomerLayout.Size
                ? GetText(CustomerLayout.From(data), "name") : "得意先不明";
            allocated = item.N("net");
            totals[type - 5].Paid += item.N("paid");
            totals[type - 5].Allocated += allocated;
            totals[type - 5].Discount += item.N("deductAmount");
            report.AppendLine($"{item.I("batchNumber")}/{item.I("batchItem"):D3}　{OpenItemType(type)}　{ShowDate(item.I("date"))}　{customer}　{name}　" +
                $"{Amount(item.N("paid"))}　{Amount(allocated)}　{Amount(item.N("deductAmount"))}");
        }
        for (int i = 0; i < totals.Length; i++)
        {
            var total = totals[i];
            report.AppendLine($"{OpenItemType(i + 5)}合計　入金額 {Amount(total.Paid)}　消込額 {Amount(total.Allocated)}　" +
                $"未消込額 {Amount(total.Paid - total.Allocated)}　値引額 {Amount(total.Discount)}");
        }
        system.SetN("S-Flag-P", 2);
        system.Set("Oi-3-Flag", "Y");
        SaveSystem(system);
        string body = report.ToString();
        db.AddSpool("prt-1", body);
        return body;
    });

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

    public IReadOnlyList<PendingSalesPayment> PendingPayments(string customer)
    {
        var items = ReadOpenItems(customer);
        return items.Where(item => item.I("type") is 5 or 6 && item.I("closed") == 0 && item.I("batchNumber") != 0)
            .Select(item => new PendingSalesPayment(item.I("number"), item.I("batchNumber"), item.I("batchItem"),
                item.N("paid"), item.N("deductAmount"), items.Where(invoice => SamePaymentBatch(invoice, item) &&
                    invoice.N("deductAmount") == 0).Select(invoice => invoice.I("number")).ToArray())).ToArray();
    }

    public void CancelPayment(string customer, int number, IReadOnlyDictionary<int, decimal> deductions) => db.Atomic(() =>
    {
        var system = SystemRecord();
        if (system.I("S-Flag-P") == 0) throw new SalesRuleException("未転記の入金がありません。");
        var client = CustomerRecord(customer);
        string code = client.S("key");
        string key = OpenItemKey(code, number);
        if (db.Read(OpenItemFile, key) is not { } data)
            throw new SalesRuleException("指定された未転記の入金が見つかりません。");
        var payment = DecodePostingItem(data);
        if (payment.I("type") is not (5 or 6) || payment.I("closed") != 0 || payment.I("batchNumber") == 0)
            throw new SalesRuleException("指定された未転記の入金が見つかりません。");

        decimal remainingAllocation = payment.N("net"), remainingDeduction = payment.N("deductAmount");
        var used = new HashSet<int>();
        foreach (var (invoiceKey, invoiceBytes) in db.Scan(OpenItemFile, code).TakeWhile(r => r.Key.StartsWith(code, StringComparison.Ordinal)))
        {
            var invoice = DecodePostingItem(invoiceBytes);
            if (!SamePaymentBatch(invoice, payment)) continue;
            decimal allocated = invoice.N("creditFor") / 100;
            remainingAllocation -= allocated;
            invoice.SetN("paid", invoice.N("paid") - allocated);
            invoice.SetN("pc", invoice.N("pc") - allocated);
            foreach (string field in new[] { "batchNumber", "batchItem", "creditFor", "closed" }) invoice.SetN(field, 0);
            if (deductions.TryGetValue(invoice.I("number"), out decimal restored))
            {
                if (!ValidPaymentAmount(restored) || restored > remainingDeduction ||
                    invoice.N("deductAmount") != 0 && restored != 0)
                    throw new SalesRuleException("戻す早期支払値引額を確認してください。");
                remainingDeduction -= restored;
                used.Add(invoice.I("number"));
                if (restored != 0) invoice.SetN("deductAmount", restored);
            }
            db.Rewrite(OpenItemFile, invoiceKey, invoice.B);
        }
        if (remainingAllocation != 0 || remainingDeduction != 0 || deductions.Keys.Any(k => !used.Contains(k)))
            throw new SalesRuleException("消込額または早期支払値引額を全額戻せません。");
        db.Delete(OpenItemFile, key);
        if (payment.I("type") == 6)
        {
            client.SetN("unapplied", client.N("unapplied") + payment.N("paid"));
            db.Rewrite(CustomerFile, code, client.B);
        }
        system.Set("Oi-3-Flag", "Y");
        SaveSystem(system);
        return true;
    });

    private static bool SamePaymentBatch(Rec invoice, Rec payment) =>
        invoice.I("type") == 2 && invoice.I("batchNumber") == payment.I("batchNumber") &&
        invoice.I("batchItem") == payment.I("batchItem");

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
