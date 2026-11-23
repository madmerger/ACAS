using System.Globalization;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed partial class PurchaseLedger
{
    private const string BatchFile = "ledgers/acas/batch.dat";
    private const string PostingFile = "ledgers/acas/posting.dat";
    private const string OpenItemFile = "ledgers/acas/openitm5.dat";
    private static readonly Layout OpenItem = new Layout().X("supplier", 7).BLong("folio").BLong("date")
        .Comp("batchNumber", 5).Comp("batchItem", 3).N9("type", 1).X("reference", 10).X("order", 10).X("hold", 1)
        .X("unapplied", 1).C3("pc", 7, 2).C3("net", 7, 2).C3("extra", 7, 2).C3("carriage", 7, 2)
        .C3("tax", 7, 2).C3("discount", 7, 2).C3("extraTax", 7, 2).C3("carriageTax", 7, 2).C3("paid", 7, 2)
        .N9("closed", 1).BChar("discountDays").Comp("discountAmount", 3, 2, true).Comp("discountTax", 3, 2, true)
        .BChar("creditDays").BLong("creditFolio").X("applied", 1).BLong("dateCleared");

    public IReadOnlyList<PurchaseInvoice>? PostInvoices()
    {
        List<PurchaseInvoice> posted = [];
        Rec? deferredFlags = null;
        bool succeeded = database.ExecuteAtomically(() =>
        {
            if (!InvoicesPending) return false;
            var system = System();
            if (system.S("Irs-Instead") == "Y") return false;
            var pending = Invoices().Where(invoice => !invoice.Posted).ToArray();
            if (pending.Length == 0 || pending.Any(invoice => invoice.Type is < 1 or > 3)) return false;
            int quarter = system.I("Current-Quarter");
            if (quarter is < 1 or > 4) return false;
            int nextBatch = system.I("Next-Batch");
            int nextPosting = system.I("Postings") + 1;

            foreach (var batch in pending.Chunk(99))
            {
                var general = GeneralLedgerEnabled;
                if (general && (nextBatch < 1 || nextBatch > 32767 || nextPosting + batch.Length > 32767)) return false;
                if (general && !WriteBatch(system, batch, nextBatch, nextPosting)) return false;
                foreach (var invoice in batch)
                {
                    var supplier = GetSupplier(invoice.Supplier);
                    if (supplier == null) return false;
                    string invoiceKey = InvoiceKey(invoice.Folio, 0);
                    var raw = database.Read(InvoiceFile, invoiceKey);
                    if (raw is null) return false;
                    var header = InvoiceHeader.From(raw);
                    header.Set("status", "z");
                    header.Set("update", "z");
                    if (!database.Rewrite(InvoiceFile, invoiceKey, header.B)) return false;
                    if (!ApplySupplierInvoice(supplier, invoice, quarter)) return false;
                    var item = NewOpenItem(invoice);
                    if (invoice.Type == 3 && !ApplyCredit(item)) return false;
                    if (!database.Write(OpenItemFile, $"{invoice.Supplier}/{invoice.Folio}", item.B)) return false;
                    posted.Add(invoice with { Posted = true });
                }
                if (general)
                {
                    nextPosting += batch.Length;
                    nextBatch++;
                }
            }

            if (GeneralLedgerEnabled)
            {
                system.SetN("Next-Batch", nextBatch);
                system.SetN("Postings", nextPosting);
            }
            system.SetN("P-Flag-I", 2);
            system.SetN("P-Flag-A", 1);
            system.SetN("File-Status-28", 0);
            system.SetN("File-Status-29", 1);
            system.Set("Oi-5-Flag", "Y");
            deferredFlags = system;
            return true;
        });
        if (succeeded) _deferredPostingFlags = deferredFlags;
        return succeeded ? posted : null;
    }

    private bool ApplySupplierInvoice(Rec supplier, PurchaseInvoice invoice, int quarter)
    {
        int count = supplier.I("activity");
        bool credit = invoice.Type == 3;
        if (!credit && count == int.MaxValue) return false;
        decimal runningTotal = count * supplier.N("average");
        decimal average = credit
            ? (runningTotal == 0 ? supplier.N("average") : (runningTotal - invoice.Net) / count)
            : (runningTotal + invoice.Net) / (count + 1);
        decimal balance = supplier.N("current") + (invoice.Type == 2 ? invoice.Total : credit ? -invoice.Total : 0);
        decimal unapplied = supplier.N("unapplied") + Math.Max(0, -balance);
        string quarterField = "q" + quarter;
        decimal turnover = supplier.N(quarterField) + (credit ? -invoice.Net : invoice.Net);
        if (average is < int.MinValue or > int.MaxValue || balance > 99999999.99m || unapplied > 99999999.99m ||
            Math.Abs(turnover) > 99999999.99m) return false;
        if (!credit) supplier.SetN("activity", count + 1);
        supplier.SetN("average", average);
        supplier.SetN(quarterField, turnover);
        if (!credit) supplier.SetN("lastInvoice", EncodeDate(invoice.Date));
        if (invoice.Type is 1 or 3) supplier.SetN("lastPayment", EncodeDate(invoice.Date));
        supplier.SetN("current", Math.Max(0, balance));
        supplier.SetN("unapplied", unapplied);
        supplier.SetN("status", 1);
        return database.Rewrite(SupplierFile, invoice.Supplier, supplier.B);
    }

    private static Rec NewOpenItem(PurchaseInvoice invoice)
    {
        var item = OpenItem.New();
        int sign = invoice.Type == 3 ? -1 : 1;
        item.Set("supplier", invoice.Supplier);
        item.Set("folio", invoice.Folio);
        item.SetN("date", EncodeDate(invoice.Date));
        item.SetN("type", invoice.Type);
        item.Set("reference", invoice.Reference);
        item.Set("order", invoice.Order);
        item.Set("unapplied", "\0");
        item.SetN("net", sign * invoice.Net);
        item.SetN("carriage", sign * invoice.Carriage);
        item.SetN("tax", sign * invoice.Tax);
        item.SetN("carriageTax", sign * invoice.CarriageTax);
        item.SetN("creditFolio", invoice.CreditFolio);
        item.SetN("creditDays", invoice.CreditDays);
        item.SetN("discountDays", invoice.DiscountDays);
        item.SetN("discountAmount", invoice.Discount);
        return item;
    }

    private bool ApplyCredit(Rec credit)
    {
        string supplier = credit.St("supplier");
        decimal gross = -OpenItemGross(credit);
        decimal remaining = gross;
        foreach (var (key, bytes) in database.Scan(OpenItemFile, supplier + "/")
            .TakeWhile(row => row.Key.StartsWith(supplier + "/", StringComparison.Ordinal))
            .OrderBy(row => row.Key != $"{supplier}/{credit.I("creditFolio"):00000000}"))
        {
            if (remaining == 0) break;
            if (bytes.Length != OpenItem.Size) return false;
            var item = OpenItem.From(bytes);
            if (item.I("closed") != 0 || item.I("type") != 2) continue;
            decimal balance = OpenItemGross(item) - item.N("paid");
            if (balance < 0) continue;
            decimal applied = Math.Min(balance, remaining);
            item.SetN("paid", item.N("paid") + applied);
            item.SetN("pc", item.N("pc") + applied);
            if (balance == applied) item.SetN("closed", 1);
            if (!database.Rewrite(OpenItemFile, key, item.B)) return false;
            remaining -= applied;
        }
        credit.SetN("paid", gross);
        credit.SetN("closed", 1);
        return true;
    }

    private static decimal OpenItemGross(Rec item) => item.N("net") + item.N("carriage") + item.N("tax") + item.N("carriageTax");

    private bool WriteBatch(Rec system, PurchaseInvoice[] invoices, int batch, int start)
    {
        decimal net = 0, tax = 0;
        for (int i = 0; i < invoices.Length; i++)
        {
            var invoice = invoices[i];
            int sign = invoice.Type == 3 ? -1 : 1;
            net += sign * (invoice.Net + invoice.Carriage);
            tax += sign * (invoice.Tax + invoice.CarriageTax);
            if (GetSupplier(invoice.Supplier) is not { } supplier) return false;
            var posting = Layouts.Posting.New();
            posting.SetN("batch", batch);
            posting.SetN("post-number", i + 1);
            posting.Set("post-code", "PL");
            posting.Set("post-date", invoice.Date.ToString("dd/MM/yy", CultureInfo.InvariantCulture));
            posting.SetN("post-dr", system.N("BL-Purch-Ac"));
            posting.SetN("post-cr", system.N("P-Creditors"));
            posting.SetN("post-amount", sign * (invoice.Net + invoice.Carriage));
            posting.Set("post-legend", $"{invoice.Folio.TrimStart('0')} : {supplier.St("name")}");
            posting.SetN("vat-ac", system.N("Vat-Ac"));
            posting.Set("post-vat-side", "DR");
            posting.SetN("vat-amount", sign * (invoice.Tax + invoice.CarriageTax));
            if (!database.Write(PostingFile, (start + i).ToString("00000000", CultureInfo.InvariantCulture), posting.B)) return false;
        }
        var header = Layouts.Batch.New();
        header.SetN("ledger", 2);
        header.SetN("batch-nos", batch);
        header.SetN("items", invoices.Length);
        header.SetN("bcycle", system.N("Cyclea"));
        header.SetN("entered", system.N("Run-Date"));
        header.SetN("input-gross", net);
        header.SetN("actual-gross", net);
        header.SetN("input-vat", tax);
        header.SetN("actual-vat", tax);
        header.Set("description", "Purchase Ledger Invoices");
        header.Set("convention", "DR");
        header.Set("batch-def-code", "PL");
        header.Set("batch-def-vat", "I");
        header.SetN("batch-start", start);
        return database.Write(BatchFile, "2" + batch.ToString("00000", CultureInfo.InvariantCulture), header.B);
    }
}
