using System.Text;
using Acas.Core.Engine;

namespace Acas.Core;

public sealed record LedgerBatch(int Ledger, int Number, int Cycle, int Items, int Status, int Cleared,
    DateTime? Activity, decimal InputGross, decimal InputTax, decimal ActualGross, decimal ActualTax, string Description);

public sealed record BatchPosting(string Key, int Number, string Date, AccountCode Account, decimal Amount, decimal Tax, string Description);

public sealed partial class JournalBatches(Db database)
{
    private readonly SystemSettings _settings = new(database);
    private static readonly DateTime Epoch = new(1600, 12, 31);

    public IReadOnlyList<LedgerBatch> Current()
    {
        if (_settings.Read() is not { } system) return [];
        return ReadBatches().Where(batch => batch.Record.I("bcycle") == system.I("Cyclea"))
            .Select(batch => Decode(batch.Record)).ToArray();
    }

    public LedgerBatch? Find(int number) => ReadBatch(number) is { } batch ? Decode(batch) : null;

    public IReadOnlyList<BatchPosting> Entries(int number)
    {
        if (ReadBatch(number) is not { } batch) return [];
        bool debit = batch.S("convention") == "DR";
        return database.Scan(JournalEntry.PostingFile).Select(row => (row.Key, Posting: Layouts.Posting.From(row.Data)))
            .Where(row => row.Posting.I("batch") == number)
            .Select(row =>
            {
                var p = row.Posting;
                int account = p.I(debit ? "post-dr" : "post-cr");
                return new BatchPosting(row.Key, p.I("post-number"), p.S("post-date"), new(account / 100, account % 100, p.I(debit ? "dr-pc" : "cr-pc")),
                    p.N("post-amount"), p.N("vat-amount"), p.St("post-legend"));
            }).ToArray();
    }

    public JournalError AmendEntry(int batchNumber, BatchPosting entry, DateTime? date, AccountCode account,
        decimal amount, decimal? tax, int rateIndex, string calculation, string description)
    {
        if (date?.Date <= Epoch || account.Ledger is < 1000 or >= 9999 || account.Sub is < 0 or > 99 || account.Division is < 0 or > 99 ||
            !PostingAmount(amount) || (tax is decimal enteredTax && !PostingAmount(enteredTax)) ||
            rateIndex is < 1 or > 3 || calculation is not ("" or "P" or "M") || !GeneralLedger.Fits(description, 32))
            return JournalError.Line;

        var result = JournalError.Number;
        database.Atomic(() =>
        {
            if (_settings.Read() is not { } system || ReadBatch(batchNumber) is not { } batch ||
                database.Read(JournalEntry.PostingFile, entry.Key) is not { } data) return;
            var posting = Layouts.Posting.From(data);
            if (posting.I("batch") != batchNumber || posting.I("post-number") != entry.Number) return;
            if ((account.Division != 0 && system.S("P-C") is not ("P" or "B")) ||
                database.Read(GeneralLedger.LedgerFile, account.Key) == null)
            {
                result = JournalError.Line;
                return;
            }
            decimal rate = system.N("Vat-Rate-" + rateIndex);
            bool autoVat = system.S("Vat") == "Y";
            decimal taxValue = tax ?? (autoVat ? calculation switch
            {
                "P" => Cob.Round(amount * rate / 100, 2),
                "M" when rate > -100 => Cob.Round(amount - amount / (1 + rate / 100), 2),
                _ => 0
            } : posting.N("vat-amount"));
            if (autoVat && calculation == "M") amount -= taxValue;
            if (!PostingAmount(amount) || !PostingAmount(taxValue))
            {
                result = JournalError.Line;
                return;
            }
            bool debit = batch.S("convention") == "DR";
            posting.SetN(debit ? "post-dr" : "post-cr", account.Ledger * 100 + account.Sub);
            posting.SetN(debit ? "dr-pc" : "cr-pc", account.Division);
            if (date is DateTime updated) posting.Set("post-date", JournalEntry.FormatDate(updated, system));
            posting.SetN("post-amount", amount);
            posting.SetN("vat-amount", taxValue);
            posting.Set("post-legend", description);
            database.Rewrite(JournalEntry.PostingFile, entry.Key, posting.B);
            result = JournalError.None;
        });
        return result;
    }

    public JournalError Amend(int number, int cycle, int items, decimal gross, decimal tax, string description)
    {
        if (items is < 0 or > 99 || !Amount(gross) || !Amount(tax) || !GeneralLedger.Fits(description, 24))
            return JournalError.Header;
        var result = JournalError.Number;
        database.Atomic(() =>
        {
            if (_settings.Read() is not { } system || ReadBatch(number) is not { } batch) return;
            if (cycle < system.I("Cyclea") || cycle > system.I("Cyclea") + 1 || cycle > 99)
            {
                result = JournalError.Cycle;
                return;
            }
            batch.SetN("bcycle", cycle);
            batch.SetN("items", items);
            batch.SetN("input-gross", gross);
            if (system.S("Vat") == "Y") batch.SetN("input-vat", tax);
            batch.Set("description", description);
            database.Rewrite(JournalEntry.BatchFile, Key(number), batch.B);
            result = JournalError.None;
        });
        return result;
    }

    public string? Proof(int? number)
    {
        if (_settings.Read() == null || !database.Exists(JournalEntry.PostingFile)) return null;
        string? body = null;
        database.Atomic(() =>
        {
            var system = _settings.Read()!;
            (string Key, Rec Record)[] batches = number is int id
                ? ReadBatch(id) is { } record ? [(Key(id), record)] : []
                : ReadBatches().Where(batch => batch.Record.I("bcycle") == system.I("Cyclea") && batch.Record.I("cleared-status") == 0).ToArray();
            if (batches.Length == 0) return;
            var postings = ReadPostings().ToLookup(record => record.I("batch"));
            var contents = new List<string>();
            foreach (var (key, batch) in batches)
            {
                var lines = postings[batch.I("batch-nos")].ToArray();
                decimal net = lines.Sum(p => p.N("post-amount"));
                decimal tax = lines.Sum(p => p.N("vat-amount"));
                bool valid = lines.All(AccountsExist);
                bool verified = valid && batch.N("input-gross") == net + tax && batch.N("input-vat") == tax;
                batch.SetN("batch-status", verified ? 1 : 0);
                batch.SetN("actual-gross", valid ? net + tax : net);
                batch.SetN("actual-vat", tax);
                if (number != null) batch.SetN("proofed", batch.I("entered"));
                database.Rewrite(JournalEntry.BatchFile, key, batch.B);
                contents.Add(FormatProof(batch, lines, system.I("Page-Lines"), valid, verified));
            }
            body = string.Join('\f', contents);
            database.AddSpool("仕訳検証帳票", body);
        });
        return body;
    }

    public string? PrintTransactions()
    {
        if (_settings.Read() is not { } system) return null;
        int pageLines = system.I("Page-Lines");
        var lines = ReadPostings().GroupBy(p => p.I("batch")).Select(group =>
            FormatProof(ReadBatch(group.Key), group, pageLines, null, null, group.Key)).ToArray();
        string body = lines.Length == 0 ? "全仕訳一覧\n仕訳がありません。" : string.Join('\f', lines);
        database.AddSpool("全仕訳一覧", body);
        return body;
    }

    public string? PrintStatus()
    {
        if (_settings.Read() is not { } system) return null;
        var report = new StringBuilder();
        int page = 0, lines = 0;
        void BeginPage()
        {
            if (++page > 1) report.Append('\f');
            report.AppendLine($"バッチ状況帳票　{page}ページ");
            report.AppendLine($"会計期間　{system.I("Cyclea"),2}　{LedgerReports.LegacyDate(system, SystemSettings.Date(system, "Run-Date"))}");
            report.AppendLine("台帳　バッチ　状態　最終処理日　　　　　　　　バッチ照合");
            report.AppendLine("　　　　　　　　　　　　　　　　　　　　　　 件数　総額　税額");
            lines = 4;
        }
        BeginPage();
        foreach (var row in Current())
        {
            if (lines >= Math.Max(29, system.I("Page-Lines"))) BeginPage();
            report.AppendLine();
            report.AppendLine(FormattableString.Invariant($"{LedgerName(row.Ledger),-8}{row.Number,5}  {StatusName(row),-11}{LedgerReports.LegacyDate(system, row.Activity),-14}{"入力",-9}{row.Items,2}    {row.InputGross,12:0.00} {Tax(row.InputTax),12}"));
            report.AppendLine(FormattableString.Invariant($"{new string(' ', 40)}{"実績",-9}{row.Items,2}    {row.ActualGross,12:0.00} {Tax(row.ActualTax),12}"));
            lines += 3;
        }
        string body = report.ToString();
        database.AddSpool("バッチ状況帳票", body);
        return body;

        static string Tax(decimal amount) => amount == 0 ? "" : LedgerReports.Money(amount);
    }

    public static string LedgerName(int ledger) => ledger switch { 1 => "総勘定", 2 => "買掛", 3 => "売掛", _ => "" };
    public static string StatusName(LedgerBatch batch) =>
        batch.Status == 0 ? "未照合" : batch.Cleared switch { 0 => "転記待ち", 1 => "転記済み", 2 => "保管済み", _ => "" };

    private IEnumerable<(string Key, Rec Record)> ReadBatches() => database.Scan(JournalEntry.BatchFile)
        .Where(row => row.Key.Length == 6 && row.Key[0] is '1' or '2' or '3')
        .Select(row => (row.Key, Layouts.Batch.From(row.Data)));

    private IEnumerable<Rec> ReadPostings() => database.Scan(JournalEntry.PostingFile)
        .Select(row => Layouts.Posting.From(row.Data)).Where(record => record.I("batch") != 0);

    private Rec? ReadBatch(int number) =>
        number is >= 0 and <= 99999 && database.Read(JournalEntry.BatchFile, Key(number)) is { } record
            ? Layouts.Batch.From(record) : null;

    private bool AccountsExist(Rec posting) =>
        database.Read(GeneralLedger.LedgerFile, posting.S("post-dr") + posting.S("dr-pc")) != null &&
        database.Read(GeneralLedger.LedgerFile, posting.S("post-cr") + posting.S("cr-pc")) != null;

    private string FormatProof(Rec? batch, IEnumerable<Rec> postings, int pageLines, bool? valid, bool? verified, int? number = null)
    {
        var report = new StringBuilder();
        string title = valid == null ? "全仕訳一覧" : "仕訳検証帳票";
        var header = batch == null ? null : Decode(batch);
        const string Columns = "番号　取引区分　日付　借方　部門　貸方　部門　税抜額　税額　税勘定　部門　税区分　摘要";
        int page = 0, count = 0;
        void BeginPage()
        {
            if (page > 0) report.Append('\f');
            report.AppendLine($"{title}　{++page}ページ");
            report.AppendLine($"バッチ {(number ?? header?.Number):00000}　{header?.Description}　{header?.Activity:yyyy年M月d日}");
            report.AppendLine(Columns);
            count = 3;
        }
        BeginPage();
        foreach (var p in postings)
        {
            if (count >= Math.Max(29, pageLines) - 6) BeginPage();
            string taxAccount = p.I("vat-ac") == 0 ? "" : p.S("vat-ac");
            string taxSide = taxAccount.Length == 0 ? "" : p.S("post-vat-side") == "DR" ? "借方" : "貸方";
            report.AppendLine(FormattableString.Invariant($"{p.I("post-number"),5}　{p.S("post-code")}　{p.S("post-date")}　{p.S("post-dr")}　{p.S("dr-pc")}　{p.S("post-cr")}　{p.S("cr-pc")}　{p.N("post-amount"),12:0.00}　{p.N("vat-amount"),12:0.00}　{taxAccount,6}　{p.S("vat-pc")}　{taxSide}　{p.St("post-legend")}"));
            count++;
            if (!AccountsExist(p))
            {
                report.AppendLine("指定された借方または貸方の勘定科目が見つかりません。");
                count++;
            }
        }
        if (valid == true && header != null)
        {
            report.AppendLine(FormattableString.Invariant($"ヘッダー　税抜額 {header.InputGross - header.InputTax:0.00}　税額 {header.InputTax:0.00}"));
            report.AppendLine(FormattableString.Invariant($"実績　　　税抜額 {header.ActualGross - header.ActualTax:0.00}　税額 {header.ActualTax:0.00}"));
        }
        if (verified != null) report.AppendLine(verified == true ? "照合結果：一致" : "照合結果：不一致");
        return report.ToString();
    }

    private static LedgerBatch Decode(Rec batch)
    {
        int days = new[] { "stored", "posted", "proofed", "entered" }.Select(batch.I).FirstOrDefault(day => day > 0);
        DateTime? date = days > 0 && days <= (DateTime.MaxValue.Date - Epoch).Days ? Epoch.AddDays(days) : null;
        return new LedgerBatch(batch.I("ledger"), batch.I("batch-nos"), batch.I("bcycle"), batch.I("items"),
            batch.I("batch-status"), batch.I("cleared-status"), date, batch.N("input-gross"), batch.N("input-vat"),
            batch.N("actual-gross"), batch.N("actual-vat"), batch.St("description"));
    }

    private static string Key(int number) => "1" + Cob.P9(number, 5);
    private static bool Amount(decimal value) => value is >= 0 and <= 999999999.99m && Cob.Trunc(value, 2) == value;
    private static bool PostingAmount(decimal value) => value is >= -99999999.99m and <= 99999999.99m && Cob.Trunc(value, 2) == value;
}
