using System.Globalization;
using System.IO.Compression;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;
using static Acas.Verify.Sales.SalesEvidence;

if (args.Length != 4)
{
    Console.Error.WriteLine("引数: 台帳のパス 証跡フォルダー 結果表のパス 出力先のパス");
    return 2;
}

using var ledger = JsonDocument.Parse(File.ReadAllText(args[0]));
var expectedIds = Workbook(args[2]);
var cases = ledger.RootElement.GetProperty("cases").EnumerateArray()
    .Where(c => c.GetProperty("id").GetString()!.StartsWith("SL-", StringComparison.Ordinal)).ToArray();
if (!expectedIds.Keys.ToHashSet().SetEquals(cases.Select(c => c.GetProperty("id").GetString()!)))
    throw new InvalidDataException("結果表と台帳で売掛のケース番号が一致しません。");

var results = cases.Select(c => Evaluate(c, args[1], expectedIds)).ToArray();
File.WriteAllText(args[3], JsonSerializer.Serialize(results,
    new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
Console.WriteLine($"売掛 {results.Length}件：一致 {results.Count(r => r.Verdict == "一致")}件、不一致 {results.Count(r => r.Verdict == "不一致")}件、対象外 {results.Count(r => r.Verdict == "対象外")}件");
foreach (var r in results.Where(r => r.Verdict != "一致"))
    Console.WriteLine($"{r.Id} {r.Verdict}: {string.Join("／", r.Differences)}");
return results.Any(r => r.Verdict == "不一致") ? 1 : 0;

static Dictionary<string, string> Workbook(string location)
{
    XNamespace ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    using var workbook = ZipFile.OpenRead(location);
    using var sheet = workbook.GetEntry("xl/worksheets/sheet4.xml")!.Open();
    var rows = XDocument.Load(sheet).Descendants(ns + "row");
    string Text(XElement row, string column) => string.Concat(row.Elements(ns + "c")
        .Where(c => (c.Attribute("r")?.Value ?? "").TrimEnd('0','1','2','3','4','5','6','7','8','9') == column)
        .Descendants(ns + "t").Select(t => t.Value));
    return rows.Select(row => (Id: Text(row, "A"), Verdict: Text(row, "N")))
        .Where(row => Regex.IsMatch(row.Id, @"\ASL-[0-9]{3}\z")).ToDictionary(row => row.Id, row => row.Verdict);
}

static Result Evaluate(JsonElement scenario, string root, Dictionary<string, string> workbook)
{
    string id = scenario.GetProperty("id").GetString()!;
    var legacy = scenario.GetProperty("legacy_result");
    string legacyVerdict = legacy.GetProperty("verdict").GetString()!;
    if (workbook[id] != legacyVerdict) return new(id, "不一致", ["結果表と台帳の実施判定が相違"]);
    if (legacyVerdict == "未実施") return new(id, "対象外", ["レガシー未実施"]);
    List<string> issues = [];
    try
    {
        using var database = new Db();
        string baseline = scenario.GetProperty("baseline").GetString()!;
        database.LoadBaseline(baseline);
        var service = new SalesLedger(database);
        var compare = legacy.GetProperty("comparison_targets");
        var evidencePath = legacy.GetProperty("evidence")[0].GetString()!;
        string evidence = string.Join("\n", compare.GetProperty("screen_text").EnumerateArray()
            .Select(p => File.ReadAllText(SafePath(root, p.GetString()!))));
        if (evidence.Length == 0) issues.Add("画面証跡がありません。");
        if (database.Exists(SalesLedger.AnalysisFile)) service.ImportAnalysisRecordLength(66);
        var before = database.Snapshot();
        var clock = ReadClock(SafePath(root, evidencePath + "/terminal.cast"));
        var screens = new SalesScreens(service, () => clock);
        var steps = scenario.GetProperty("runner").GetProperty("steps").EnumerateArray().ToArray();
        string[] path = scenario.GetProperty("menu_path").EnumerateArray().Select(e => e.GetString()!).ToArray();
        Screen? result = Replay(id, path, steps, screens, evidence, issues);
        if (result == null) issues.Add("新画面の操作を再現できません。");
        else CheckScreen(id, path, evidence, result, issues);
        var after = database.Snapshot();
        CheckDiff(compare, root, before, after, issues);
        CheckSnapshot(root, evidencePath + "/before-records/records.json", before, "操作前", issues);
        CheckSnapshot(root, evidencePath + "/after-records/records.json", after, "操作後", issues);
        CheckReports(compare, root, database, issues);
    }
    catch (Exception ex) when (ex is IOException or InvalidDataException or JsonException or ArgumentException or
        InvalidOperationException or KeyNotFoundException or SalesRuleException)
    {
        issues.Add("検証処理: " + ex.Message);
    }
    return new(id, issues.Count == 0 ? "一致" : "不一致", issues);
}

static Screen? Replay(string id, string[] path, JsonElement[] steps, SalesScreens screens, string evidence, List<string> issues)
{
    if (path[0] != "B")
    {
        issues.Add("証跡は空データからの共通設定・業務用マスター一括投入を含み、売掛の操作手順がありません。");
        return null;
    }
    var start = (FormScreen)screens.Navigation().Open!();
    if (path.Length == 1) return start;
    if (steps.Length < 3 || steps[2].GetProperty("text").GetString() != "\r")
        throw new InvalidDataException("処理日の入力操作を再生できません。");
    var main = Submit(start) as MenuScreen ?? throw new InvalidDataException("売掛元帳メニューに到達しませんでした。");
    MenuItem option = main.Items.Single(item => item.Label[0] == path[1][0] + 0xFEE0);
    Screen current = option.Open!();
    if (path.Length > 2)
    {
        if (current is not MenuScreen submenu && option.Children == null)
            throw new InvalidDataException("操作先のメニューがありません。");
        var items = current is MenuScreen opened ? opened.Items : option.Children!;
        current = items.Single(item => item.Number?.ToString(CultureInfo.InvariantCulture) == path[2]).Open!();
    }
    string Input(int index) => steps[index].TryGetProperty("text", out var text) ? text.GetString()! : "";
    switch (id)
    {
        case "SL-091":
            var analysis = Input(5).Split('\r');
            return Approve(Submit(current, ("SalesAnalysisCode", analysis[0]), ("SalesAnalysisAccount", analysis[1]),
                ("SalesAnalysisDescription", analysis[2]), ("SalesAnalysisPrintCode", analysis[3])));
        case "SL-100": case "SL-101":
            var header = Input(4).Split('\r');
            bool credit = header[4] == "3";
            int firstLine = credit ? 6 : 5;
            var line = Submit(current, ("SalesInvoiceCustomer", header[1]), ("SalesInvoiceReference", header[2]),
                ("SalesInvoiceOrder", header[3]), ("SalesInvoiceType", header[4]));
            var draft = (MenuScreen)Submit(line, ("SalesLineProduct", Input(firstLine).TrimEnd('\r')),
                ("SalesLineAnalysis", Input(firstLine + 1).TrimEnd('\r')), ("SalesLineDescription", Input(firstLine + 2).TrimEnd('\r')),
                ("SalesLineQuantity", Input(firstLine + 3).TrimEnd('\r')), ("SalesLineUnitPrice", Input(firstLine + 4).TrimEnd('\r')),
                ("SalesLineDiscount", Input(firstLine + 5).TrimEnd('\r')), ("SalesLineVatCode", Input(firstLine + 6).TrimEnd('\r')));
            return Approve(draft.Items.Single(i => i.Id == "SalesInvoiceSaveDraft").Open!());
        case "SL-103":
            return Approve(Submit(current, ("SalesPrintMode", Input(5).TrimEnd('\r'))));
        case "SL-400":
            var editor = Submit(current, ("SalesUpdateCustomerCode", Input(5).TrimEnd('\r')));
            return Approve(Submit(editor, ("SalesCustomerName", Input(6).TrimEnd('\r'))));
        case "SL-401":
            var removal = Submit(current, ("SalesDeleteCustomerCode", Input(5).TrimEnd('\r')));
            return Approve(Submit(removal, ("SalesCustomerRemovalAction", Input(6).StartsWith('K') ? "1" : "0")));
        case "SL-402":
            return Submit(current, ("SalesDisplayCustomerCode", Input(5).TrimEnd('\r')));
        case "SL-403":
            var fields = Input(6).TrimEnd('\r').Split('\t');
            return Approve(Submit(current, ("SalesNewCustomerCode", Input(5).TrimEnd('\r')),
                ("SalesCustomerName", fields[0]), ("SalesCustomerAddress1", fields[1])));
        default:
            if (path[1] == "A" && evidence.Contains("Start Of Day", StringComparison.Ordinal))
                return current;
            return current;
    }
}

static Screen Submit(Screen screen, params (string Id, object? Value)[] overrides)
{
    if (screen is not FormScreen form) throw new InvalidDataException("入力フォームに到達しませんでした。");
    var values = form.Fields.ToDictionary(field => field.Id, field => field switch
    {
        TextField t => (object?)t.Value, ChoiceField c => c.Value, DateField d => d.Value, _ => null
    });
    foreach (var (id, value) in overrides)
        if (!values.TryGetValue(id, out _)) throw new InvalidDataException("フォームの項目が見つかりません。");
        else values[id] = value;
    return form.Submit(new FormValues(values));
}

static Screen Approve(Screen screen) => screen is ConfirmationScreen confirmation
    ? confirmation.Confirm() : throw new InvalidDataException("確認ダイアログに到達しませんでした。");

static void CheckScreen(string id, string[] path, string evidence, Screen result, List<string> issues)
{
    bool Has(string text) => evidence.Contains(text, StringComparison.Ordinal);
    bool Match(string text) => result.Title.Contains(text, StringComparison.Ordinal);
    bool FileError(string subject) => result is InformationScreen info && info.Message == $"{subject}ファイルがありません。";
    string route = string.Concat(path);
    bool match = route switch
    {
        "B" or "BA" => Has("Start Of Day") && result is FormScreen date && date.Fields.Any(f => f is DateField),
        "BB" => Has("Customer File Set-Up & Maintenance") && result is MenuScreen menu && menu.Items.Count == 6,
        "BB1" when id == "SL-403" => Has("Customer Record Creation") && Match("得意先表示"),
        "BB1" => Has("Customer Record Creation") && result is FormScreen registration && registration.Fields.Any(f => f.Id == "SalesNewCustomerCode"),
        "BB2" when id == "SL-400" => Has("Customer Record Amendment") && Match("得意先表示"),
        "BB2" => Has("Customer Record Amendment") && result is FormScreen && Match("変更"),
        "BB3" when id == "SL-401" => Has("Function  Menu") && result is MenuScreen && Match("得意先保守"),
        "BB3" => Has("Customer Record Deletion") && result is FormScreen && Match("削除"),
        "BB4" => Has("Report Attributes") && result is FormScreen && Match("得意先一覧印刷"),
        "BB5" when id == "SL-402" => Has("T-003") && result is InformationScreen missing && missing.Message == "得意先が見つかりません。",
        "BB5" => Has("Customer Record Display") && result is FormScreen && Match("表示"),
        "BC" or "BH" or "BO" or "BP" or "BQ" => Has("T-019") && FileError("売掛明細"),
        "BD" when id is "SL-100" or "SL-101" => Has("Invoice Ok to") && result is InformationScreen saved && saved.Message.EndsWith("保存しました。", StringComparison.Ordinal),
        "BD" or "BT2" or "BT3" => Has("Invoicing Data Entry") && result is FormScreen invoice && invoice.Fields.Any(f => f.Id == "SalesInvoiceDate"),
        "BE" or "BT4" => Has("Invoicing Data Amend") && result is FormScreen && Match("修正"),
        "BF" when id == "SL-104" => Has("Sales Ledger System Menu") && result is ReportScreen,
        "BF" => Has("No Transactions to proof") && result is InformationScreen empty && empty.Message.Contains("ありません"),
        "BG" => Has("Error writing to Open Item 2 File") && FileError("転記先の売掛明細"),
        "BI" or "BJ" => Has("T-030") && FileError("入金明細"),
        "BK" => Has("T-011") && FileError("入金明細"),
        "BL" => Has("Product Analysis File Set-Up & Maintenance") && result is MenuScreen && Match("分析コード管理"),
        "BL1" when id == "SL-091" => Has("Set-Up P/A Records") && result is InformationScreen failure && failure.Message.Contains("状態39"),
        "BL1" => Has("Set-Up P/A Records") && result is FormScreen && Match("登録"),
        "BL2" => Has("Amend/Delete P/A Records") && result is FormScreen && Match("変更・削除"),
        "BL3" => Has("Print P/A Records") && result is ReportScreen,
        "BL4" => Has("Print All P/A Records") && result is ReportScreen,
        "BL5" => Has("Display P/A Records") && result is FormScreen && Match("表示"),
        "BM" or "BN" => Has("Sales Ledger System Menu") && result is MenuScreen && result.Title == "売掛元帳",
        "BR" or "BS" or "BV" => Has("Report Attributes") && result is FormScreen && Match("得意先"),
        "BT" or "BT1" => Has("Invoicing Fixed Data") && result is FormScreen fixedForm && fixedForm.Fields.Count == 11,
        "BT5" => Has("Invoicing Data Deletion") && result is FormScreen && Match("削除"),
        "BT6" => Has("Invoicing Menu") && result is ReportScreen && Match("削除帳票"),
        "BT7" when id == "SL-103" => Has("Invoice Printing") && result is ReportScreen && Match("請求書"),
        "BT7" => Has("Invoice Printing") && result is FormScreen && Match("請求書印刷"),
        "BT8" => Has("Delivery / Picking Note Print") && result is FormScreen && Match("配送・出庫票印刷"),
        "BU" => Has("End of Cycle Processing") && result is ConfirmationScreen,
        "BX" => Has("ACAS System Menu") && Match("業務メニュー"),
        "BZ" => result is TableScreen settings && SettingsMatch(evidence, settings, issues),
        _ => false
    };
    if (!match) issues.Add(route == "BZ" ? "共通設定の利用者情報が証跡と相違。" : "画面の到達先または業務結果が証跡と相違");
}


internal sealed record Result(string Id, string Verdict, IReadOnlyList<string> Differences);
