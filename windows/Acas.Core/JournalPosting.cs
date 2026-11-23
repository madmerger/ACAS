using System.Text;
using Acas.Core.Engine;

namespace Acas.Core;

public enum PostingStatus { Posted, MissingFiles, OpenBatches, NothingToPost, MissingAccount }

public sealed record PostingResult(PostingStatus Status, string? Report = null);

public sealed partial class JournalBatches
{
    public PostingResult Post()
    {
        var result = new PostingResult(PostingStatus.MissingFiles);
        database.Atomic(() =>
        {
            if (_settings.Read() is not { } system || !database.Exists(JournalEntry.BatchFile)) return;
            var current = ReadBatches().Where(b => b.Record.I("bcycle") == system.I("Cyclea")).ToArray();
            if (current.Any(b => b.Record.I("batch-status") == 0))
            {
                result = new(PostingStatus.OpenBatches);
                return;
            }

            var waiting = current.Where(b => b.Record.I("ledger") == 1 && b.Record.I("batch-status") == 1 &&
                b.Record.I("cleared-status") == 0).ToArray();
            var postings = ReadPostings().ToLookup(p => p.I("batch"));
            var movements = waiting.Select(b => (b.Key, b.Record,
                Lines: postings[b.Record.I("batch-nos")].SelectMany(ExpandPosting)
                    .OrderBy(m => m.Account, StringComparer.Ordinal).ThenBy(m => m.Number).ToArray()))
                .Where(b => b.Lines.Length != 0).ToArray();
            if (movements.Length == 0)
            {
                result = new(PostingStatus.NothingToPost);
                return;
            }
            var accounts = new Dictionary<string, Rec>(StringComparer.Ordinal);
            foreach (string key in movements.SelectMany(b => b.Lines).Select(m => m.Account).Distinct())
            {
                if (database.Read(GeneralLedger.LedgerFile, key) is not { } data)
                {
                    result = new(PostingStatus.MissingAccount);
                    return;
                }
                accounts.Add(key, Layouts.Ledger.From(data));
            }

            var report = new StringBuilder();
            int page = 0, count = 0;
            int pageLines = Math.Max(29, system.I("Page-Lines"));
            var date = SystemSettings.Date(system, "Run-Date");
            foreach (var (key, batch, lines) in movements)
            {
                void BeginPage()
                {
                    if (page != 0) report.Append('\f');
                    report.AppendLine($"仕訳転記帳票　{++page}ページ");
                    report.AppendLine($"会計期間 {batch.I("bcycle"):00}　バッチ {batch.I("batch-nos"):00000}　{date:yyyy年M月d日}　{batch.St("description")}");
                    report.AppendLine("勘定　部門　仕訳番号　日付　借方　貸方　残高　摘要");
                    count = 3;
                }

                BeginPage();
                foreach (var group in lines.GroupBy(m => m.Account))
                {
                    var account = accounts[group.Key];
                    var balance = account.N("balance");
                    decimal debits = Math.Max(0, balance), credits = Math.Max(0, -balance);
                    string code = $"{group.Key[..6]}　{group.Key[6..]}";
                    void WriteBalance(string label)
                    {
                        report.AppendLine(FormattableString.Invariant($"{code}　　{date:yyyy年M月d日}　{debits:0.00}　{credits:0.00}　{balance:0.00}　{label}"));
                        count++;
                    }

                    WriteBalance("繰越残高");
                    foreach (var movement in group)
                    {
                        if (count >= pageLines - 1)
                        {
                            WriteBalance("小計");
                            BeginPage();
                            WriteBalance("繰越残高");
                        }
                        debits += Math.Max(0, movement.Amount);
                        credits += Math.Max(0, -movement.Amount);
                        balance = (balance + movement.Amount) % 100000000m;
                        report.AppendLine(FormattableString.Invariant($"{code}　{movement.Number:00000}　{movement.Date}　{Math.Max(0, movement.Amount):0.00}　{Math.Max(0, -movement.Amount):0.00}　　{movement.Description}"));
                        count++;
                    }
                    WriteBalance(account.St("name"));
                    account.SetN("balance", balance);
                    database.Rewrite(GeneralLedger.LedgerFile, group.Key, account.B);
                }
                batch.SetN("cleared-status", 1);
                batch.SetN("posted", system.I("Run-Date"));
                database.Rewrite(JournalEntry.BatchFile, key, batch.B);
            }
            string body = report.ToString();
            database.AddSpool("仕訳転記帳票", body);
            result = new(PostingStatus.Posted, body);
        });
        return result;
    }

    private sealed record Movement(string Account, int Number, string Date, decimal Amount, string Description);

    private static IEnumerable<Movement> ExpandPosting(Rec line)
    {
        var amount = line.N("post-amount");
        var tax = line.N("vat-amount");
        var side = line.S("post-vat-side");
        Movement Move(string account, string division, decimal value) => new(line.S(account) + line.S(division),
            line.I("post-number"), line.S("post-date"), value % 100000000m, line.St("post-legend"));
        yield return Move("post-dr", "dr-pc", amount + (side == "CR" ? tax : 0));
        yield return Move("post-cr", "cr-pc", -(amount + (side == "DR" ? tax : 0)));
        if (tax != 0 && line.I("vat-ac") != 0)
            yield return Move("vat-ac", "vat-pc", side == "CR" ? -tax : tax);
    }
}
