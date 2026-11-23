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
    private static readonly string[] ChartPlacements =
        ["直接収益", "直接原価", "雑収益", "間接原価", "固定資産", "流動資産", "流動負債", "資本"];
    private const string Places = "11112222334444555666778888";
    private readonly SystemSettings _settings = new(database);

    public string? PrintChart()
    {
        if (!database.Exists(GeneralLedger.LedgerFile) || _settings.Read() is not { } system) return null;
        const string title = "勘定科目一覧";
        string division = system.S("P-C") switch { "B" => "拠点", "P" => "部門", _ => "" };
        var report = new PagedReport(title, system, $"階層       見出し        明細           {division,-13} 配置              科目名",
            LegacyDate(system, SystemSettings.Date(system, "Run-Date"), raw: true));
        var records = Records().ToArray();
        if (records.Length == 0) report.Line("勘定科目がありません。");
        foreach (var row in records)
        {
            int level = row.I("level");
            string heading = level == 0 ? "" : Code(row);
            string detail = level == 0 ? Code(row) : "";
            string pc = row.I("pc") == 0 ? "" : row.I("pc").ToString(CultureInfo.InvariantCulture);
            int placement = row.S("place")[0] - 'A';
            string category = level == 0 || placement is < 0 or > 25 ? "" : ChartPlacements[Places[placement] - '1'];
            string tier = level == 0 ? "" : new string(' ', level * 2) + level;
            report.Line($"{tier,-13}{heading,-14}{detail,-13}{pc,7}          {category,-19}{row.St("name")}");
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
        string division = system.S("P-C") switch { "B" => "拠点", "P" => "部門", _ => "" };
        string columns = structured
            ? $"{"勘定",-12}{"明細階層",-24}{"第4階層",-24}{"第3階層",-24}{"第2階層",-24}第1階層\n" +
              new string(' ', 12) + string.Concat(Enumerable.Repeat($"{"借方",-12}{"貸方",-12}", 5))
            : $"{"勘定",-12}{division,-8}{"科目名",-30}{"当期残高",-27}{"前年残高",-27}{"第" + recent + "四半期",-15}第{previous}四半期\n" +
              new string(' ', 50) + $"{"借方",-12}{"貸方",-15}{"借方",-12}貸方";
        var report = new PagedReport(title, system, columns,
            LegacyDate(system, SystemSettings.Date(system, "Run-Date")));
        report.Line("");
        if (structured)
        {
            decimal debit = 0, credit = 0;
            RollUp(records, (level, row, dr, cr, parent) =>
            {
                if (row == null) return;
                decimal net = dr - cr;
                string code = new string(' ', level - 1) + Code(row);
                report.Line(CostColumns(code, level == 5 ? dr : Debit(net), level == 5 ? cr : Credit(net), level));
                if (level == 1) report.Line("");
                if (!parent)
                {
                    debit += Debit(net);
                    credit += Credit(net);
                }
            }, retainDetailOnHeader: true);
            var rule = new string(' ', 108) + " ==========  ==========";
            report.Line("");
            report.Line("");
            report.Line(rule);
            report.Line($"{new string(' ', 20)}{"合計",-88}{Money(debit),11} {Money(credit),11}");
            report.Line(rule);
        }
        else
        {
            decimal currentDebit = 0, currentCredit = 0, priorDebit = 0, priorCredit = 0;
            int previousLedger = 0;
            foreach (var row in records)
            {
                int ledger = row.I("nos") / 100;
                if (ledger != previousLedger) report.Line("");
                previousLedger = ledger;
                decimal balance = row.N("balance"), last = row.N("last");
                currentDebit += Debit(balance);
                currentCredit += Credit(balance);
                priorDebit += Debit(last);
                priorCredit += Credit(last);
                string Quarter(int quarter) => quarter == 0 ? "" : EditedMoney(row.N("q" + quarter), true);
                string pc = row.I("pc") == 0 ? "" : row.I("pc").ToString(CultureInfo.InvariantCulture);
                report.Line(DetailColumns(Code(row), pc, row.St("name"), Debit(balance), Credit(balance), Debit(last), Credit(last),
                    Quarter(recent), Quarter(previous)));
            }
            var rule = new string(' ', 50) + "=========== ===========    =========== ===========";
            report.Line("");
            report.Line("");
            report.Line(rule);
            report.Line(DetailColumns("", "", "合計", currentDebit, currentCredit, priorDebit, priorCredit, "", ""));
            report.Line(rule);
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

    private static void RollUp(IEnumerable<Rec> records, Action<int, Rec?, decimal, decimal, bool> output,
        bool retainDetailOnHeader = false)
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
            if (rows[5] is { } detail && detail.I("nos") != number)
            {
                Close(5);
                if (retainDetailOnHeader && level != 0) rows[5] = detail;
            }
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
    internal static string LegacyDate(Rec system, DateTime? date, bool raw = false) =>
        date?.ToString((raw ? 1 : system.I("Date-Form")) switch
        {
            2 => "MM'/'dd'/'yyyy",
            3 => "yyyy'/'MM'/'dd",
            _ => "dd'/'MM'/'yyyy"
        }, CultureInfo.InvariantCulture) ?? "";
    private static string EditedMoney(decimal value, bool creditSuffix = false) => value == 0 ? "" :
        Money(Math.Abs(value)) + (creditSuffix && value < 0 ? "CR" : creditSuffix ? "  " : "");

    private static string DetailColumns(string code, string pc, string name, decimal currentDebit, decimal currentCredit,
        decimal priorDebit, decimal priorCredit, string recent, string previous) =>
        $"{code,-12}{pc,2}      {name,-30}{EditedMoney(currentDebit),11} {EditedMoney(currentCredit),11}    " +
        $"{EditedMoney(priorDebit),11} {EditedMoney(priorCredit),11}    {recent,13}  {previous,13}";

    private static string CostColumns(string code, decimal debit, decimal credit, int level) =>
        $"{code,-12}{new string(' ', (5 - level) * 24)}{EditedMoney(debit),11} {EditedMoney(credit),11} ";
    private static string Code(Rec row) => $"{row.S("nos")[..4]}.{row.S("nos")[4..]}";

    private string Save(string title, string body)
    {
        database.AddSpool(title, body);
        return body;
    }

    internal sealed class PagedReport(string title, Rec system, string columns, string? date = null)
    {
        private readonly StringBuilder _body = new();
        private int _lines, _page;

        public void Line(string text)
        {
            if (_page == 0 || _lines >= Math.Max(29, system.I("Page-Lines")))
            {
                if (_page != 0) _body.Append('\f');
                _body.AppendLine($"{title}　{++_page}ページ");
                _body.AppendLine($"{system.St("Usera")}　{date ?? Date(system)}");
                _body.AppendLine(columns);
                _lines = 3 + columns.Count(ch => ch == '\n');
            }
            _body.AppendLine(text);
            _lines++;
        }

        public override string ToString() => _body.ToString();
    }
}
