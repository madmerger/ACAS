using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Acas.Core.Engine;
using Acas.Core.Programs;

namespace Acas.App;

public partial class MainWindow
{
    private string _evidence = "";

    // ---- 同一性テスト (レガシー証跡のシナリオを実画面で再生し比較) ----
    private void LoadEvidence(string dir)
    {
        var ledger = Path.Combine(dir, "入力", "シナリオ台帳.json");
        if (!File.Exists(ledger)) { Status.Text = "シナリオ台帳が見つかりません: " + ledger; return; }
        _evidence = dir; EvidenceDir.Text = dir;
        _ledger = JsonDocument.Parse(File.ReadAllText(ledger));
        _all.Clear();
        foreach (var c in _ledger.RootElement.GetProperty("cases").EnumerateArray())
            _all.Add(new CaseRow { Id = c.GetProperty("id").GetString()!, Title = c.GetProperty("title").GetString()!, Subsystem = c.GetProperty("subsystem").GetString()!, Json = c });
        FilterChanged(this, null!);
        Status.Text = $"シナリオ {_all.Count} 件を読み込みました";
    }

    private void BrowseEvidence(object s, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.OpenFileDialog { Title = "シナリオ台帳.json を選択", Filter = "シナリオ台帳|*.json" };
        if (dlg.ShowDialog(this) == true) LoadEvidence(Path.GetDirectoryName(Path.GetDirectoryName(dlg.FileName)!)!);
    }

    private void FilterChanged(object s, TextChangedEventArgs e)
    {
        var fs = Filter.Text.Split(new[] { ',', ' ' }, StringSplitOptions.RemoveEmptyEntries);
        _shown.Clear();
        foreach (var r in _all)
            if (fs.Length == 0 || fs.Any(f => r.Id.StartsWith(f, StringComparison.OrdinalIgnoreCase))) _shown.Add(r);
    }

    private async void PlaySelected(object s, RoutedEventArgs e) => await PlayRows(Cases.SelectedItems.Cast<CaseRow>().ToList());
    private async void PlayAll(object s, RoutedEventArgs e) => await PlayRows(_shown.ToList());
    private void CancelPlay(object s, RoutedEventArgs e) => _play?.Cancel();

    private async Task PlayRows(List<CaseRow> rows)
    {
        if (rows.Count == 0) return;
        _play?.Cancel();
        var cts = _play = new CancellationTokenSource();
        int.TryParse(Delay.Text, out int delay); delay = Math.Clamp(delay, 0, 5000);
        foreach (var row in rows)
        {
            if (cts.IsCancellationRequested) break;
            Cases.SelectedItem = row; Cases.ScrollIntoView(row);
            Caption.Text = row.Id + "  " + row.Title; Verdict.Text = "実行中"; Verdict.Foreground = System.Windows.Media.Brushes.White;
            Status.Text = "再生中: " + row.Id;
            try { await PlayOne(row, delay, cts.Token); }
            catch (OperationCanceledException) { row.Verdict = ""; Verdict.Text = "中止"; break; }
            Verdict.Text = row.Verdict;
            Verdict.Foreground = row.Verdict == "一致" ? System.Windows.Media.Brushes.LightGreen : row.Verdict == "不一致" ? System.Windows.Media.Brushes.Salmon : System.Windows.Media.Brushes.Khaki;
            UpdateSummary();
            if (delay > 0) await Task.Delay(Math.Max(600, delay * 6));
        }
        Status.Text = "再生終了";
        RefreshReports(this, new RoutedEventArgs());
    }

    private async Task PlayOne(CaseRow row, int delay, CancellationToken ct)
    {
        var ctx = new Ctx(new Db());           // 再生はメモリ DB 上で行い、業務用ローカル DB を汚さない
        _ctx = ctx; Term.Crt = ctx.Crt;
        var c = row.Json; var root = _evidence;
        if (row.Subsystem == "CALC")
        {
            var calc = Calc.Run(c);
            var t = ctx.Crt;
            t.V("計算ロジック検証", 0201, fg: 6);
            t.V("入力    : " + c.GetProperty("input_data").GetRawText(), 0501);
            if (calc == null)
            {
                t.V("判定    : 対象外 (レガシー未実施のため比較対象なし)", 0901, fg: 6);
                row.Verdict = "対象外";
                row.Result = new { id = row.Id, match = (bool?)null, verdict = "対象外", result = "", reason = "レガシー側未実施 (HTTP/ブラウザ専用の期待で端末版に判定面が無い) のため比較対象なし" };
            }
            else
            {
                var legacy = Calc.LegacyLine(c, root);
                bool same = legacy != null && legacy == calc.Value.Line;
                t.V("移行後  : " + calc.Value.Summary, 0701, fg: 7);
                t.V("出力行  : " + calc.Value.Line.Trim(), 0901);
                t.V("レガシー: " + (legacy ?? "(証跡なし)").Trim(), 1101);
                t.V("判定    : " + (same ? "一致" : "不一致"), 1301, fg: same ? 2 : 4);
                row.Verdict = same ? "一致" : "不一致";
                row.Result = new { id = row.Id, match = (bool?)same, verdict = row.Verdict, result = calc.Value.Summary, reason = same ? "" : $"旧[{legacy}] 新[{calc.Value.Line}]" };
            }
            Term.Refresh();
            if (delay > 0) await Task.Delay(Math.Max(400, delay * 3), ct);
            return;
        }
        CaseResult r;
        try
        {
            r = await Task.Run(() => CaseRunner.Run(c, root, ctx, async i =>
            {
                ct.ThrowIfCancellationRequested();
                if (delay > 0) await Task.Delay(i < 0 ? delay : delay * 4, ct).ConfigureAwait(false);
            }), ct);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex) { r = new CaseResult { Id = row.Id, Error = ex.ToString() }; }
        row.Verdict = r.Match ? "一致" : "不一致";
        row.Result = new { id = row.Id, match = (bool?)r.Match, verdict = row.Verdict, screens = r.ScreensMatch, records = r.RecordsMatch, reports = r.ReportsMatch, japanese = r.Japanese, diffs = r.Diffs, untranslated = r.Untranslated, error = r.Error?.Split('\n')[0] };
        Term.Refresh();
    }

    private void UpdateSummary() =>
        Summary.Text = $"一致 {_all.Count(r => r.Verdict == "一致")} / 不一致 {_all.Count(r => r.Verdict == "不一致")} / 対象外 {_all.Count(r => r.Verdict == "対象外")}";

    private void WriteResults(string path) =>
        File.WriteAllText(path, JsonSerializer.Serialize(_all.Where(r => r.Result != null).Select(r => r.Result), new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));

    private void SaveResults(object s, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.SaveFileDialog { FileName = "同一性テスト結果.json", Filter = "JSON|*.json" };
        if (dlg.ShowDialog(this) == true) { WriteResults(dlg.FileName); Status.Text = "保存しました: " + dlg.FileName; }
    }

    // ---- 計算 ----
    private void DoCalc(object s, RoutedEventArgs e)
    {
        var p = CalcIn.Text.Split(',').Select(x => x.Trim()).ToArray();
        try
        {
            CalcOut.Text = CalcKind.SelectedIndex switch
            {
                0 => Calc.Maps09(p[0].ToUpperInvariant()) is { } cd ? $"チェックディジット = {cd}" : "コード不正 (使用できない文字)",
                1 => Common.Maps04(CalcIn.Text.Trim()) is var b && b != 0 ? $"有効な日付です (通算日 {b})" : "日付不正",
                2 => $"VAT 額 = {decimal.Parse(Calc.LineVat(p[0], p[1]).Split('|')[1], System.Globalization.CultureInfo.InvariantCulture):0.00}",
                3 => $"年齢区分 = {Calc.AgeBucket(int.Parse(p[0]))} 日",
                _ => $"平均原価 = {Calc.LineAvg(p[0], p[1]).Split('|')[1].Trim()}",
            };
        }
        catch (Exception) { CalcOut.Text = "入力値が不正です"; }
    }

    // ---- 帳票 ----
    private List<(string Name, string Body)> _reports = new();
    private void RefreshReports(object s, RoutedEventArgs e)
    {
        _reports = new();
        if (_ctx != null) foreach (var (n, l) in _ctx.Reports) _reports.Add(("[今回] " + Path.GetFileName(n), string.Join("\n", l)));
        foreach (var sp in _db.Spool().AsEnumerable().Reverse().Take(50)) _reports.Add(($"[保存 #{sp.Id}] {Path.GetFileName(sp.Name)} {sp.Created[..19]}", sp.Body));
        ReportList.ItemsSource = _reports.Select(r => r.Name).ToList();
        if (_reports.Count > 0) ReportList.SelectedIndex = 0; else ReportBody.Text = "(帳票はありません)";
    }
    private void ReportSelected(object s, SelectionChangedEventArgs e)
    {
        if (ReportList.SelectedIndex >= 0 && ReportList.SelectedIndex < _reports.Count) ReportBody.Text = _reports[ReportList.SelectedIndex].Body.Replace("\f", "\n――――― 改ページ ―――――\n");
    }
}
