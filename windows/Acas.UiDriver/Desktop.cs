using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Irs;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;
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

    public Desktop(string executable, bool audit = false, string? baseline = null, string? irsDirectory = null,
        Action<Db>? prepare = null)
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
                    if (audit) SeedAudit(db, AuditFile("取込.txt"));
                    else db.LoadBaseline(baseline!);
                    prepare?.Invoke(db);
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

    private static void SeedAudit(Db db, string importFile)
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
        using var fixture = new Db();
        var accounts = new IrsBookkeeping(fixture);
        accounts.SaveAccount(10001, 0, "監査用勘定", "A", amend: false);
        File.WriteAllBytes(importFile, accounts.ExportAccounts(csv: false));
    }

    internal string AuditFile(string filename) => Path.Combine(_folder, filename);

    internal Window FileDialog(string title) => Wait(() =>
        Window.FindFirstDescendant(c => c.ByClassName("#32770").And(c.ByName(title)))?.AsWindow(), title);

    internal static void SelectDialogFile(Window dialog, string path, bool save)
    {
        const uint setWindowText = 0x000C, getWindowText = 0x000D, abortIfHung = 0x0002;
        var filename = dialog.FindFirstDescendant(c =>
            c.ByClassName("Edit").And(c.ByAutomationId(save ? "1001" : "1148")))
            ?? throw new InvalidOperationException("ファイル名の入力欄が見つかりません。");
        IntPtr handle = filename.Properties.NativeWindowHandle.Value;
        if (save)
        {
            filename.Click();
            Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_A);
            Keyboard.Type(path);
            var entered = new StringBuilder(path.Length + 1);
            if (SendMessageTimeout(handle, getWindowText, new IntPtr(entered.Capacity), entered,
                    abortIfHung, 2000, out _) == IntPtr.Zero || entered.ToString() != path)
                throw new InvalidOperationException("監査用の保存先を入力できませんでした。");
            Keyboard.Press(VirtualKeyShort.RETURN);
            return;
        }
        if (SendMessageTimeout(handle, setWindowText, IntPtr.Zero, path,
                abortIfHung, 2000, out var setText) == IntPtr.Zero || setText == IntPtr.Zero)
            throw new InvalidOperationException("ファイル名を設定できませんでした。");
        ClickNativeDialogButton(dialog, "1");
    }

    internal static void ClickNativeDialogButton(Window dialog, string id)
    {
        const uint buttonClick = 0x00F5;
        var button = dialog.FindFirstDescendant(c => c.ByAutomationId(id).And(c.ByClassName("Button")));
        if (button is null || !PostMessage(button.Properties.NativeWindowHandle.Value, buttonClick, IntPtr.Zero, IntPtr.Zero))
            throw new InvalidOperationException("ファイル選択画面のボタンを操作できませんでした。");
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, string lParam,
        uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wParam, StringBuilder lParam,
        uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

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

    public System.Drawing.Rectangle PrepareRecording(bool topmost = false)
    {
        Window.Patterns.Window.Pattern.SetWindowVisualState(WindowVisualState.Maximized);
        var window = Wait(() => Window.Patterns.Window.Pattern.WindowVisualState.Value == WindowVisualState.Maximized
            ? Window : null, "最大化したアプリの画面範囲");
        if (topmost) KeepAbove(_process.MainWindowHandle, activate: true);
        return window.BoundingRectangle;
    }

    public static void KeepAbove(IntPtr handle, bool activate)
    {
        const uint noSize = 0x0001, noMove = 0x0002, noActivate = 0x0010, showWindow = 0x0040;
        if (!SetWindowPos(handle, new IntPtr(-1), 0, 0, 0, 0, noSize | noMove | showWindow | (activate ? 0 : noActivate)))
            throw new InvalidOperationException("ウィンドウを最前面に移動できません。");
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

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
