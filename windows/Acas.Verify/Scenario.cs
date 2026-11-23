using System.Text.Encodings.Web;
using System.Text.Json;
using Acas.Core.Programs.Calculation;

namespace Acas.Verify;

public sealed record Scenario(string Id, string Title, string Subsystem, bool Excluded, string? Evidence,
    string? Driver, JsonElement Input, string Baseline, JsonElement LegacyTargets, JsonElement Steps)
{
    public static int GroupOf(string subsystem) => subsystem switch
    {
        "SYS" or "GL" => 1, "SL" => 2, "PL" => 3, "ST" or "IRS" or "INT" => 4, "CALC" => 5,
        _ => throw new InvalidDataException($"不明なサブシステム：{subsystem}")
    };

    public int Group => GroupOf(Subsystem);

    public static IReadOnlyList<Scenario> Load(string ledger)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(ledger));
        return document.RootElement.GetProperty("cases").EnumerateArray().Select(FromJson).ToArray();
    }

    private static Scenario FromJson(JsonElement item)
    {
        var legacy = item.GetProperty("legacy_result");
        var evidence = legacy.GetProperty("evidence");
        var programs = item.GetProperty("programs");
        return new(item.GetProperty("id").GetString()!, item.GetProperty("title").GetString()!,
            item.GetProperty("subsystem").GetString()!, legacy.GetProperty("verdict").GetString() == "未実施",
            evidence.GetArrayLength() == 0 ? null : evidence[0].GetString(),
            programs.GetArrayLength() == 0 ? null : programs[0].GetString(),
            item.TryGetProperty("input_data", out var input) ? input.Clone() : default,
            item.GetProperty("baseline").GetString()!,
            legacy.TryGetProperty("comparison_targets", out var targets) ? targets.Clone() : default,
            item.TryGetProperty("runner", out var runner) && runner.TryGetProperty("steps", out var steps) ? steps.Clone() : default);
    }

    public (string First, string Second, string AutomationId) CalcInput()
    {
        string Value(string key)
        {
            var property = Input.GetProperty(key);
            return property.ValueKind == JsonValueKind.String ? property.GetString()! : property.GetRawText();
        }
        return Driver switch
        {
            "drv09" => (Value("code"), "", "CalcCheckDigit"),
            "drv04" => (Value("date"), "", "CalcDate"),
            "drvvat" => (Value("net"), Value("rate"), "CalcTax"),
            "drvage" => (Value("days"), "", "CalcAge"),
            "drvavg" => (Value("value"), Value("qty"), "CalcAverage"),
            _ => throw new InvalidDataException("対応する計算ドライバがありません。")
        };
    }

    public string ExpectedLine(string root)
    {
        if (Evidence is null) throw new InvalidDataException("台帳に証跡がありません。");
        string path = EvidencePath(root, Path.Combine(Evidence, "00-output.txt"));
        return File.ReadLines(path).FirstOrDefault(line => !string.IsNullOrWhiteSpace(line))
            ?? throw new InvalidDataException("証跡に計算結果がありません。");
    }

    internal static string EvidencePath(string root, string file)
    {
        string dir = Path.GetFullPath(root);
        string path = Path.GetFullPath(Path.Combine(dir, file));
        string relative = Path.GetRelativePath(dir, path);
        if (Path.IsPathRooted(relative) || relative == ".." || relative.StartsWith(".." + Path.DirectorySeparatorChar))
            throw new InvalidDataException("証跡が指定範囲外にあります。");
        return path;
    }

    public Outcome CompareCalculation(string root)
    {
        if (Excluded) return Outcome.Exclude(this);
        try
        {
            var (first, second, _) = CalcInput();
            string actual = Calculations.Run(Driver!, first, second);
            string expected = ExpectedLine(root);
            return Outcome.Compare(this, actual == expected, Calculations.Summary(Driver!, actual),
                $"旧：「{expected}」／新：「{actual}」", "新計算");
        }
        catch (Exception e) when (e is IOException or FormatException or OverflowException or InvalidDataException or KeyNotFoundException)
        {
            return Outcome.Compare(this, false, "", e.Message, "新計算");
        }
    }
}

public sealed record Outcome(string Id, string Title, string Subsystem, int Group, string Verdict, bool? Match,
    string Result, string Reason, string Source, double? VideoSeconds = null)
{
    public static Outcome Exclude(Scenario scenario) => new(scenario.Id, scenario.Title, scenario.Subsystem,
        scenario.Group, "対象外", null, "", "台帳のレガシー判定が未実施", "台帳");

    public static Outcome Compare(Scenario scenario, bool match, string result, string reason, string source) =>
        new(scenario.Id, scenario.Title, scenario.Subsystem, scenario.Group, match ? "一致" : "不一致", match,
            result, match ? "" : reason, source);

    public static Outcome Missing(Scenario scenario, string reason) => new(scenario.Id, scenario.Title, scenario.Subsystem,
        scenario.Group, "未検証", null, "", reason, "");

    public static JsonSerializerOptions JsonOptions { get; } = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = true
    };

    public static void Write(string path, IReadOnlyList<Outcome> outcomes) =>
        File.WriteAllText(path, JsonSerializer.Serialize(outcomes, JsonOptions));
}

public sealed record RunOptions(string Ledger, string Evidence, string Output, int? Group, string? Extra,
    IReadOnlySet<string> Cases)
{
    public static RunOptions Parse(string[] args, string extraFlag)
    {
        if (args.Length < 4 || (args.Length - 2) % 2 != 0) throw new ArgumentException("台帳と証跡ルートを指定してください。");
        int? group = null;
        string? output = null, extra = null;
        var cases = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (int index = 2; index < args.Length; index += 2)
        {
            string value = args[index + 1];
            if (args[index] == "--out" && output is null) output = value;
            else if (args[index] == extraFlag && extra is null) extra = value;
            else if (args[index] == "--case" && !string.IsNullOrWhiteSpace(value)) cases.Add(value);
            else if (args[index] == "--group" && group is null)
            {
                int number = "①②③④⑤".IndexOf(value, StringComparison.Ordinal) + 1;
                if (value.Length != 1 || (number == 0 && !int.TryParse(value, out number)) || number is < 1 or > 5)
                    throw new ArgumentException("グループは①〜⑤（1〜5）で指定してください。");
                group = number;
            }
            else throw new ArgumentException($"不明または重複した指定です：{args[index]}");
        }
        return new(args[0], args[1], output ?? throw new ArgumentException("結果の保存先を指定してください。"), group, extra, cases);
    }

    public IReadOnlyList<Scenario> Scenarios()
    {
        var selected = Scenario.Load(Ledger).Where(scenario =>
            (Group is null || Group == scenario.Group) && (Cases.Count == 0 || Cases.Contains(scenario.Id))).ToArray();
        var missing = Cases.Except(selected.Select(scenario => scenario.Id), StringComparer.OrdinalIgnoreCase).ToArray();
        if (missing.Length > 0) throw new ArgumentException($"指定範囲にないケースです：{string.Join("、", missing)}");
        return selected;
    }
}
