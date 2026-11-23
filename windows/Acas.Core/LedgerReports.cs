using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core;

public sealed class LedgerReports(Db database)
{
    public const string FinalFile = "ledgers/acas/final.dat";
    private static readonly Layout Final = new Layout().X("place", 1).N9("nos", 6).N9("pc", 2)
        .X("name", 24).C3("balance", 8, 2).C3("last", 8, 2);
    private static readonly string[] Categories =
        ["収益", "直接原価", "雑収益", "間接原価", "固定資産", "流動資産", "流動負債", "資本"];
    private const string Places = "11112222334444555666778888";
    private readonly SystemSettings _settings = new(database);

    public string? PrintChart()
    {
        if (!database.Exists(GeneralLedger.LedgerFile) || _settings.Read() is not { } system) return null;
        const string title = "勘定科目一覧";
        var report = new PagedReport(title, system, "勘定コード　部門・拠点　階層　科目名");
        var records = Records().ToArray();
        if (records.Length == 0) report.Line("勘定科目がありません。");
        foreach (var row in records)
        {
            int level = row.I("level");
            report.Line($"{Code(row)}　{row.S("pc")}　{(level == 0 ? "明細" : $"第{level}階層")}　{row.St("name")}");
        }
        return Save(title, report.ToString());
    }

    public string? TrialBalance(bool structured)
    {
        if (!database.Exists(GeneralLedger.LedgerFile) || _settings.Read() is not { } system) return null;
        string title = structured
            ? system.S("P-C") == "B" ? "拠点別試算表" : "部門別試算表"
            : "詳細試算表";
        var records = Records().ToArray();
        var (recent, previous) = system.I("Current-Quarter") switch
        {
            1 => (4, 3), 2 => (1, 4), 3 => (2, 1), 4 => (3, 2), _ => (0, 0)
        };
        string division = system.S("P-C") == "B" ? "拠点" : "部門";
        string columns = structured
            ? "勘定　階層　借方　貸方"
            : $"勘定　{division}　名称　当期借方　当期貸方　前期借方　前期貸方　第{recent}四半期　第{previous}四半期";
        var report = new PagedReport(title, system, columns);
        if (structured)
        {
            decimal debit = 0, credit = 0;
            RollUp(records, (level, row, dr, cr, parent) =>
            {
                if (row == null) return;
                decimal net = dr - cr;
                report.Line($"{Code(row)}　{(level == 5 ? "明細" : $"第{level}階層")}　{Money(level == 5 ? dr : Debit(net))}　{Money(level == 5 ? cr : Credit(net))}");
                if (!parent)
                {
                    debit += Debit(net);
                    credit += Credit(net);
                }
            });
            report.Line($"合計　{Money(debit)}　{Money(credit)}");
        }
        else
        {
            decimal currentDebit = 0, currentCredit = 0, priorDebit = 0, priorCredit = 0;
            foreach (var row in records)
            {
                decimal balance = row.N("balance"), last = row.N("last");
                currentDebit += Debit(balance);
                currentCredit += Credit(balance);
                priorDebit += Debit(last);
                priorCredit += Credit(last);
                string Quarter(int quarter) => quarter == 0 ? "" : Money(row.N("q" + quarter));
                report.Line($"{Code(row)}　{row.S("pc")}　{row.St("name")}　{Money(Debit(balance))}　{Money(Credit(balance))}　{Money(Debit(last))}　{Money(Credit(last))}　{Quarter(recent)}　{Quarter(previous)}");
            }
            report.Line($"合計　{Money(currentDebit)}　{Money(currentCredit)}　{Money(priorDebit)}　{Money(priorCredit)}");
        }
        return Save(title, report.ToString());
    }

    public string? FinancialStatements()
    {
        if (!database.Exists(GeneralLedger.LedgerFile) || _settings.Read() is not { } system) return null;
        const string title = "損益計算書・貸借対照表";
        string? body = null;
        database.Atomic(() =>
        {
            database.Recreate(FinalFile);
            RollUp(Records(), (level, row, debit, credit, _) =>
            {
                if (level != 1 || row == null) return;
                var final = Final.New();
                final.Set("place", row.S("place"));
                final.SetN("nos", row.I("nos"));
                final.Set("name", row.S("name"));
                final.SetN("balance", debit - credit);
                database.Write(FinalFile, final.S("place") + final.S("nos") + final.S("pc"), final.B);
            });

            var report = new StringBuilder();
            void Header(string label)
            {
                report.AppendLine($"{label}　{Date(system)}　{system.St("Usera")}");
                report.AppendLine("科目　当期　前期");
            }
            void Line(string name, decimal current, decimal last) =>
                report.AppendLine($"{name}　{Money(current)}　{Money(last)}");

            Header("損益計算書");
            string? place = null;
            string totalName = "";
            int category = 0;
            decimal currentTotal = 0, lastTotal = 0, currentRun = 0, lastRun = 0;
            decimal currentGross = 0, lastGross = 0, currentProfit = 0, lastProfit = 0;
            foreach (var (_, data) in database.Scan(FinalFile))
            {
                var row = Final.From(data);
                string nextPlace = row.S("place");
                if (nextPlace != place)
                {
                    int i = nextPlace[0] - 'A';
                    int next = i >= 0 && i < Places.Length ? Places[i] - '0' : 0;
                    if (next != category)
                    {
                        if (category != 0)
                        {
                            Line("小計", currentTotal, lastTotal);
                            int direction = category is 1 or 3 or 5 ? 1 : -1;
                            currentRun += direction * currentTotal;
                            lastRun += direction * lastTotal;
                            switch (next)
                            {
                                case 3:
                                    totalName = "売上総利益";
                                    Line(totalName, currentGross = currentRun, lastGross = lastRun);
                                    break;
                                case 5:
                                    totalName = "当期純利益";
                                    Line(totalName, currentProfit = currentRun + currentGross, lastProfit = lastRun + lastGross);
                                    Header("貸借対照表");
                                    break;
                                case 8:
                                    totalName = "正味流動資産";
                                    Line(totalName, currentRun, lastRun);
                                    break;
                            }
                            if (next is 3 or 5 or 8) currentRun = lastRun = 0;
                        }
                        if (next > 0) report.AppendLine(Categories[next - 1]);
                        category = next;
                        currentTotal = lastTotal = 0;
                    }
                    place = nextPlace;
                }
                int sign = category is 1 or 3 or 5 ? -1 : 1;
                decimal current = sign * row.N("balance"), last = sign * row.N("last");
                Line(row.St("name"), current, last);
                currentTotal += current;
                lastTotal += last;
            }
            Line("当期純利益", currentProfit, lastProfit);
            Line(totalName, currentRun + currentProfit, lastRun + lastProfit);
            body = Save(title, report.ToString());
        });
        return body;
    }

    private IEnumerable<Rec> Records() => database.Scan(GeneralLedger.LedgerFile)
        .Select(row => Layouts.Ledger.From(row.Data))
        .TakeWhile(row => row.I("nos") / 100 != 9999);

    private static void RollUp(IEnumerable<Rec> records, Action<int, Rec?, decimal, decimal, bool> output)
    {
        var rows = new Rec?[6];
        var debits = new decimal[6];
        var credits = new decimal[6];

        void Close(int level)
        {
            int parent = Math.Min(level - 1, 4);
            while (parent > 0 && rows[parent] == null) parent--;
            output(level, rows[level], debits[level], credits[level], parent > 0);
            if (parent > 0)
            {
                debits[parent] += debits[level];
                credits[parent] += credits[level];
            }
            rows[level] = null;
            debits[level] = credits[level] = 0;
        }

        foreach (var row in records)
        {
            int number = row.I("nos"), level = row.I("level");
            if (rows[5] is { } detail && detail.I("nos") != number) Close(5);
            if (rows.Skip(1).Take(4).Any(header => header?.I("nos") == number)) continue;
            if (level is >= 1 and <= 4)
            {
                if (rows[level] != null)
                    for (int i = 4; i >= level; i--) Close(i);
                rows[level] = row;
            }
            else
            {
                rows[5] = row;
                decimal balance = row.N("balance");
                debits[5] += Debit(balance);
                credits[5] += Credit(balance);
            }
        }
        for (int i = 5; i >= 1; i--) Close(i);
    }

    internal static string Date(Rec system) => $"{SystemSettings.Date(system, "Run-Date"):yyyy年M月d日}";
    internal static decimal Debit(decimal value) => Math.Max(value, 0);
    internal static decimal Credit(decimal value) => Math.Max(-value, 0);
    internal static string Money(decimal value) => value.ToString("0.00", CultureInfo.InvariantCulture);
    private static string Code(Rec row) => $"{row.S("nos")[..4]}.{row.S("nos")[4..]}";

    private string Save(string title, string body)
    {
        database.AddSpool(title, body);
        return body;
    }

    internal sealed class PagedReport(string title, Rec system, string columns)
    {
        private readonly StringBuilder _body = new();
        private int _lines, _page;

        public void Line(string text)
        {
            if (_page == 0 || _lines >= Math.Max(29, system.I("Page-Lines")))
            {
                if (_page != 0) _body.Append('\f');
                _body.AppendLine($"{title}　{++_page}ページ");
                _body.AppendLine($"{system.St("Usera")}　{Date(system)}");
                _body.AppendLine(columns);
                _lines = 3;
            }
            _body.AppendLine(text);
            _lines++;
        }

        public override string ToString() => _body.ToString();
    }
}
