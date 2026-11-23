using System.Globalization;
using System.Text;
using Acas.Core.Engine;
using Acas.Core.Programs.Irs;

namespace Acas.Core.Programs.Integration;

public enum TransferLedger { Sales = 1, Purchases = 2 }
public enum TransferDestination { Dedicated, Shared }

public sealed partial class LedgerTransfer(Db db)
{
    private const string Directory = "ledgers/acas/";
    private const string SystemFile = Directory + "system.dat";
    private const string SystemKey = "00000001";
    private const string BatchFile = Directory + "batch.dat";
    private const string PostingFile = Directory + "posting.dat";
    private static readonly DateTime Epoch = new(1600, 12, 31);
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;
    private static readonly Layout PurchaseInvoice = InvoiceLayout(false);
    private static readonly Layout SalesInvoice = InvoiceLayout(true);
    private static readonly Layout SalesInvoiceWithReference = InvoiceLayout(true, includeReference: true);
    private static readonly Layout PurchaseParty = PartyLayout(false);
    private static readonly Layout SalesParty = PartyLayout(true);
    private static readonly Layout SalesCreditDeductions = new Layout().Fill(30).C3("deductions", 8, 2).Fill(988);

    private Rec Settings() => db.Read(SystemFile, SystemKey) is { Length: 1024 } data
        ? Layouts.System.From(data) : throw new IrsException("元帳のシステム設定がありません。");

    private static Layout InvoiceLayout(bool sales, bool includeReference = false)
    {
        var layout = new Layout().N9("number", 8);
        if (sales) layout.X("letter", 1);
        layout.BChar("test").X("party", 7).BLong("date").X("order", 10).N9("type", 1).X("reference", 10);
        if (sales) layout.X("description", 32);
        layout.C3("current", 7, 2).C3("goods", 7, 2).C3("extra", 7, 2).C3("shipping", 7, 2)
            .C3("tax", 7, 2).C3("discount", 7, 2).C3("extratax", 7, 2).C3("shippingtax", 7, 2)
            .X("status", 1);
        if (sales) layout.X("printFlags", 5);
        layout.BChar("lines").BChar("deductDays").Comp("deductAmount", 3, 2)
            .Comp("deductTax", 3, 2).BChar("days");
        if (!sales || includeReference) layout.BLong("creditInvoice").X("dayBook", 1).X("updated", 1);
        return layout.Fill((sales ? includeReference ? 140 : 134 : 129) - layout.Size);
    }

    private static Rec ReadInvoice(bool sales, byte[] data) => Read(!sales ? PurchaseInvoice :
        data.Length == SalesInvoiceWithReference.Size ? SalesInvoiceWithReference : SalesInvoice, data);

    private static Layout PartyLayout(bool sales)
    {
        var layout = new Layout().X("key", 7);
        if (!sales) layout.N9("status", 1).Fill(1);
        layout.X("name", 30).Fill(sales ? 160 : 171);
        if (sales) layout.N9("status", 1).Fill(22);
        layout.BLong("activity").BLong("lastInvoice").BLong("lastPayment").BLong("average").Fill(16)
            .C3("current", 8, 2).C3("last", 8, 2)
            .Group(4, (l, i) => l.C3("quarter" + i, 8, 2)).C3("unapplied", 8, 2);
        return layout.Fill(300 - layout.Size);
    }

    private static Rec Read(Layout layout, byte[] data)
    {
        if (data.Length != layout.Size) throw new IrsException("レコード長が一致しません（状態番号39）。");
        return layout.From(data);
    }

    private static string InvoiceFile(bool sales) => Directory + (sales ? "invoice.dat" : "pinvoice.dat");
    private static string PartyFile(bool sales) => Directory + (sales ? "salesled.dat" : "purchled.dat");
    private static string ItemFile(bool sales) => Directory + (sales ? "openitm3.dat" : "openitm5.dat");
    private static string TransferTitle(bool sales) => sales ? "売掛請求の転記" : "買掛請求の転記";
    private int FirstGlPosting(Rec system)
    {
        int last = db.Scan(PostingFile).Select(row => Cob.ToInt(row.Key)).DefaultIfEmpty(0).Max();
        return Math.Max(system.I("Postings") + 1, last == 0 ? 1 : last + 2);
    }

    private int IrsSequence(string file) => db.Scan(file, "~").Select(row => Cob.ToInt(row.Key[1..])).DefaultIfEmpty(0).Max();
    private static string IrsSequenceKey(int sequence) => "~" + Cob.P9(sequence, 8);

    private static decimal Net(Rec invoice, bool sales) => invoice.N("goods") + invoice.N("shipping") +
        (sales ? invoice.N("extra") + invoice.N("discount") + invoice.N("deductAmount") : 0);
    private static decimal Tax(Rec invoice, bool sales) => invoice.N("tax") + invoice.N("shippingtax") +
        (sales ? invoice.N("extratax") : 0);
    private static DateTime DateOf(int day, DateTime fallback) =>
        day > 0 && day <= (DateTime.MaxValue.Date - Epoch).Days ? Epoch.AddDays(day) : fallback;
    private static int DayOf(DateTime date) => (date.Date - Epoch).Days;
    private static string Money(decimal value) => value.ToString("0.00", Invariant);
    private static string PicMoney(decimal value, int width) => Money(Math.Abs(value)).PadLeft(width) + (value < 0 ? "CR" : "  ");

    public IrsReport TransferInvoices(TransferLedger ledger, DateTime date, TransferDestination destination)
    {
        var sys = Settings();
        bool sales = ledger == TransferLedger.Sales;
        string title = TransferTitle(sales);
        string invoiceFile = InvoiceFile(sales), partyFile = PartyFile(sales);
        Layout parties = sales ? SalesParty : PurchaseParty;
        var pending = db.Scan(invoiceFile).Where(x => x.Key.EndsWith("/00", StringComparison.Ordinal))
            .Select(x => (x.Key, Row: ReadInvoice(sales, x.Data)))
            .Where(x => x.Row.I("test") == 0 && x.Row.I("type") is >= 1 and <= 3 &&
                (sales ? x.Row.St("printFlags").Contains('L') && x.Row.St("status") is not ("z" or "Z")
                    : x.Row.St("status") is "P" or "p")).ToArray();
        bool toNominal = sys.I("Level-1") == 1 || sys.S("Irs-Instead") == "Y";
        bool toIrs = sys.S("Irs-Instead") == "Y";
        string handoff = (destination == TransferDestination.Shared ? Directory : IrsBookkeeping.Directory) + "postings2irs.dat";
        int sequence = toIrs ? IrsSequence(handoff) : 0;
        var staged = new Dictionary<(string File, string Key), byte[]>();
        var report = new StringBuilder().AppendLine(title).AppendLine($"{IrsRecords.Text(sys, "Usera")}　{date:yyyy年M月d日}")
            .AppendLine("番号　日付　取引先　区分　旧残高　新残高　税抜額　付加価値税　合計");
        var legacy = new StringBuilder()
            .Append((sales ? "SL060 (3.01.14)" : "PL060 (3.01.07)").PadRight(54))
            .Append("Invoice Posting Report".PadRight(70)).Append("Page   1\n")
            .Append(IrsRecords.Text(sys, "Usera").PadRight(122)).Append(date.ToString("dd/MM/yyyy", Invariant)).Append("\n\n")
            .Append(" Number     Date    <------------Supplier------------>    Type  ".PadRight(64))
            .Append(" Old Balance  New Balance            Net         Vat       Gross\n\n");
        var totals = new (decimal Net, decimal Tax)[4];
        decimal totalDeductions = 0;
        int deductionCount = 0;
        int batchLedger = sales ? 3 : 2;
        int firstBatch = sys.I("Next-Batch"), relative = sys.I("Postings") + 1, quarter = sys.I("Current-Quarter");
        if (toNominal)
        {
            firstBatch = Math.Max(firstBatch, db.Scan(BatchFile)
                .Where(x => x.Key.StartsWith(batchLedger.ToString(Invariant), StringComparison.Ordinal))
                .Select(x => Cob.ToInt(x.Key[1..]) + 1).DefaultIfEmpty(1).Max());
            if (!toIrs) relative = FirstGlPosting(sys);
        }
        string marker = sales ? "SL" : "PL";
        string[] names = ["", "入金", "請求書", "貸方票"];
        string[] legacyNames = ["", "Receipt", "Invoice", "Cr. Note"];
        if (toNominal && (firstBatch <= 0 || relative <= 0 || firstBatch + pending.Length / 99 + 1 > short.MaxValue))
            throw new IrsException("転記番号を割り当てられません。");
        int debit = sys.I(sales ? "S-Debtors" : "BL-Purch-Ac");
        int credit = sys.I(sales ? "SL-Sales-Ac" : "P-Creditors");
        int batchCount = toNominal ? pending.Length / 99 + 1 : 0;
        for (int batchIndex = 0; batchIndex < Math.Max(batchCount, 1); batchIndex++)
        {
            int batchNumber = firstBatch + batchIndex;
            string batchKey = batchLedger + Cob.P9(batchNumber, 5);
            var batch = Layouts.Batch.New();
            batch.SetN("ledger", batchLedger);
            batch.SetN("batch-nos", batchNumber);
            batch.SetN("bcycle", sys.I("Cyclea"));
            batch.SetN("entered", DayOf(date));
            batch.Set("description", sales ? "Sales Ledger Invoices" : "Purchase Ledger Invoices");
            batch.Set("convention", sales ? "CR" : "DR");
            batch.Set("batch-def-code", marker);
            batch.Set("batch-def-vat", sales ? "O" : "I");
            batch.SetN("batch-start", relative);
            decimal batchNet = 0, batchTax = 0;
            int itemNumber = 0;
            var rows = toNominal ? pending.Skip(batchIndex * 99).Take(99) : pending.AsEnumerable();
            foreach (var (invoiceKey, invoice) in rows)
            {
                int type = invoice.I("type"), number = invoice.I("number");
                DateTime invoiceDate = DateOf(invoice.I("date"), date);
                string partyKey = invoice.S("party");
                var party = staged.TryGetValue((partyFile, partyKey), out var modified) ? Read(parties, modified)
                    : db.Read(partyFile, partyKey) is { } bytes ? Read(parties, bytes)
                    : throw new IrsException($"取引先 {partyKey} が見つかりません。");
                string name = IrsRecords.Text(party, "name");
                var openItem = OpenItem(sales, invoice, batchNumber, itemNumber + 1);
                decimal net = Net(openItem, sales), postingTax = Tax(openItem, sales);
                decimal tax = postingTax + (sales ? openItem.N("deductTax") : 0), gross = net + tax;
                decimal goods = openItem.N("goods") + (sales ? openItem.N("extra") : 0);
                decimal balance = party.N("current") - party.N("unapplied");
                if (type is 1 or 2)
                {
                    int count = party.I("activity");
                    party.SetN("activity", count + 1);
                    party.SetN("average", (count * party.N("average") + goods) / (count + 1));
                }
                if (quarter is >= 1 and <= 4)
                    party.SetN("quarter" + quarter, party.N("quarter" + quarter) + goods);
                if (type != 1)
                    party.SetN("current", party.N("current") + gross);
                decimal deduction = 0;
                if (type == 3)
                {
                    deduction = ApplyCredit(staged, sales, openItem, Math.Abs(gross), out int clearedDeductions);
                    party.SetN("current", party.N("current") - deduction);
                    totalDeductions += deduction;
                    deductionCount += clearedDeductions;
                }
                if (type is 1 or 2) party.SetN("lastInvoice", invoice.I("date"));
                if (type is 1 or 3) party.SetN("lastPayment", invoice.I("date"));
                if (party.N("current") < 0)
                {
                    party.SetN("unapplied", party.N("unapplied") - party.N("current"));
                    party.SetN("current", 0);
                }
                party.SetN("status", 1);
                staged[(partyFile, partyKey)] = party.B;

                decimal newBalance = party.N("current") - party.N("unapplied");
                totals[type].Net += net;
                totals[type].Tax += tax;
                report.AppendLine($"{number}　{invoiceDate:yyyy年M月d日}　{partyKey}　{name}　{names[type]}　{Money(balance)}　{Money(newBalance)}　{Money(net)}　{Money(tax)}　{Money(gross)}" +
                    (deduction == 0 ? "" : $"　延滞加算免除 {Money(deduction)}"));
                legacy.Append(number.ToString(Invariant).PadLeft(8)).Append(' ')
                    .Append(invoiceDate.ToString("dd/MM/yyyy", Invariant)).Append(' ')
                    .Append(partyKey.PadRight(9)).Append(name.PadRight(25)).Append("  ").Append(legacyNames[type].PadRight(9))
                    .Append(PicMoney(balance, 10)).Append(PicMoney(newBalance, 10))
                    .Append(deduction == 0 ? new string(' ', 7) : Money(deduction).PadLeft(7))
                    .Append(PicMoney(net, 10)).Append(PicMoney(tax, 10)).Append(PicMoney(gross, 10)).Append('\n');

                invoice.Set("status", "z");
                if (!sales) invoice.Set("updated", "z");
                staged[(invoiceFile, invoiceKey)] = invoice.B;
                staged[(ItemFile(sales), OpenItemKey(partyKey, number))] = openItem.B;
                if (!toNominal) continue;
                batchNet += net;
                batchTax += postingTax;
                string legend = $"{number} : {name}";
                legend = IrsRecords.Fit(legend, 32);
                itemNumber++;
                if (toIrs)
                {
                    var post = IrsRecords.Journal.New();
                    post.SetN("number", itemNumber);
                    post.Set("code", marker);
                    post.Set("date", IrsRecords.DateText(date));
                    post.SetN("debit", debit);
                    post.SetN("credit", credit);
                    IrsRecords.Signed(post, "amount", net);
                    IrsRecords.Text(post, "legend", legend);
                    post.SetN("taxDefault", sales ? 32 : 31);
                    post.Set("taxSide", sales ? "CR" : "DR");
                    IrsRecords.Signed(post, "tax", postingTax);
                    staged[(handoff, IrsSequenceKey(++sequence))] =
                        [.. Encoding.ASCII.GetBytes(Cob.P9(batchNumber, 5)), .. post.B];
                }
                else
                {
                    var post = Layouts.Posting.New();
                    post.SetN("batch", batchNumber);
                    post.SetN("post-number", itemNumber);
                    post.Set("post-code", marker);
                    post.Set("post-date", IrsRecords.DateText(date));
                    post.SetN("post-dr", debit);
                    post.SetN("post-cr", credit);
                    post.SetN("vat-ac", sys.I("Vat-Ac"));
                    post.SetN("post-amount", net);
                    post.SetN("vat-amount", postingTax);
                    post.Set("post-vat-side", sales ? "CR" : "DR");
                    IrsRecords.Text(post, "post-legend", legend);
                    string postKey = Cob.P9(relative++, 8);
                    if (db.Read(PostingFile, postKey) is not null) throw new IrsException("連携転記番号が既に使用されています。");
                    staged[(PostingFile, postKey)] = post.B;
                }
            }
            if (!toNominal) continue;
            if (db.Read(BatchFile, batchKey) is not null) throw new IrsException("連携伝票番号が既に使用されています。");
            batch.SetN("items", itemNumber);
            foreach (string kind in new[] { "input", "actual" })
            {
                batch.SetN(kind + "-gross", batchNet);
                batch.SetN(kind + "-vat", batchTax);
            }
            staged[(BatchFile, batchKey)] = batch.B;
            if (!toIrs && batchIndex < batchCount - 1) relative++;
        }
        if (toNominal && !toIrs && relative > short.MaxValue)
            throw new IrsException("転記番号を割り当てられません。");
        if (totalDeductions != 0)
        {
            const string balanceKey = "00000004";
            var balances = ReadStaged(staged, SalesCreditDeductions, SystemFile, balanceKey) ?? SalesCreditDeductions.New();
            balances.SetN("deductions", balances.N("deductions") + totalDeductions);
            staged[(SystemFile, balanceKey)] = balances.B;
            ApplyDeductions(staged, true, deductionCount, totalDeductions);
            report.AppendLine($"延滞加算免除合計　{Money(totalDeductions)}");
        }
        foreach (int type in Enumerable.Range(1, 3))
        {
            var (net, tax) = totals[type];
            report.AppendLine($"転記合計　{names[type]}　{Money(net)}　{Money(tax)}　{Money(net + tax)}");
            string label = type == 3 ? "Credit Notes" : legacyNames[type] + "s";
            legacy.Append(type == 1 ? "\n\n           Total  Posted " : "\n           Total  Posted ")
                .Append(label.PadRight(18))
                .Append(PicMoney(net, 11)).Append(PicMoney(tax, 11)).Append(PicMoney(net + tax, 11));
            legacy.Append('\n');
        }
        if (totalDeductions != 0)
            legacy.Append("           Total  Amount Late Deductions").Append(PicMoney(totalDeductions, 11)).Append('\n');
        legacy.Append('\n');
        var result = new IrsReport(title, report.ToString(), legacy.ToString());
        db.Atomic(() =>
        {
            foreach (var ((file, key), data) in staged) db.Put(file, key, data);
            db.AddSpool(Directory + "prt-1", result.Body);
        });
        return result;
    }

    private static Layout OpenItemLayout(bool sales) => new Layout().X("party", 7).BLong("invoice").BLong("date")
        .Comp("batch", 5).Comp("item", 3).N9("type", 1).X("description", sales ? 25 : 20).X("held", 1).X("unapplied", 1)
        .C3("current", 7, 2).C3("goods", 7, 2).C3("extra", 7, 2).C3("shipping", 7, 2).C3("tax", 7, 2)
        .C3("discount", 7, 2).C3("extratax", 7, 2).C3("shippingtax", 7, 2).C3("paid", 7, 2)
        .N9("status", 1).BChar("deductDays").Comp("deductAmount", 3, 2, true)
        .Comp("deductTax", 3, 2, true).BChar("days").BLong("creditInvoice").X("applied", 1).BLong("cleared");

    private static Rec OpenItem(bool sales, Rec invoice, int batch, int item)
    {
        var row = OpenItemLayout(sales).New();
        row.Set("party", invoice.S("party"));
        row.Set("description", sales ? invoice.S("description")[..25] : invoice.S("reference") + invoice.S("order"));
        row.SetN("invoice", invoice.N("number"));
        row.SetN("batch", batch);
        row.SetN("item", item);
        foreach (string field in new[] { "date", "type", "deductDays", "days" })
            row.SetN(field, invoice.N(field));
        foreach (string field in new[] { "goods", "shipping", "tax", "shippingtax" })
            row.SetN(field, row.I("type") == 3 ? -invoice.N(field) : invoice.N(field));
        foreach (string field in new[] { "extra", "discount", "extratax", "deductAmount", "deductTax" })
            row.SetN(field, sales && row.I("type") == 3 ? -invoice.N(field) : invoice.N(field));
        if (invoice.L.F.ContainsKey("creditInvoice")) row.SetN("creditInvoice", invoice.I("creditInvoice"));
        return row;
    }

    private decimal ApplyCredit(Dictionary<(string File, string Key), byte[]> staged, bool sales, Rec credit, decimal remaining,
        out int deductionsCleared)
    {
        string file = ItemFile(sales), prefix = credit.S("party") + "/";
        string reference = OpenItemKey(credit.S("party"), credit.I("creditInvoice"));
        var layout = OpenItemLayout(sales);
        var keys = db.Scan(file, prefix).Select(row => row.Key)
            .Concat(staged.Keys.Where(x => x.File == file).Select(x => x.Key))
            .Distinct(StringComparer.Ordinal).Where(k => k.StartsWith(prefix, StringComparison.Ordinal))
            .OrderBy(k => k != reference).ThenBy(k => k, StringComparer.Ordinal).ToArray();
        decimal deducted = 0;
        deductionsCleared = 0;
        foreach (string key in keys)
        {
            if (remaining == 0) break;
            var invoice = ReadStaged(staged, layout, file, key)!;
            if (invoice.I("type") != 2 || invoice.I("status") == 1) continue;
            decimal outstanding = Net(invoice, sales) + Tax(invoice, sales) - invoice.N("paid") +
                (sales ? invoice.N("deductTax") : 0);
            if (outstanding < 0) continue;
            decimal deduction = sales && invoice.I("date") + 1 + invoice.I("deductDays") > credit.I("date")
                ? invoice.N("deductAmount") + invoice.N("deductTax") : 0;
            decimal applied = Math.Min(remaining, Math.Max(0, outstanding - deduction));
            invoice.SetN("paid", invoice.N("paid") + applied);
            invoice.SetN("current", invoice.N("current") + applied);
            credit.SetN("paid", credit.N("paid") + applied);
            remaining -= applied;
            if (applied == outstanding - deduction)
            {
                invoice.SetN("status", 1);
                if (deduction > 0)
                {
                    invoice.SetN("deductAmount", 0);
                    invoice.SetN("deductTax", 0);
                    deducted += deduction;
                    deductionsCleared++;
                }
            }
            staged[(file, key)] = invoice.B;
        }
        if (remaining == 0) credit.SetN("status", 1);
        return deducted;
    }
}
