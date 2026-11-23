using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Acas.Verify;

namespace Acas.UiDriver;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        try
        {
            if (args is ["--audit-xaml", var source, "--out", var staticOutput])
                return JapaneseAudit.Write(staticOutput, JapaneseAudit.Xaml(source));
            if (args is ["--audit-ui", var auditApp, "--out", var runtimeOutput])
            {
                using var desktop = new Desktop(auditApp, audit: true);
                return JapaneseAudit.Write(runtimeOutput, JapaneseAudit.Runtime(desktop));
            }
            var options = RunOptions.Parse(args, "--app");
            if (options.Extra is not { } app) throw new ArgumentException("検証するアプリを指定してください。");
            var scenarios = options.Scenarios();
            var ui = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var text = new TextBlock { FontSize = 18, Foreground = Brushes.White, TextWrapping = TextWrapping.Wrap };
            var overlay = new Window
            {
                Title = "同一性検証", WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize,
                Width = 630, SizeToContent = SizeToContent.Height, Topmost = true, ShowActivated = false,
                ShowInTaskbar = false, Left = SystemParameters.WorkArea.Left + 15, Top = SystemParameters.WorkArea.Top + 8,
                Content = new Border { Background = new SolidColorBrush(Color.FromRgb(23, 43, 69)),
                    Padding = new Thickness(14, 8, 14, 8), Child = text }
            };
            var stopwatch = Stopwatch.StartNew();
            ui.Startup += async (_, _) =>
            {
                try
                {
                    var results = await Task.Run(() => Run(app, options, scenarios, stopwatch,
                        label => overlay.Dispatcher.Invoke(() => text.Text = label),
                        bounds => overlay.Dispatcher.Invoke(() =>
                        {
                            var dpi = VisualTreeHelper.GetDpi(overlay);
                            overlay.Left = bounds.Right / dpi.DpiScaleX - overlay.Width - 24;
                            overlay.Top = bounds.Top / dpi.DpiScaleY + 38;
                        })));
                    Outcome.Write(options.Output, results);
                    ui.Shutdown(results.All(r => r.Verdict is "一致" or "対象外") ? 0 : 1);
                }
                catch (Exception e)
                {
                    Console.Error.WriteLine(e.Message);
                    ui.Shutdown(2);
                }
            };
            return ui.Run(overlay);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e.Message);
            Console.Error.WriteLine("使い方：Acas.UiDriver <台帳> <証跡ルート> --app <Acas.App.exe> --out <結果> [--group <①〜⑤>] [--case <ケース識別子>]");
            return 2;
        }
    }

    private static IReadOnlyList<Outcome> Run(string app, RunOptions options, IReadOnlyList<Scenario> scenarios,
        Stopwatch clock, Action<string> show, Action<System.Drawing.Rectangle> position)
    {
        using var desktop = scenarios.Any(s => s.Group == 5 && !s.Excluded) ? new Desktop(app) : null;
        if (desktop is not null)
        {
            var bounds = desktop.PrepareRecording();
            position(bounds);
            Console.WriteLine($"アプリの画面範囲：左 {bounds.Left}、上 {bounds.Top}、幅 {bounds.Width}、高さ {bounds.Height}");
        }
        var outcomes = new List<Outcome>();
        foreach (var scenario in scenarios)
        {
            Desktop? accounting = null;
            try
            {
                string title = $"{scenario.Id}　{scenario.Title}";
                double elapsed = clock.Elapsed.TotalSeconds;
                show($"{title}\n検証中");
                Outcome outcome;
                if (scenario.Excluded) outcome = Outcome.Exclude(scenario);
                else
                {
                    try
                    {
                        if (scenario.Group == 1 && GroupOnePlan.For(scenario) is { } plan)
                        {
                            accounting = new Desktop(app, baseline: scenario.Baseline);
                            position(accounting.PrepareRecording());
                            outcome = accounting.RunGroupOne(scenario, options.Evidence, plan);
                        }
                        else if (scenario.Group == 5)
                        {
                            var (first, second, id) = scenario.CalcInput();
                            string actual = desktop!.Calculate(id, first, second);
                            string legacy = scenario.ExpectedLine(options.Evidence);
                            string expected = ExpectedCalculationText(scenario.Driver!, legacy);
                            outcome = Outcome.Compare(scenario, actual == expected, actual,
                                $"旧証跡：「{legacy}」／期待表示：「{expected}」／新：「{actual}」", "実画面");
                        }
                        else outcome = Outcome.Missing(scenario, "このケースのネイティブ画面操作は未登録です。");
                    }
                    catch (Exception e)
                    {
                        outcome = Outcome.Compare(scenario, false, "", e.Message, "実画面");
                    }
                }
                outcomes.Add(outcome with { VideoSeconds = elapsed });
                show($"{title}\n{outcome.Verdict}");
                Console.WriteLine($"{scenario.Id}　{outcome.Verdict}　{outcome.Reason}");
                Thread.Sleep(500);
            }
            finally
            {
                accounting?.Dispose();
            }
        }
        return outcomes;
    }

    private static string ExpectedCalculationText(string driver, string legacy)
    {
        if (driver == "drv09")
        {
            string[] codeResult = legacy[6..].Split(' ', StringSplitOptions.RemoveEmptyEntries);
            return $"検査数字＝{codeResult[0]}　判定：{(codeResult[1] == "Y" ? "有効" : "無効")}";
        }
        if (driver == "drv04")
        {
            // The original ten-character input can itself contain the delimiter.
            string[] dateResult = legacy[11..].Split('|', 2, StringSplitOptions.TrimEntries);
            return dateResult[0] == "0" ? "日付不正（通算日＝0）" :
                $"日付有効　通算日＝{dateResult[0]}　正規化＝{dateResult[1]}";
        }
        string result = legacy[(legacy.LastIndexOf('|') + 1)..].Trim();
        var invariant = CultureInfo.InvariantCulture;
        return driver switch
        {
            "drvvat" => $"消費税額＝{decimal.Parse(result, invariant).ToString("0.00", invariant)}",
            "drvage" => $"経過日数区分＝{int.Parse(result, invariant).ToString(invariant)}日",
            "drvavg" => $"平均原価＝{result}",
            _ => throw new InvalidDataException("対応する計算ドライバがありません。")
        };
    }
}
