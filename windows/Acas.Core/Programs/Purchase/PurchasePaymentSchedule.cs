using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed record ScheduledPurchaseLine(int Folio, int Period, decimal Amount, string Reference,
    decimal Deduction = 0, int Slot = 1);

public sealed record ScheduledPurchasePayment(string Supplier, int Number, DateTime? Date,
    bool BankTransfer, bool Continues, IReadOnlyList<ScheduledPurchaseLine> Lines,
    int Cheque = 0, int SortCode = 0, int Account = 0, decimal Gross = 0);

public sealed record PurchaseRemittance(string Supplier, string Name, string[] Address, string Date,
    string Method, decimal Amount, IReadOnlyList<ScheduledPurchaseLine> Lines);

public sealed partial class PurchaseLedger
{
    private const string ChequeFile = "ledgers/acas/cheque.dat";
    private static readonly Layout PaymentScheduleLayout = new Layout()
        .X("supplier", 7).BChar("number").X("continuation", 1).BLong("date").BLong("cheque")
        .BLong("sort").BLong("account").C3("gross", 7, 2)
        .Group(9, (layout, i) => layout.BLong("folio" + i).BChar("period" + i)
            .C3("amount" + i, 7, 2).C3("deduction" + i, 3, 2).X("reference" + i, 10));

    public bool PaymentScheduleFileAvailable => database.Exists(PaymentFile);

    public IReadOnlyList<ScheduledPurchasePayment>? ScheduledPayments()
    {
        var rows = database.Scan(PaymentFile);
        if (rows.Any(row => row.Data.Length != PaymentScheduleLayout.Size)) return null;
        return rows.Select(row => ToScheduledPayment(PaymentScheduleLayout.From(row.Data))).ToArray();
    }

    private static ScheduledPurchasePayment ToScheduledPayment(Rec record) =>
        new(record.St("supplier"), record.I("number"), DecodeDate(record.I("date")),
            record.I("sort") != 0, record.S("continuation") == "C",
            Enumerable.Range(1, 9).Where(i => record.N("amount" + i) != 0)
                .Select(i => new ScheduledPurchaseLine(record.I("folio" + i), record.I("period" + i),
                    record.N("amount" + i), record.St("reference" + i), record.N("deduction" + i), i)).ToArray(),
            record.I("cheque"), record.I("sort"), record.I("account"), record.N("gross"));

    public bool CreatePaymentSchedule(int age) => database.ExecuteAtomically(() =>
    {
        var system = System();
        if (age is < 0 or > 99 || system.I("File-Status-29") == 0 || PaymentItems() is not { } records) return false;
        int day = system.I("Run-Date"), cutoff = day - age;
        if (cutoff <= 0) return false;
        int scheduleDate = cutoff;
        var items = records.Select(row => row.Record).ToLookup(record => record.St("supplier"));
        database.Recreate(PaymentFile);
        foreach (var supplier in Suppliers().Where(supplier => supplier.N("current") > 0))
        {
            string code = supplier.St("key");
            var eligible = items[code].Where(record => record.I("type") == 2 && record.I("closed") == 0 &&
                record.I("batchNumber") == 0 && record.S("hold") != "H" && record.I("date") <= cutoff);
            var details = new List<(Rec Item, decimal Amount, decimal Deduction)>();
            int supplierDate = scheduleDate;
            foreach (var item in eligible)
            {
                scheduleDate = item.I("date");
                int days = day - scheduleDate;
                decimal deduction = item.I("discountDays") >= days ? item.N("discountAmount") : 0;
                decimal amount = OpenItemGross(item) - item.N("paid") - deduction;
                if (amount > 0) details.Add((item, amount, deduction));
            }
            var groups = details.Chunk(9).ToArray();
            if (groups.Length > sbyte.MaxValue) return false;
            for (int group = 0; group < groups.Length; group++)
            {
                var next = PaymentScheduleLayout.New();
                int number = group + 1;
                next.Set("supplier", code);
                next.SetN("number", number);
                if (groups[group].Length == 9) next.Set("continuation", "C");
                next.SetN("date", supplierDate);
                next.SetN("sort", supplier.N("sort"));
                if (supplier.I("sort") != 0) next.SetN("account", supplier.N("account"));
                decimal gross = 0;
                int slot = 0;
                foreach (var (item, amount, deduction) in groups[group])
                {
                    slot++;
                    next.SetN("folio" + slot, item.I("folio"));
                    next.SetN("period" + slot, Math.Clamp((day - item.I("date")) / 30 * 30, 0, 90));
                    next.SetN("amount" + slot, amount);
                    next.SetN("deduction" + slot, deduction);
                    next.Set("reference" + slot, item.S("reference"));
                    gross += amount;
                }
                if (!AmountFits(gross, 9999999.99m)) return false;
                next.SetN("gross", gross);
                if (!database.Write(PaymentFile, ScheduleKey(code, number), next.B)) return false;
            }
        }
        system.SetN("Age-To-Pay", age);
        return SaveSystem(system);
    });

    public bool AmendPaymentSchedule(string supplier, int number, IReadOnlyDictionary<int, decimal> amounts) =>
        database.ExecuteAtomically(() =>
        {
            var row = database.Scan(PaymentFile).FirstOrDefault(row => row.Data.Length == PaymentScheduleLayout.Size &&
                PaymentScheduleLayout.From(row.Data) is { } candidate && candidate.St("supplier") == supplier && candidate.I("number") == number);
            if (row.Data is null || GetSupplier(supplier) is null) return false;
            var record = PaymentScheduleLayout.From(row.Data);
            foreach (var (slot, amount) in amounts)
            {
                if (slot is < 1 or > 9 || !AmountFits(amount, 9999999.99m) || record.N("amount" + slot) == 0) return false;
                record.SetN("amount" + slot, amount);
            }
            decimal gross = Enumerable.Range(1, 9).Sum(slot => record.N("amount" + slot));
            if (!AmountFits(gross, 9999999.99m)) return false;
            record.SetN("gross", gross);
            return database.Rewrite(PaymentFile, row.Key, record.B);
        });

    public bool GenerateChequeData(int firstCheque, DateTime date) => database.ExecuteAtomically(() =>
    {
        int day = EncodeDate(date);
        if (firstCheque is < 0 or > 99999999 || day <= 0 || !database.Exists(PaymentFile)) return false;
        var rows = database.Scan(PaymentFile);
        if (rows.Any(row => row.Data.Length != PaymentScheduleLayout.Size)) return false;
        database.Recreate(ChequeFile);
        var system = System();
        string format = system.I("Date-Form") switch { 2 => "MM/dd/yyyy", 3 => "yyyy/MM/dd", _ => "dd/MM/yyyy" };
        int number = firstCheque, index = 0;
        foreach (var (key, bytes) in rows)
        {
            var record = PaymentScheduleLayout.From(bytes);
            decimal gross = record.N("gross");
            if (gross < 0.01m) continue;
            string supplier = record.St("supplier");
            var account = GetSupplier(supplier);
            string[] address = (account?.St("address1") ?? "PL902 Missing data").Split(
                system.S("PL-Delim") is { Length: > 0 } delimiter ? delimiter[0] : '\\');
            bool transfer = record.I("sort") != 0;
            string method = transfer ? "BACS" : number.ToString(CultureInfo.InvariantCulture).PadLeft(9);
            var words = ChequeWords(gross);
            var export = new StringBuilder().Append(Pad(supplier, 7)).Append(',').Append(Pad(account?.St("name") ?? "PL902 Missing data", 30)).Append(',');
            for (int line = 0; line < 5; line++) export.Append(Pad(address.ElementAtOrDefault(line) ?? "", 32)).Append(',');
            export.Append(words.First).Append(',').Append(words.Second).Append(',')
                .Append(EditedAmount(gross)).Append(',').Append(Pad(method, 9)).Append(',')
                .Append(date.ToString(format, CultureInfo.InvariantCulture)).Append(',');
            for (int slot = 1; slot <= 9; slot++)
            {
                int folio = record.I("folio" + slot);
                decimal value = record.N("amount" + slot);
                export.Append(record.S("reference" + slot)).Append(',')
                    .Append(folio == 0 ? new string(' ', 8) : folio.ToString(CultureInfo.InvariantCulture).PadLeft(8)).Append(',')
                    .Append(value == 0 ? new string(' ', 10) : EditedAmount(value)).Append(slot < 9 ? ',' : ' ');
            }
            if (export.Length != 645 || !database.Write(ChequeFile, (++index).ToString("00000000", CultureInfo.InvariantCulture),
                    Encoding.Latin1.GetBytes(export.ToString()))) return false;
            record.SetN("date", day);
            record.SetN("cheque", transfer ? 0 : number++);
            if (number == 100000000) number = 0;
            if (!database.Rewrite(PaymentFile, key, record.B)) return false;
        }
        return true;
    });

    public IReadOnlyList<PurchaseRemittance>? Remittances()
    {
        if (!database.Exists(ChequeFile)) return null;
        var records = database.Scan(ChequeFile);
        if (records.Any(row => row.Data.Length != 645)) return null;
        return records.Select(row =>
        {
            string text = Encoding.Latin1.GetString(row.Data);
            var details = Enumerable.Range(0, 9).Select(i => 366 + i * 31)
                .Where(start => !string.IsNullOrWhiteSpace(text.Substring(start + 20, 10)))
                .Select(start => new ScheduledPurchaseLine(
                    int.Parse(text.AsSpan(start + 11, 8), CultureInfo.InvariantCulture), 0,
                    decimal.Parse(text.AsSpan(start + 20, 10), CultureInfo.InvariantCulture), text.Substring(start, 10).TrimEnd()))
                .ToArray();
            return new PurchaseRemittance(text[..7].TrimEnd(), text.Substring(8, 30).TrimEnd(),
                Enumerable.Range(0, 5).Select(i => text.Substring(39 + i * 33, 32).TrimEnd()).ToArray(),
                text.Substring(355, 10), text.Substring(345, 9).Trim(), decimal.Parse(text.AsSpan(334, 10), CultureInfo.InvariantCulture), details);
        }).ToArray();
    }

    public IReadOnlyList<ScheduledPurchasePayment>? ApplyChequeRegister()
    {
        IReadOnlyList<ScheduledPurchasePayment>? register = null;
        bool ok = database.ExecuteAtomically(() =>
        {
            if (ScheduledPayments() is not { } scheduled || scheduled.Count == 0) return false;
            var system = System();
            int batch = Math.Max(1, system.I("BL-Next-Batch"));
            bool general = GeneralLedgerEnabled;
            if (general)
            {
                int batches = (scheduled.Count + 98) / 99;
                while (batch + batches < short.MaxValue && Enumerable.Range(batch, batches).Any(number =>
                    database.Read(BatchFile, FormattableString.Invariant($"2{number:00000}")) is not null))
                    batch++;
                if (batch + batches >= short.MaxValue) return false;
            }
            var postings = new List<PurchasePayment>();
            int line = 0;
            foreach (var payment in scheduled)
            {
                if (payment.Date is not { } date || GetSupplier(payment.Supplier) is null) return false;
                int day = EncodeDate(date);
                int paymentBatch = batch + (general ? 1 : 0) + line / 999;
                int number = line++ % 999 + 1;
                if (paymentBatch >= short.MaxValue) return false;
                int folio = paymentBatch * 1000 + number;
                decimal applied = 0, deduction = 0;
                foreach (var detail in payment.Lines)
                {
                    string key = OpenItemKey(payment.Supplier, detail.Folio);
                    if (database.Read(OpenItemFile, key) is not { } bytes || bytes.Length != OpenItem.Size) return false;
                    var item = OpenItem.From(bytes);
                    if (item.I("type") != 2 || item.I("closed") != 0 || item.I("batchNumber") != 0) return false;
                    decimal remaining = OpenItemGross(item) - item.N("paid") - detail.Deduction;
                    if (detail.Amount > remaining) return false;
                    item.SetN("paid", item.N("paid") + detail.Amount);
                    if (detail.Amount == remaining)
                    {
                        item.SetN("closed", 1);
                        item.SetN("net", item.N("net") - detail.Deduction);
                        item.SetN("discountAmount", 0);
                        item.SetN("batchNumber", paymentBatch);
                        item.SetN("batchItem", number);
                        item.SetN("dateCleared", day);
                        deduction += detail.Deduction;
                    }
                    applied += detail.Amount;
                    if (!database.Rewrite(OpenItemFile, key, item.B)) return false;
                }
                if (deduction > 999.99m || !AmountFits(applied, 9999999.99m)) return false;
                var record = OpenItem.New();
                record.Set("supplier", payment.Supplier);
                record.SetN("folio", folio);
                record.SetN("date", day);
                record.SetN("dateCleared", day);
                record.SetN("batchNumber", paymentBatch);
                record.SetN("batchItem", number);
                record.SetN("type", 5);
                record.Set("reference", payment.Cheque.ToString("0000000000", CultureInfo.InvariantCulture));
                record.SetN("paid", payment.Gross);
                record.SetN("net", applied);
                record.SetN("discountAmount", deduction);
                if (!database.Write(OpenItemFile, OpenItemKey(payment.Supplier, folio), record.B)) return false;
                postings.Add(ToPayment(record, []) with { Applied = payment.Gross });
            }
            if (general)
            {
                system.SetN("BL-Next-Batch", batch);
                if (!WritePaymentBatches(system, postings)) return false;
            }
            int nextBatch = Math.Max(system.I("BL-Next-Batch"), batch + (general ? 1 : 0) + (line - 1) / 999 + 1);
            if (nextBatch > short.MaxValue) return false;
            system.SetN("BL-Next-Batch", nextBatch);
            database.Recreate(PaymentFile);
            register = scheduled;
            return SaveSystem(system);
        });
        return ok ? register : null;
    }

    private static string ScheduleKey(string supplier, int number) => FormattableString.Invariant($"{supplier}/{number:00}");
    private static string Pad(string text, int width) => text.Length > width ? text[..width] : text.PadRight(width);
    private static string EditedAmount(decimal amount) => amount.ToString("0.00", CultureInfo.InvariantCulture).PadLeft(10);

    private static (string First, string Second) ChequeWords(decimal amount)
    {
        int pounds = (int)amount;
        int pence = (int)((amount - pounds) * 100);
        string first = "";
        if (pounds >= 1000000) first += Words(pounds / 1000000) + " Million ";
        if (pounds / 100000 % 10 != 0) first += Words(pounds / 100000 % 10) + " Hundred and ";
        if (pounds / 1000 % 100 != 0) first += Words(pounds / 1000 % 100) + " Thousand ";
        string second = pounds / 100 % 10 != 0 ? Words(pounds / 100 % 10) + " Hundred and " : "";
        if (pounds % 100 != 0) second += Words(pounds % 100);
        if (pounds != 0) second += " Pounds ";
        second += pence != 0 ? Words(pence) + " Pence " : "ONLY";
        return (first.PadRight(64, '*')[..64], Pad(second, 64));
    }

    private static string Words(int value)
    {
        string[] units = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
            "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
        string[] tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
        return value < 20 ? units[value] : tens[value / 10] + (value % 10 == 0 ? "" : "-" + units[value % 10]);
    }
}
