using System.Globalization;
using System.IO.Compression;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

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
    Console.WriteLine($"{r.Id} {r.Verdict}: {ConsoleText(string.Join("／", r.Differences))}");
return results.Any(r => r.Verdict == "不一致") ? 1 : 0;

static string ConsoleText(string text) => string.Concat(text.Select(c =>
    char.IsControl(c) ? $"\\u{(int)c:x4}" : c.ToString()));

static Dictionary<string, string> Workbook(string location)
{
    const int maxSheetSize = 16 * 1024 * 1024;
    XNamespace ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    using var workbook = ZipFile.OpenRead(location);
    var entry = workbook.GetEntry("xl/worksheets/sheet4.xml")
        ?? throw new InvalidDataException("結果表に売掛のシートがありません。");
    if (entry.Length > maxSheetSize) throw new InvalidDataException("結果表の売掛シートが大きすぎます。");
    using var sheet = entry.Open();
    using var reader = XmlReader.Create(sheet, new XmlReaderSettings
    {
        DtdProcessing = DtdProcessing.Prohibit,
        MaxCharactersInDocument = maxSheetSize
    });
    var rows = XDocument.Load(reader).Descendants(ns + "row");
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

static bool SettingsMatch(string evidence, TableScreen settings, List<string> issues)
{
    var expected = new List<string>();
    string Value(string pattern)
    {
        var match = Regex.Match(evidence, pattern);
        return match.Success ? match.Groups[1].Value : throw new InvalidDataException("共通設定の証跡から項目値を抽出できません。");
    }
    string Text(string field) => Value(field + @"\s*\[([^\]\r\n]*)\]").TrimEnd('_', ' ').Replace('_', ' ');
    string Number(string field) => int.Parse(Value(field + @"\s*-?\s*\[(\d+)\]"), CultureInfo.InvariantCulture)
        .ToString(CultureInfo.InvariantCulture);
    string Date(string text) => DateTime.ParseExact(text, "dd/MM/yyyy", CultureInfo.InvariantCulture)
        .ToString("yyyy年MM月dd日", CultureInfo.InvariantCulture);
    expected.Add(Value(@"Name\s*-\s*\{([^}]+)\}").Trim());
    var addresses = Regex.Match(evidence, @"Address\s*-\s*\[([^\]]*)\]\s*\[([^\]]*)\]\s*\[([^\]]*)\]\s*\[([^\]]*)\]");
    if (!addresses.Success) return false;
    expected.AddRange(addresses.Groups.Values.Skip(1).Select(g => g.Value.TrimEnd('_', ' ').Replace('_', ' ')));
    expected.Add(Text("Post Code"));
    expected.Add(Text("Country -"));
    expected.Add(Number("Date Format") switch { "1" => "日・月・年", "2" => "月・日・年", "3" => "年・月・日", _ => "未設定" });
    expected.Add(Date(Text("Start Date -")));
    expected.Add(Date(Text("End\\s+Date -")));
    expected.Add(Number("System Print Lines"));
    for (int i = 1; i <= 5; i++)
        expected.Add(SalesLedger.Amount(decimal.Parse(Value($@"\({i}\)\s*-\s*\[(\d{{2}}\.\d{{2}})\]"), CultureInfo.InvariantCulture)));
    expected.Add(Text("VAT Reg no -"));
    expected.Add(Text("Printed") == "Y" ? "はい" : "いいえ");
    expected.Add(Number("Current Cycle"));
    expected.Add(Number("Current Quarter"));
    expected.Add(Number("Cycle Period"));
    expected.Add(Number("Data File Handling"));
    expected.Add(Number("Dual file type Flag"));
    if (expected.Count != settings.Rows.Count) return false;
    var different = settings.Rows.Where((row, index) => row.Cells[1] != expected[index]).Select(row => row.Cells[0]).ToArray();
    if (different.Length == 0) return true;
    issues.Add("共通設定の相違項目: " + string.Join("、", different));
    return false;
}

static void CheckSnapshot(string root, string path, SortedDictionary<string, SortedDictionary<string, string>> actual,
    string phase, List<string> issues)
{
    using var export = JsonDocument.Parse(File.ReadAllText(SafePath(root, path)));
    foreach (var file in export.RootElement.GetProperty("files").EnumerateObject())
    {
        var expected = file.Value.GetProperty("records").EnumerateObject().ToDictionary(r => r.Name,
            r => r.Value.GetProperty("hex").GetString()!, StringComparer.Ordinal);
        actual.TryGetValue(file.Name, out var rows);
        IEnumerable<string> actualKeys = rows?.Keys.AsEnumerable() ?? [];
        foreach (string key in expected.Keys.Union(actualKeys))
        {
            if (expected.TryGetValue(key, out string? hex) && rows != null && rows.TryGetValue(key, out string? bytes) &&
                hex.Equals(bytes, StringComparison.OrdinalIgnoreCase)) continue;
            issues.Add($"{phase}の固定長レコードが相違: {file.Name}／{key}");
        }
    }
}

static void CheckDiff(JsonElement comparison, string root, SortedDictionary<string, SortedDictionary<string, string>> before,
    SortedDictionary<string, SortedDictionary<string, string>> after, List<string> issues)
{
    string path = comparison.GetProperty("keyed_record_diff").GetString() ?? throw new InvalidDataException("レコード証跡パスがありません。");
    using var diff = JsonDocument.Parse(File.ReadAllText(SafePath(root, path)));
    if (diff.RootElement.TryGetProperty("export_errors", out var errors) && errors.GetArrayLength() != 0)
        issues.Add("固定長レコードの証跡に抽出エラーがあります。");
    var expected = diff.RootElement.GetProperty("changes").EnumerateArray().ToDictionary(
        c => (File: c.GetProperty("file").GetString()!, Key: c.GetProperty("key").GetString()!),
        c => (Before: Hex(c.GetProperty("before")), After: Hex(c.GetProperty("after"))));
    static string? Hex(JsonElement value) => value.ValueKind == JsonValueKind.Null ? null : value.GetProperty("hex").GetString()!.ToLowerInvariant();
    var actual = new Dictionary<(string File, string Key), (string? Before, string? After)>();
    foreach (string file in before.Keys.Union(after.Keys))
    {
        before.TryGetValue(file, out var b);
        after.TryGetValue(file, out var a);
        IEnumerable<string> bkeys = b?.Keys.AsEnumerable() ?? [];
        IEnumerable<string> akeys = a?.Keys.AsEnumerable() ?? [];
        foreach (string key in bkeys.Union(akeys))
        {
            string? left = b?.GetValueOrDefault(key);
            string? right = a?.GetValueOrDefault(key);
            if (left != right) actual[(file, key)] = (left, right);
        }
    }
    foreach (var key in expected.Keys.Union(actual.Keys))
    {
        if (expected.TryGetValue(key, out var e) && actual.TryGetValue(key, out var a) && e == a) continue;
        issues.Add($"固定長レコード差分が相違: {key.File}／{key.Key}");
    }
}

static void CheckReports(JsonElement comparison, string root, Db database, List<string> issues)
{
    var expected = comparison.GetProperty("report_files").EnumerateArray().Select(p => SafePath(root, p.GetString()!))
        .GroupBy(p => (Path.GetFileName(p), Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(p)))))
        .Select(g => g.First()).ToArray();
    var actual = database.Spool().GroupBy(r => r.Name)
        .ToDictionary(g => g.Key, g => new Queue<string>(g.Select(report => report.Body)
            .Skip(g.Key is "prt-2" or "prt-3" && g.Count() > 1 && g.First().Body.Length == 0 ? 1 : 0)));
    foreach (var path in expected)
    {
        string name = Path.GetFileName(path);
        string legacy = File.ReadAllText(path);
        if (!actual.TryGetValue(name, out var entries) || !entries.TryDequeue(out var body))
        {
            issues.Add(legacy.Contains("Product Analysis Codes", StringComparison.Ordinal) && legacy.Contains('\0')
                ? $"{name}: レガシーの分析コード全件印刷はオープン時の状態39と読み取り時の状態47を処理せず、NULを含む明細を出力し続けます。証跡は停止までの出力で、移行版は状態39で停止します。"
                : $"帳票が作成されていません: {name}");
            continue;
        }
        if (legacy.Length == 0 && body.Length == 0) continue;
        if (legacy.Contains("None to report", StringComparison.Ordinal) && body.Contains("対象となる請求書はありません。", StringComparison.Ordinal)) continue;
        if (SalesReportValues.Difference(legacy, body) is { } problem) issues.Add($"{name}: {problem}");
    }
    foreach (var (name, entries) in actual)
        if (entries.Count > 0) issues.Add($"証跡にない帳票が作成されました: {name}（{entries.Count}件）");
}

static DateTime ReadClock(string path)
{
    using var header = JsonDocument.Parse(File.ReadLines(path).First());
    return DateTimeOffset.FromUnixTimeSeconds(header.RootElement.GetProperty("timestamp").GetInt64()).UtcDateTime;
}

static string SafePath(string root, string path)
{
    if (Path.IsPathRooted(path) || path.Contains(':')) throw new InvalidDataException("証跡パスが相対パスではありません。");
    var parts = path.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
    string location = Path.GetFullPath(root);
    foreach (string part in parts)
    {
        if (part is "." or ".." || part.EndsWith(' ') || part.EndsWith('.'))
            throw new InvalidDataException("証跡フォルダー外のパスを参照できません。");
        location = Path.Combine(location, part);
        if (File.GetAttributes(location).HasFlag(FileAttributes.ReparsePoint))
            throw new InvalidDataException("証跡パスのリンクは利用できません。");
    }
    return location;
}

internal sealed record Result(string Id, string Verdict, IReadOnlyList<string> Differences);
