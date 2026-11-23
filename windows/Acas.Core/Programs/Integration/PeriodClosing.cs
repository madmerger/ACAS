using System.Security.Cryptography;
using System.Text;
using Acas.Core.Engine;
using Acas.Core.Programs.Irs;

namespace Acas.Core.Programs.Integration;

public sealed record ClosingOptions(bool HasUnpostedInvoices, bool RequiresQuarterChoice, bool HasSales, bool HasPurchases);

public sealed partial class LedgerTransfer
{
    public ClosingOptions ClosingWarning(TransferLedger ledger)
    {
        var system = Settings();
        bool sales = ledger == TransferLedger.Sales;
        if (system.I("File-Status-15") != 1)
            throw new IrsException("期末処理に必要なシステムファイルがありません。");
        if (system.I("S-Flag-P") is 1 or 2 || system.I("P-Flag-P") is 1 or 2 ||
            system.I("S-Flag-A") == 1 || system.I("P-Flag-A") == 1)
            throw new IrsException("未完了の更新があるため期末処理を実行できません。");
        if (system.I(sales ? "Level-3" : "Level-2") != 1)
            throw new IrsException("指定の元帳は使用されていません。");
        return new(system.I("S-Flag-I") == 1 || system.I("P-Flag-I") == 1,
            system.I("Period") is not (3 or 13), system.I("Level-3") == 1, system.I("Level-2") == 1);
    }

    public void ClosePeriod(TransferLedger ledger, DateTime date, string password, bool proceedWithUnposted, bool endOfQuarter)
        => ClosePeriod([ledger], date, password, proceedWithUnposted, endOfQuarter);

    public void ClosePeriod(IReadOnlyCollection<TransferLedger> ledgers, DateTime date, string password, bool proceedWithUnposted, bool endOfQuarter)
    {
        if (ledgers.Count == 0) throw new IrsException("処理する元帳を選択してください。");
        var options = ClosingWarning(ledgers.First());
        if (options.HasUnpostedInvoices && !proceedWithUnposted)
            throw new IrsException("未転記の請求書が残っています。");
        var system = Settings();
        foreach (var ledger in ledgers)
        {
            bool sales = ledger == TransferLedger.Sales;
            if (sales ? !options.HasSales : !options.HasPurchases)
                throw new IrsException("指定の元帳は使用されていません。");
            if (system.I(sales ? "File-Status-19" : "File-Status-29") != 1 && !db.Exists(ItemFile(sales)))
                throw new IrsException("未決済明細ファイルがありません。");
        }
        if (!CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(system.S("Pass-Word")), LegacyPassword(password)))
            throw new IrsException("暗証番号が一致しません。");
        if (date.Date <= Epoch) throw new IrsException("処理日が有効範囲外です。");
        int days = DayOf(date);
        int cycle = system.I("Cyclea") + 1;
        int quarter = system.I("Current-Quarter");
        int period = system.I("Period");
        bool yearEnd = period == 3 ? cycle == 13 : period == 13 ? cycle == 53 : endOfQuarter && quarter == 4;
        bool quarterEnd = yearEnd || (period == 3 ? cycle is 4 or 7 or 10 : period == 13 ? cycle is 14 or 27 or 40 : endOfQuarter);
        if (yearEnd) { cycle = 1; quarter = 1; }
        else if (quarterEnd) quarter++;
        system.SetN("Cyclea", cycle);
        system.SetN("Current-Quarter", quarter);
        var staged = new Dictionary<(string Path, string Key), byte[]?>();
        var balances = db.Read(SystemFile, "00000004") ?? new byte[1024];
        if (balances.Length != 1024) throw new IrsException("期末残高レコードの長さが正しくありません。");
        foreach (var ledger in ledgers.Distinct().Order())
            StageClosing(staged, system, balances, ledger == TransferLedger.Sales, days, quarter, quarterEnd, yearEnd);
        staged[(SystemFile, SystemKey)] = system.B;
        staged[(SystemFile, "00000004")] = balances;
        db.Atomic(() =>
        {
            foreach (var ((path, key), data) in staged)
                if (data is null) db.Delete(path, key); else db.Put(path, key, data);
        });
    }

    private void StageClosing(Dictionary<(string Path, string Key), byte[]?> staged, Rec system, byte[] balances,
        bool sales, int days, int quarter, bool quarterEnd, bool yearEnd)
    {
        var partyFile = PartyFile(sales);
        foreach (var (key, data) in db.Scan(partyFile))
        {
            var row = Read(sales ? SalesParty : PurchaseParty, data);
            decimal current = row.N("current");
            if (current == 0 && row.N("last") == 0 && row.N("unapplied") == 0) row.SetN("status", 0);
            if (current < 0)
            {
                row.SetN("unapplied", row.N("unapplied") - current);
                row.SetN("current", 0);
            }
            row.SetN("last", Math.Max(0, current));
            if (quarterEnd && quarter is >= 1 and <= 4) row.SetN("quarter" + quarter, 0);
            if (yearEnd)
            {
                row.SetN("activity", 0);
                row.SetN("average", 0);
            }
            staged[(partyFile, key)] = row.B;
        }

        string invoices = InvoiceFile(sales), items = ItemFile(sales);
        var ownNumbers = system.S("Sl-Own-Nos") == "Y";
        var itemsLayout = OpenItemLayout(sales);
        var invoiceRows = db.Scan(invoices);
        foreach (var (key, data) in db.Scan(items))
        {
            var row = Read(itemsLayout, data);
            if (row.I("status") == 1 || row.I("type") == 1)
            {
                staged[(items, key)] = null;
                if (row.I("status") != 1 || row.I("type") != 2 || (sales && ownNumbers)) continue;
                string prefix = Cob.P9(row.I("invoice"), 8) + (sales ? "/ /" : "/");
                foreach (var invoice in invoiceRows.Where(x => x.Key.StartsWith(prefix, StringComparison.Ordinal)))
                    staged[(invoices, invoice.Key)] = null;
                continue;
            }
            if (row.I("type") is 5 or 6) row.SetN("deductAmount", 0);
            row.Set("applied", "z");
            row.SetN("current", 0);
            staged[(items, key)] = row.B;
        }

        string values = Directory + "value.dat";
        var valueLayout = new Layout().X("system", 1).Fill(35).Comp("items", 5).Comp("lastItems", 5).Fill(4)
            .C3("total", 8, 2).C3("lastTotal", 8, 2).Fill(6);
        foreach (var (key, data) in db.Scan(values))
        {
            if (yearEnd) { staged[(values, key)] = null; continue; }
            var row = Read(valueLayout, data);
            if (row.S("system") != (sales ? "S" : "P")) continue;
            row.SetN("lastItems", row.N("items"));
            row.SetN("items", 0);
            row.SetN("lastTotal", row.N("total"));
            row.SetN("total", 0);
            staged[(values, key)] = row.B;
        }

        var groups = invoiceRows.GroupBy(i => i.Key[..i.Key.LastIndexOf('/')], StringComparer.Ordinal);
        foreach (var group in groups)
        {
            var rows = group.Where(x => !staged.ContainsKey((invoices, x.Key))).ToArray();
            if (rows.Length == 0) continue;
            var header = rows.FirstOrDefault(x => x.Key.EndsWith("/00", StringComparison.Ordinal));
            int count = 0;
            bool delete = false;
            if (header.Data != null)
            {
                var row = Read(sales ? SalesInvoice : PurchaseInvoice, header.Data);
                if (row.I("test") == 0)
                {
                    int type = row.I("type");
                    bool applied = row.St("status") is "z" or "Z";
                    bool expired = sales && type == 4 && days - system.I("PF-Retention") > row.I("date");
                    delete = expired || (applied && (type is 1 or 3 ||
                        sales && ownNumbers && type == 2 && row.I("lines") == 0 && days - 92 > row.I("date")));
                    if (delete || applied && type == 2) count = Math.Max(0, row.I("lines"));
                    if (!sales && applied && type < 4) row.Set("dayBook", "B");
                    if (applied && type == 2) row.SetN("lines", 0);
                    header.Data = row.B;
                }
            }
            foreach (var (key, data) in rows)
            {
                bool isHeader = key == header.Key;
                staged[(invoices, key)] = delete || (!isHeader && count-- > 0) ? null :
                    ThroughTemporaryInvoice(isHeader ? header.Data! : data);
            }
        }

        int offset = sales ? 0 : 60;
        balances.AsSpan(offset + 6, 6).CopyTo(balances.AsSpan(offset, 6));
        for (int i = 1; i <= 7; i++)
        {
            var field = balances.AsSpan(offset + i * 6, 6);
            field.Clear();
            field[^1] = 0x0c;
        }
        system.Set(sales ? "Oi-3-Flag" : "Oi-5-Flag", "Y");
        system.SetN(sales ? "S-End-Cycle-Date" : "BL-End-Cycle-Date", days);
    }

    internal static byte[] ThroughTemporaryInvoice(byte[] data)
    {
        byte[] output = (byte[])data.Clone();
        if (output.Length > 129) output.AsSpan(129).Fill((byte)' ');
        return output;
    }

    private static byte[] LegacyPassword(string password)
    {
        const string alphabet = "CKQUAELSMWYIZJRPBXFVGNODTH";
        byte[] output = [(byte)' ', (byte)' ', (byte)' ', (byte)' '];
        if (password.Length > output.Length || password.Any(c => c != ' ' && !char.IsAsciiLetter(c)))
            throw new IrsException("暗証番号が正しくありません。");
        for (int i = 0; i < password.Length; i++)
        {
            int original = alphabet.IndexOf(char.ToUpperInvariant(password[i]));
            if (original < 0) continue;
            int n = Math.Abs(original + 1 + (i + 1) * (i + 1) + 3 - 26);
            if (n != 0) output[3 - i] = (byte)alphabet[n - 1];
        }
        return output;
    }
}
