using System.Text;
using System.Text.Json;
using Acas.Core.Engine;

// 同一性テストのヘッドレス一括再生: Acas.Verify <シナリオ台帳.json> <証跡ルート> [ケースID接頭辞...] [--out result.json] [-v]
Console.OutputEncoding = Encoding.UTF8;
var ledger = args[0]; var root = args[1];
var filters = args.Skip(2).Where(a => !a.StartsWith("-")).ToArray();
bool verbose = args.Contains("-v");
string? outPath = null;
for (int i = 0; i < args.Length - 1; i++) if (args[i] == "--out") { outPath = args[i + 1]; filters = filters.Where(f => f != outPath).ToArray(); }
foreach (var b in I18n.Misaligned()) Console.WriteLine("括弧位置ずれ: " + b);
using var doc = JsonDocument.Parse(File.ReadAllText(ledger));
int ok = 0, ng = 0; var results = new List<object>();
foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
{
    var id = c.GetProperty("id").GetString()!;
    if (filters.Length > 0 && !filters.Any(f => id.StartsWith(f))) continue;
    if (c.GetProperty("subsystem").GetString() == "CALC")
    {
        var calc = Acas.Core.Programs.Calc.Run(c);
        if (calc == null)
        {
            Console.WriteLine($"N/A {id} 対象外 (レガシー未実施: 比較対象なし)");
            results.Add(new { id, match = (bool?)null, verdict = "対象外", result = "", reason = "レガシー側未実施 (HTTP/ブラウザ専用の期待で端末版に判定面が無い) のため比較対象なし" });
            continue;
        }
        var legacy = Acas.Core.Programs.Calc.LegacyLine(c, root);
        bool same = legacy != null && legacy == calc.Value.Line;
        if (same) ok++; else ng++;
        Console.WriteLine($"{(same ? "OK  " : "NG  ")}{id} {calc.Value.Summary}");
        if (!same) Console.WriteLine($"   旧[{legacy}] 新[{calc.Value.Line}]");
        results.Add(new { id, match = (bool?)same, verdict = same ? "一致" : "不一致", result = calc.Value.Summary, reason = same ? "" : $"旧[{legacy}] 新[{calc.Value.Line}]" });
        continue;
    }
    if (!c.GetProperty("runner").TryGetProperty("steps", out _)) { Console.WriteLine($"SKIP {id}"); continue; }
    CaseResult r;
    try { r = await CaseRunner.Run(c, root); }
    catch (Exception e) { r = new CaseResult { Id = id, Error = e.ToString() }; }
    if (r.Match) ok++; else ng++;
    Console.WriteLine($"{(r.Match ? "OK  " : "NG  ")}{id} 画面={(r.ScreensMatch ? "○" : "×")}({r.ScreensCompared}) レコード={(r.RecordsMatch ? "○" : "×")} 帳票={(r.ReportsMatch ? "○" : "×")} 日本語={(r.Japanese ? "○" : "×")}");
    if (!r.Match && (verbose || filters.Length > 0))
    {
        if (r.Error != null) Console.WriteLine("   ERR " + r.Error.Split('\n')[0]);
        foreach (var d in r.Diffs) Console.WriteLine("   " + d);
        foreach (var u in r.Untranslated.Take(Environment.GetEnvironmentVariable("ACAS_UNTR_ALL") == "1" ? 9999 : 15)) Console.WriteLine("   未翻訳: " + u);
    }
    results.Add(new { id, match = r.Match, screens = r.ScreensMatch, records = r.RecordsMatch, reports = r.ReportsMatch, japanese = r.Japanese, diffs = r.Diffs, untranslated = r.Untranslated, error = r.Error });
}
Console.WriteLine($"一致 {ok} / 不一致 {ng}");
if (outPath != null) File.WriteAllText(outPath, JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
