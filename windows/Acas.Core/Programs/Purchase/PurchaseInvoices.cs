using System.Globalization;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed record PurchaseLine(string Code, decimal Net, int TaxCode, decimal Tax, string Description);

public sealed record PurchaseInvoice(string Folio, string Supplier, DateTime Date, string Order,
    string Reference, int Type, IReadOnlyList<PurchaseLine> Lines, int CreditDays, decimal Discount,
    int DiscountDays, decimal Carriage, decimal CarriageTax, bool Posted = false, int CreditFolio = 0)
{
    public decimal Net => Lines.Sum(line => line.Net);
    public decimal Tax => Lines.Sum(line => line.Tax);
    public decimal Total => Net + Tax + Carriage + CarriageTax;
}

public sealed partial class PurchaseLedger
{
    public const string InvoiceFile = "ledgers/acas/pinvoice.dat";
    private const string DeletedFolioFile = "ledgers/acas/delfolio.dat";

    private static readonly Layout InvoiceHeader = new Layout().N9("folio", 8).BChar("line").X("supplier", 7)
        .BLong("date").X("order", 10).N9("type", 1).X("reference", 10)
        .C3("pc", 7, 2).C3("net", 7, 2).C3("extra", 7, 2).C3("carriage", 7, 2).C3("tax", 7, 2)
        .C3("discountPercent", 7, 2).C3("extraTax", 7, 2).C3("carriageTax", 7, 2)
        .X("status", 1).BChar("lines").BChar("discountDays").Comp("discount", 3, 2)
        .Comp("discountTax", 3, 2).BChar("creditDays").BLong("creditFolio").X("dayBook", 1).X("update", 1).X("padding", 30);
    private static readonly Layout InvoiceLine = new Layout().N9("folio", 8).BChar("line").X("product", 12)
        .X("analysis", 2).X("filler1", 3).BShort("quantity").X("type", 1).X("description", 24)
        .X("filler2", 2).C3("net", 7, 2).C3("unit", 7, 2).Comp("discount", 2, 2).C3("tax", 7, 2)
        .N9("taxCode", 1).X("update", 1).X("padding", 55);
    private static readonly Layout DeletedFolio = new Layout().N9("folio", 8).BLong("date").X("supplier", 7);

    public bool InvoiceFileAvailable => System().I("File-Status-26") == 1 && database.Exists(InvoiceFile);
    public bool InvoicesPending => System().I("P-Flag-I") == 1 && InvoiceFileAvailable;
    public string NextFolio => Math.Max(1, System().I("Next-Folio")).ToString("00000000", CultureInfo.InvariantCulture);
    public decimal TaxRate(int code) => code is >= 1 and <= 3 ? System().N("Vat-Rate-" + code) : 0;
    public bool GeneralLedgerEnabled => System().I("Level-1") == 1;

    public bool SaveInvoiceSettings(int next, int? taxAccount)
    {
        if (next is < 1 or > 99999999 || taxAccount is < 0 or > 999999) return false;
        var system = System();
        system.SetN("Next-Folio", next);
        if (taxAccount is { } value) system.SetN("Vat-Ac", value);
        SaveSystem(system);
        return true;
    }

    private static string InvoiceKey(string folio, int line) => $"{folio}/{line:00}";

    public PurchaseInvoice? Invoice(string folio)
    {
        var bytes = database.Read(InvoiceFile, InvoiceKey(folio, 0));
        if (bytes?.Length != InvoiceHeader.Size) return null;
        var header = InvoiceHeader.From(bytes);
        if (DecodeDate(header.I("date")) is not { } date) return null;
        var lines = new List<PurchaseLine>();
        for (int i = 1; i <= header.I("lines"); i++)
        {
            bytes = database.Read(InvoiceFile, InvoiceKey(folio, i));
            if (bytes?.Length != InvoiceLine.Size) return null;
            var line = InvoiceLine.From(bytes);
            lines.Add(new(line.St("analysis"), line.N("net"), line.I("taxCode"), line.N("tax"), line.St("description")));
        }
        return new(folio, header.St("supplier"), date, header.St("order"), header.St("reference"), header.I("type"), lines,
            header.I("creditDays"), header.N("discount"), header.I("discountDays"), header.N("carriage"), header.N("carriageTax"),
            header.S("status") is "Z" or "z", header.I("creditFolio"));
    }

    public IEnumerable<PurchaseInvoice> Invoices() => database.Scan(InvoiceFile)
        .Where(row => row.Key.Length == 11 && row.Key.EndsWith("/00", StringComparison.Ordinal))
        .Select(row => Invoice(row.Key[..8])).OfType<PurchaseInvoice>();

    private static bool AmountFits(decimal amount, decimal limit) => amount >= 0 && amount <= limit && decimal.Round(amount, 2) == amount;

    public bool SaveInvoice(PurchaseInvoice invoice, bool create, bool acceptMissingCreditTarget = false)
    {
        if (invoice.Folio.Length != 8 || invoice.Folio.Any(character => character is < '0' or > '9')
            || invoice.Type is < 1 or > 3 || invoice.Lines.Count is < 1 or > 40 || EncodeDate(invoice.Date) <= 0
            || !FitsRecord(invoice.Order, 10) || !FitsRecord(invoice.Reference, 10)
            || !AmountFits(invoice.Net, 9999999.99m) || !AmountFits(invoice.Tax, 9999999.99m)
            || !AmountFits(invoice.Carriage, 9999999.99m) || !AmountFits(invoice.CarriageTax, 999999.99m)
            || !AmountFits(invoice.Discount, 999.99m) || invoice.CreditDays is < 0 or > 99 || invoice.DiscountDays is < 0 or > 99
            || invoice.CreditFolio is < 0 or >= 99999999 || (invoice.Type != 3 && invoice.CreditFolio != 0)
            || invoice.Lines.Any(line => !FitsRecord(line.Code, 2) || string.IsNullOrWhiteSpace(line.Code)
                || !AmountFits(line.Net, 9999999.99m) || line.Net == 0 || !AmountFits(line.Tax, 999999.99m) || line.TaxCode is < 0 or > 3))
            return false;

        return database.ExecuteAtomically(() =>
        {
            if (GetSupplier(invoice.Supplier) is null) return false;
            bool analysisUnavailable = HasInvalidAnalysisLength;
            if (!analysisUnavailable && invoice.Lines.Any(line => Analysis(line.Code) is null)) return false;
            var before = Invoice(invoice.Folio);
            string headerKey = InvoiceKey(invoice.Folio, 0);
            var originalHeader = database.Read(InvoiceFile, headerKey);
            if (create ? originalHeader != null || invoice.Folio != NextFolio : before is not { Posted: false })
                return false;
            if (invoice.CreditFolio != 0)
            {
                string targetFolio = invoice.CreditFolio.ToString("00000000", CultureInfo.InvariantCulture);
                if (targetFolio == invoice.Folio) return false;
                var target = Invoice(targetFolio);
                if (target is null ? !acceptMissingCreditTarget : target.Type != 2 || target.Supplier != invoice.Supplier)
                    return false;
            }
            for (int i = 1; i <= invoice.Lines.Count; i++)
                if (i > (before?.Lines.Count ?? 0) && database.Read(InvoiceFile, InvoiceKey(invoice.Folio, i)) != null)
                    return false;

            var header = originalHeader is null ? InvoiceHeader.New() : InvoiceHeader.From(originalHeader);
            header.Set("folio", invoice.Folio);
            header.Set("supplier", invoice.Supplier);
            header.SetN("date", EncodeDate(invoice.Date));
            header.Set("order", invoice.Order);
            header.Set("reference", invoice.Reference);
            header.SetN("type", invoice.Type);
            header.SetN("net", invoice.Net);
            header.SetN("tax", invoice.Tax);
            header.Set("status", "P");
            header.SetN("lines", invoice.Lines.Count);
            header.SetN("creditDays", invoice.CreditDays);
            header.SetN("discount", invoice.Discount);
            header.SetN("discountDays", invoice.DiscountDays);
            header.SetN("carriage", invoice.Carriage);
            header.SetN("carriageTax", invoice.CarriageTax);
            header.SetN("creditFolio", invoice.CreditFolio);
            database.Put(InvoiceFile, headerKey, header.B);
            for (int i = 1; i <= invoice.Lines.Count; i++)
            {
                string key = InvoiceKey(invoice.Folio, i);
                var input = invoice.Lines[i - 1];
                var original = database.Read(InvoiceFile, key);
                var line = original is null ? InvoiceLine.New() : InvoiceLine.From(original);
                line.Set("folio", invoice.Folio);
                line.SetN("line", i);
                line.Set("type", invoice.Type.ToString(CultureInfo.InvariantCulture));
                line.Set("analysis", input.Code);
                var analysis = Analysis(input.Code);
                line.Set("description", analysis?.S("description") ?? new string('\0', 24));
                line.SetN("net", input.Net);
                line.SetN("tax", input.Tax);
                line.SetN("taxCode", input.TaxCode);
                database.Put(InvoiceFile, key, line.B);
            }
            for (int i = invoice.Lines.Count + 1; i <= (before?.Lines.Count ?? 0); i++) database.Delete(InvoiceFile, InvoiceKey(invoice.Folio, i));

            var system = System();
            system.SetN("File-Status-26", 1);
            system.SetN("P-Flag-I", 1);
            if (create) system.SetN("Next-Folio", int.Parse(invoice.Folio, CultureInfo.InvariantCulture) + 1);
            SaveSystem(system);
            return true;
        });
    }

    public bool DeleteInvoice(string folio)
    {
        return database.ExecuteAtomically(() =>
        {
            if (Invoice(folio) is not { Posted: false } invoice) return false;
            var record = DeletedFolio.New();
            record.Set("folio", folio);
            record.SetN("date", EncodeDate(invoice.Date));
            record.Set("supplier", invoice.Supplier);
            database.Put(DeletedFolioFile, folio, record.B);
            for (int i = 0; i <= invoice.Lines.Count; i++) database.Delete(InvoiceFile, InvoiceKey(folio, i));
            return true;
        });
    }
}
