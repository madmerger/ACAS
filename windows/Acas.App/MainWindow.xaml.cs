using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using Acas.Core.Engine;
using Acas.Core.Programs;

namespace Acas.App;

public sealed class CaseRow : INotifyPropertyChanged
{
    public string Id { get; init; } = "";
    public string Title { get; init; } = "";
    public string Subsystem { get; init; } = "";
    public JsonElement Json;
    private string _verdict = "";
    public string Verdict { get => _verdict; set { _verdict = value; PropertyChanged?.Invoke(this, new(nameof(Verdict))); } }
    public object? Result;
    public event PropertyChangedEventHandler? PropertyChanged;
}

public partial class MainWindow : Window
{
    private readonly string _dbFile;
    private Db _db;
    private Ctx? _ctx;                       // 画面に表示中の実行コンテキスト
    private Task? _program;
    private JsonDocument? _ledger;
    private readonly List<CaseRow> _all = new();
    private readonly ObservableCollection<CaseRow> _shown = new();
    private CancellationTokenSource? _play;

    public MainWindow()
    {
        InitializeComponent();
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AcasJa");
        Directory.CreateDirectory(dir);
        _dbFile = Path.Combine(dir, "acas.db");
        bool fresh = !File.Exists(_dbFile);
        _db = new Db(_dbFile);
        if (fresh) _db.LoadBaseline("biz");
        DbPath.Text = _dbFile;
        foreach (var b in new[] { "biz", "company", "empty", "irs-biz", "sl-ready", "sl-invoice", "sl-printed", "pl-invoice" }) Baselines.Items.Add(b);
        Baselines.SelectedIndex = 0;
        Cases.ItemsSource = _shown;
        Terms.ItemsSource = I18n.Table.OrderBy(k => k.Key, StringComparer.Ordinal).ToList();
        Term.Crt = new Crt();
        PreviewTextInput += OnText;
        PreviewKeyDown += OnKey;
        Loaded += OnLoaded;
    }

    private static string? Arg(string name)
    {
        int i = Array.IndexOf(App.Args, name);
        return i >= 0 && i + 1 < App.Args.Length ? App.Args[i + 1] : null;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        var ev = Arg("--evidence") ?? Environment.GetEnvironmentVariable("ACAS_EVIDENCE");
        if (ev == null)
            foreach (var cand in new[] { Path.Combine(AppContext.BaseDirectory, "evidence"), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "work", "evidence") })
                if (File.Exists(Path.Combine(cand, "入力", "シナリオ台帳.json"))) { ev = cand; break; }
        if (ev != null) LoadEvidence(ev);
        if (Arg("--delay") is { } d) Delay.Text = d;
        if (Arg("--play") is { } play)
        {
            Tabs.SelectedIndex = 1;
            Filter.Text = play;
            await PlayRows(_shown.ToList());
            if (Arg("--out") is { } o) WriteResults(o);
            if (App.Args.Contains("--exit")) Close();
        }
        else StartAcas(this, new RoutedEventArgs());
    }

    // ---- 業務 (ローカル DB 上で対話実行) ----
    private void Start(bool irs)
    {
        _play?.Cancel();
        var ctx = new Ctx(_db);
        _ctx = ctx; Term.Crt = ctx.Crt;
        Caption.Text = irs ? "IRS 簡易会計" : "ACAS 会計システム"; Verdict.Text = "";
        Status.Text = "業務実行中";
        _program = Task.Run(async () =>
        {
            try { if (irs) await Launcher.RunIrs(ctx); else await Launcher.RunAcas(ctx); }
            catch (Exception ex) when (ex is not StopRun and not Halt) { Dispatcher.Invoke(() => Status.Text = "エラー: " + ex.Message); return; }
            Dispatcher.Invoke(() => { if (_ctx == ctx) Status.Text = "業務を終了しました。「ACAS を起動」で再開できます。"; RefreshReports(this, new RoutedEventArgs()); });
        });
        Term.Focus();
    }
    private void StartAcas(object s, RoutedEventArgs e) => Start(false);
    private void StartIrs(object s, RoutedEventArgs e) => Start(true);
    private void StopProgram(object s, RoutedEventArgs e)
    {
        _play?.Cancel();
        _ctx = null; Term.Crt = new Crt();
        Status.Text = "中断しました";
    }
    private void LoadBaseline(object s, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "ローカルデータベースの内容を全て消去し、初期データ「" + Baselines.SelectedItem + "」を読み込みます。よろしいですか?", "初期データ読込", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
        StopProgram(s, e);
        _db.LoadBaseline((string)Baselines.SelectedItem);
        Status.Text = "初期データを読み込みました: " + Baselines.SelectedItem;
    }

    // ---- キー入力 ----
    private void FocusTerminal(object s, MouseButtonEventArgs e) => Term.Focus();
    private bool TermActive => _ctx != null && Term.IsKeyboardFocusWithin;
    private void OnText(object s, TextCompositionEventArgs e)
    {
        if (!TermActive) return;
        foreach (var ch in e.Text) if (ch >= ' ') _ctx!.Crt.Keys.Post(new Acas.Core.Engine.Key(K.Char, ch));
        e.Handled = true;
    }
    private void OnKey(object s, KeyEventArgs e)
    {
        if (!TermActive) return;
        K? k = e.Key switch
        {
            System.Windows.Input.Key.Enter => K.Enter, System.Windows.Input.Key.Escape => K.Esc,
            System.Windows.Input.Key.Tab => (Keyboard.Modifiers & ModifierKeys.Shift) != 0 ? K.BackTab : K.Tab,
            System.Windows.Input.Key.Up => K.Up, System.Windows.Input.Key.Down => K.Down, System.Windows.Input.Key.Left => K.Left, System.Windows.Input.Key.Right => K.Right,
            System.Windows.Input.Key.Home => K.Home, System.Windows.Input.Key.End => K.End, System.Windows.Input.Key.Back => K.Backspace, System.Windows.Input.Key.Delete => K.Delete,
            System.Windows.Input.Key.PageUp => K.PgUp, System.Windows.Input.Key.PageDown => K.PgDn,
            >= System.Windows.Input.Key.F1 and <= System.Windows.Input.Key.F12 => K.F1 + (e.Key - System.Windows.Input.Key.F1),
            _ => null,
        };
        if (k == null) return;
        _ctx!.Crt.Keys.Post(new Acas.Core.Engine.Key(k.Value));
        e.Handled = true;
    }
}
