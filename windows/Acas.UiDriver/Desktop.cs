using System.Diagnostics;
using System.IO;
using Acas.Core;
using Acas.Core.Engine;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.UIA3;
using Microsoft.Data.Sqlite;

namespace Acas.UiDriver;

internal sealed partial class Desktop : IDisposable
{
    private readonly UIA3Automation _automation = new();
    private readonly Process _process;
    private readonly string _folder;
    private readonly string _databasePath;
    public Window Window { get; }

    public Desktop(string executable, bool audit = false, string? baseline = null, string? irsDirectory = null)
    {
        if (!File.Exists(executable)) throw new FileNotFoundException("アプリが見つかりません。", executable);
        _folder = Directory.CreateTempSubdirectory("acas-ui-").FullName;
        try
        {
            _databasePath = LocalDatabasePath.Resolve(Path.Combine(_folder, "ui.db"));
            if (audit || baseline is not null)
            {
                using (var db = new Db(_databasePath))
                {
                    if (audit) SeedAudit(db);
                    else db.LoadBaseline(baseline!);
                }
                SqliteConnection.ClearAllPools();
            }
            var start = new ProcessStartInfo(Path.GetFullPath(executable)) { UseShellExecute = false };
            start.ArgumentList.Add("--database");
            start.ArgumentList.Add(_databasePath);
            if (irsDirectory != null) start.Environment["ACAS_IRS"] = irsDirectory;
            _process = Process.Start(start) ?? throw new InvalidOperationException("アプリを起動できません。");
            Window = Wait(() =>
            {
                _process.Refresh();
                return _process.MainWindowHandle == IntPtr.Zero ? null : _automation.FromHandle(_process.MainWindowHandle).AsWindow();
            }, "アプリのウィンドウ");
            Window.Focus();
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    private static void SeedAudit(Db db)
    {
        db.LoadBaseline("biz");
        var settings = new SystemSettings(db);
        var system = settings.Read()!;
        foreach (string field in new[] { "Usera", "Address-1", "Address-2", "Address-3", "Address-4",
            "Post-Code", "Country", "VAT-Reg-Number", "Print-Spool-Name", "Print-Spool-Name2", "Print-Spool-Name3" })
            system.Set(field, "123");
        system.Set("Arch", "Y");
        db.Rewrite(SystemSettings.SystemFile, "00000001", system.B);
        foreach (var (key, data) in db.Scan(GeneralLedger.LedgerFile))
        {
            var record = Layouts.Ledger.From(data);
            record.Set("name", key);
            db.Put(GeneralLedger.LedgerFile, key, record.B);
        }
        var journal = new JournalEntry(db);
        journal.Open();
        var date = SystemSettings.Date(system, "Run-Date") ?? new DateTime(2025, 4, 1);
        var header = new JournalHeader(system.I("Next-Batch"), new(33, 3000m, "", "N"),
            0, true, date, system.I("Cyclea"), 1, 100m, 0m, "1");
        var status = journal.Save(header, [new(date, new(4000, 0), 100m, "2")]);
        if (status != JournalError.None)
            throw new InvalidOperationException($"監査用の仕訳を作成できません（{(int)status}）。");
        db.AddSpool("検証帳票", "日本語表示を確認する検証帳票");
    }

    public string Calculate(string id, string first, string second)
    {
        if (Window.FindFirstDescendant(c => c.ByAutomationId("ScreenMenuBack")) is { } back && !back.IsOffscreen)
            back.AsButton().Invoke();
        if (Window.FindFirstDescendant(c => c.ByAutomationId(id)) is null)
            Find("MenuCalculations").AsTreeItem().Select();
        SelectAction(id);
        Find("CalcFirst").AsTextBox().Text = first;
        if (Window.FindFirstDescendant(c => c.ByAutomationId("CalcSecond")) is { } field)
            field.AsTextBox().Text = second;
        Find("FormSubmit").AsButton().Invoke();
        return Find("ScreenMessage").Name;
    }

    public void SelectAction(string id)
    {
        Find(id).AsListBoxItem().Select();
        Find("ScreenMenuOpen").AsButton().Invoke();
    }

    public AutomationElement Find(string id) => Wait(() => Window.FindFirstDescendant(c => c.ByAutomationId(id)), id);

    public Window? Confirmation() =>
        (_automation.GetDesktop().FindFirstChild(c => c.ByProcessId(_process.Id).And(c.ByAutomationId("Confirmation"))) ??
         Window.FindFirstDescendant(c => c.ByAutomationId("Confirmation")))?.AsWindow();

    public System.Drawing.Rectangle PrepareRecording()
    {
        Window.Patterns.Window.Pattern.SetWindowVisualState(WindowVisualState.Maximized);
        return Wait(() => Window.Patterns.Window.Pattern.WindowVisualState.Value == WindowVisualState.Maximized
            ? Window : null, "最大化したアプリの画面範囲").BoundingRectangle;
    }

    public void OpenTree(string id)
    {
        var item = Find(id).AsTreeItem();
        if (item.IsSelected)
            Find(id == "MenuReports" ? "MenuCalculations" : "MenuReports").AsTreeItem().Select();
        item.Select();
    }

    internal static T Wait<T>(Func<T?> find, string name) where T : class
    {
        var timer = Stopwatch.StartNew();
        do
        {
            if (find() is { } result) return result;
            Thread.Sleep(40);
        } while (timer.Elapsed < TimeSpan.FromSeconds(5));
        throw new InvalidOperationException($"画面要素が見つかりません：{name}");
    }

    public void Dispose()
    {
        try
        {
            if (_process is not null && !_process.HasExited)
            {
                _process.CloseMainWindow();
                if (!_process.WaitForExit(3000))
                {
                    _process.Kill();
                    _process.WaitForExit();
                }
            }
        }
        finally
        {
            _process?.Dispose();
            _automation.Dispose();
            SqliteConnection.ClearAllPools();
            Directory.Delete(_folder, true);
        }
    }
}
