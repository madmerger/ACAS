using System.Security.Cryptography;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed record SalesOpenItem(int Number, int Date, int Type, string Description, decimal Amount, decimal Paid,
    bool Closed, bool Held)
{
    public decimal Outstanding => Amount - Paid;
}

public sealed partial class SalesLedger
{
    public const string OpenItemFile = Prefix + "openitm3.dat";
    private const string ValueFile = Prefix + "value.dat";
    private int cyclePasswordFailures;
    private long cyclePasswordRetryAfter;
    private static readonly Layout OpenItemLayout = new Layout()
        .X("customer", 7).BLong("number").BLong("date").Comp("batchNumber", 5).Comp("batchItem", 3).N9("type", 1).X("description", 25)
        .X("held", 1).X("unapplied", 1).C3("pc", 7, 2).C3("net", 7, 2).C3("extra", 7, 2)
        .C3("carriage", 7, 2).C3("vat", 7, 2).C3("discount", 7, 2).C3("extraVat", 7, 2).C3("carriageVat", 7, 2)
        .C3("paid", 7, 2).N9("closed", 1).BChar("deductDays").Comp("deductAmount", 3, 2, true)
        .Comp("deductVat", 3, 2, true).BChar("days").BLong("creditFor").X("applied", 1).BLong("closedDate");
    private static readonly Layout AnalysisValueLayout = new Layout().X("code", 3).N9("account", 6)
        .X("description", 24).X("print", 3).Comp("countCurrent", 5).Comp("countLast", 5).Comp("countYear", 5)
        .C3("valueCurrent", 8, 2).C3("valueLast", 8, 2).C3("valueYear", 8, 2);
    private static readonly Layout SalesTotalsLayout = new Layout()
        .Group(10, (l, i) => l.C3("total" + i, 8, 2)).Fill(964);

    public bool HasOpenItems() => HasFile("openitm3.dat") && SystemRecord().I("File-Status-19") == 1;
    private Rec[] ReadOpenItems(string? code = null)
    {
        if (!HasOpenItems()) throw new SalesRuleException("売掛明細ファイルがありません。");
        var rows = db.Scan(OpenItemFile, code);
        if (code != null) rows = rows.TakeWhile(row => row.Key.StartsWith(code, StringComparison.Ordinal)).ToList();
        if (rows.Any(row => row.Data.Length != OpenItemLayout.Size))
            throw new SalesRuleException("売掛明細ファイルのレコード長が一致しません。（状態39）");
        return rows.Select(row => OpenItemLayout.From(row.Data)).ToArray();
    }

    public static string OpenItemType(int type) => type switch
    {
        5 => "入金", 6 => "未消込振替", 9 => "繰越入金", >= 1 and <= 4 => InvoiceType((InvoiceKind)type), _ => "その他"
    };

    public IReadOnlyList<SalesOpenItem> OpenItems(string code) => ReadOpenItems(code).Select(row =>
    {
        int type = row.I("type");
        decimal amount = row.N("net") + row.N("extra") + row.N("carriage") + row.N("vat") + row.N("discount") +
            row.N("extraVat") + row.N("carriageVat") + row.N("deductAmount") + row.N("deductVat");
        decimal paid = row.N("paid");
        if (type == 3) paid = -paid;
        if (type == 1) paid = amount;
        if (type is 5 or 6) amount = 0;
        return new SalesOpenItem(row.I("number"), row.I("date"), type, GetText(row, "description"), amount, paid,
            row.I("closed") == 1, !string.IsNullOrWhiteSpace(row.St("held")));
    }).ToArray();

    public string Statements(DateTime date, string pattern, bool aged)
    {
        int cutoff = EncodeDate(date);
        if (cutoff <= 0) throw new SalesRuleException("基準日を入力してください。");
        var sys = SystemRecord();
        var report = new StringBuilder(aged ? "売掛金年齢表\n" : "得意先明細書\n").AppendLine(GetText(sys, "Usera"))
            .AppendLine($"基準日　{ShowDate(cutoff)}");
        var ages = new[] { sys.I("SL-Days-1"), sys.I("SL-Days-2"), sys.I("SL-Days-3") };
        if (aged) report.AppendLine($"得意先番号　得意先名　{ages[0]}日未満　{ages[1]}日未満　{ages[2]}日未満　{ages[2]}日以上　残高");
        foreach (var c in Customers().Where(c => MatchCustomer(c, pattern)))
        {
            var items = OpenItems(c.Code).Where(i => !i.Closed && i.Date <= cutoff).ToArray();
            if (items.Length == 0) continue;
            if (aged)
            {
                var bands = new decimal[4];
                foreach (var item in items)
                {
                    int day = cutoff - item.Date;
                    int band = Array.FindIndex(ages, age => day < age);
                    bands[band < 0 ? 3 : band] += item.Outstanding;
                }
                report.AppendLine($"{c.Code}　{c.Details.Name}　{string.Join("　", bands.Select(Amount))}　{Amount(bands.Sum())}");
            }
            else
            {
                report.AppendLine($"{c.Code}　{c.Details.Name}");
                AppendAddress(report, c.Details.Address1, c.Details.Address2, sys.S("SL-Delim")[0]);
                report.AppendLine("日付　番号　種類　摘要　金額　入金額　残高");
                foreach (var item in items)
                    report.AppendLine($"{ShowDate(item.Date)}　{item.Number:D8}　{OpenItemType(item.Type)}　{item.Description}　{Amount(item.Amount)}　{Amount(item.Paid)}　{Amount(item.Outstanding)}");
                report.AppendLine($"合計　{Amount(items.Sum(i => i.Outstanding))}");
            }
        }
        return report.ToString();
    }

    public string Reminders(DateTime date, string pattern, decimal minimum, int low, int medium, int high)
    {
        int cutoff = EncodeDate(date);
        if (cutoff <= 0 || pattern.Length > 7 || minimum is < 0 or > 999999.99m ||
            low is < 0 or > 99 || medium is < 0 or > 99 || high is < 0 or > 99)
            throw new SalesRuleException("基準日、金額または経過日数を確認してください。");
        return db.Atomic(() =>
        {
            var sys = SystemRecord();
            var customers = Customers().Where(c => c.Details.Dunning && MatchCustomer(c, pattern)).ToArray();
            var report = new StringBuilder("督促状\n").AppendLine(GetText(sys, "Usera")).AppendLine($"基準日　{ShowDate(cutoff)}");
            var letters = Enumerable.Range(1, 3).Select(i => new StringBuilder()).ToArray();
            foreach (var customer in customers)
            {
                decimal balance = customer.Balance - customer.Unapplied;
                if (balance < 0.01m || balance < minimum) continue;
                var oldest = OpenItems(customer.Code).Where(i => !i.Closed && i.Type == 2 && i.Date < cutoff)
                    .Select(i => (int?)i.Date).Min();
                int overdue = oldest is int invoiceDate ? cutoff - invoiceDate : 0;
                if (overdue < low) continue;
                int level = overdue < medium ? 1 : overdue < high ? 2 : 3;
                var letter = new StringBuilder($"督促区分　{level}\n得意先　{customer.Code}　{customer.Details.Name}\n");
                AppendAddress(letter, customer.Details.Address1, customer.Details.Address2, sys.S("SL-Delim")[0]);
                letter.AppendLine($"請求日　{(oldest is int day ? ShowDate(day) : "")}　未入金額　{Amount(balance)}").AppendLine();
                report.Append(letter);
                letters[level - 1].Append(letter);
            }
            for (int i = 0; i < letters.Length; i++) KeepReport($"letter.{i + 1:D3}", letters[i].ToString());
            sys.SetN("SL-Days-1", low);
            sys.SetN("SL-Days-2", medium);
            sys.SetN("SL-Days-3", high);
            SaveSystem(sys);
            return report.ToString();
        });
    }

    private static bool MatchCustomer(SalesCustomer customer, string pattern) =>
        pattern.Length <= 7 && customer.Code.Length == 7 && pattern.ToUpperInvariant()
            .Select((ch, i) => ch is ' ' or '_' || ch == customer.Code[i]).All(m => m);

    public bool CheckCyclePassword(string password)
    {
        const string alphabet = "CKQUAELSMWYIZJRPBXFVGNODTH";
        if (password.Length > 4) return false;
        Span<byte> encoded = stackalloc byte[4];
        encoded.Fill(0x20);
        for (int i = 0; i < password.Length; i++)
        {
            if (!char.IsAsciiLetter(password[i])) continue;
            int index = alphabet.IndexOf(char.ToUpperInvariant(password[i])) + 1;
            int val = Math.Abs(index + (i + 1) * (i + 1) + 3 - 26);
            if (val is >= 1 and <= 26) encoded[3 - i] = (byte)alphabet[val - 1];
        }
        var sys = SystemRecord();
        var field = sys.L.F["Pass-Word"];
        return CryptographicOperations.FixedTimeEquals(encoded, sys.B.AsSpan(field.Off, field.Len));
    }

    public void CloseCycle(string password, bool quarterClose, bool allowUnposted, DateTime today) => db.Atomic(() =>
    {
        var sys = SystemRecord();
        if (sys.I("File-Status-15") != 1) throw new SalesRuleException("期間締めに必要なファイルがありません。");
        if (sys.I("S-Flag-A") == 1 || sys.I("P-Flag-A") == 1 || sys.I("S-Flag-P") is 1 or 2 || sys.I("P-Flag-P") is 1 or 2)
            throw new SalesRuleException("分析または入金処理が完了していません。");
        if (!allowUnposted && (sys.I("S-Flag-I") == 1 || sys.I("P-Flag-I") == 1))
            throw new SalesRuleException("未転記の請求書があります。");
        if (Environment.TickCount64 < cyclePasswordRetryAfter)
            throw new SalesRuleException("パスワードを続けて間違えたため、しばらく待ってから再試行してください。");
        if (!CheckCyclePassword(password))
        {
            if (++cyclePasswordFailures >= 5)
            {
                cyclePasswordRetryAfter = Environment.TickCount64 + 60_000;
                cyclePasswordFailures = 0;
            }
            throw new SalesRuleException("期間締めのパスワードが一致しません。");
        }
        cyclePasswordFailures = 0;
        _ = ReadOpenItems();
        int closeDate = EncodeDate(today);
        if (closeDate <= 0) throw new SalesRuleException("期間締めの日付が有効な範囲にありません。");
        int cycle = sys.I("Cyclea") + 1;
        int quarter = sys.I("Current-Quarter");
        bool advanceYear = sys.I("Period") switch { 3 => cycle == 13, 13 => cycle == 53, _ => quarterClose && quarter == 4 };
        bool advanceQuarter = advanceYear || (sys.I("Period") switch
        {
            3 => cycle is 4 or 7 or 10, 13 => cycle is 14 or 27 or 40, _ => quarterClose
        });
        if (advanceYear) cycle = quarter = 1;
        else if (advanceQuarter) quarter++;
        if (quarter is < 1 or > 4 || cycle is < 1 or > 127)
            throw new SalesRuleException("会計期間の設定を確認してください。");
        CloseCustomerBalances(advanceYear, advanceQuarter ? quarter : null);
        CloseOpenItems(sys.St("Sl-Own-Nos") == "Y");
        CloseAnalysisTotals(advanceYear);
        CloseInvoices(sys, closeDate);
        if (db.Read(SystemFile, "00000004") is { Length: 1024 } totalsBytes)
        {
            var totals = SalesTotalsLayout.From(totalsBytes);
            totals.SetN("total1", totals.N("total2"));
            for (int i = 2; i <= 8; i++) totals.SetN("total" + i, 0);
            db.Rewrite(SystemFile, "00000004", totals.B);
        }
        sys.SetN("Cyclea", cycle);
        sys.SetN("Current-Quarter", quarter);
        sys.SetN("S-End-Cycle-Date", closeDate);
        sys.Set("Oi-3-Flag", "Y");
        SaveSystem(sys);
        return true;
    });

    private void CloseCustomerBalances(bool newYear, int? quarter)
    {
        foreach (var (key, data) in db.Scan(CustomerFile))
        {
            if (data.Length != CustomerLayout.Size) throw new SalesRuleException("得意先ファイルのレコード長が一致しません。");
            var entry = CustomerLayout.From(data);
            decimal balance = entry.N("balance");
            decimal unapplied = entry.N("unapplied");
            if (balance == 0 && unapplied == 0 && entry.N("last") == 0) entry.SetN("active", 0);
            if (balance < 0)
            {
                entry.SetN("unapplied", unapplied - balance);
                entry.SetN("balance", 0);
            }
            entry.SetN("last", entry.N("balance"));
            if (quarter is int q) entry.SetN("quarter" + q, 0);
            if (newYear) { entry.SetN("average", 0); entry.SetN("activity", 0); }
            db.Rewrite(CustomerFile, key, entry.B);
        }
    }

    private void CloseOpenItems(bool ownNumbers)
    {
        foreach (var (key, data) in db.Scan(OpenItemFile))
        {
            var item = OpenItemLayout.From(data);
            if (item.I("closed") == 1 || item.I("type") == 1)
            {
                if (item.I("closed") == 1 && item.I("type") == 2 && !ownNumbers)
                {
                    string prefix = InvoiceKey(item.I("number"), " ", 0)[..^2];
                    foreach (var row in db.Scan(InvoiceFile, prefix).TakeWhile(row => row.Key.StartsWith(prefix, StringComparison.Ordinal)))
                        db.Delete(InvoiceFile, row.Key);
                }
                db.Delete(OpenItemFile, key);
                continue;
            }
            if (item.I("type") is 5 or 6) item.SetN("deductAmount", 0);
            item.Set("applied", "z");
            item.SetN("pc", 0);
            db.Rewrite(OpenItemFile, key, item.B);
        }
    }

    private void CloseAnalysisTotals(bool newYear)
    {
        if (newYear) { db.Recreate(ValueFile); return; }
        foreach (var (key, data) in db.Scan(ValueFile))
        {
            if (data.Length != AnalysisValueLayout.Size) throw new SalesRuleException("分析実績ファイルのレコード長が一致しません。");
            var item = AnalysisValueLayout.From(data);
            if (!item.St("code").StartsWith('S')) continue;
            item.SetN("countLast", item.N("countCurrent"));
            item.SetN("valueLast", item.N("valueCurrent"));
            item.SetN("countCurrent", 0);
            item.SetN("valueCurrent", 0);
            db.Rewrite(ValueFile, key, item.B);
        }
    }

    private void CloseInvoices(Rec sys, int closeDate)
    {
        if (db.Scan(InvoiceFile).Any(row => row.Data.Length != InvoiceSize))
            throw new SalesRuleException("請求書ファイルのレコード長が一致しません。");
        foreach (var invoice in Invoices())
        {
            var h = InvoiceHeader.From(db.Read(InvoiceFile, invoice.Key)!);
            bool applied = h.St("status") is "z" or "Z";
            int type = h.I("type");
            bool stripLines = applied && type == 2 && h.I("lines") != 0;
            bool remove = (type == 4 && closeDate - sys.I("PF-Retention") > h.I("date")) ||
                (applied && (type is 1 or 3 || (type == 2 && !stripLines && sys.St("Sl-Own-Nos") == "Y" && closeDate - 92 > h.I("date"))));
            if (stripLines) h.SetN("lines", 0);
            if (applied && type < 4) h.Set("dayBook", "B");
            foreach (var (key, data) in db.Scan(InvoiceFile, invoice.Key).TakeWhile(row =>
                row.Key.StartsWith(invoice.Key[..^2], StringComparison.Ordinal)))
            {
                if (data.Length != InvoiceSize) throw new SalesRuleException("請求書ファイルのレコード長が一致しません。");
                if (remove || (stripLines && key != invoice.Key)) db.Delete(InvoiceFile, key);
                else
                {
                    byte[] output = key == invoice.Key ? h.B[..InvoiceSize] : data;
                    output.AsSpan(129).Fill(0x20);
                    db.Rewrite(InvoiceFile, key, output);
                }
            }
        }
    }
}
