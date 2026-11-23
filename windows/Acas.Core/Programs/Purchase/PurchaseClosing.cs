using System.Globalization;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed partial class PurchaseLedger
{
    private const string CustomerFile = "ledgers/acas/salesled.dat";
    private const string SalesOpenItemFile = "ledgers/acas/openitm3.dat";
    private const string SalesInvoiceFile = "ledgers/acas/invoice.dat";
    private const string SalesSortFile = "ledgers/acas/oisort.wrk";
    private const string CycleWorkFile = "ledgers/acas/work.tmp";
    private static readonly Layout SalesAccount = new Layout().Fill(193).N9("status", 1).Fill(22).BLong("activity").Fill(8)
        .BLong("average").Fill(16).C3("current", 8, 2).C3("last", 8, 2)
        .Group(4, (layout, i) => layout.C3("q" + i, 8, 2)).C3("unapplied", 8, 2).Fill(10);
    private static readonly Layout SalesOpenItem = new Layout().Fill(7).BLong("folio").Fill(10).N9("type", 1).Fill(27)
        .C3("pc", 7, 2).Fill(40).N9("closed", 1).Fill(1).Comp("discountAmount", 3, 2, true).Fill(9)
        .X("applied", 1).Fill(4);
    private static readonly Layout SalesCycleInvoice = new Layout().N9("folio", 8).X("letter", 1).BChar("line")
        .Fill(7).BLong("date").Fill(10).N9("type", 1).Fill(82).X("status", 1).Fill(5)
        .BChar("lines").Fill(14).X("dayBook", 1).Fill(1);
    private static readonly Layout CycleTotals = new Layout().Group(2, (layout, i) =>
        layout.C3("last" + i, 8, 2).Group(7, (record, j) => record.C3($"total{i}_{j}", 8, 2)).Fill(12)).Fill(904);

    public bool MatchesCyclePassword(string password)
    {
        const string alphabet = "CKQUAELSMWYIZJRPBXFVGNODTH";
        if (password.Length > 4) return false;
        char[] encoded = [' ', ' ', ' ', ' '];
        for (int i = 0; i < password.Length; i++)
        {
            int index = alphabet.IndexOf(char.ToUpperInvariant(password[i]));
            if (index < 0) continue;
            int position = Math.Abs(index + 1 + (i + 1) * (i + 1) + 3 - 26);
            if (position != 0) encoded[3 - i] = alphabet[position - 1];
        }
        return System().S("Pass-Word") == new string(encoded);
    }

    public bool ClosePeriod(DateTime date, bool purchase, bool sales, bool quarter, bool allowUnposted) =>
        database.ExecuteAtomically(() =>
        {
            var system = System();
            int day = EncodeDate(date);
            if (day <= 0 || (!purchase && !sales) || system.I("File-Status-15") != 1 ||
                system.I("P-Flag-P") != 0 || system.I("S-Flag-P") != 0 ||
                system.I("P-Flag-A") == 1 || system.I("S-Flag-A") == 1 ||
                (!allowUnposted && (system.I("P-Flag-I") == 1 || system.I("S-Flag-I") == 1)) ||
                (purchase && (system.I("Level-2") != 1 || system.I("File-Status-29") != 1)) ||
                (sales && (system.I("Level-3") != 1 || system.I("File-Status-19") != 1)))
                return false;
            int cycle = system.I("Cyclea") + 1;
            int currentQuarter = system.I("Current-Quarter");
            if (currentQuarter is < 1 or > 4 || cycle is < 1 or > sbyte.MaxValue) return false;
            int period = system.I("Period");
            bool newYear = period switch { 3 => cycle == 13, 13 => cycle == 53, _ => quarter && currentQuarter == 4 };
            bool newQuarter = newYear || (period switch { 3 => cycle is 4 or 7 or 10, 13 => cycle is 14 or 27 or 40, _ => quarter });
            if (newYear) (cycle, currentQuarter) = (1, 1);
            else if (newQuarter && ++currentQuarter > 4) return false;
            system.SetN("Cyclea", cycle);
            system.SetN("Current-Quarter", currentQuarter);
            foreach (bool isSales in new[] { true, false })
            {
                if (isSales ? !sales : !purchase) continue;
                string accounts = isSales ? CustomerFile : SupplierFile;
                var accountLayout = isSales ? SalesAccount : SupplierLayout;
                string open = isSales ? SalesOpenItemFile : OpenItemFile;
                var itemLayout = isSales ? SalesOpenItem : OpenItem;
                string invoices = isSales ? SalesInvoiceFile : InvoiceFile;
                var header = isSales ? SalesCycleInvoice : InvoiceHeader;
                string sort = isSales ? SalesSortFile : PaymentSortFile;
                if (!RollAccounts(accounts, accountLayout, currentQuarter, newQuarter, newYear)) return false;
                foreach (var (key, bytes) in database.Scan(open))
                {
                    if (bytes.Length != itemLayout.Size) return false;
                    var item = itemLayout.From(bytes);
                    int type = item.I("type");
                    if (item.I("closed") == 1 || type == 1)
                    {
                        if (item.I("closed") == 1 && type == 2 && !(isSales && system.S("Sl-Own-Nos") == "Y"))
                            DeleteCycleInvoice(invoices, header, FolioPrefix(item.I("folio"), isSales));
                        if (!database.Delete(open, key)) return false;
                    }
                    else
                    {
                        if (type is 5 or 6) item.SetN("discountAmount", 0);
                        item.Set("applied", "z");
                        item.SetN("pc", 0);
                        if (!database.Rewrite(open, key, item.B)) return false;
                    }
                }
                database.Recreate(sort);
                if (!RollAnalysisValues(isSales ? "S" : "P", newYear) ||
                    !PackCycleInvoices(invoices, header, isSales, day, system)) return false;
                system.SetN(isSales ? "S-End-Cycle-Date" : "BL-End-Cycle-Date", day);
                system.Set(isSales ? "Oi-3-Flag" : "Oi-5-Flag", "Y");
            }
            const string key4 = "00000004";
            if (database.Read(SystemFile, key4) is { } bytes4 && bytes4.Length == CycleTotals.Size)
            {
                var totals = CycleTotals.From(bytes4);
                if (sales) RollCycleTotals(totals, 1);
                if (purchase) RollCycleTotals(totals, 2);
                if (!database.Rewrite(SystemFile, key4, totals.B)) return false;
            }
            return SaveSystem(system);
        });

    private bool RollAccounts(string file, Layout layout, int quarter, bool newQuarter, bool newYear)
    {
        var accounts = database.Scan(file);
        foreach (var (key, bytes) in accounts)
        {
            if (bytes.Length != layout.Size) return false;
            var row = layout.From(bytes);
            decimal amount = row.N("current");
            if (amount == 0 && row.N("last") == 0 && row.N("unapplied") == 0) row.SetN("status", 0);
            if (amount < 0)
            {
                decimal credit = row.N("unapplied") - amount;
                if (!AmountFits(credit, 99999999.99m)) return false;
                row.SetN("unapplied", credit);
                row.SetN("current", 0);
            }
            row.SetN("last", Math.Max(amount, 0));
            if (newQuarter) row.SetN("q" + quarter, 0);
            if (newYear)
            {
                row.SetN("average", 0);
                row.SetN("activity", 0);
            }
            if (!database.Rewrite(file, key, row.B)) return false;
        }
        return true;
    }

    private bool RollAnalysisValues(string subsystem, bool newYear)
    {
        if (newYear)
        {
            database.Recreate(ValuesFile);
            return true;
        }
        foreach (var (key, bytes) in database.Scan(ValuesFile))
        {
            if (bytes.Length != AnalysisValue.Size) return false;
            var row = AnalysisValue.From(bytes);
            if (row.S("system") != subsystem) continue;
            row.SetN("priorAmount", row.N("amount"));
            row.SetN("priorCount", row.I("count"));
            row.SetN("amount", 0);
            row.SetN("count", 0);
            if (!database.Rewrite(ValuesFile, key, row.B)) return false;
        }
        return true;
    }

    private static void RollCycleTotals(Rec totals, int ledger)
    {
        totals.SetN("last" + ledger, totals.N($"total{ledger}_1"));
        for (int i = 1; i <= 7; i++) totals.SetN($"total{ledger}_{i}", 0);
    }

    private bool PackCycleInvoices(string file, Layout header, bool sales, int day, Rec system)
    {
        database.Recreate(CycleWorkFile);
        foreach (var (key, bytes) in database.Scan(file))
        {
            if (database.Read(file, key) is null) continue;
            int size = sales ? 134 : header.Size;
            if (bytes.Length != size) return false;
            var record = header.From(bytes);
            if (record.I("line") == 0)
            {
                int type = record.I("type"), lines = record.I("lines");
                string prefix = key[..^2];
                bool applied = record.S("status") is "z" or "Z";
                bool expired = sales && type == 4 && record.I("date") < day - system.I("PF-Retention");
                bool remove = expired || (applied && (type is 1 or 3 ||
                    (sales && type == 2 && lines == 0 && system.S("Sl-Own-Nos") == "Y" && record.I("date") < day - 92)));
                if (remove)
                {
                    DeleteCycleInvoice(file, header, prefix);
                    continue;
                }
                if (applied && type < 4) record.Set("dayBook", "B");
                if (applied && type == 2 && lines > 0)
                {
                    for (int line = 1; line <= lines; line++) database.Delete(file, prefix + line.ToString("00", CultureInfo.InvariantCulture));
                    record.SetN("lines", 0);
                }
            }
            if (sales) record.B.AsSpan(129, size - 129).Fill((byte)' ');
            if (!database.Rewrite(file, key, record.B.AsSpan(0, size).ToArray()) ||
                !database.Write(CycleWorkFile, key, record.B.AsSpan(0, 129).ToArray())) return false;
        }
        return true;
    }

    private void DeleteCycleInvoice(string file, Layout header, string prefix)
    {
        var data = database.Read(file, prefix + "00");
        int lines = data is null ? sbyte.MaxValue : header.From(data).I("lines");
        for (int line = 0; line <= lines; line++)
        {
            bool found = database.Delete(file, prefix + line.ToString("00", CultureInfo.InvariantCulture));
            if (line > 0 && data is null && !found) break;
        }
    }

    private static string FolioPrefix(int folio, bool sales) =>
        folio.ToString("00000000", CultureInfo.InvariantCulture) + (sales ? "/ /" : "/");
}
