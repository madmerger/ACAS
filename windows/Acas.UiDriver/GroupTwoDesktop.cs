using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;
using Acas.Verify;
using Acas.Verify.Sales;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace Acas.UiDriver;

internal sealed partial class Desktop
{
    private static readonly IReadOnlyDictionary<string, string> SalesActions = new Dictionary<string, string>
    {
        ["A"] = "Date", ["B"] = "Customers", ["C"] = "Enquiry", ["D"] = "SalesEntry",
        ["E"] = "SalesAmend", ["F"] = "SalesProof", ["G"] = "SalesPost", ["H"] = "PaymentEntry",
        ["I"] = "PaymentAmend", ["J"] = "PaymentProof", ["K"] = "PaymentPost", ["L"] = "Analysis",
        ["M"] = "AnalysisReport", ["N"] = "DayBook", ["O"] = "Statements", ["P"] = "Reminders",
        ["Q"] = "AgedDebtors", ["R"] = "Alphabetical", ["S"] = "Turnover", ["T"] = "Invoicing",
        ["U"] = "Cycle", ["V"] = "Dump", ["X"] = "Exit", ["Z"] = "Setup",
        ["B1"] = "CustomerCreate", ["B2"] = "CustomerUpdate", ["B3"] = "CustomerDelete",
        ["B4"] = "CustomerPrint", ["B5"] = "CustomerDisplay",
        ["L1"] = "AnalysisCreate", ["L2"] = "AnalysisChange", ["L3"] = "AnalysisPrint",
        ["L4"] = "AnalysisPrintAll", ["L5"] = "AnalysisDisplay",
        ["T1"] = "InvoiceFixed", ["T2"] = "InvoiceBatch", ["T3"] = "InvoiceImmediate",
        ["T4"] = "InvoiceAmend", ["T5"] = "InvoiceDelete", ["T6"] = "InvoiceDeletionReport",
        ["T7"] = "InvoicePrint", ["T8"] = "InvoicePickingPrint"
    };

    public static void PrepareSales(Db database, Scenario scenario)
    {
        if (database.Exists(SalesLedger.AnalysisFile))
            new SalesLedger(database).ImportAnalysisRecordLength(66);
        if (scenario.Id == "SL-090")
            foreach (var (key, _) in database.Scan(SalesLedger.CustomerFile))
                database.Delete(SalesLedger.CustomerFile, key);
    }

    public Outcome RunGroupTwo(Scenario scenario, string root)
    {
        var evidence = scenario.Evidence ?? throw new InvalidDataException("台帳に証跡がありません。");
        var compare = scenario.LegacyTargets;
        string legacy = string.Join("\n", compare.GetProperty("screen_text").EnumerateArray()
            .Select(p => File.ReadAllText(SalesEvidence.SafePath(root, p.GetString()!))));
        if (string.IsNullOrWhiteSpace(legacy)) throw new InvalidDataException("画面証跡がありません。");
        var clock = SalesEvidence.ReadClock(SalesEvidence.SafePath(root, evidence + "/terminal.cast"));
        var issues = new List<string>();
        using var database = new Db(_databasePath);
        var before = database.Snapshot();
        OpenTree("SalesNavigation");
        SetSalesDate("SalesStartDate", clock.Date);
        if (scenario.Id == "SL-090")
            return ReplaySharedCustomers(scenario, root, legacy, database);

        string Step(int i) => scenario.Steps[i].GetProperty("text").GetString()!;
        string route = "B";
        if (scenario.Steps.GetArrayLength() > 2)
        {
            if (Step(1) != "B" || Step(2) != "\r") throw new InvalidDataException("処理日の台帳手順が不正です。");
            SubmitSales();
            string option = Step(3);
            SelectAction("Sales" + SalesActions[option]);
            route += option;
            if (scenario.Steps.GetArrayLength() > 4 && SalesActions.TryGetValue(option + Step(4), out string? child))
            {
                string input = Step(4);
                var fixedEntry = option + input == "T1" ? Wait(() =>
                    Window.FindFirstDescendant(c => c.ByAutomationId("SalesFixedNumber").Or(c.ByAutomationId("SalesInvoiceFixed"))),
                    "次回請求番号または固定項目メニュー") : null;
                if (fixedEntry?.AutomationId == "SalesFixedNumber")
                {
                    var field = fixedEntry.AsTextBox();
                    field.Text = input + field.Text.PadLeft(8, '0')[1..];
                    var expected = Regex.Matches(legacy, @"Next Invoice\s*-\s*\[(\d{8})\]");
                    if (expected.Count == 0 || field.Text != expected[^1].Groups[1].Value)
                        issues.Add("固定項目設定の次回請求番号（確定前）が画面証跡と一致しません。");
                }
                else SelectAction("Sales" + child);
                route += input;
            }
        }
        var started = DateTime.Now;
        ReplaySalesData(scenario.Id, Step);
        string result = CheckSalesSurface(scenario.Id, route, legacy, database, issues);
        var ended = DateTime.Now;
        var after = database.Snapshot();
        SalesEvidence.CheckDiff(compare, root, before, after, issues);
        SalesEvidence.CheckSnapshot(root, evidence + "/before-records/records.json", before, "操作前", issues);
        SalesEvidence.CheckSnapshot(root, evidence + "/after-records/records.json", after, "操作後", issues);
        SalesEvidence.CheckReports(compare, root, database, issues, time => IsPrintTime(time, started, ended));
        return Outcome.Compare(scenario, issues.Count == 0, result, string.Join("／", issues), "実画面");
    }

    private void ReplaySalesData(string id, Func<int, string> input)
    {
        string Step(int i) => input(i).TrimEnd('\r');
        switch (id)
        {
            case "SL-091":
                var analysis = input(5).Split('\r');
                SetSalesText(("SalesAnalysisCode", analysis[0]), ("SalesAnalysisAccount", analysis[1]),
                    ("SalesAnalysisDescription", analysis[2]), ("SalesAnalysisPrintCode", analysis[3]));
                SubmitSales();
                ConfirmSales();
                break;
            case "SL-100":
            case "SL-101":
                var header = input(4).Split('\r');
                SetSalesText(("SalesInvoiceCustomer", header[1]), ("SalesInvoiceReference", header[2]),
                    ("SalesInvoiceOrder", header[3]));
                ChooseSales("SalesInvoiceType", int.Parse(header[4], CultureInfo.InvariantCulture) - 1);
                SubmitSales();
                int first = header[4] == "3" ? 6 : 5;
                SetSalesText(("SalesLineProduct", Step(first)), ("SalesLineAnalysis", Step(first + 1)),
                    ("SalesLineDescription", Step(first + 2)), ("SalesLineQuantity", Step(first + 3)),
                    ("SalesLineUnitPrice", Step(first + 4)), ("SalesLineDiscount", Step(first + 5)));
                ChooseSales("SalesLineVatCode", int.Parse(Step(first + 6), CultureInfo.InvariantCulture) - 1);
                SubmitSales();
                SelectAction("SalesInvoiceSaveDraft");
                ConfirmSales();
                break;
            case "SL-103":
                ChooseSales("SalesPrintMode", Step(5) == "R" ? 1 : 0);
                SubmitSales();
                ConfirmSales();
                break;
            case "SL-400":
                SetSalesText(("SalesUpdateCustomerCode", Step(5)));
                SubmitSales();
                SetSalesText(("SalesCustomerName", Step(6)));
                SubmitSales();
                ConfirmSales();
                break;
            case "SL-401":
                SetSalesText(("SalesDeleteCustomerCode", Step(5)));
                SubmitSales();
                ChooseSales("SalesCustomerRemovalAction", Step(6) == "K" ? 1 : 0);
                SubmitSales();
                ConfirmSales();
                break;
            case "SL-402":
                SetSalesText(("SalesDisplayCustomerCode", Step(5)));
                SubmitSales();
                break;
            case "SL-403":
                var fields = Step(6).Split('\t');
                SetSalesText(("SalesNewCustomerCode", Step(5)), ("SalesCustomerName", fields[0]),
                    ("SalesCustomerAddress1", fields[1]));
                SubmitSales();
                ConfirmSales();
                break;
        }
    }

    private Outcome ReplaySharedCustomers(Scenario scenario, string root, string legacy, Db database)
    {
        using var records = JsonDocument.Parse(File.ReadAllText(SalesEvidence.SafePath(root,
            scenario.LegacyTargets.GetProperty("keyed_record_diff").GetString()!)));
        var customers = records.RootElement.GetProperty("changes").EnumerateArray()
            .Where(c => c.GetProperty("file").GetString() == SalesLedger.CustomerFile)
            .ToDictionary(c => c.GetProperty("key").GetString()!,
                c => c.GetProperty("after").GetProperty("hex").GetString()!);
        var displayed = new List<string>();
        var issues = new List<string>();
        SubmitSales();
        SelectAction("SalesCustomers");
        foreach (var (code, _) in customers)
        {
            string number = code[..^1];
            string screen = legacy.Split('\n').WindowForCustomer(number);
            string Value(string pattern) => Regex.Match(screen, pattern).Groups[1].Value.TrimEnd('_', ' ');
            string name = Value(@"Customer Name:\s*\[([^\]]+)");
            if (name.Length == 0) throw new InvalidDataException("得意先登録の画面証跡を特定できません。");
            SelectAction("SalesCustomerCreate");
            SetSalesText(("SalesNewCustomerCode", number), ("SalesCustomerName", name),
                ("SalesCustomerAddress1", Value(@"Addr:\s*\[([^\]]+)")),
                ("SalesCustomerAddress2", Value(@"Addr:[^\n]+\n\s*\[([^\]]+)")),
                ("SalesCustomerPhone", Value(@"Telephone\s*:\s*\[([^\]]+)")),
                ("SalesCustomerEmail", Value(@"Email Sales\s*:\s*\[([^\]]+)")),
                ("SalesCustomerCreditDays", Value(@"Credit period:\s*\[([^\]]+)")),
                ("SalesCustomerCreditLimit", Value(@"Credit limit\s*:\s*\[([^\]]+)")));
            SubmitSales();
            ConfirmSales();
            var cells = ReadSalesTable("SalesCustomerDetail");
            if (cells.Length < 2 || cells[0].Cells[1] != code || cells[1].Cells[1] != name)
                issues.Add($"得意先表示が証跡と相違：{code}");
            else displayed.Add($"{code}　{name}");
            Find("ScreenMenuBack").AsButton().Invoke();
        }
        var after = database.Snapshot().GetValueOrDefault(SalesLedger.CustomerFile);
        if (after is null || after.Count != customers.Count || customers.Any(pair =>
            !pair.Value.Equals(after.GetValueOrDefault(pair.Key), StringComparison.OrdinalIgnoreCase)))
            issues.Add("得意先の固定長レコードが共有証跡と一致しません。");
        return Outcome.Compare(scenario, issues.Count == 0, "共有証跡の売掛範囲：" + string.Join("、", displayed),
            string.Join("／", issues), "実画面");
    }

    private string CheckSalesSurface(string id, string route, string legacy, Db database, List<string> issues)
    {
        var confirmation = route == "BU" ? Wait(Confirmation, "期間締め確認") : null;
        string title = confirmation?.Name ?? Find("ScreenTitle").Name;
        bool Legacy(string value) => legacy.Contains(value, StringComparison.Ordinal);
        bool Has(string element) => Window.FindFirstDescendant(c => c.ByAutomationId(element)) is not null;
        string message = confirmation?.FindFirstDescendant(c => c.ByAutomationId("ConfirmationMessage"))?.Name ??
            Window.FindFirstDescendant(c => c.ByAutomationId("ScreenMessage"))?.Name ?? "";
        bool FileMissing(string file) => message == $"{file}ファイルがありません。";
        bool titleIs(string expected, string surface) => title == expected && Has(surface);
        bool report = Has("ReportDocument");
        bool matches = route switch
        {
            "B" => Legacy("Start Of Day") && titleIs("売掛処理日入力", "SalesStartDate"),
            "BA" => Legacy("Start Of Day") && titleIs("売掛処理日入力", "SalesProcessingDate"),
            "BB" => Legacy("Customer File Set-Up & Maintenance") && titleIs("得意先保守", "SalesCustomerBack"),
            "BB1" when id == "SL-403" => Legacy("Customer Record Creation") && titleIs("得意先表示", "SalesCustomerDetail"),
            "BB1" => Legacy("Customer Record Creation") && titleIs("得意先登録", "SalesNewCustomerCode"),
            "BB2" when id == "SL-400" => Legacy("Customer Record Amendment") && titleIs("得意先表示", "SalesCustomerDetail"),
            "BB2" => Legacy("Customer Record Amendment") && titleIs("得意先変更", "SalesUpdateCustomerCode"),
            "BB3" when id == "SL-401" => Legacy("Function  Menu") && titleIs("得意先保守", "SalesCustomerBack"),
            "BB3" => Legacy("Customer Record Deletion") && titleIs("得意先削除", "SalesDeleteCustomerCode"),
            "BB4" => Legacy("Report Attributes") && titleIs("得意先一覧印刷", "Form"),
            "BB5" when id == "SL-402" => Legacy("T-003") && message == "得意先が見つかりません。",
            "BB5" => Legacy("Customer Record Display") && titleIs("得意先表示", "SalesDisplayCustomerCode"),
            "BC" or "BH" or "BO" or "BP" or "BQ" => Legacy("T-019") && FileMissing("売掛明細"),
            "BD" when id is "SL-100" or "SL-101" => Legacy("Invoice Ok to") && message.EndsWith("保存しました。", StringComparison.Ordinal),
            "BD" or "BT2" or "BT3" => Legacy("Invoicing Data Entry") && Has("SalesInvoiceDate"),
            "BE" or "BT4" => Legacy("Invoicing Data Amend") && title.Contains("修正") && Has("Form"),
            "BF" when id == "SL-104" => Legacy("Sales Ledger System Menu") && report,
            "BF" => Legacy("No Transactions to proof") && message.Contains("ありません"),
            "BG" => Legacy("Error writing to Open Item 2 File") && FileMissing("転記先の売掛明細"),
            "BI" or "BJ" => Legacy("T-030") && FileMissing("入金明細"),
            "BK" => Legacy("T-011") && FileMissing("入金明細"),
            "BL" => Legacy("Product Analysis File Set-Up & Maintenance") && titleIs("売上分析コード管理", "ScreenMenu"),
            "BL1" when id == "SL-091" => Legacy("Set-Up P/A Records") && message.Contains("状態39"),
            "BL1" => Legacy("Set-Up P/A Records") && titleIs("売上分析コード登録", "SalesAnalysisCode"),
            "BL2" => Legacy("Amend/Delete P/A Records") && titleIs("売上分析コード変更・削除", "SalesFindAnalysisCode"),
            "BL3" => Legacy("Print P/A Records") && report,
            "BL4" => Legacy("Print All P/A Records") && report,
            "BL5" => Legacy("Display P/A Records") && titleIs("売上分析コード表示", "SalesFindAnalysisCode"),
            "BM" or "BN" => Legacy("Sales Ledger System Menu") && titleIs("売掛元帳", "ScreenMenu"),
            "BR" or "BS" or "BV" => Legacy("Report Attributes") && title.Contains("得意先") && Has("Form"),
            "BT" or "BT1" => Legacy("Invoicing Fixed Data") && titleIs("請求書固定項目設定", "SalesFixedNumber"),
            "BT5" => Legacy("Invoicing Data Deletion") && titleIs("請求書削除", "Form"),
            "BT6" => Legacy("Invoicing Menu") && title.Contains("削除帳票") && report,
            "BT7" when id == "SL-103" => Legacy("Invoice Printing") && title.Contains("請求書") && report,
            "BT7" => Legacy("Invoice Printing") && titleIs("請求書印刷", "SalesPrintMode"),
            "BT8" => Legacy("Delivery / Picking Note Print") && titleIs("配送・出庫票印刷", "SalesPrintMode"),
            "BU" => Legacy("End of Cycle Processing") && confirmation is not null,
            "BX" => Legacy("ACAS System Menu") && titleIs("業務メニュー", "ScreenMessage"),
            "BZ" => titleIs("共通設定", "SalesSetupSettings") && SalesEvidence.SettingsMatch(legacy,
                new TableScreen(title, "SalesSetupSettings", ["項目", "内容"], ReadSalesTable("SalesSetupSettings")), issues),
            _ => false
        };
        string result = message.Length > 0 ? $"{title}：{message}" : title;
        if (!matches) issues.Add($"画面の到達先または業務結果が証跡と相違：{result}");
        if (report)
        {
            var document = Find("ReportDocument");
            string? body = document.Patterns.Text.IsSupported ? document.Patterns.Text.Pattern.DocumentRange.GetText(-1) : null;
            string? saved = database.Spool().LastOrDefault().Body;
            if (string.IsNullOrWhiteSpace(body) || saved is null || Normalize(body) != Normalize(saved))
                issues.Add("表示された帳票本文と保存した帳票本文が一致しません。");
        }
        return result;
    }

    private TableRow[] ReadSalesTable(string id) => Find(id).AsDataGridView().Rows
        .Select(row => new TableRow(row.Cells.Select(cell => cell.Patterns.Value.IsSupported ?
            cell.Value?.ToString() ?? "" : cell.Name).ToArray())).ToArray();

    private static bool IsPrintTime(string time, DateTime started, DateTime ended)
    {
        var minute = new DateTime(started.Year, started.Month, started.Day, started.Hour, started.Minute, 0);
        for (; minute <= ended; minute = minute.AddMinutes(1))
            if (minute.ToString("HH:mm", CultureInfo.InvariantCulture) == time) return true;
        return false;
    }

    private void SubmitSales() => Find("FormSubmit").AsButton().Invoke();

    private void ConfirmSales()
    {
        var dialog = Wait(Confirmation, "確認画面");
        Wait(() => dialog.FindFirstDescendant(c => c.ByAutomationId("ConfirmationConfirm")), "確定").AsButton().Invoke();
    }

    private void SetSalesText(params (string Id, string Value)[] values)
    {
        foreach (var (id, value) in values) Find(id).AsTextBox().Text = value;
    }

    private void ChooseSales(string id, int index)
    {
        var combo = Find(id).AsComboBox();
        combo.Expand();
        combo.Select(index);
        combo.Collapse();
    }

    private void SetSalesDate(string id, DateTime date)
    {
        var input = Wait(() => Find(id).FindFirstDescendant(c => c.ByAutomationId("PART_TextBox")), id).AsTextBox();
        input.Focus();
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_A);
        Keyboard.Type(date.ToString("d", CultureInfo.GetCultureInfo("ja-JP")));
        Keyboard.Press(VirtualKeyShort.TAB);
    }
}

internal static class SalesLegacyCustomerScreen
{
    public static string WindowForCustomer(this string[] lines, string number)
    {
        for (int i = lines.Length - 20; i >= 0; i--)
            if (lines[i].Contains($"Customer Nos : [{number}]", StringComparison.Ordinal) &&
                lines[i + 16].Contains("Escape Code [S]", StringComparison.Ordinal))
                return string.Join("\n", lines.Skip(i).Take(20));
        throw new InvalidDataException($"保存時の画面証跡が見つかりません：{number}");
    }
}
