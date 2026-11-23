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
        bool succeeded = database.ExecuteAtomically(() =>
        {
            if (!InvoicesPending) return false;
            var system = System();
            if (system.S("Irs-Instead") == "Y") return false;
            var pending = Invoices().Where(invoice => !invoice.Posted).ToArray();
            if (pending.Length == 0 || pending.Any(invoice => invoice.Type is not (1 or 2))) return false;
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
            SaveSystem(system);
            return true;
        });
        return succeeded ? posted : null;
    }

    private bool ApplySupplierInvoice(Rec supplier, PurchaseInvoice invoice, int quarter)
    {
        int count = supplier.I("activity");
        if (count == int.MaxValue) return false;
        decimal average = (count * supplier.N("average") + invoice.Net) / (count + 1);
        decimal balance = supplier.N("current") + (invoice.Type == 2 ? invoice.Total : 0);
        string quarterField = "q" + quarter;
        decimal turnover = supplier.N(quarterField) + invoice.Net;
        if (average > int.MaxValue || balance > 99999999.99m || turnover > 99999999.99m) return false;
        supplier.SetN("activity", count + 1);
        supplier.SetN("average", average);
        supplier.SetN(quarterField, turnover);
        supplier.SetN("lastInvoice", EncodeDate(invoice.Date));
        if (invoice.Type == 1) supplier.SetN("lastPayment", EncodeDate(invoice.Date));
        supplier.SetN("current", balance);
        supplier.SetN("status", 1);
        return database.Rewrite(SupplierFile, invoice.Supplier, supplier.B);
    }

    private static Rec NewOpenItem(PurchaseInvoice invoice)
    {
        var item = OpenItem.New();
        item.Set("supplier", invoice.Supplier);
        item.Set("folio", invoice.Folio);
        item.SetN("date", EncodeDate(invoice.Date));
        item.SetN("type", invoice.Type);
        item.Set("reference", invoice.Reference);
        item.Set("order", invoice.Order);
        item.Set("unapplied", "\0");
        item.SetN("net", invoice.Net);
        item.SetN("carriage", invoice.Carriage);
        item.SetN("tax", invoice.Tax);
        item.SetN("carriageTax", invoice.CarriageTax);
        item.SetN("creditDays", invoice.CreditDays);
        item.SetN("discountDays", invoice.DiscountDays);
        item.SetN("discountAmount", invoice.Discount);
        return item;
    }

    private bool WriteBatch(Rec system, PurchaseInvoice[] invoices, int batch, int start)
    {
        decimal net = 0, tax = 0;
        for (int i = 0; i < invoices.Length; i++)
        {
            var invoice = invoices[i];
            net += invoice.Net + invoice.Carriage;
            tax += invoice.Tax + invoice.CarriageTax;
            if (GetSupplier(invoice.Supplier) is not { } supplier) return false;
            var posting = Layouts.Posting.New();
            posting.SetN("batch", batch);
            posting.SetN("post-number", i + 1);
            posting.Set("post-code", "PL");
            posting.Set("post-date", invoice.Date.ToString("dd/MM/yy", CultureInfo.InvariantCulture));
            posting.SetN("post-dr", system.N("BL-Purch-Ac"));
            posting.SetN("post-cr", system.N("P-Creditors"));
            posting.SetN("post-amount", invoice.Net + invoice.Carriage);
            posting.Set("post-legend", $"{invoice.Folio.TrimStart('0')} : {supplier.St("name")}");
            posting.SetN("vat-ac", system.N("Vat-Ac"));
            posting.Set("post-vat-side", "DR");
            posting.SetN("vat-amount", invoice.Tax + invoice.CarriageTax);
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
