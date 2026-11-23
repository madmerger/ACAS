using System.Globalization;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed record PurchasePaymentLine(int Folio, DateTime? Date, decimal Balance, decimal Discount, decimal Applied);

public sealed record PurchasePayment(string Supplier, int Folio, int Batch, int Item, DateTime? Date,
    bool UnappliedCredit, decimal Amount, decimal Applied, decimal Discount, IReadOnlyList<PurchasePaymentLine> Lines,
    decimal? OldBalance = null, decimal? NewBalance = null);

public sealed partial class PurchaseLedger
{
    private const string PaymentSortFile = "ledgers/acas/poisort.wrk";
    private const string IrsPostingFile = "ledgers/acas/postings2irs.dat";
    private static readonly Layout IrsPosting = new Layout().N9("batch", 5).N9("number", 5)
        .X("code", 2).X("date", 8).N9("debit", 5).N9("credit", 5).N9("amount", 7, 2)
        .X("legend", 32).N9("taxAccount", 2).X("taxSide", 2).N9("taxAmount", 7, 2);
    private static readonly Layout PurchaseTotals = new Layout().Fill(102).C3("payments", 8, 2).Fill(916);
    private static string OpenItemKey(string supplier, int folio) => FormattableString.Invariant($"{supplier}/{folio:00000000}");

    public IReadOnlyList<PurchasePaymentLine>? PayableInvoices(string supplier, DateTime date)
    {
        var rows = PaymentItems(supplier);
        return rows?.Select(row => row.Record)
            .Where(item => item.I("type") == 2 && item.I("batchNumber") == 0 && OpenItemGross(item) > item.N("paid"))
            .Select(item => PayableLine(item, date)).ToArray();
    }

    public bool SavePayment(string supplierCode, DateTime date, decimal amount, bool unappliedCredit,
        IReadOnlyDictionary<int, decimal> allocations) => database.ExecuteAtomically(() =>
    {
        var system = System();
        int day = EncodeDate(date);
        int batch = Math.Max(1, system.I("BL-Next-Batch"));
        if (system.I("P-Flag-I") == 1 || system.I("File-Status-29") == 0 || day <= 0 || batch >= short.MaxValue ||
            day < system.I("Start-Date") || day > system.I("End-Date") || amount <= 0 || !AmountFits(amount, 9999999.99m) ||
            allocations.Any(pair => pair.Value <= 0 || !AmountFits(pair.Value, amount)) || allocations.Values.Sum() > amount)
            return false;
        if (GetSupplier(supplierCode) is not { } supplier || (unappliedCredit && supplier.N("unapplied") < amount) ||
            PaymentItems(supplierCode) is not { } rows)
            return false;
        const int number = 1;
        int folio = batch * 1000 + number;
        decimal deduction = 0;
        decimal applied = 0;
        foreach (var row in rows)
        {
            var item = row.Record;
            if (item.I("type") != 2 || item.I("batchNumber") != 0) continue;
            decimal balance = OpenItemGross(item) - item.N("paid");
            if (balance == 0 && item.I("closed") == 0)
            {
                item.SetN("closed", 1);
                item.SetN("dateCleared", day);
                if (!database.Rewrite(OpenItemFile, row.Key, item.B)) return false;
            }
            if (!allocations.TryGetValue(item.I("folio"), out decimal value)) continue;
            var line = PayableLine(item, date);
            if (value > line.Balance || balance <= 0) return false;
            item.SetN("batchNumber", batch);
            item.SetN("batchItem", number);
            item.SetN("paid", item.N("paid") + value);
            item.SetN("pc", item.N("pc") + value);
            item.SetN("creditFolio", value * 100);
            if (value == line.Balance)
            {
                item.SetN("closed", 1);
                item.SetN("dateCleared", day);
                if (line.Discount != 0)
                {
                    item.SetN("net", item.N("net") - line.Discount);
                    item.SetN("discountAmount", 0);
                    deduction += line.Discount;
                }
            }
            applied += value;
            if (!database.Rewrite(OpenItemFile, row.Key, item.B)) return false;
        }
        if (applied != allocations.Values.Sum() || deduction > 999.99m) return false;
        var payment = OpenItem.New();
        payment.Set("supplier", supplierCode);
        payment.SetN("folio", folio);
        payment.SetN("date", day);
        payment.SetN("batchNumber", batch);
        payment.SetN("batchItem", number);
        payment.SetN("type", unappliedCredit ? 6 : 5);
        payment.SetN("paid", amount);
        payment.SetN("net", applied);
        payment.SetN("discountAmount", deduction);
        if (!database.Write(OpenItemFile, OpenItemKey(supplierCode, folio), payment.B)) return false;
        if (unappliedCredit)
        {
            supplier.SetN("unapplied", supplier.N("unapplied") - amount);
            if (!database.Rewrite(SupplierFile, supplierCode, supplier.B)) return false;
        }
        system.SetN("BL-Next-Batch", batch + 1);
        if (!unappliedCredit || system.I("P-Flag-P") == 2) system.SetN("P-Flag-P", 1);
        system.Set("Oi-5-Flag", "Y");
        return SaveSystem(system);
    });

    public bool CancelPayment(string supplier, int folio, IReadOnlyDictionary<int, decimal> restoredDiscounts) =>
        database.ExecuteAtomically(() =>
        {
            var system = System();
            if (system.I("P-Flag-P") == 0 || PaymentItems(supplier) is not { } rows) return false;
            var target = rows.Select(row => row.Record).FirstOrDefault(item => item.I("folio") == folio && PendingPayment(item));
            if (target is null || GetSupplier(supplier) is not { } account) return false;
            decimal restored = 0;
            foreach (var (key, item) in rows.Where(row => row.Record.I("type") == 2 && SamePayment(row.Record, target)))
            {
                decimal amount = item.N("creditFolio") / 100;
                item.SetN("paid", item.N("paid") - amount);
                item.SetN("pc", item.N("pc") - amount);
                item.SetN("batchNumber", 0);
                item.SetN("batchItem", 0);
                item.SetN("creditFolio", 0);
                item.SetN("closed", 0);
                if (restoredDiscounts.TryGetValue(item.I("folio"), out decimal discount))
                {
                    if (item.N("discountAmount") != 0 || !AmountFits(discount, 999.99m)) return false;
                    item.SetN("discountAmount", discount);
                    item.SetN("net", item.N("net") + discount);
                    restored += discount;
                }
                if (!database.Rewrite(OpenItemFile, key, item.B)) return false;
            }
            if (restored != target.N("discountAmount") || restored != restoredDiscounts.Values.Sum()) return false;
            if (target.I("type") == 6)
            {
                decimal credit = account.N("unapplied") + target.N("paid");
                if (!AmountFits(credit, 99999999.99m)) return false;
                account.SetN("unapplied", credit);
                if (!database.Rewrite(SupplierFile, supplier, account.B)) return false;
            }
            if (!database.Delete(OpenItemFile, OpenItemKey(supplier, folio))) return false;
            system.SetN("P-Flag-P", 1);
            return SaveSystem(system);
        });

    public IReadOnlyList<PurchasePayment>? Payments()
    {
        var rows = PaymentItems();
        return rows?.Select(row => row.Record).Where(PendingPayment).OrderBy(item => item.I("batchNumber"))
            .ThenBy(item => item.I("batchItem")).Select(item => ToPayment(item, rows)).ToArray();
    }

    public IReadOnlyList<PurchasePayment>? ProvePayments()
    {
        IReadOnlyList<PurchasePayment>? result = null;
        bool ok = database.ExecuteAtomically(() =>
        {
            var system = System();
            if (system.I("P-Flag-P") == 0 || PaymentItems() is not { } rows) return false;
            var sorted = rows.Select(row => row.Record).Where(item => item.I("type") is not (1 or 3) &&
                    (item.I("batchNumber") != 0 || item.I("batchItem") != 0))
                .OrderBy(item => item.I("batchNumber")).ThenBy(item => item.I("batchItem")).ThenByDescending(item => item.I("type"))
                .ThenBy(item => item.I("date")).ThenBy(item => item.I("folio")).ToArray();
            database.Recreate(PaymentSortFile);
            for (int i = 0; i < sorted.Length; i++)
                if (!database.Write(PaymentSortFile, (i + 1).ToString("00000000", CultureInfo.InvariantCulture), sorted[i].B))
                    return false;
            result = sorted.Where(PendingPayment).Select(item => ToPayment(item, rows)).ToArray();
            system.SetN("P-Flag-P", 2);
            system.Set("Oi-5-Flag", "Y");
            return SaveSystem(system);
        });
        return ok ? result : null;
    }

    public bool PaymentsVerified => System().I("P-Flag-P") == 2;

    public IReadOnlyList<PurchasePayment>? PostPayments()
    {
        List<PurchasePayment> posted = [];
        bool ok = database.ExecuteAtomically(() =>
        {
            var system = System();
            if (system.I("P-Flag-P") != 2 || PaymentItems() is not { } rows) return false;
            foreach (var (key, item) in rows)
            {
                if (item.I("type") == 2 && item.I("batchNumber") != 0 && item.I("batchItem") != 0)
                {
                    item.SetN("batchNumber", 0);
                    item.SetN("batchItem", 0);
                    item.SetN("creditFolio", 0);
                    if (!database.Rewrite(OpenItemFile, key, item.B)) return false;
                }
                else if (PendingPayment(item))
                {
                    string code = item.St("supplier");
                    if (GetSupplier(code) is not { } supplier) return false;
                    decimal paid = item.N("paid");
                    decimal applied = item.N("net");
                    decimal old = supplier.N("current") - supplier.N("unapplied");
                    decimal balance = supplier.N("current") - applied - item.N("discountAmount");
                    decimal unapplied = supplier.N("unapplied") + paid - applied + Math.Max(0, -balance);
                    if (!AmountFits(unapplied, 99999999.99m)) return false;
                    supplier.SetN("current", Math.Max(0, balance));
                    supplier.SetN("unapplied", unapplied);
                    supplier.SetN("lastPayment", item.I("date"));
                    var detail = ToPayment(item, []) with { OldBalance = old, NewBalance = Math.Max(0, balance) - unapplied };
                    posted.Add(detail);
                    item.SetN("paid", applied);
                    item.SetN("closed", 1);
                    if (!database.Rewrite(SupplierFile, code, supplier.B) || !database.Rewrite(OpenItemFile, key, item.B))
                        return false;
                }
            }
            if (GeneralLedgerEnabled && !WritePaymentBatches(system, posted)) return false;
            const string totalsKey = "00000004";
            if (database.Read(SystemFile, totalsKey) is { } data && data.Length == PurchaseTotals.Size)
            {
                var totals = PurchaseTotals.From(data);
                decimal paid = totals.N("payments") + posted.Where(payment => !payment.UnappliedCredit).Sum(payment => payment.Amount);
                if (Math.Abs(paid) > 99999999.99m) return false;
                totals.SetN("payments", paid);
                if (!database.Rewrite(SystemFile, totalsKey, totals.B)) return false;
            }
            system.SetN("P-Flag-P", 0);
            system.Set("Oi-5-Flag", "Y");
            return SaveSystem(system);
        });
        return ok ? posted : null;
    }

    private bool WritePaymentBatches(Rec system, List<PurchasePayment> posted)
    {
        int batch = Math.Max(1, system.I("BL-Next-Batch"));
        int start = system.I("Postings") + 1;
        bool irs = system.S("Irs-Instead") == "Y";
        if (posted.Count == 0) return true;
        foreach (var group in posted.Chunk(99))
        {
            if (batch >= short.MaxValue || (!irs && start + group.Length > short.MaxValue)) return false;
            decimal total = group.Sum(item => item.Applied);
            if (!AmountFits(total, 99999999.99m)) return false;
            for (int i = 0; i < group.Length; i++)
            {
                var item = group[i];
                if (GetSupplier(item.Supplier) is not { } supplier) return false;
                if (irs)
                {
                    if (!WriteIrsPayment(system, item, supplier, batch, i + 1)) return false;
                    continue;
                }
                var record = Layouts.Posting.New();
                record.SetN("batch", batch);
                record.SetN("post-number", i + 1);
                record.Set("post-code", "PL");
                record.Set("post-date", item.Date?.ToString("dd/MM/yy", CultureInfo.InvariantCulture) ?? "");
                record.SetN("post-dr", system.N("P-Creditors"));
                record.SetN("post-cr", system.N("BL-Pay-Ac"));
                record.SetN("post-amount", item.Applied);
                record.Set("post-legend", $"{item.Folio} : {supplier.St("name")}");
                record.Set("post-vat-side", "DR");
                if (!database.Write(PostingFile, (start + i).ToString("00000000", CultureInfo.InvariantCulture), record.B))
                    return false;
            }
            var header = Layouts.Batch.New();
            header.SetN("ledger", 2);
            header.SetN("batch-nos", batch);
            header.SetN("items", group.Length);
            header.SetN("bcycle", system.N("Cyclea"));
            header.SetN("entered", system.N("Run-Date"));
            header.SetN("input-gross", total);
            header.SetN("actual-gross", total);
            header.Set("description", "Purchase Ledger Payments");
            header.Set("convention", "DR");
            header.Set("batch-def-code", "PL");
            header.Set("batch-def-vat", "I");
            header.SetN("batch-start", start);
            if (!database.Write(BatchFile, "2" + batch.ToString("00000", CultureInfo.InvariantCulture), header.B)) return false;
            if (!irs) start += group.Length;
            batch++;
        }
        if (!irs) system.SetN("Postings", start);
        system.SetN("BL-Next-Batch", batch);
        return true;
    }

    private bool WriteIrsPayment(Rec system, PurchasePayment payment, Rec supplier, int batch, int number)
    {
        var record = IrsPosting.New();
        record.SetN("batch", batch);
        record.SetN("number", number);
        record.Set("code", "PL");
        record.Set("date", payment.Date?.ToString("dd/MM/yy", CultureInfo.InvariantCulture) ?? "");
        record.SetN("debit", system.N("P-Creditors"));
        record.SetN("credit", system.N("BL-Pay-Ac"));
        record.SetN("amount", payment.Applied);
        record.Set("legend", $"{payment.Folio} : {supplier.St("name")}");
        record.SetN("taxAccount", 31);
        record.Set("taxSide", "DR");
        return database.Write(IrsPostingFile, FormattableString.Invariant($"{batch:00000}{number:00000}"), record.B);
    }

    private List<(string Key, Rec Record)>? PaymentItems(string? supplier = null)
    {
        List<(string, Rec)> rows = [];
        string prefix = supplier == null ? "" : supplier + "/";
        foreach (var (key, bytes) in database.Scan(OpenItemFile, prefix))
        {
            if (!key.StartsWith(prefix, StringComparison.Ordinal)) break;
            if (bytes.Length != OpenItem.Size) return null;
            rows.Add((key, OpenItem.From(bytes)));
        }
        return rows;
    }

    private static PurchasePaymentLine PayableLine(Rec item, DateTime date)
    {
        decimal balance = OpenItemGross(item) - item.N("paid");
        decimal discount = item.I("date") + item.I("discountDays") >= EncodeDate(date) ? item.N("discountAmount") : 0;
        discount = Math.Clamp(discount, 0, balance);
        return new(item.I("folio"), DecodeDate(item.I("date")), balance - discount, discount, 0);
    }

    private static bool PendingPayment(Rec item) => item.I("type") is 5 or 6 && item.I("closed") == 0 && item.I("batchNumber") != 0;
    private static bool SamePayment(Rec invoice, Rec payment) => invoice.St("supplier") == payment.St("supplier") &&
        invoice.I("batchNumber") == payment.I("batchNumber") && invoice.I("batchItem") == payment.I("batchItem");

    private static PurchasePayment ToPayment(Rec item, List<(string Key, Rec Record)> rows) =>
        new(item.St("supplier"), item.I("folio"), item.I("batchNumber"), item.I("batchItem"), DecodeDate(item.I("date")),
            item.I("type") == 6, item.N("paid"), item.N("net"), item.N("discountAmount"), rows.Select(row => row.Record)
                .Where(line => line.I("type") == 2 && SamePayment(line, item))
                .Select(line => new PurchasePaymentLine(line.I("folio"), DecodeDate(line.I("date")),
                    OpenItemGross(line) - line.N("paid"), line.N("discountAmount"), line.N("creditFolio") / 100))
                .OrderBy(line => line.Date).ThenBy(line => line.Folio).ToArray());
}
