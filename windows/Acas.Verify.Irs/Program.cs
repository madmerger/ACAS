using System.IO.Compression;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Acas.Core.Engine;

Console.OutputEncoding = Encoding.UTF8;
if (args.Length is < 1 or > 2)
{
    Console.Error.WriteLine("使い方: Acas.Verify.Irs 証跡.zip [結果.json]");
    return 2;
}

using var zip = ZipFile.OpenRead(args[0]);
using var ledger = ReadJson("入力/シナリオ台帳.json");
var results = new List<CaseResult>();
foreach (var item in ledger.RootElement.GetProperty("cases").EnumerateArray())
{
    string id = item.GetProperty("id").GetString()!;
    if (!id.StartsWith("IRS-", StringComparison.Ordinal) && !id.StartsWith("INT-", StringComparison.Ordinal)) continue;
    var legacy = item.GetProperty("legacy_result");
    if (legacy.GetProperty("verdict").GetString() == "未実施")
    {
        results.Add(new(id, "対象外", [legacy.GetProperty("reason").GetString()!]));
        continue;
    }

    var diffs = new List<string>();
    string[] unmeasured = [];
    try
    {
        var targets = legacy.GetProperty("comparison_targets");
        var referenceScreens = targets.GetProperty("screen_text").EnumerateArray().Select(p => Read(p.GetString()!)).ToArray();
        var root = legacy.GetProperty("evidence")[0].GetString()!;
        using var doc = JsonDocument.Parse(Read(root + "/terminal.cast").Split('\n', 2)[0]);
        DateTime date = DateTimeOffset.FromUnixTimeSeconds(doc.RootElement.GetProperty("timestamp").GetInt64()).UtcDateTime.Date;
        using var db = new Db();
        db.LoadBaseline(item.GetProperty("baseline").GetString()!);
        var before = db.Snapshot();
        var run = new Scenario(db, date, item);
        try { run.Replay(referenceScreens); }
        catch (InvalidOperationException ex) { diffs.Add(ex.Message); }
        using var delta = ReadJson(targets.GetProperty("keyed_record_diff").GetString()!);
        using var afterRecords = ReadJson(root + "/after-records/records.json");
        var unsupported = afterRecords.RootElement.GetProperty("unsupported_files").EnumerateArray()
            .Select(f => f.GetString()!).ToHashSet(StringComparer.Ordinal);
        unmeasured = CompareRecords(before, db.Snapshot(), delta.RootElement, unsupported, diffs);

        var expectedReports = targets.GetProperty("report_files").EnumerateArray().Select(p => p.GetString()!).ToArray();
        if (expectedReports.Length == 0)
        {
            if (db.Spool().Count > 0) diffs.Add("証跡にない帳票が出力されました。");
        }
        else
        {
            foreach (string path in expectedReports)
            {
                if (run.Report?.LegacyBody is not string body)
                {
                    diffs.Add("帳票出力なし: " + path);
                    continue;
                }
                var expectedLines = NormalizeReports(Read(path)).Split('\n');
                var actualLines = NormalizeReports(body).Split('\n');
                var unequal = Enumerable.Range(0, Math.Max(expectedLines.Length, actualLines.Length))
                    .Where(i => expectedLines.ElementAtOrDefault(i) != actualLines.ElementAtOrDefault(i)).Select(i => i + 1).ToArray();
                if (unequal.Length > 0) diffs.Add($"帳票内容の相違: {path} 行 {string.Join(",", unequal)}");
            }
        }
    }
    catch (Exception ex) { diffs.Add(ex.GetType().Name + ": " + ex.Message); }
    results.Add(new(id, diffs.Count == 0 ? "一致" : "不一致", diffs, unmeasured));
}

foreach (var result in results)
{
    Console.WriteLine($"{LogText(result.Id)} {result.Verdict}");
    foreach (var diff in result.Differences) Console.WriteLine("  " + LogText(diff));
    foreach (var file in result.UnmeasuredFiles ?? []) Console.WriteLine("  論理レコード未採取: " + LogText(file));
}
Console.WriteLine(string.Join(" / ", new[] { "一致", "不一致", "対象外" }
    .Select(verdict => $"{verdict} {results.Count(r => r.Verdict == verdict)}")));
if (args.Length == 2)
    File.WriteAllText(args[1], JsonSerializer.Serialize(results,
        new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
return results.Any(r => r.Verdict == "不一致") ? 1 : 0;

static string LogText(string value) => string.Concat(value.Select(c =>
    char.IsControl(c) || char.GetUnicodeCategory(c) is System.Globalization.UnicodeCategory.Format
        or System.Globalization.UnicodeCategory.LineSeparator or System.Globalization.UnicodeCategory.ParagraphSeparator
        ? $"\\u{(int)c:X4}" : c.ToString()));

string Read(string name)
{
    const int MaxEntryBytes = 16 * 1024 * 1024;
    var entry = zip.GetEntry(name) ?? throw new InvalidDataException("証跡が見つかりません: " + name);
    if (entry.Length > MaxEntryBytes) throw new InvalidDataException("証跡の展開サイズが上限を超えています: " + name);
    using var stream = entry.Open();
    using var payload = new MemoryStream((int)entry.Length);
    Span<byte> buffer = stackalloc byte[8192];
    int read;
    while ((read = stream.Read(buffer)) != 0)
    {
        if (payload.Length + read > MaxEntryBytes)
            throw new InvalidDataException("証跡の展開サイズが上限を超えています: " + name);
        payload.Write(buffer[..read]);
    }
    payload.Position = 0;
    using var reader = new StreamReader(payload, Encoding.UTF8);
    return reader.ReadToEnd();
}

JsonDocument ReadJson(string name) => JsonDocument.Parse(Read(name));

static string NormalizeReports(string body) => string.Join('\n', body.Replace("\r\n", "\n")
    .Split('\n').Select(line => line.TrimEnd(' ', '\r')).SkipWhile(string.IsNullOrEmpty)).TrimEnd('\n');

static string[] CompareRecords(SortedDictionary<string, SortedDictionary<string, string>> before,
    SortedDictionary<string, SortedDictionary<string, string>> after, JsonElement expected, HashSet<string> unsupported,
    List<string> diffs)
{
    static Dictionary<(string, string), string> Flatten(SortedDictionary<string, SortedDictionary<string, string>> snapshot) =>
        snapshot.SelectMany(file => file.Value.Select(record => (Key: (file.Key, record.Key), record.Value)))
            .ToDictionary(r => r.Key, r => r.Value);
    var b = Flatten(before);
    var a = Flatten(after);
    var e = expected.GetProperty("changes").EnumerateArray().ToDictionary(
        row => (row.GetProperty("file").GetString()!, row.GetProperty("key").GetString()!),
        row => row.GetProperty("after").ValueKind == JsonValueKind.Null ? null : row.GetProperty("after").GetProperty("hex").GetString());
    var changed = b.Keys.Union(a.Keys).Where(key => !Same(b.GetValueOrDefault(key), a.GetValueOrDefault(key))).ToHashSet();
    foreach (var key in e.Keys.Union(changed.Where(key => !unsupported.Contains(key.Item1))).Order())
    {
        if (!e.TryGetValue(key, out var expectedHex)) { diffs.Add($"証跡にない更新: {key}"); continue; }
        if (!changed.Contains(key)) { diffs.Add($"必要な更新なし: {key}"); continue; }
        var actual = a.GetValueOrDefault(key);
        if (Same(expectedHex, actual)) continue;
        if (expectedHex is null || actual is null) { diffs.Add($"削除の相違: {key}"); continue; }
        var expectedBytes = Convert.FromHexString(expectedHex);
        var actualBytes = Convert.FromHexString(actual);
        var offsets = Enumerable.Range(0, Math.Min(expectedBytes.Length, actualBytes.Length))
            .Where(i => expectedBytes[i] != actualBytes[i]).ToArray();
        diffs.Add($"レコード相違: {key} 旧{expectedBytes.Length}バイト 新{actualBytes.Length}バイト 相違位置 {string.Join(",", offsets)}");
    }
    return changed.Select(key => key.Item1).Where(unsupported.Contains).Distinct().Order().ToArray();
    static bool Same(string? left, string? right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);
}

sealed record CaseResult(string Id, string Verdict, IReadOnlyList<string> Differences, IReadOnlyList<string>? UnmeasuredFiles = null);
