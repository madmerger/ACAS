using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Acas.Core.Engine;

public sealed class CaseResult
{
    public string Id = "", Title = "", Subsystem = "";
    public bool ScreensMatch, RecordsMatch, ReportsMatch, Japanese;
    public int Steps, ScreensCompared;
    public List<string> Diffs = new();
    public List<string> Untranslated = new();
    public List<string[]> Screens = new();         // 日本語表示(各ステップ後)
    public string? Error;
    public bool Match => Error == null && ScreensMatch && RecordsMatch && ReportsMatch && Japanese;
}

/// <summary>
/// 同一性テストのケース再生。シナリオ台帳のキー入力を同じ順で与え、各ステップ後の画面(原文 Shadow)を
/// レガシー実測画面と、DB の論理レコード差分をレガシー record-diff.json と比較する。
/// </summary>
public static class CaseRunner
{
    private static readonly Regex TimeRx = new(@"\d\d:\d\d:\d\d", RegexOptions.Compiled);
    public static string Norm(string line) => TimeRx.Replace(line.TrimEnd(), "HH:MM:SS");

    public static Key[] StepKeys(JsonElement step)
    {
        var keys = new List<Key>();
        if (step.TryGetProperty("text", out var t)) foreach (var ch in t.GetString()!) keys.Add(Key.Of(ch));
        if (step.TryGetProperty("key", out var k))
            keys.Add(new Key(k.GetString() switch
            {
                "ENTER" => K.Enter, "TAB" => K.Tab, "ESC" => K.Esc, "HOME" => K.Home, "UP" => K.Up, "DOWN" => K.Down,
                "F1" => K.F1, "F2" => K.F2, "F3" => K.F3, "F4" => K.F4, "F8" => K.F8, _ => K.Enter
            }));
        return keys.ToArray();
    }

    /// <summary>レガシー実行日 (terminal.cast ヘッダの timestamp, UTC)。</summary>
    public static DateTime LegacyClock(string runDir)
    {
        var cast = Path.Combine(runDir, "terminal.cast");
        if (File.Exists(cast))
        {
            using var r = new StreamReader(cast);
            var head = r.ReadLine();
            if (head != null)
            {
                using var doc = JsonDocument.Parse(head);
                if (doc.RootElement.TryGetProperty("timestamp", out var ts))
                    return DateTimeOffset.FromUnixTimeSeconds(ts.GetInt64()).UtcDateTime;
            }
        }
        return new DateTime(2026, 11, 23, 4, 20, 0);
    }

    /// <param name="onStep">UI 再生用: 各キー送出前に呼ばれる(待ち時間を入れる)。</param>
    public static async Task<CaseResult> Run(JsonElement c, string evidenceRoot, Ctx? ctx = null, Func<int, Task>? onStep = null)
    {
        var res = new CaseResult { Id = c.GetProperty("id").GetString()!, Title = c.GetProperty("title").GetString()!, Subsystem = c.GetProperty("subsystem").GetString()! };
        var legacy = c.GetProperty("legacy_result");
        string? runDir = null;
        if (legacy.TryGetProperty("evidence", out var ev) && ev.GetArrayLength() > 0)
            runDir = Path.Combine(evidenceRoot, ev[0].GetString()!.Replace('/', Path.DirectorySeparatorChar));
        var runner = c.GetProperty("runner");
        var app = runner.GetProperty("app").GetString();
        ctx ??= new Ctx(new Db());
        ctx.Db.LoadBaseline(c.GetProperty("baseline").GetString()!);
        if (runDir != null) { var t0 = LegacyClock(runDir); ctx.Now = () => t0; }
        var before = ctx.Db.Snapshot();
        Task prog = app == "irs" ? Programs.Launcher.RunIrs(ctx) : Programs.Launcher.RunAcas(ctx);
        var steps = runner.GetProperty("steps");
        res.ScreensMatch = true; int i = 0;
        foreach (var step in steps.EnumerateArray())
        {
            if (onStep != null) await onStep(i);
            foreach (var k in StepKeys(step))
            {
                if (prog.IsCompleted) break;
                if (onStep != null) await onStep(-1);
                ctx.Crt.Keys.Post(k);
            }
            if (prog.IsFaulted && prog.Exception!.InnerException is not StopRun) { res.Error = prog.Exception.InnerException!.ToString(); break; }
            res.Screens.Add(ctx.Crt.VisibleLines());
            if (runDir != null)
            {
                var name = step.TryGetProperty("name", out var n) ? n.GetString() : "screen";
                var f = Path.Combine(runDir, $"{i:00}-{name}.txt");
                if (File.Exists(f))
                {
                    res.ScreensCompared++;
                    var exp = File.ReadAllText(f).Split('\n');
                    var act = ctx.Crt.ShadowLines();
                    for (int r = 0; r < Crt.Rows; r++)
                    {
                        var e = r < exp.Length ? Norm(exp[r]) : ""; var a = Norm(act[r]);
                        if (e != a) { res.ScreensMatch = false; if (res.Diffs.Count < 12) res.Diffs.Add($"step {i} 行{r + 1}: 旧[{e}] 新[{a}]"); }
                    }
                }
            }
            i++;
        }
        res.Steps = i;
        // レコード差分
        res.RecordsMatch = true;
        var after = ctx.Db.Snapshot();
        if (runDir != null && File.Exists(Path.Combine(runDir, "record-diff.json")))
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(runDir, "record-diff.json")));
            var expCh = new SortedDictionary<string, string?>(StringComparer.Ordinal);
            foreach (var ch in doc.RootElement.GetProperty("changes").EnumerateArray())
            {
                string? hex = ch.TryGetProperty("after", out var af) && af.ValueKind == JsonValueKind.Object ? af.GetProperty("hex").GetString() : null;
                expCh[ch.GetProperty("file").GetString() + "|" + ch.GetProperty("key").GetString()] = hex;
            }
            var actCh = new SortedDictionary<string, string?>(StringComparer.Ordinal);
            var files = new HashSet<string>(before.Keys); files.UnionWith(after.Keys);
            foreach (var f in files)
            {
                before.TryGetValue(f, out var b); after.TryGetValue(f, out var a);
                var keys = new HashSet<string>(); if (b != null) keys.UnionWith(b.Keys); if (a != null) keys.UnionWith(a.Keys);
                foreach (var k in keys)
                {
                    string? bv = b != null && b.TryGetValue(k, out var x) ? x : null, av = a != null && a.TryGetValue(k, out var y) ? y : null;
                    if (bv != av && Records.Tracked(f)) actCh[f + "|" + k] = av;
                }
            }
            foreach (var k in expCh.Keys.Union(actCh.Keys).ToList())
            {
                expCh.TryGetValue(k, out var e); actCh.TryGetValue(k, out var a);
                bool ein = expCh.ContainsKey(k), ain = actCh.ContainsKey(k);
                if (ein && ain && Records.Same(k, e, a)) continue;
                res.RecordsMatch = false;
                if (res.Diffs.Count < 16) res.Diffs.Add($"レコード {k}: 旧[{(ein ? Records.Describe(e, a) : "変更なし")}] 新[{(ain ? (a == null ? "削除" : "変更") : "変更なし")}]");
            }
        }
        res.ReportsMatch = Records.CompareReports(ctx, runDir, res.Diffs);
        res.Untranslated.AddRange(ctx.Crt.Untranslated);
        res.Japanese = res.Untranslated.Count == 0;
        return res;
    }
}
