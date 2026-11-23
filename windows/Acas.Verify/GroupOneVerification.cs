using System.Text;
using System.Text.Json;
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
            var navigation = model.Navigation().SelectMany(item => item.Children?.Prepend(item) ?? [item])
                .ToDictionary(item => item.Id);
            Screen screen = model.Start();
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
                    case ActionType.Text or ActionType.Choice:
                        var field = (screen as FormScreen)?.Fields.SingleOrDefault(field => field.Id == action.Id);
                        if (field is not (TextField or PasswordField) && action.Type == ActionType.Text ||
                            field is not ChoiceField && action.Type == ActionType.Choice)
                            throw new InvalidOperationException($"該当する入力欄がありません：{action.Id}（{screen.Title}）");
                        if (field is ChoiceField choice && choice.Options.All(option => option.Value != action.Value))
                            throw new InvalidOperationException($"指定した選択肢がありません：{action.Id}／{action.Value}");
                        inputs[action.Id] = action.Value;
                        break;
                    default:
                        screen = Move(navigation, screen, action, inputs);
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
        var actual = Changes(before, database.Snapshot());
        foreach (var ((file, key), change) in expected)
        {
            if (!actual.Remove((file, key), out var found)) differences.Add($"レコード差分なし：{file} {key}");
            else if (change != found) differences.Add($"レコード内容：{file} {key} の前後バイト列が異なります。");
        }
        foreach (var (file, key) in actual.Keys)
            differences.Add($"想定外のレコード差分：{file} {key}");

        var oldReports = targets.GetProperty("report_files").EnumerateArray()
            .Select(path => Normalize(Content(path.GetString()!))).Distinct(StringComparer.Ordinal).ToArray();
        var newReports = database.Spool().Select(report => Normalize(report.Body)).ToArray();
        if (oldReports.Length != newReports.Length)
            differences.Add($"帳票数：旧 {oldReports.Length}／新 {newReports.Length}（旧証跡の同一内容コピーを除く）。");
        else if (!newReports.Order(StringComparer.Ordinal).SequenceEqual(oldReports.Order(StringComparer.Ordinal)))
            differences.Add("帳票本文：正規化後のテキストが異なります（文言・配置・値は要切り分け）。");
        return Outcome.Compare(scenario, differences.Count == 0, string.Join("\n", observations),
            string.Join("\n", differences), source);
    }

    private static string? Hex(JsonElement record) =>
        record.ValueKind == JsonValueKind.Null ? null : record.GetProperty("hex").GetString();

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
