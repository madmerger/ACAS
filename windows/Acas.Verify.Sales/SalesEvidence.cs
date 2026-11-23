using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

namespace Acas.Verify.Sales;

public static class SalesEvidence
{
    public static bool SettingsMatch(string evidence, TableScreen settings, List<string> issues)
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

    public static void CheckSnapshot(string root, string path, SortedDictionary<string, SortedDictionary<string, string>> actual,
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

    public static void CheckDiff(JsonElement comparison, string root, SortedDictionary<string, SortedDictionary<string, string>> before,
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

    public static void CheckReports(JsonElement comparison, string root, Db database, List<string> issues,
        Func<string, bool>? acceptsPrintTime = null)
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
            if (SalesReportValues.Difference(legacy, body, acceptsPrintTime) is { } problem) issues.Add($"{name}: {problem}");
        }
        foreach (var (name, entries) in actual)
            if (entries.Count > 0) issues.Add($"証跡にない帳票が作成されました: {name}（{entries.Count}件）");
    }

    public static DateTime ReadClock(string path)
    {
        using var header = JsonDocument.Parse(File.ReadLines(path).First());
        return DateTimeOffset.FromUnixTimeSeconds(header.RootElement.GetProperty("timestamp").GetInt64()).UtcDateTime;
    }

    public static string SafePath(string root, string path)
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
}
