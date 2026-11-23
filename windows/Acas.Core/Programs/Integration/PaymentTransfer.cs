using System.Text;
using Acas.Core.Engine;
using Acas.Core.Programs.Irs;

namespace Acas.Core.Programs.Integration;

public sealed partial class LedgerTransfer
{
    private const string PayFile = Directory + "pay.dat";
    private const string ValueFile = Directory + "value.dat";
    private const string BalanceKey = "00000004";

    private static readonly Layout PaymentQueue = new Layout().X("party", 7).BChar("number").X("continuation", 1)
        .BLong("date").BLong("cheque").BLong("sortCode").BLong("account").C3("gross", 7, 2)
        .Group(9, (l, i) => l.BLong("folio" + i).BChar("period" + i)
            .C3("amount" + i, 7, 2).C3("deduction" + i, 3, 2).X("reference" + i, 10));
    private static readonly Layout ValueRecord = new Layout().X("code", 3).Fill(33)
        .Comp("countThis", 5).Comp("countLast", 5).Comp("countYear", 5)
        .C3("amountThis", 8, 2).C3("amountLast", 8, 2).C3("amountYear", 8, 2);
    private static readonly Layout BalanceRecord = new Layout().Fill(42).C3("salesPayments", 8, 2)
        .Fill(54).C3("purchasePayments", 8, 2).Fill(916);

    private sealed record PaymentEntry(DateTime Date, decimal Amount, string Legend);

    public IrsReport TransferPayments(TransferLedger ledger, DateTime date, TransferDestination destination)
    {
        bool sales = ledger == TransferLedger.Sales;
        var sys = Settings();
        string flag = sales ? "S-Flag-P" : "P-Flag-P";
        if (sys.I(flag) != 2) throw new IrsException("転記前に入出金の照合を完了してください。");
        string title = sales ? "売掛入金の転記" : "買掛支払の転記";
        string itemsFile = ItemFile(sales), partiesFile = PartyFile(sales);
        var items = OpenItemLayout(sales);
        var partyLayout = sales ? SalesParty : PurchaseParty;
        var staged = new Dictionary<(string File, string Key), byte[]>();
        var report = new StringBuilder().AppendLine(title)
            .AppendLine("伝票番号　日付　取引先　区分　旧残高　新残高　消込額　控除額　入出金額");
        var totals = new (decimal Applied, decimal Deducted, decimal Paid)[2];
        int deductionCount = 0;

        IEnumerable<PaymentEntry> Prepare()
        {
            foreach (var (key, data) in db.Scan(itemsFile))
            {
                var row = Read(items, data);
                int type = row.I("type"), batch = row.I("batch"), number = row.I("item");
                if (type == 2 && batch != 0 && number != 0)
                {
                    row.SetN("batch", 0);
                    row.SetN("item", 0);
                    row.SetN("creditInvoice", 0);
                    staged[(itemsFile, key)] = row.B;
                    continue;
                }
                if (type is not (5 or 6) || row.I("status") == 1 || (batch == 0 && number == 0)) continue;
                string partyKey = row.S("party");
                var party = ReadStaged(staged, partyLayout, partiesFile, partyKey)
                    ?? throw new IrsException($"取引先 {partyKey} が見つかりません。");
                string name = IrsRecords.Text(party, "name");
                decimal applied = row.N("goods"), paid = row.N("paid"), deducted = row.N("deductAmount");
                decimal oldBalance = party.N("current") - party.N("unapplied");
                decimal current = party.N("current") - applied - deducted;
                party.SetN("current", Math.Max(0, current));
                party.SetN("unapplied", party.N("unapplied") + paid - applied - Math.Min(0, current));
                party.SetN("lastPayment", row.N("date"));
                staged[(partiesFile, partyKey)] = party.B;
                row.SetN("paid", applied);
                row.SetN("status", 1);
                staged[(itemsFile, key)] = row.B;

                var d = DateOf(row.I("date"), date);
                totals[type - 5].Applied += applied;
                totals[type - 5].Paid += paid;
                totals[type - 5].Deducted += deducted;
                if (deducted != 0) deductionCount++;
                string kind = type == 6 ? "貸方振替" : sales ? "入金" : "支払";
                report.AppendLine($"{batch:00000}/{number:000}　{d:yyyy年M月d日}　{partyKey}　{name}　{kind}　" +
                    $"{Money(oldBalance)}　{Money(party.N("current") - party.N("unapplied"))}　{Money(applied)}　{Money(deducted)}　{Money(paid)}");
                string reference = sales ? $"{batch:00000}/{number:000}  :  " : $"{row.I("invoice")} : ";
                yield return new(d, applied, reference + name);
            }
        }

        StagePaymentBatches(staged, sys, date, sales, destination, Prepare());
        ApplyDeductions(staged, sales, deductionCount, totals.Sum(t => t.Deducted));
        var balances = db.Read(SystemFile, BalanceKey) is { } data ? Read(BalanceRecord, data) : BalanceRecord.New();
        string paymentField = sales ? "salesPayments" : "purchasePayments";
        balances.SetN(paymentField, balances.N(paymentField) + totals[0].Paid);
        staged[(SystemFile, BalanceKey)] = balances.B;
        sys.Set(sales ? "Oi-3-Flag" : "Oi-5-Flag", "Y");
        sys.SetN(flag, 0);
        foreach (int i in Enumerable.Range(0, totals.Length))
        {
            var (applied, deducted, paid) = totals[i];
            report.AppendLine($"{(i == 1 ? "貸方振替合計" : sales ? "入金合計" : "支払合計")}　{Money(applied)}　{Money(deducted)}　{Money(paid)}");
        }
        return SavePaymentTransfer(staged, sys, new(title, report.ToString()));
    }

    public IrsReport TransferChequeRegister(DateTime date, TransferDestination destination)
    {
        var sys = Settings();
        if (!db.Exists(PayFile)) throw new IrsException("支払予定ファイルがありません。");
        var staged = new Dictionary<(string File, string Key), byte[]>();
        var items = OpenItemLayout(false);
        string itemFile = ItemFile(false), partyFile = PartyFile(false);
        const string title = "小切手台帳";
        var report = new StringBuilder().AppendLine(title)
            .AppendLine("支払日　仕入先　支払方法　支払額");
        int series = 0, deductionCount = 0;
        decimal total = 0, deductions = 0;

        IEnumerable<PaymentEntry> Prepare()
        {
            if (sys.I("BL-Next-Batch") == 0) sys.SetN("BL-Next-Batch", 1);
            foreach (var (_, data) in db.Scan(PayFile))
            {
                var pay = Read(PaymentQueue, data);
                string partyKey = pay.S("party");
                var party = ReadStaged(staged, PurchaseParty, partyFile, partyKey);
                string name = party is null ? "仕入先不明" : IrsRecords.Text(party, "name");
                if (++series > 999)
                {
                    series = 1;
                    IncrementBatch(sys, "BL-Next-Batch");
                }
                int batch = sys.I("BL-Next-Batch");
                int day = pay.I("date");
                var d = DateOf(day, date);
                decimal applied = 0, deducted = 0;
                for (int i = 1; i <= 9; i++)
                {
                    decimal amount = pay.N("amount" + i);
                    if (amount == 0) continue;
                    string key = OpenItemKey(partyKey, pay.I("folio" + i));
                    var invoice = ReadStaged(staged, items, itemFile, key);
                    if (invoice is null || invoice.I("type") != 2 || invoice.S("party") != partyKey) continue;
                    decimal paid = invoice.N("paid") + amount;
                    decimal discount = pay.N("deduction" + i);
                    invoice.SetN("paid", paid);
                    if (paid == invoice.N("goods") + invoice.N("shipping") + invoice.N("tax") + invoice.N("shippingtax") - discount)
                    {
                        invoice.SetN("status", 1);
                        invoice.SetN("goods", invoice.N("goods") - discount);
                        invoice.SetN("deductAmount", 0);
                        invoice.SetN("batch", batch);
                        invoice.SetN("item", series);
                        invoice.SetN("cleared", day);
                        deducted += discount;
                    }
                    staged[(itemFile, key)] = invoice.B;
                    applied += amount;
                }
                decimal gross = pay.N("gross");
                int number = batch * 1000 + series;
                string paymentKey = OpenItemKey(partyKey, number);
                if (ReadStaged(staged, items, itemFile, paymentKey) is not null)
                    throw new IrsException("支払伝票番号が既に使用されています。");
                var payment = items.New();
                payment.Set("party", partyKey);
                payment.Set("description", pay.I("cheque").ToString("0000000000", Invariant));
                payment.SetN("invoice", number);
                payment.SetN("batch", batch);
                payment.SetN("item", series);
                payment.SetN("date", day);
                payment.SetN("cleared", day);
                payment.SetN("type", 5);
                payment.SetN("paid", gross);
                payment.SetN("goods", applied);
                payment.SetN("deductAmount", deducted);
                staged[(itemFile, paymentKey)] = payment.B;
                if (deducted != 0) deductionCount++;
                deductions += deducted;
                total += gross;
                string method = pay.I("cheque") == 0 ? "口座振込" : $"小切手 {pay.I("cheque")}";
                report.AppendLine($"{d:yyyy年M月d日}　{partyKey}　{name}　{method}　{Money(gross)}");
                yield return new(d, gross, $"{number} : {name}");
            }
            IncrementBatch(sys, "BL-Next-Batch");
        }

        StagePaymentBatches(staged, sys, date, false, destination, Prepare());
        ApplyDeductions(staged, false, deductionCount, deductions);
        report.AppendLine($"支払総額　{Money(total)}");
        return SavePaymentTransfer(staged, sys, new(title, report.ToString()), clearQueue: true);
    }

    private void StagePaymentBatches(Dictionary<(string File, string Key), byte[]> staged, Rec sys,
        DateTime date, bool sales, TransferDestination destination, IEnumerable<PaymentEntry> entries)
    {
        if (sys.I("Level-1") != 1)
        {
            foreach (var _ in entries) { }
            return;
        }
        bool irs = sys.S("Irs-Instead") == "Y";
        string batchField = sales ? "Next-Batch" : "BL-Next-Batch";
        string code = sales ? "SL" : "PL", side = sales ? "CR" : "DR";
        string file = irs ? (destination == TransferDestination.Shared ? Directory : IrsBookkeeping.Directory) + "postings2irs.dat" : PostingFile;
        int ledger = sales ? 3 : 2;
        int debit = sys.I(sales ? "SL-Pay-Ac" : "P-Creditors");
        int credit = sys.I(sales ? "S-Debtors" : "BL-Pay-Ac");
        int batchNumber = 0, count = 0, relative = 0, start = 0;
        int nextRelative = irs ? sys.I("Postings") + 1 : FirstGlPosting(sys);
        int sequence = irs ? IrsSequence(file) : 0;
        decimal total = 0;

        void Open()
        {
            while (db.Read(BatchFile, ledger + Cob.P9(sys.I(batchField), 5)) is not null)
                IncrementBatch(sys, batchField);
            batchNumber = sys.I(batchField);
            IncrementBatch(sys, batchField);
            start = relative = nextRelative;
            count = 0;
            total = 0;
        }

        void Close()
        {
            var batch = Layouts.Batch.New();
            batch.SetN("ledger", ledger);
            batch.SetN("batch-nos", batchNumber);
            batch.SetN("bcycle", sys.I("Cyclea"));
            batch.SetN("entered", DayOf(date));
            batch.Set("description", sales ? "Sales-Ledger Payments" : "Purchase Ledger Payments");
            batch.Set("convention", side);
            batch.Set("batch-def-code", code);
            batch.Set("batch-def-vat", sales ? "O" : "I");
            batch.SetN("batch-start", start);
            batch.SetN("items", count);
            batch.SetN("input-gross", total);
            batch.SetN("actual-gross", total);
            StageNew(staged, BatchFile, ledger + Cob.P9(batchNumber, 5), batch.B);
            if (!irs)
            {
                if (relative > short.MaxValue) throw new IrsException("転記番号を割り当てられません。");
                sys.SetN("Postings", relative);
                nextRelative = relative + 1;
            }
        }

        Open();
        foreach (var entry in entries)
        {
            string legend = IrsRecords.Fit(entry.Legend, 32);
            count++;
            if (irs)
            {
                var posting = IrsRecords.Journal.New();
                posting.SetN("number", count);
                posting.Set("code", code);
                posting.Set("date", IrsRecords.DateText(entry.Date));
                posting.SetN("debit", debit);
                posting.SetN("credit", credit);
                IrsRecords.Signed(posting, "amount", entry.Amount);
                IrsRecords.Text(posting, "legend", legend);
                posting.SetN("taxDefault", sales ? 32 : 31);
                posting.Set("taxSide", side);
                IrsRecords.Signed(posting, "tax", 0);
                string batchKey = Cob.P9(batchNumber, 5);
                StageNew(staged, file, IrsSequenceKey(++sequence), [.. Encoding.ASCII.GetBytes(batchKey), .. posting.B]);
            }
            else
            {
                var posting = Layouts.Posting.New();
                posting.SetN("batch", batchNumber);
                posting.SetN("post-number", count);
                posting.Set("post-code", code);
                posting.Set("post-date", IrsRecords.DateText(entry.Date));
                posting.SetN("post-dr", debit);
                posting.SetN("post-cr", credit);
                posting.SetN("post-amount", entry.Amount);
                posting.Set("post-vat-side", side);
                IrsRecords.Text(posting, "post-legend", legend);
                StageNew(staged, file, Cob.P9(relative++, 8), posting.B);
            }
            total += entry.Amount;
            if (count == 99)
            {
                Close();
                Open();
            }
        }
        Close();
    }

    private void ApplyDeductions(Dictionary<(string File, string Key), byte[]> staged, bool sales, int count, decimal total)
    {
        if (total == 0) return;
        string code = sales ? "Szd" : "Pzb";
        foreach (string key in new[] { code, code[..2] + " " })
        {
            var row = ReadStaged(staged, ValueRecord, ValueFile, key);
            if (row is null) break;
            row.SetN("countThis", row.N("countThis") - count);
            row.SetN("countYear", row.N("countYear") - count);
            row.SetN("amountThis", row.N("amountThis") - total);
            row.SetN("amountYear", row.N("amountYear") - total);
            staged[(ValueFile, key)] = row.B;
        }
    }

    private static string OpenItemKey(string party, int number) => party + "/" + Cob.P9(number, 8);

    private Rec? ReadStaged(Dictionary<(string File, string Key), byte[]> staged, Layout layout, string file, string key) =>
        (staged.GetValueOrDefault((file, key)) ?? db.Read(file, key)) is { } data ? Read(layout, data) : null;

    private void StageNew(Dictionary<(string File, string Key), byte[]> staged, string file, string key, byte[] data)
    {
        if (db.Read(file, key) is not null || !staged.TryAdd((file, key), data))
            throw new IrsException("連携転記番号が既に使用されています。");
    }

    private static void IncrementBatch(Rec system, string field)
    {
        int value = system.I(field);
        if (value is < 0 or >= short.MaxValue) throw new IrsException("伝票番号を割り当てられません。");
        system.SetN(field, value + 1);
    }

    private IrsReport SavePaymentTransfer(Dictionary<(string File, string Key), byte[]> staged, Rec system, IrsReport report,
        bool clearQueue = false)
    {
        staged[(SystemFile, SystemKey)] = system.B;
        db.Atomic(() =>
        {
            foreach (var ((file, key), data) in staged) db.Put(file, key, data);
            if (clearQueue) db.Recreate(PayFile);
            db.AddSpool(Directory + "prt-1", report.Body);
        });
        return report;
    }
}
