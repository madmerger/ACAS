using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Acas.App;
using Acas.Core;
using Acas.Core.Engine;

namespace Acas.Verify;

public static class GroupOneVerification
{
    public static Outcome Run(Scenario scenario, string evidence, GroupOnePlan plan)
    {
        const string source = "新画面モデル";
        try
        {
            using var database = new Db();
            database.LoadBaseline(scenario.Baseline);
            var before = database.Snapshot();
            var model = new AccountingScreens(database);
            var navigation = model.Navigation().Concat(SubsystemScreens.Load(typeof(AccountingScreens).Assembly, database))
                .SelectMany(item => item.Children?.Prepend(item) ?? [item])
                .ToDictionary(item => item.Id);
            Screen screen = model.Start();
            MenuScreen? currentMenu = null;
            var inputs = new Dictionary<string, object?>();
            var observations = new List<string>();
            var differences = new List<string>();
            foreach (var action in plan.Actions)
            {
                switch (action.Type)
                {
                    case ActionType.Check:
                        if (!Observe(navigation, screen, action, observations))
                            differences.Add($"画面：{action.Id} {action.Value} を確認できません（{screen.Title}）。" +
                                (screen is FormScreen { Error: { } error } && action.Id == "Status" ? $"表示：{error}" : ""));
                        break;
                    case ActionType.Text or ActionType.Choice or ActionType.DateText:
                        var field = (screen as FormScreen)?.Fields.SingleOrDefault(field => field.Id == action.Id);
                        if (field is not (TextField or PasswordField) && action.Type == ActionType.Text ||
                            field is not ChoiceField && action.Type == ActionType.Choice ||
                            field is not DateField && action.Type == ActionType.DateText)
                            throw new InvalidOperationException($"該当する入力欄がありません：{action.Id}（{screen.Title}）");
                        if (field is ChoiceField choice && choice.Options.All(option => option.Value != action.Value))
                            throw new InvalidOperationException($"指定した選択肢がありません：{action.Id}／{action.Value}");
                        inputs[action.Id] = action.Type == ActionType.DateText
                            ? DateTime.TryParseExact(action.Value, "dd/MM/yyyy", CultureInfo.InvariantCulture,
                                DateTimeStyles.None, out var date) ? date : null
                            : action.Value;
                        break;
                    case ActionType.RejectChoice:
                        if (screen is not FormScreen form ||
                            form.Fields.FirstOrDefault(field => field.Id == action.Id) is not ChoiceField options ||
                            options.Options.Any(option => option.Value == action.Value))
                            differences.Add($"画面：{action.Id} で不正値「{action.Value}」を拒否できません。");
                        else observations.Add($"{action.Id}：不正値「{action.Value}」は選択できません。");
                        break;
                    case ActionType.Key or ActionType.Close:
                        differences.Add($"実画面での操作が必要です：{action.Type} {action.Id}。");
                        break;
                    default:
                        if (action.Type == ActionType.Tree) currentMenu = null;
                        screen = action is { Type: ActionType.Menu, Id: "ScreenMenuBack" } && currentMenu is not null
                            ? currentMenu : Move(navigation, screen, action, inputs);
                        if (screen is MenuScreen menu) currentMenu = menu;
                        inputs.Clear();
                        break;
                }
            }
            return Compare(scenario, evidence, plan, before, database, observations, differences, source);
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or IOException or JsonException)
        {
            return Outcome.Compare(scenario, false, "", e.Message, source);
        }
    }

    private static Screen Move(IReadOnlyDictionary<string, MenuItem> navigation, Screen screen, ScreenAction action,
        Dictionary<string, object?> inputs) => action.Type switch
    {
        ActionType.Tree when navigation.TryGetValue(action.Id, out var item) && item.Open != null => item.Open(),
        ActionType.Menu when screen is FormScreen { Back: { } back } && action.Id == "FormBack" => back(),
        ActionType.Menu when screen is MenuScreen menu &&
            menu.Items.FirstOrDefault(item => item.Id == action.Id)?.Open is { } open => open(),
        ActionType.Confirm when screen is ConfirmationScreen confirm => confirm.Confirm(),
        ActionType.Cancel when screen is ConfirmationScreen cancel => cancel.Cancel(),
        ActionType.TableRow when screen is TableScreen table && table.Id == action.Id &&
            table.Rows.FirstOrDefault(row => row.Cells[0] == action.Value)?.Open is { } open => open(),
        ActionType.Submit when screen is FormScreen form => form.Submit(new FormValues(
            form.Fields.ToDictionary(field => field.Id, field => inputs.TryGetValue(field.Id, out var value) ? value :
                field switch
                {
                    TextField text => text.Value,
                    PasswordField => "",
                    DateField date => date.Value,
                    ChoiceField choice => choice.Value,
                    _ => null
                }))),
        _ => throw new InvalidOperationException($"画面操作が見つかりません：{action.Type} {action.Id}（{screen.Title}）")
    };

    private static bool Observe(IReadOnlyDictionary<string, MenuItem> navigation, Screen screen, ScreenAction action,
        List<string> observations)
    {
        string? actual = (action.Id, screen) switch
        {
            ("Status", FormScreen form) => form.Error,
            ("ScreenTitle", _) => screen.Title,
            ("ScreenMessage", InformationScreen info) => info.Message,
            ("Confirmation", ConfirmationScreen confirm) => confirm.Message,
            ("ReportDocument", ReportScreen report) when !string.IsNullOrWhiteSpace(report.Body) => report.Body,
            (_, TableScreen table) when table.Id == action.Id => string.Join("\n", table.Rows.Select(row => string.Join(" ", row.Cells))),
            (_, FormScreen form) => form.Fields.FirstOrDefault(field => field.Id == action.Id)?.Label,
            (_, MenuScreen menu) => menu.Items.FirstOrDefault(item => item.Id == action.Id)?.Caption,
            _ => null
        };
        actual ??= navigation.GetValueOrDefault(action.Id)?.Caption;
        if (actual is null || !actual.Contains(action.Value, StringComparison.Ordinal)) return false;
        observations.Add(action.Value.Length == 0 ? $"{screen.Title}：{action.Id}" : $"{action.Id}：{action.Value}");
        return true;
    }

    public static Outcome Compare(Scenario scenario, string evidence, GroupOnePlan plan,
        SortedDictionary<string, SortedDictionary<string, string>> before, Db database,
        List<string> observations, List<string> differences, string source)
    {
        var targets = scenario.LegacyTargets;
        string Content(string relative) => File.ReadAllText(Scenario.EvidencePath(evidence, relative), Encoding.Latin1);
        if (!targets.GetProperty("screen_text").EnumerateArray().Any(path =>
            Content(path.GetString()!).Contains(plan.LegacyScreen, StringComparison.OrdinalIgnoreCase)))
            differences.Add($"画面証跡：旧画面に確認点「{plan.LegacyScreen}」が見つかりません。");

        string diffPath = Scenario.EvidencePath(evidence, targets.GetProperty("keyed_record_diff").GetString()!);
        using var legacy = JsonDocument.Parse(File.ReadAllText(diffPath));
        var expected = legacy.RootElement.GetProperty("changes").EnumerateArray().ToDictionary(
            change => (change.GetProperty("file").GetString()!, change.GetProperty("key").GetString()!),
            change => (Before: Hex(change.GetProperty("before")), After: Hex(change.GetProperty("after"))));
        if (scenario.Id == "GL-035" && legacy.RootElement.GetProperty("unsupported_files").EnumerateArray()
            .Any(file => file.GetString() == LedgerReports.FinalFile))
        {
            string run = Path.GetDirectoryName(diffPath)!;
            string oldBefore = Path.Combine(run, "before-files", LedgerReports.FinalFile);
            string oldAfter = Path.Combine(run, "files", LedgerReports.FinalFile);
            try
            {
                if (File.Exists(oldBefore)) throw new InvalidDataException("実行前にも決算ファイルが存在します。");
                foreach (var (key, data) in ReadFinalEvidence(File.ReadAllBytes(oldAfter)))
                    expected.Add((LedgerReports.FinalFile, key), (null, data));
            }
            catch (Exception ex) when (ex is IOException or InvalidDataException)
            {
                differences.Add($"旧決算ファイルを比較できません：{ex.Message}");
            }
        }
        var actual = Changes(before, database.Snapshot());
        foreach (var ((file, key), change) in expected)
        {
            if (!actual.Remove((file, key), out var found)) differences.Add($"レコード差分なし：{file} {key}");
            else if (change != found)
            {
                differences.Add($"レコード内容：{file} {key} の前後バイト列が異なります。");
                if (scenario.Id == "SYS-001")
                {
                    if (change.Before != found.Before) differences.Add($"実行前：{ByteDifferences(change.Before, found.Before)}");
                    if (change.After != found.After) differences.Add($"実行後：{ByteDifferences(change.After, found.After)}");
                }
            }
        }
        foreach (var (file, key) in actual.Keys)
            differences.Add($"想定外のレコード差分：{file} {key}");

        var oldReports = targets.GetProperty("report_files").EnumerateArray()
            .Select(path => ComparableReport(scenario.Id, Content(path.GetString()!), legacy: true))
            .Distinct(StringComparer.Ordinal).ToArray();
        var newReports = database.Spool().Select(report => ComparableReport(scenario.Id, report.Body, legacy: false)).ToArray();
        if (oldReports.Length != newReports.Length)
            differences.Add($"帳票数：旧 {oldReports.Length}／新 {newReports.Length}（旧証跡の同一内容コピーを除く）。");
        else if (!newReports.Order(StringComparer.Ordinal).SequenceEqual(oldReports.Order(StringComparer.Ordinal)))
            differences.Add("帳票本文：正規化後のテキストが異なります（文言・配置・値は要切り分け）。");
        return Outcome.Compare(scenario, differences.Count == 0, string.Join("\n", observations),
            string.Join("\n", differences), source);
    }

    private static string? Hex(JsonElement record) =>
        record.ValueKind == JsonValueKind.Null ? null : record.GetProperty("hex").GetString();

    private static string ComparableReport(string id, string report, bool legacy)
    {
        bool chart = id is "GL-033" or "GL-206";
        bool detail = id is "GL-034" or "GL-225";
        bool structured = id == "GL-226";
        bool batch = id == "GL-221";
        if (!chart && !detail && !structured && !batch) return Normalize(report);
        var pages = report.Replace("\r", "", StringComparison.Ordinal).TrimEnd('\n', '\f').Split('\f');
        return string.Join('\f', pages.Select(page =>
        {
            var lines = page.TrimStart('\n').Split('\n').Select(line => line.TrimEnd()).ToArray();
            if (lines.Length < (chart ? 3 : 4)) return page;
            var first = lines[0];
            var second = lines[1];
            string pageNumber = Regex.Match(chart && legacy ? second : first,
                legacy ? @"Page\s*-?\s*(\d+)" : @"(\d+)ページ").Groups[1].Value;
            string date = Regex.Match(chart && legacy ? first : second, @"\b\d{2,4}/\d{2}/\d{2,4}\b").Value;
            if (pageNumber.Length == 0 || date.Length == 0) return page;
            string metadata;
            if (batch)
            {
                string cycle = Regex.Match(second, legacy ? @"Cycle\s*-\s*(\d+)" : @"会計期間\s*(\d+)").Groups[1].Value;
                if (cycle.Length == 0) return page;
                metadata = cycle;
            }
            else
            {
                metadata = legacy ? second[..Math.Min(second.Length, 32)].TrimEnd() :
                    second[..second.LastIndexOf(date, StringComparison.Ordinal)].TrimEnd();
            }
            int column = Array.FindIndex(lines, line => line.StartsWith(
                legacy ? chart ? "---Level---" : batch ? "Ledger" : "Account" :
                    chart ? "階層" : batch ? "台帳" : "勘定", StringComparison.Ordinal));
            if (column < 2) return page;
            if (detail)
            {
                var quarters = Regex.Matches(lines[column], legacy ? @"Quarter (\d+)" : @"第(\d+)四半期")
                    .Select(match => match.Groups[1].Value).ToArray();
                if (quarters.Length != 2) return page;
                metadata += "\n" + string.Join(",", quarters);
            }
            string[] rows = lines.Skip(column + (chart ? 1 : 2)).SkipWhile(string.IsNullOrWhiteSpace)
                .Reverse().SkipWhile(string.IsNullOrWhiteSpace).Reverse().ToArray();
            if (legacy)
                for (int i = 0; i < rows.Length; i++)
                {
                    if (chart && rows[i].Length > 57)
                    {
                        var name = rows[i].Length > 76 ? rows[i][76..] : "";
                        string placement = rows[i][57..Math.Min(76, rows[i].Length)].Trim() switch
                        {
                            "Direct Income" => "直接収益", "Direct Costs" => "直接原価", "Sundry Income" => "雑収益",
                            "Indirect Cost" => "間接原価", "Fixed Assets" => "固定資産", "Current Asset" => "流動資産",
                            "Current Liab." => "流動負債", "Capital A/Cs" => "資本", var value => value
                        };
                        rows[i] = (rows[i][..57] + placement.PadRight(19) + name).TrimEnd();
                    }
                    if (detail || structured)
                        rows[i] = Regex.Replace(rows[i], @"^ {20}[Tt] o t a l.{0,2}", "                    合計".PadRight(29));
                }
            if (detail || structured)
                for (int i = 0; i < rows.Length; i++)
                    if (rows[i].TrimStart().StartsWith("合計", StringComparison.Ordinal))
                        rows[i] = Normalize(rows[i]);
            return pageNumber + "\n" + date + "\n" + metadata + "\n" + string.Join('\n', rows);
        }));
    }

    private static string ByteDifferences(string? expected, string? actual)
    {
        if (expected is null || actual is null) return "一方にのみレコードがあります。";
        byte[] old = Convert.FromHexString(expected), current = Convert.FromHexString(actual);
        var offsets = Enumerable.Range(0, Math.Min(old.Length, current.Length)).Where(i => old[i] != current[i]);
        return $"旧 {old.Length}／新 {current.Length} バイト、差の位置（0 起点）：{string.Join(", ", offsets)}";
    }

    private static Dictionary<string, string> ReadFinalEvidence(byte[] file)
    {
        const int pageSize = 4096;
        if (file.Length != 2 * pageSize || BinaryPrimitives.ReadUInt32LittleEndian(file.AsSpan(12)) != 0x00053162 ||
            BinaryPrimitives.ReadUInt32LittleEndian(file.AsSpan(16)) != 9 ||
            BinaryPrimitives.ReadUInt32LittleEndian(file.AsSpan(20)) != pageSize ||
            file[pageSize + 25] != 5)
            throw new InvalidDataException("旧決算ファイルが単一リーフの Berkeley DB B-tree ではありません。");
        var page = file.AsSpan(pageSize);
        int entries = BinaryPrimitives.ReadUInt16LittleEndian(page[20..]);
        if (entries == 0 || entries % 2 != 0 || entries > (pageSize - 26) / 2)
            throw new InvalidDataException("旧決算ファイルの索引件数が不正です。");
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        for (int index = 0; index < entries; index += 2)
        {
            var key = FinalEntry(page, entries, index, 9);
            var data = FinalEntry(page, entries, index + 1, 45);
            if (!data.StartsWith(key) || !result.TryAdd(Encoding.ASCII.GetString(key), Convert.ToHexString(data).ToLowerInvariant()))
                throw new InvalidDataException("旧決算ファイルのレコードキーが不正です。");
        }
        return result;
    }

    private static ReadOnlySpan<byte> FinalEntry(ReadOnlySpan<byte> page, int entries, int index, int length)
    {
        int offset = BinaryPrimitives.ReadUInt16LittleEndian(page[(26 + index * 2)..]);
        if (offset < 26 + entries * 2 || offset + 3 + length > page.Length ||
            BinaryPrimitives.ReadUInt16LittleEndian(page[offset..]) != length || page[offset + 2] != 1)
            throw new InvalidDataException("旧決算ファイルのレコード形式が不正です。");
        return page.Slice(offset + 3, length);
    }

    private static string Normalize(string report) =>
        string.Join(' ', report.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    private static Dictionary<(string File, string Key), (string? Before, string? After)> Changes(
        SortedDictionary<string, SortedDictionary<string, string>> before,
        SortedDictionary<string, SortedDictionary<string, string>> after)
    {
        var result = new Dictionary<(string File, string Key), (string? Before, string? After)>();
        foreach (string file in before.Keys.Union(after.Keys))
        {
            var previous = before.GetValueOrDefault(file) ?? [];
            var current = after.GetValueOrDefault(file) ?? [];
            foreach (string key in previous.Keys.Union(current.Keys))
            {
                string? a = previous.GetValueOrDefault(key), b = current.GetValueOrDefault(key);
                if (a != b) result.Add((file, key), (a, b));
            }
        }
        return result;
    }
}
