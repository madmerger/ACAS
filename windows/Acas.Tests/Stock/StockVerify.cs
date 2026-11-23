using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Stock;

namespace Acas.Tests.Stock;

/// <summary>ST- ケースのヘッドレス同一性検証。レガシー証跡（画面見出し・論理レコード差分・帳票 prt-1）と移行版の結果を比較する。</summary>
public static class StockVerify
{
    public sealed class Result
    {
        public string Id { get; set; } = "";
        public string Title { get; set; } = "";
        public string LegacyVerdict { get; set; } = "";
        public string Verdict { get; set; } = "";
        public int Steps { get; set; }
        public int ScreensCompared { get; set; }
        public bool ScreensMatch { get; set; } = true;
        public bool RecordsMatch { get; set; } = true;
        public bool ReportsMatch { get; set; } = true;
        public bool Japanese { get; set; } = true;
        public List<string> Diffs { get; } = [];
        public List<string> Untranslated { get; } = [];
        public List<string[]> Screens { get; } = [];
        public bool Match => Verdict == "一致";
    }

    /// <summary>レガシー見出し（空白除去）→ 移行版の画面タイトル。</summary>
    public static readonly IReadOnlyDictionary<string, string> TitleMap = new Dictionary<string, string>
    {
        ["ACASSystemMenu"] = "システムメニュー",
        ["StockControl-StartOfDay"] = "在庫管理　処理日入力",
        ["StockControlSystemMenu"] = StockScreenModel.MainTitle,
        ["StockFileSet-Up&Maintenance"] = StockScreenModel.MaintenanceTitle,
        ["StockRecordCreation"] = "在庫品目登録",
        ["StockRecordDeletion"] = "在庫品目削除",
        ["StockRecordDisplay"] = "在庫品目照会",
        ["StockMovementsMenu"] = StockScreenModel.MovementsTitle,
        ["StockAdditionsEntry"] = "在庫入庫入力",
        ["StockDeductionsEntry"] = "在庫出庫入力",
        ["StockBarcodeAdditionsEntry"] = "バーコード入庫入力",
        ["StockEndofMonthProcessing"] = "在庫月末処理",
        ["StockControl-ReportsMenu"] = StockScreenModel.ReportsTitle,
        ["StockValuationReport"] = "在庫評価表",
        ["StockActivityReport"] = "在庫受払表",
        ["StockRe-OrderReport"] = "発注点割れ一覧表",
        ["StockHistoryReport"] = "在庫履歴表",
        ["StockReport"] = "在庫一覧表",
        ["StockActivityReset"] = "在庫期間締め",
        ["StockCompressionUtility"] = "在庫ファイル圧縮",
        ["SystemSet-Up"] = "システム設定",
    };

    private static readonly Regex Version = new(@"\(\d+\.\d+\.\d+\)(.*)$");

    /// <summary>レガシー画面テキストの見出しを移行版タイトルへ写像する（見つからなければ null）。</summary>
    public static string? LegacyTitle(string screen)
    {
        foreach (var line in screen.Split('\n').Take(4))
        {
            var m = Version.Match(line);
            if (!m.Success) continue;
            string rest = Regex.Replace(m.Groups[1].Value, @"\s+(at\s+\d\d:\d\d.*|\d\d/\d\d/\d{4}.*)$", "").Replace(" ", "");
            var hit = TitleMap.Keys.Where(k => rest.Contains(k, StringComparison.Ordinal)).OrderByDescending(k => k.Length).FirstOrDefault();
            if (hit != null) return TitleMap[hit];
        }
        return null;
    }

    private static string? SafeEvidenceDir(string root, string relative)
    {
        try
        {
            if (Path.IsPathRooted(relative) || relative.StartsWith(@"\\", StringComparison.Ordinal)) return null;
            string baseDir = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(Path.Combine(baseDir, relative));
            if (!full.StartsWith(baseDir, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)) return null;
            for (var d = new DirectoryInfo(full); d != null && d.FullName.Length >= baseDir.Length - 1; d = d.Parent)
                if (d.Exists && d.Attributes.HasFlag(FileAttributes.ReparsePoint)) return null;
            if (Directory.Exists(full) && Directory.EnumerateFileSystemEntries(full, "*", SearchOption.AllDirectories)
                    .Any(e => File.GetAttributes(e).HasFlag(FileAttributes.ReparsePoint))) return null;
            return full;
        }
        catch (Exception e) when (e is ArgumentException or IOException or NotSupportedException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static List<Result> Run(string ledgerPath, string evidenceRoot, string prefix = "ST-")
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(ledgerPath));
        var results = new List<Result>();
        foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            string id = c.GetProperty("id").GetString()!;
            if (!id.StartsWith(prefix, StringComparison.Ordinal)) continue;
            results.Add(RunCase(c, evidenceRoot));
        }
        return results;
    }

    private static Result RunCase(JsonElement c, string root)
    {
        var lr = c.GetProperty("legacy_result");
        var r = new Result
        {
            Id = c.GetProperty("id").GetString()!,
            Title = c.GetProperty("title").GetString()!,
            LegacyVerdict = lr.GetProperty("verdict").GetString() ?? "",
        };
        var evidence = lr.TryGetProperty("evidence", out var ev) ? ev.EnumerateArray().Select(e => e.GetString()!).ToList() : [];
        string? full = evidence.Count == 0 ? null : SafeEvidenceDir(root, evidence[0]);
        if (full == null) { r.Verdict = "対象外"; r.Diffs.Add(evidence.Count == 0 ? "レガシー未実施（証跡なし）" : "証跡パスが証跡ルート外、またはリンクを含むため読み込まない"); return r; }
        if (!Directory.Exists(full)) { r.Verdict = "対象外"; r.Diffs.Add("レガシー未実施（証跡なし）"); return r; }
        string dir = full;
        try
        {
            using var db = new Db();
            db.LoadBaseline(c.GetProperty("baseline").GetString()!);
            var steps = c.GetProperty("runner").TryGetProperty("steps", out var st) ? st.EnumerateArray().ToList() : [];
            if (steps.Count == 0) { CheckSeed(r, db, dir); Finish(r); return r; }
            var before = db.Snapshot();
            var clock = LegacyClock(dir);
            var model = new StockScreenModel(db, () => clock);
            var screens = Directory.GetFiles(dir, "*-screen.txt").OrderBy(f => f, StringComparer.Ordinal).ToList();
            Screen? current = null;
            var pending = new Dictionary<string, object?>();
            for (int i = 0; i < steps.Count; i++)
            {
                if (steps[i].TryGetProperty("text", out var t))
                {
                    r.Steps++;
                    current = Step(model, current, t.GetString()!.TrimEnd('\r'), pending);
                }
                if (i >= screens.Count) continue;
                string? expected = LegacyTitle(File.ReadAllText(screens[i], Encoding.Latin1));
                string actual = current?.Title ?? "システムメニュー";
                r.ScreensCompared++;
                r.Screens.Add([Path.GetFileName(screens[i]), expected ?? "（見出しなし）", actual]);
                if (expected != null && expected != actual) { r.ScreensMatch = false; r.Diffs.Add($"画面 {Path.GetFileName(screens[i])}: レガシー「{expected}」/ 移行版「{actual}」"); }
                if (current != null) Audit(r, current, db);
            }
            CompareRecords(r, before, db.Snapshot(), dir);
            CompareReport(r, model.LastReport, dir);
        }
        catch (Exception e) { r.Diffs.Add("例外: " + e.GetType().Name + " " + e.Message); r.ScreensMatch = false; }
        Finish(r);
        return r;
    }

    private static void Finish(Result r) =>
        r.Verdict = r.ScreensMatch && r.RecordsMatch && r.ReportsMatch && r.Japanese && r.Diffs.Count == 0 ? "一致" : "不一致";

    private static DateTime LegacyClock(string dir)
    {
        var first = File.ReadLines(Path.Combine(dir, "terminal.cast")).First();
        using var h = JsonDocument.Parse(first);
        return DateTimeOffset.FromUnixTimeSeconds(h.RootElement.GetProperty("timestamp").GetInt64()).UtcDateTime;
    }

    /// <summary>端末入力 1 回分を画面モデルの操作へ変換する。</summary>
    private static Screen? Step(StockScreenModel model, Screen? current, string text, Dictionary<string, object?> pending)
    {
        switch (current)
        {
            case null:
                return text.Equals("D", StringComparison.OrdinalIgnoreCase) ? model.Start() : null;
            case MenuScreen menu:
                MenuItem? item = menu.Title == StockScreenModel.MainTitle
                    ? (text.Length == 1 && StockScreenModel.MainMenuKeys.TryGetValue(char.ToUpperInvariant(text[0]), out var id) ? menu.Items.FirstOrDefault(x => x.Id == id) : null)
                    : menu.Items.FirstOrDefault(x => x.Number is int n && n.ToString() == text);
                return item?.Open?.Invoke() ?? current;
            case FormScreen form:
                var next = form.Fields.FirstOrDefault(f => !pending.ContainsKey(f.Id));
                if (next == null) return current;
                if (pending.Count == 0 && text.Trim().Length == 0 && next is TextField) { pending.Clear(); return Submit(form, pending); }
                pending[next.Id] = next switch
                {
                    TextField => text,
                    DateField d => text.Trim().Length == 0 ? d.Value : DateTime.ParseExact(text.Trim(), "dd/MM/yyyy", null),
                    ChoiceField ch => text.Trim().Length == 0 ? ch.Value : text.Trim().ToUpperInvariant(),
                    _ => text,
                };
                return form.Fields.All(f => pending.ContainsKey(f.Id)) ? Submit(form, pending) : current;
            case ConfirmationScreen confirm:
                return text.Trim().Equals("Y", StringComparison.OrdinalIgnoreCase) ? confirm.Confirm() : confirm.Cancel();
            default:
                return current;
        }
    }

    private static Screen Submit(FormScreen form, Dictionary<string, object?> pending)
    {
        var values = form.Fields.ToDictionary(f => f.Id, f => pending.TryGetValue(f.Id, out var v) ? v : f switch
        {
            TextField t => t.Value,
            DateField d => d.Value,
            ChoiceField ch => ch.Value,
            _ => (object?)null,
        });
        pending.Clear();
        return form.Submit(new FormValues(values));
    }

    private static readonly Regex Ascii = new(@"[A-Za-z][A-Za-z0-9\-/]*");
    private static readonly Regex Word = new(@"[A-Za-z]{2,}");

    /// <summary>画面に出る文言から業務データ値を除き、2 文字以上の英字が残れば未翻訳とする。</summary>
    public static void Audit(Result r, Screen s, Db db)
    {
        var data = new HashSet<string>(StringComparer.Ordinal);
        foreach (var f in db.Snapshot().Values)
            foreach (var hex in f.Values)
                foreach (Match m in Ascii.Matches(Encoding.Latin1.GetString(Convert.FromHexString(hex)))) data.Add(m.Value);
        var texts = new List<string> { s.Title };
        switch (s)
        {
            case InformationScreen i: texts.Add(i.Message); break;
            case MenuScreen m: texts.AddRange(m.Items.Select(x => x.Caption)); break;
            case FormScreen f:
                texts.Add(f.SubmitLabel);
                foreach (var fld in f.Fields)
                {
                    texts.Add(fld.Label);
                    if (fld is ChoiceField ch) texts.AddRange(ch.Options.Select(o => o.Label));
                }
                break;
            case ConfirmationScreen c: texts.Add(c.Message); texts.Add(c.ConfirmLabel); break;
            case TableScreen t: texts.AddRange(t.Columns); texts.Add(t.EmptyMessage); break;
            case ReportScreen rep: texts.Add(rep.Body); break;
        }
        foreach (var text in texts)
            foreach (Match m in Ascii.Matches(text))
                if (!data.Contains(m.Value) && Word.IsMatch(m.Value) && !r.Untranslated.Contains(m.Value))
                {
                    r.Untranslated.Add(m.Value);
                    r.Japanese = false;
                }
    }

    private static (List<string> Unsupported, List<(string File, string Key, string Op, string? After)> Changes) LegacyDiff(string dir)
    {
        using var d = JsonDocument.Parse(File.ReadAllText(Path.Combine(dir, "record-diff.json")));
        var unsupported = d.RootElement.TryGetProperty("unsupported_files", out var u) ? u.EnumerateArray().Select(x => x.GetString()!).ToList() : [];
        var changes = d.RootElement.GetProperty("changes").EnumerateArray().Select(c => (
            c.GetProperty("file").GetString()!, c.GetProperty("key").GetString()!, c.GetProperty("operation").GetString()!,
            c.TryGetProperty("after", out var a) && a.ValueKind == JsonValueKind.Object && a.TryGetProperty("hex", out var h) ? h.GetString() : null)).ToList();
        return (unsupported, changes);
    }

    private static void CompareRecords(Result r, SortedDictionary<string, SortedDictionary<string, string>> before,
        SortedDictionary<string, SortedDictionary<string, string>> after, string dir)
    {
        var (unsupported, legacy) = LegacyDiff(dir);
        var ours = new List<(string File, string Key, string Op, string? After)>();
        foreach (var file in before.Keys.Union(after.Keys).Where(f => !unsupported.Contains(f)))
        {
            var b = before.GetValueOrDefault(file) ?? new(StringComparer.Ordinal);
            var a = after.GetValueOrDefault(file) ?? new(StringComparer.Ordinal);
            foreach (var k in b.Keys.Union(a.Keys))
            {
                bool hb = b.TryGetValue(k, out var vb), ha = a.TryGetValue(k, out var va);
                if (hb && ha && vb == va) continue;
                ours.Add((file, k, !hb ? "追加" : !ha ? "削除" : "変更", ha ? va : null));
            }
        }
        string Key((string File, string Key, string Op, string? After) x) => $"{x.File}|{x.Key}|{x.Op}|{x.After?.ToLowerInvariant()}";
        var ls = legacy.Select(Key).ToHashSet();
        var os = ours.Select(Key).ToHashSet();
        foreach (var x in ls.Except(os)) { r.RecordsMatch = false; r.Diffs.Add("レコード（レガシーのみ）: " + x); }
        foreach (var x in os.Except(ls)) { r.RecordsMatch = false; r.Diffs.Add("レコード（移行版のみ）: " + x); }
    }

    private static List<string> Normalize(IEnumerable<string> lines)
    {
        var l = lines.Select(x => Regex.Replace(x.Replace("\r", "").Replace("\f", "").TrimEnd(), @"\d\d:\d\d$", "HH:MM")).ToList();
        while (l.Count > 0 && l[^1].Length == 0) l.RemoveAt(l.Count - 1);
        return l;
    }

    private static string? Sha(string json, string file)
    {
        using var d = JsonDocument.Parse(json);
        var root = d.RootElement.TryGetProperty("after", out var a) ? a : d.RootElement;
        return root.TryGetProperty(file, out var f) && f.TryGetProperty("sha256", out var s) ? s.GetString() : null;
    }

    private static void CompareReport(Result r, StockReport? report, string dir)
    {
        const string prt = "ledgers/acas/prt-1";
        string path = Path.Combine(dir, "files", "ledgers", "acas", "prt-1");
        bool printed = File.Exists(path) && new FileInfo(path).Length > 0
            && Sha(File.ReadAllText(Path.Combine(dir, "before.json")), prt) != Sha(File.ReadAllText(Path.Combine(dir, "result.json")), prt);
        if (!printed)
        {
            if (report != null) { r.ReportsMatch = false; r.Diffs.Add("帳票: レガシーは出力なし / 移行版は「" + report.Title + "」を出力"); }
            return;
        }
        if (report == null) { r.ReportsMatch = false; r.Diffs.Add("帳票: レガシーは prt-1 を出力 / 移行版は出力なし"); return; }
        var exp = Normalize(File.ReadAllText(path, Encoding.Latin1).Split('\n'));
        var act = Normalize(report.Legacy);
        for (int i = 0; i < Math.Max(exp.Count, act.Count); i++)
        {
            string e = i < exp.Count ? exp[i] : "（なし）", a = i < act.Count ? act[i] : "（なし）";
            if (e == a) continue;
            r.ReportsMatch = false;
            r.Diffs.Add($"帳票 {i + 1} 行目: レガシー「{e}」/ 移行版「{a}」");
            if (r.Diffs.Count > 20) break;
        }
    }

    /// <summary>ST-090: 業務用マスタ投入（SYS-001 内）の在庫レコードが同梱初期データと一致するか。</summary>
    private static void CheckSeed(Result r, Db db, string dir)
    {
        var (_, legacy) = LegacyDiff(dir);
        var stock = db.Snapshot().GetValueOrDefault(StockService.StockFile) ?? new(StringComparer.Ordinal);
        foreach (var c in legacy.Where(x => x.File == StockService.StockFile))
            if (!stock.TryGetValue(c.Key, out var hex) || hex != c.After?.ToLowerInvariant())
            { r.RecordsMatch = false; r.Diffs.Add("初期在庫レコード不一致: " + c.Key); }
        r.Screens.Add(["（画面操作なし）", "業務用マスタ投入", "同梱初期データ biz"]);
    }
}
