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
    private static readonly Layout PurchaseParty = PartyLayout(false);
    private static readonly Layout SalesParty = PartyLayout(true);

    private Rec Settings() => db.Read(SystemFile, SystemKey) is { Length: 1024 } data
        ? Layouts.System.From(data) : throw new IrsException("元帳のシステム設定がありません。");

    private static Layout InvoiceLayout(bool sales)
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
            .Comp("deductTax", 3, 2).BChar("days").BLong("creditInvoice").X("dayBook", 1).X("updated", 1);
        return layout.Fill((sales ? 134 : 129) - layout.Size);
    }

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

    private static decimal Net(Rec invoice) => invoice.N("goods") + invoice.N("shipping");
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
        Layout invoices = sales ? SalesInvoice : PurchaseInvoice;
        Layout parties = sales ? SalesParty : PurchaseParty;
        var pending = db.Scan(invoiceFile).Where(x => x.Key.EndsWith("/00", StringComparison.Ordinal))
            .Select(x => (x.Key, Row: Read(invoices, x.Data)))
            .Where(x => x.Row.I("test") == 0 && x.Row.I("type") is >= 1 and <= 3 &&
                (sales ? x.Row.St("printFlags").Contains('L') && x.Row.St("status") is not ("z" or "Z")
                    : x.Row.St("status") is "P" or "p")).ToArray();
        bool toNominal = sys.I("Level-1") == 1 || sys.S("Irs-Instead") == "Y";
        bool toIrs = sys.S("Irs-Instead") == "Y";
        string handoff = (destination == TransferDestination.Shared ? Directory : IrsBookkeeping.Directory) + "postings2irs.dat";
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
        int firstBatch = sys.I("Next-Batch"), relative = sys.I("Postings") + 1, quarter = sys.I("Current-Quarter");
        if (toNominal)
        {
            firstBatch = Math.Max(firstBatch, db.Scan(BatchFile).Select(x => Cob.ToInt(x.Key[1..]) + 1).DefaultIfEmpty(0).Max());
            relative = Math.Max(relative, db.Scan(PostingFile).Select(x => Cob.ToInt(x.Key) + 1).DefaultIfEmpty(0).Max());
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
            string batchKey = (int)ledger + Cob.P9(batchNumber, 5);
            var batch = Layouts.Batch.New();
            batch.SetN("ledger", (int)ledger);
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
                decimal net = Net(invoice), tax = Tax(invoice, sales), gross = net + tax;
                decimal balance = party.N("current") - party.N("unapplied");
                if (type is 1 or 2)
                {
                    int count = party.I("activity");
                    party.SetN("activity", count + 1);
                    party.SetN("average", (count * party.N("average") + invoice.N("goods")) / (count + 1));
                }
                if (quarter is >= 1 and <= 4)
                    party.SetN("quarter" + quarter, party.N("quarter" + quarter) + invoice.N("goods"));
                if (type != 1)
                    party.SetN("current", party.N("current") + gross);
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
                report.AppendLine($"{number}　{invoiceDate:yyyy年M月d日}　{partyKey}　{name}　{names[type]}　{Money(balance)}　{Money(newBalance)}　{Money(net)}　{Money(tax)}　{Money(gross)}");
                legacy.Append(number.ToString(Invariant).PadLeft(8)).Append(' ')
                    .Append(invoiceDate.ToString("dd/MM/yyyy", Invariant)).Append(' ')
                    .Append(partyKey.PadRight(9)).Append(name.PadRight(25)).Append("  ").Append(legacyNames[type].PadRight(9))
                    .Append(PicMoney(balance, 10)).Append(PicMoney(newBalance, 10)).Append(' ', 7)
                    .Append(PicMoney(net, 10)).Append(PicMoney(tax, 10)).Append(PicMoney(gross, 10)).Append('\n');

                invoice.Set("status", "z");
                invoice.Set("updated", sales ? "Z" : "z");
                staged[(invoiceFile, invoiceKey)] = invoice.B;
                string openKey = partyKey + "/" + Cob.P9(number, 8);
                staged[(ItemFile(sales), openKey)] = OpenItem(sales, invoice, batchNumber, itemNumber + 1).B;
                if (!toNominal) continue;
                batchNet += net;
                batchTax += tax;
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
                    IrsRecords.Signed(post, "tax", tax);
                    staged[(handoff, batchKey + "/" + Cob.P9(itemNumber, 5))] =
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
                    post.SetN("vat-amount", tax);
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
        foreach (var ((file, key), data) in staged) db.Put(file, key, data);
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
        legacy.Append('\n');
        var result = new IrsReport(title, report.ToString(), legacy.ToString());
        db.AddSpool(Directory + "prt-1", result.Body);
        return result;
    }

    private static Layout OpenItemLayout(bool sales) => new Layout().X("party", 7).BLong("invoice").BLong("date")
        .N9("batch", 5).N9("item", 3).N9("type", 1).X("description", sales ? 25 : 20).X("held", 1).X("unapplied", 1)
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
        foreach (string field in new[] { "date", "type", "goods", "extra", "shipping", "tax", "discount", "extratax",
            "shippingtax", "deductDays", "deductAmount", "deductTax", "days", "creditInvoice" })
            row.SetN(field, invoice.N(field));
        return row;
    }
}
