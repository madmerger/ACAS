using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Irs;

public sealed record IrsReport(string Title, string Body, string? LegacyBody = null);
public sealed record IrsHeading(int Slot, string Title, string Sign);

public sealed partial class IrsBookkeeping
{
    private const string FinalsFile = Directory + "final.dat";
    private static readonly Layout HeadingLayout = new Layout().Group(26, (l, i) => l.X("title" + i, 24))
        .Group(26, (l, i) => l.X("sign" + i, 1)).X("filler", 5);

    public void SaveReport(IrsReport report) => db.AddSpool(Directory + "prt-1", report.Body);

    private static string Money(decimal amount) => amount.ToString("0.00", CultureInfo.InvariantCulture);
    private string Header(string title) => $"{title}\n{Configuration().Client}　{Today:yyyy年M月d日}\n\n";

    public IrsReport AccountReport()
    {
        const string title = "勘定科目表";
        var config = Configuration();
        var report = new StringBuilder(Header(title)).AppendLine("主勘定　補助勘定　勘定名　勘定区分");
        var legacy = new StringBuilder("\n").Append(config.Operator.PadRight(28))
            .Append("Incomplete Records System".PadRight(44)).Append(IrsRecords.DateText(Today)).Append("\n\n")
            .Append(config.Client.PadRight(31)).Append("Accounts Directory".PadRight(40)).Append("Page -  1\n\n")
            .Append("             Main A/C       Sub-Account     ------Description------    A/C Type\n\n");
        foreach (var account in Accounts())
        {
            string owner = Cob.P9(account.Code, 5);
            string child = account.SubAccount == 0 ? "" : Cob.P9(account.SubAccount, 5);
            report.AppendLine($"{owner}　{child.PadRight(5)}　{account.Name}　{account.Category}");
            legacy.Append(' ', 14).Append(owner).Append(' ', 11).Append(child.PadRight(14))
                .Append(account.Name.PadRight(24)).Append(' ', 7).Append(account.Category).Append('\n');
        }
        return new(title, report.ToString(), legacy.ToString());
    }

    public IrsReport DefaultReport()
    {
        const string title = "転記の既定勘定";
        var config = Configuration();
        var report = new StringBuilder(Header(title)).AppendLine("番号　勘定コード　勘定名　取引区分　付加価値税");
        var legacy = new StringBuilder("\n").Append(config.Operator.PadRight(29))
            .Append("Incomplete Records System".PadRight(42)).Append(IrsRecords.DateText(Today)).Append("\n\n")
            .Append(config.Client.PadRight(33)).Append("Posting Defaults\n\n")
            .Append("             A/C Nos     ------Description------    Code VAT\n\n\n");
        foreach (var item in Defaults())
        {
            string slot = item.Slot.ToString(CultureInfo.InvariantCulture);
            legacy.Append(slot.PadLeft(12));
            report.Append(slot.PadLeft(2));
            if (item.Account != 0)
            {
                string code = Cob.P9(item.Account, 5);
                string tax = item.Tax switch { "I" => "仕入税", "O" => "売上税", _ => "対象外" };
                report.Append($"　{code}　{item.Name}　{item.Code}　{tax}");
                legacy.Append("  ").Append(code).Append("      ").Append(item.Name.PadRight(28))
                    .Append(item.Code).Append("     ").Append(item.Tax);
            }
            report.AppendLine();
            legacy.Append('\n');
        }
        return new(title, report.ToString(), legacy.ToString());
    }

    public IrsReport TrialBalance(bool details, bool includeZero)
    {
        const string title = "試算表";
        var accounts = Accounts();
        var rows = details ? accounts : accounts.GroupBy(x => x.Code).Select(group =>
        {
            var first = group.First();
            return first with { SubAccount = 0, Debit = group.Sum(x => x.Debit), Credit = group.Sum(x => x.Credit) };
        }).ToArray();
        var report = new StringBuilder(Header(title)).AppendLine("勘定コード　勘定名　借方　貸方　残高");
        foreach (var a in rows.Where(x => includeZero || x.Balance != 0))
            report.AppendLine($"{Key(a.Code, a.SubAccount)}　{a.Name}　{Money(a.Debit)}　{Money(a.Credit)}　{Money(a.Balance)}");
        report.AppendLine($"合計　{Money(accounts.Sum(a => a.Debit))}　{Money(accounts.Sum(a => a.Credit))}　{Money(accounts.Sum(a => a.Balance))}");
        return new(title, report.ToString());
    }

    public IrsReport AuditReport(string type, string order, DateTime? start = null, DateTime? end = null)
    {
        string title = type switch { "L" => "元帳明細", "D" => "付加価値税日計帳", _ => "監査証跡" };
        IEnumerable<IrsJournalEntry> rows = Journal();
        rows = order switch
        {
            "1" => rows.OrderBy(r => r.Code, StringComparer.Ordinal).ThenBy(r => r.Number),
            "2" => rows.OrderBy(r => r.Date).ThenBy(r => r.Number),
            _ => rows.OrderBy(r => r.Number)
        };
        if (type != "D") return JournalReport(title, rows);
        var settings = Configuration();
        return VatDaybook(title, rows, start ?? settings.Start, end ?? settings.End);
    }

    private IrsReport VatDaybook(string title, IEnumerable<IrsJournalEntry> rows, DateTime? start, DateTime? end)
    {
        const int amountWidth = 13;
        string Amount(decimal? value) => (value is decimal amount ? Money(amount) : "").PadLeft(amountWidth);
        string Columns(decimal? inputNet, decimal? inputTax, decimal? outputNet, decimal? outputTax) =>
            $" | {Amount(inputNet)} | {Amount(inputTax)} | {Amount(outputNet)} | {Amount(outputTax)} | ";
        string Heading(string caption, int width) => caption.PadLeft(width - caption.Length);
        var report = new StringBuilder(Header(title)).Append(Heading("番号", 5)).Append(" | ").Append(Heading("日付", 14));
        foreach (string label in new[] { "仕入税抜", "仕入税額", "売上税抜", "売上税額" })
            report.Append(" | ").Append(Heading(label, amountWidth));
        report.AppendLine(" | 摘要");
        decimal inputNet = 0, inputTax = 0, outputNet = 0, outputTax = 0;
        foreach (var row in rows.Where(r => r.TaxDefault is 31 or 32 && r.Date >= start && r.Date <= end))
        {
            bool input = row.TaxDefault == 31;
            int sign = row.TaxSide == (input ? "CR" : "DR") ? -1 : 1;
            decimal net = sign * row.Amount, tax = sign * row.Tax;
            if (input) { inputNet += net; inputTax += tax; }
            else { outputNet += net; outputTax += tax; }
            string columns = input ? Columns(net, tax, null, null) : Columns(null, null, net, tax);
            report.AppendLine($"{Cob.P9(row.Number, 5)} | {row.Date:yyyy年MM月dd日}{columns}{row.Legend}");
        }
        report.Append(Heading("合計", 5)).Append(" | ").Append(' ', 14)
            .AppendLine(Columns(inputNet, inputTax, outputNet, outputTax));
        return new(title, report.ToString());
    }

    public IrsReport JournalReport(string title, IEnumerable<IrsJournalEntry> rows)
    {
        var report = new StringBuilder(Header(title)).AppendLine("番号　日付　借方　貸方　摘要　金額　付加価値税");
        decimal amount = 0, tax = 0;
        foreach (var row in rows)
        {
            report.AppendLine($"{Cob.P9(row.Number, 5)}　{row.Date:yyyy年M月d日}　{Cob.P9(row.Debit, 5)}　{Cob.P9(row.Credit, 5)}　{row.Legend}　{Money(row.Amount)}　{Money(row.Tax)}");
            amount += row.Amount;
            tax += row.Tax;
        }
        report.AppendLine($"合計　{Money(amount)}　{Money(tax)}");
        return new(title, report.ToString());
    }

    public IReadOnlyList<IrsHeading> Headings()
    {
        var row = db.Read(FinalsFile, "1") is { } data ? ReadRecord(HeadingLayout, data, 650) : HeadingLayout.New();
        return Enumerable.Range(1, 26).Select(i => new IrsHeading(i, IrsRecords.Text(row, "title" + i),
            row.St("sign" + i))).ToArray();
    }

    public void SaveHeadings(IEnumerable<IrsHeading> headings)
    {
        var row = HeadingLayout.New();
        foreach (var item in headings)
        {
            if (item.Slot is < 1 or > 26 || item.Sign is not ("" or "+" or "-"))
                throw new IrsException("決算書の表示符号が正しくありません。");
            IrsRecords.Text(row, "title" + item.Slot, item.Title);
            row.Set("sign" + item.Slot, item.Sign);
        }
        int size = Math.Max(650, Array.FindLastIndex(row.B, b => b != (byte)' ') + 1);
        db.Put(FinalsFile, "1", row.B[..size]);
    }

    public IrsReport FinalAccounts(int comparison)
    {
        if (comparison is < 0 or > 4) throw new IrsException("比較年度は０～４から選択してください。");
        const string title = "決算書";
        var accounts = db.Scan(AccountsFile).Select(x => ReadRecord(IrsRecords.Account, x.Data, IrsRecords.Account.Size))
            .Where(x => x.St("kind") == "O").ToArray();
        var report = new StringBuilder(Header(title)).AppendLine("区分　当期　比較年度");
        var amounts = new decimal[26];
        var priors = new decimal[26];
        foreach (var line in Headings())
        {
            string category = ((char)('A' + line.Slot - 1)).ToString();
            var group = accounts.Where(a => a.St("category") == category).ToArray();
            var amount = group.Sum(a => a.N("debit") - a.N("credit"));
            var prior = comparison == 0 ? 0 : group.Sum(a => a.N("debit" + comparison) - a.N("credit" + comparison));
            int sign = line.Sign == "-" ? -1 : 1;
            amounts[line.Slot - 1] = amount;
            priors[line.Slot - 1] = prior;
            if (group.Length != 0 || line.Title != "")
                report.AppendLine($"{(line.Title == "" ? $"区分 {category}" : line.Title)}　{Money(sign * amount)}　{Money(sign * prior)}");
            if (category == "H")
                report.AppendLine($"売上総利益　{Money(-amounts[..8].Sum())}　{Money(-priors[..8].Sum())}");
            if (category == "T")
                report.AppendLine($"資産合計　{Money(amounts[14..20].Sum())}　{Money(priors[14..20].Sum())}");
        }
        return new(title, report.ToString());
    }

    public byte[] ExportAccounts(bool csv)
    {
        using var output = new MemoryStream();
        foreach (var (_, data) in db.Scan(AccountsFile))
        {
            var row = ReadRecord(IrsRecords.Account, data, IrsRecords.Account.Size);
            if (row.S("kind") != "O") continue;
            var kind = row.I("child") == 0 ? "O" : "S";
            byte[] line = csv
                ? IrsRecords.Encode($"C{row.S("owner")},{row.S("child")},{CsvCell(IrsRecords.Text(row, "name"))},{row.S("category")},{kind}", 256)
                : [(byte)'T', .. row.B[..10], (byte)kind[0], .. row.B[11..35], row.B[^1]];
            output.Write(line);
            output.WriteByte(10);
        }
        return output.ToArray();
    }

    private static string CsvCell(string value)
    {
        var trimmed = value.TrimStart();
        if ((trimmed.Length > 0 && trimmed[0] is '=' or '+' or '-' or '@') ||
            (value.Length > 0 && value[0] is '\t' or '\r' or '\n'))
            value = "'" + value;
        return "\"" + value.Replace("\"", "\"\"") + "\"";
    }

    public int ImportAccounts(byte[] archive)
    {
        var lines = global::System.Text.Encoding.Latin1.GetString(archive).Split('\n');
        var accounts = new Dictionary<string, Rec>(StringComparer.Ordinal);
        foreach (var raw in lines)
        {
            string line = raw.TrimEnd('\r');
            if (line.Length == 0) continue;
            if (line.Length != 37 || line[0] != 'T' || !line.AsSpan(1, 10).ToArray().All(char.IsAsciiDigit))
                throw new IrsException("科目表の固定長テキスト形式ではありません。");
            var row = IrsRecords.Account.New();
            var bytes = global::System.Text.Encoding.Latin1.GetBytes(line);
            bytes.AsSpan(1, 35).CopyTo(row.B);
            row.Set("kind", "O");
            row.B[^1] = bytes[^1];
            if (!accounts.TryAdd(line.Substring(1, 10), row))
                throw new IrsException("科目表に重複する勘定コードがあります。");
        }
        if (accounts.Count == 0) throw new IrsException("取り込む科目がありません。");
        int count = accounts.Count;
        foreach (var account in accounts.Values.Where(row => row.I("child") != 0).ToArray())
        {
            var reference = account.Clone();
            int child = account.I("child");
            reference.SetN("owner", child);
            reference.SetN("child", 0);
            reference.Set("kind", "S");
            var pointer = global::System.Text.Encoding.ASCII.GetBytes(Cob.P9(account.I("owner"), 5));
            pointer.CopyTo(reference.B, reference.L.F["name"].Off);
            if (!accounts.TryAdd(Key(child), reference))
                throw new IrsException("科目表に重複する補助勘定コードがあります。");
        }
        db.Atomic(() =>
        {
            db.Recreate(AccountsFile);
            foreach (var (key, row) in accounts) db.Write(AccountsFile, key, row.B);
        });
        return count;
    }
}
