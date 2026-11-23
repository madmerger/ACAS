using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using Acas.Core.Engine;
using Acas.Core.Programs.Stock;
using Acas.Verify;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace Acas.UiDriver;

internal sealed partial class Desktop
{
    private static readonly (string Id, string Title, string Surface)[] StockMaintenance =
    [
        ("StockItemCreate", "在庫品目登録", "FormSubmit"),
        ("StockItemAmend", "在庫品目マスター管理", "ScreenMessage"),
        ("StockItemDelete", "在庫品目削除", "FormSubmit"),
        ("StockItemRenumber", "在庫品目マスター管理", "FormSubmit"),
        ("StockItemDisplay", "在庫品目照会", "StockItemList"),
        ("StockItemPrint", "在庫品目マスター管理", "ScreenMessage"),
    ];
    private static readonly (string Id, string Title, string Surface)[] StockMovements =
    [
        ("StockAdditions", "在庫入庫入力", "StockMovementNumber"),
        ("StockDeductions", "在庫出庫入力", "StockMovementNumber"),
        ("StockBarcodeAdditions", "バーコード入庫入力", "StockMovementNumber"),
        ("StockOrders", "在庫月末処理", "StockOrderNumber"),
        ("StockAuditReports", "在庫入出庫メニュー", "ConfirmationMessage"),
    ];
    private static readonly (string Id, string Title)[] StockReports =
    [
        ("StockValuationReport", "在庫評価表"), ("StockActivityReport", "在庫受払表"),
        ("StockReorderReport", "発注点割れ一覧表"), ("StockHistoryReport", "在庫履歴表"),
        ("StockListReport", "在庫一覧表"),
    ];
    private static readonly (string Id, string Title, string Surface)[] IrsMain =
    [
        ("IrsConfigurationMenu", "システム設定・保守", "IrsRunDate"),
        ("IrsAccountsMenu", "勘定科目表", "ScreenMenuOpen"),
        ("IrsDefaultsMenu", "既定勘定", "ScreenMenuOpen"),
        ("IrsPostingMenu", "仕訳転記", "IrsPostingMode"),
        ("IrsTrialBalanceMenu", "試算表", "FormSubmit"),
        ("IrsAuditMenu", "監査証跡", "FormSubmit"),
        ("IrsFinalMenu", "決算書作成", "FormSubmit"),
        ("IrsAmendmentMenu", "簡易記帳", "ScreenMenuOpen"),
        ("IrsAnalysisMenu", "簡易記帳", "ScreenMenuOpen"),
        ("IrsRebuildMenu", "勘定残高の再計算", "FormSubmit"),
        ("IrsExitMenu", "簡易記帳", "ScreenMessage"),
    ];
    private static readonly (string Id, string Title, string Surface)[] IrsAccounts =
    [
        ("IrsAccountCreate", "科目表登録", "FormSubmit"),
        ("IrsAccountAmend", "科目表変更", "FormSubmit"),
        ("IrsAccountList", "科目表表示", "IrsAccountGrid"),
        ("IrsAccountPrint", "勘定科目表", "ReportDocument"),
        ("IrsAccountExport", "科目表の書き出し", "ConfirmationMessage"),
        ("IrsAccountImport", "科目表の取り込み", "ConfirmationMessage"),
    ];
    private static readonly (string Id, string Title, string Surface)[] IrsDefaults =
    [
        ("IrsDefaultCreate", "既定勘定登録", "IrsKeepDefaults"),
        ("IrsDefaultAmend", "既定勘定変更", "IrsDefaultEditGrid"),
        ("IrsDefaultList", "既定勘定表示", "IrsDefaultGrid"),
        ("IrsDefaultPrint", "転記の既定勘定", "ReportDocument"),
        ("IrsFinalSettingsMenu", "決算書の見出し設定", "FormSubmit"),
    ];

    public Outcome RunGroupFour(Scenario scenario, string root)
    {
        string dir = Path.Combine(root, scenario.Evidence ?? throw new InvalidDataException("レガシー証跡なし"));
        var inputs = scenario.Steps.EnumerateArray().Where(s => s.TryGetProperty("text", out _))
            .Select(s => s.GetProperty("text").GetString()!.TrimEnd('\r')).ToArray();
        using var clock = JsonDocument.Parse(File.ReadLines(Path.Combine(dir, "terminal.cast")).First());
        DateTime date = DateTimeOffset.FromUnixTimeSeconds(clock.RootElement.GetProperty("timestamp").GetInt64()).UtcDateTime;
        using var db = new Db(_databasePath);
        var before = db.Snapshot();
        var spool = db.Spool().Count();
        string screen = scenario.Subsystem == "ST" ? ReplayStock(scenario.Id, inputs, date)
            : scenario.Id is "INT-402" or "INT-403" or "INT-405" ? ReplayTransfer(scenario.Id, date)
            : ReplayIrs(scenario.Id, inputs, date, dir);
        var differences = new List<string>();
        CompareGroupFourRecords(dir, scenario.Id == "ST-090", before, db.Snapshot(), differences);
        var reports = db.Spool().Skip(spool).ToArray();
        if (scenario.Id != "ST-090")
        {
            var paths = scenario.LegacyTargets.GetProperty("report_files").EnumerateArray()
                .Select(path => path.GetString()!).Where(path => path.Contains("/spool/", StringComparison.Ordinal)).Order().ToArray();
            if (paths.Length != reports.Length)
                differences.Add($"新規印刷件数：レガシー {paths.Length}件／移行版 {reports.Length}件");
            for (int i = 0; i < Math.Min(paths.Length, reports.Length); i++)
            {
                string body = OpenGroupFourReport(reports[i].Id);
                if (Normalize(body) != Normalize(reports[i].Body))
                    differences.Add("帳票画面の本文が保存内容と一致しません。");
                string reference = File.ReadAllText(Path.Combine(root, paths[i]), System.Text.Encoding.Latin1);
                CheckGroupFourReport(scenario.Id, reference, body, differences);
            }
        }
        return Outcome.Compare(scenario, differences.Count == 0, screen + $"／新規帳票 {reports.Length}件",
            string.Join("；", differences), "実画面・論理レコード");
    }

    private string OpenGroupFourReport(long id)
    {
        if (Confirmation() != null) ConfirmGroupFour(false);
        OpenTree("MenuReports");
        var table = Find("ReportList").AsDataGridView();
        var row = table.Rows.Single(x => x.Cells[0].Name == $"帳票 {id}");
        row.Patterns.SelectionItem.Pattern.Select();
        Find("ReportListOpen").AsButton().Invoke();
        return Find("ReportDocument").Patterns.Text.Pattern.DocumentRange.GetText(-1);
    }

    private static void CheckGroupFourReport(string id, string legacy, string body, List<string> differences)
    {
        var matches = id switch
        {
            "ST-208" => Regex.Matches(legacy, @"(?m)^(\w+)\s+(\w+)\s+(\S+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\d+)\s+(\d+).*\n\s*Description: ([^\r\n]+)"),
            "ST-214" => Regex.Matches(legacy, @"Total (Additions|Deductions|Changes)\s+([\d.,-]+)"),
            "ST-400" or "ST-402" => Regex.Matches(legacy, @"(?m)^(\d\d/\d\d/\d{4})\s+(\w+)\s+(.+?)\s{2,}(\d+)\s+([\d.,-]+)(?:\s+([\d.,-]+))?"),
            "IRS-206" => Regex.Matches(legacy, @"(?m)^\s{10,}(\d{5})\s+(?:(\d{5})\s+)?(.+?)\s{2,}([A-Z])\s*$"),
            "IRS-213" => Regex.Matches(legacy, @"(?m)^ {8,}(\d{1,2})(?:\s+(\d{5})\s+(.+?)\s{2,}([A-Z]{2})\s+([NIO]))?[ \r]*$"),
            "INT-405" => Regex.Matches(legacy, @"(?m)^\s+(?:(\d+)\s+(\d\d/\d\d/\d{4})\s+(\w+)\s+(.+?)\s+(Invoice)\s+([\d.]+)\s+([\d.]+)\s+|Total\s+Posted\s+(Receipts|Invoices|Credit Notes)\s+)([\d.]+)\s+([\d.]+)\s+([\d.]+)"),
            _ => throw new InvalidDataException($"未登録の帳票比較：{id}"),
        };
        string[] lines = body.Replace("\r", "").Split('\n').Select(Normalize).ToArray();
        if (matches.Count == 0) differences.Add($"帳票のレガシー比較行を抽出できません：{id}");
        foreach (Match m in matches)
        {
            string G(int i) => m.Groups[i].Value.Trim();
            string Money(int i, int places = 2) => decimal.Parse(G(i).TrimEnd('-'), CultureInfo.InvariantCulture)
                .ToString("F" + places, CultureInfo.InvariantCulture) + (G(i).EndsWith('-') ? "-" : "");
            string Tax(int i) => G(i) switch { "I" => "仕入税", "O" => "売上税", _ => "対象外" };
            string expected = id switch
            {
                "ST-208" => $"略号 {G(1)} 品目番号 {G(2)} 品名 {G(10)} 保管場所 {G(3)} 売価 {Money(4)} 原価 {Money(5, 4)} 在庫金額 {Money(6)} 在庫数 {G(7)} 発注点 {G(8)} 発注量 {G(9)}",
                "ST-214" => (G(1) switch { "Additions" => "入庫合計", "Deductions" => "出庫合計", _ => "増減合計" }) + " " + Money(2),
                "ST-400" => $"品目番号 {G(2)} 品名 {G(3)} 数量 {G(4)} 単価 {Money(5)} 金額 {Money(6)}",
                "ST-402" => $"品目番号 {G(2)} 品名 {G(3)} 数量 {G(4)} 金額 {Money(5)}",
                "IRS-206" => $"{G(1)} {G(2)} {G(3)} {G(4)}",
                "IRS-213" => G(2).Length == 0 ? G(1) : $"{G(1)} {G(2)} {G(3)} {G(4)} {Tax(5)}",
                "INT-405" => (G(8).Length == 0 ? $"{G(1)} {LegacyDate(G(2)):yyyy年M月d日} {G(3)} {G(4)} 請求書 {Money(6)} {Money(7)}"
                    : "転記合計 " + (G(8) switch { "Receipts" => "入金", "Invoices" => "請求書", _ => "貸方票" })) +
                    $" {Money(9)} {Money(10)} {Money(11)}",
                _ => throw new InvalidDataException($"未登録の帳票比較：{id}"),
            };
            if (!lines.Contains(Normalize(expected), StringComparer.Ordinal))
                differences.Add($"帳票比較行なし：{Normalize(expected)}");
        }
    }

    private string ReplayStock(string id, string[] input, DateTime date)
    {
        OpenTree("StockNavigation");
        const string main = "在庫管理メニュー", maintenance = "在庫品目マスター管理", movement = "在庫入出庫メニュー";
        if (input.Length == 1) return Screen("在庫管理　処理日入力", "StockRunDate");
        SetDate("StockRunDate", date);
        SubmitGroupFour();
        if (id == "ST-090")
        {
            SelectAction("StockMaintenance");
            SelectAction("StockItemDisplay");
            return Screen("在庫品目照会", "StockItemList");
        }
        string key = input[2];
        if (key == "F")
        {
            Find("ScreenMenu").Focus();
            Keyboard.Press(VirtualKeyShort.KEY_F);
            return Screen(main, "ScreenMenuOpen");
        }
        var top = key switch
        {
            "A" => ("StockDateEntry", "在庫管理　処理日入力", "StockRunDate"),
            "B" => ("StockMaintenance", maintenance, "ScreenMenuOpen"),
            "C" => ("StockMovements", movement, "ScreenMenuOpen"),
            "D" => ("StockReports", "在庫帳票メニュー", "ScreenMenuOpen"),
            "E" => ("StockEndOfCycle", "在庫期間締め", "FormSubmit"),
            "X" => ("StockExit", "システムメニュー", "ScreenMessage"),
            "Y" => ("StockCompression", "在庫ファイル圧縮", "ConfirmationMessage"),
            "Z" => ("StockSystemSetUp", "システム設定", "ScreenMessage"),
            _ => throw new InvalidDataException($"在庫の未登録操作：{key}"),
        };
        SelectAction(top.Item1);
        if (input.Length == 3) return Screen(top.Item2, top.Item3);
        int index = int.Parse(input[3], CultureInfo.InvariantCulture) - 1;
        var option = key switch
        {
            "B" => StockMaintenance[index],
            "C" => StockMovements[index],
            "D" => (StockReports[index].Id, StockReports[index].Title, "StockReportFromKey"),
            _ => throw new InvalidDataException($"在庫の未登録操作：{key}"),
        };
        SelectAction(option.Item1);
        if (input.Length == 4) return Screen(option.Item2, option.Item3);
        SubmitGroupFour(("StockMovementNumber", input[4]));
        if (id is "ST-401" or "ST-403")
            return Screen(option.Item2, "ConfirmationMessage", StockMessages.ST203);
        SetGroupFourText("StockMovementQuantity", input[5].Trim());
        if (id == "ST-400") SetGroupFourText("StockMovementPrice", input[6].Trim());
        SubmitGroupFour();
        SubmitGroupFour();
        return Screen(movement, "ScreenMenuOpen");
    }

    private string ReplayIrs(string id, string[] input, DateTime date, string dir)
    {
        OpenTree("IrsNavigation");
        if (input.Length == 0) return Screen("簡易記帳", "ScreenMenuOpen");
        if (id is "IRS-090" or "INT-400" or "INT-401")
        {
            if (id != "IRS-090") SelectAction("IrsConfigurationMenu");
            SetDate("IrsRunDate", date);
            SubmitGroupFour();
            string[] fields = input.Single(line => line.Contains('\t')).Split('\t');
            string original = Find("IrsClient").AsTextBox().Text;
            string client = fields[2] + (fields[2].Length < original.Length ? original[fields[2].Length..] : "");
            var tax = Directory.GetFiles(dir, "*-screen.txt").Order(StringComparer.Ordinal)
                .Select(f => Regex.Match(File.ReadAllText(f), @"VAT Rate  - \[(\d{4})\]")).Last(m => m.Success);
            SetDate("IrsPeriodStart", LegacyDate(fields[7]));
            SetDate("IrsPeriodEnd", LegacyDate(fields[8]));
            SelectGroupFourChoice("IrsPlatform", int.Parse(fields[9], CultureInfo.InvariantCulture) - 1);
            SubmitGroupFour(("IrsOperator", fields[0]), ("IrsTaxRate", (int.Parse(tax.Groups[1].Value, CultureInfo.InvariantCulture) / 100m).ToString(CultureInfo.InvariantCulture)),
                ("IrsClient", client), ("IrsAddressFirst", fields[3]), ("IrsAddressSecond", fields[4]),
                ("IrsAddressThird", fields[5]), ("IrsAddressFourth", fields[6]), ("IrsPrinter", fields[10]));
            return Screen("システム設定の詳細", "ScreenMessage");
        }
        if (id == "IRS-091")
        {
            SelectAction("IrsAccountsMenu");
            if (Confirmation() != null) ConfirmGroupFour(false);
            SelectAction("IrsAccountCreate");
            SelectGroupFourChoice("IrsKeepAccounts", 0);
            SubmitGroupFour();
            ConfirmGroupFour(true);
            var accounts = input.Single(s => s.EndsWith("00000", StringComparison.Ordinal)).Split('\r');
            for (int i = 0; i < accounts.Length && accounts[i] != "00000"; i += 4)
            {
                SelectGroupFourChoice("IrsAccountCategory", accounts[i + 3][0] - 'A');
                SubmitGroupFour(("IrsAccountCode", accounts[i]), ("IrsAccountName", accounts[i + 2]));
            }
            OpenTree("IrsNavigation");
            SelectAction("IrsDefaultsMenu");
            SelectAction("IrsDefaultCreate");
            SelectGroupFourChoice("IrsKeepDefaults", 0);
            SubmitGroupFour();
            SubmitGroupFour();
            var defaults = input[^1].Split('\r');
            SelectGroupFourChoice("IrsDefaultSlot01Tax", 0);
            SubmitGroupFour(("IrsDefaultSlot01Account", defaults[0]), ("IrsDefaultSlot01Code", defaults[1]),
                ("IrsDefaultSlot30Account", defaults[4]), ("IrsDefaultSlot31Account", defaults[5]),
                ("IrsDefaultSlot32Account", defaults[6]));
            return Screen("既定勘定変更", "IrsDefaultEditGrid");
        }
        if (id == "IRS-400")
        {
            SelectAction("IrsPostingMenu");
            SelectGroupFourChoice("IrsPostingMode", 2);
            SubmitGroupFour();
            SubmitGroupFour();
            ConfirmGroupFour(true);
            SelectGroupFourChoice("IrsPostingDefault", 0);
            SubmitGroupFour();
            ConfirmGroupFour(true);
            SelectGroupFourChoice("IrsPostingSide", 0);
            SetDate("IrsPostingDate", LegacyDate(input[6]));
            SubmitGroupFour(("IrsPostingAccount", input[7]), ("IrsPostingLegend", input[8]), ("IrsPostingAmount", input[9]), ("IrsPostingTax", input[10]));
            return Screen("仕訳転記", "ScreenMenuOpen");
        }
        int index = input[0] switch { "A" => 9, "X" => 10, _ => int.Parse(input[0], CultureInfo.InvariantCulture) - 1 };
        var entry = IrsMain[index];
        SelectAction(entry.Id);
        if (index == 1 && input.Length > 1) ConfirmGroupFour(false);
        if ((index == 1 && input.Length > 2) || (index == 2 && input.Length > 1))
        {
            var sub = (index == 1 ? IrsAccounts : IrsDefaults)[int.Parse(input[^1], CultureInfo.InvariantCulture) - 1];
            SelectAction(sub.Id);
            return Screen(sub.Title, sub.Surface);
        }
        return Screen(entry.Title, entry.Surface);
    }

    private string ReplayTransfer(string id, DateTime date)
    {
        OpenTree("IntegrationNavigation");
        string ledger = id == "INT-402" ? "Sales" : "Purchase";
        SelectAction("Integration" + ledger + "Menu");
        SetDate("IntegrationRunDate", date);
        SubmitGroupFour();
        SelectAction("Integration" + ledger + (id == "INT-405" ? "Post" : "Close"));
        if (id != "INT-405")
        {
            Screen("期末処理", "ConfirmationMessage");
            ConfirmGroupFour(true);
            return Screen("期末処理", "IntegrationClosingPassword");
        }
        ConfirmGroupFour(true);
        var report = Find("ReportDocument").Patterns.Text.Pattern.DocumentRange.GetText(-1);
        if (string.IsNullOrWhiteSpace(report)) throw new InvalidDataException("転記帳票の画面本文が空です。");
        Find("ReportBack").AsButton().Invoke();
        return Screen("買掛元帳", "ScreenMenuOpen");
    }

    private string Screen(string expected, string surface, string? expectedMessage = null)
    {
        if (surface == "ConfirmationMessage")
        {
            var dialog = Wait(Confirmation, "確認画面");
            if (dialog.Title != expected) throw new InvalidDataException($"確認画面：期待「{expected}」／実際「{dialog.Title}」");
            string message = dialog.FindFirstDescendant(c => c.ByAutomationId(surface))?.Name ?? "";
            if (message.Length == 0) throw new InvalidDataException("確認文がありません。");
            if (expectedMessage != null && message != expectedMessage)
                throw new InvalidDataException($"確認文：期待「{expectedMessage}」／実際「{message}」");
            return $"{expected}：{message}";
        }
        string title = Find("ScreenTitle").Name;
        if (title != expected) throw new InvalidDataException($"画面：期待「{expected}」／実際「{title}」");
        if (surface != "ScreenMessage" && Window.FindFirstDescendant(c => c.ByAutomationId("ScreenMessage")) is { } error)
            throw new InvalidDataException($"画面：{title}：{error.Name}");
        var element = Find(surface);
        return surface == "ScreenMessage" ? $"{title}：{element.Name}" : title;
    }

    private void SubmitGroupFour(params (string Id, string Value)[] values)
    {
        foreach (var entry in values) SetGroupFourText(entry.Id, entry.Value);
        Find("FormSubmit").AsButton().Invoke();
    }

    private void SetGroupFourText(string id, string value) => Find(id).AsTextBox().Text = value;

    private void SetDate(string id, DateTime date)
    {
        var field = Find(id);
        var text = field.FindFirstDescendant(c => c.ByControlType(FlaUI.Core.Definitions.ControlType.Edit))?.AsTextBox()
            ?? throw new InvalidDataException($"日付入力欄が見つかりません：{id}");
        text.Focus();
        text.Text = date.ToString("d", CultureInfo.CurrentCulture);
        Keyboard.Press(VirtualKeyShort.TAB);
    }

    private static DateTime LegacyDate(string text) =>
        DateTime.ParseExact(text.Trim(), ["dd/MM/yy", "dd/MM/yyyy"], CultureInfo.InvariantCulture);

    private void SelectGroupFourChoice(string id, int index)
    {
        var combo = Find(id).AsComboBox();
        combo.Expand();
        combo.Select(index);
        combo.Collapse();
    }

    private void ConfirmGroupFour(bool accept)
    {
        var dialog = Wait(Confirmation, "確認画面");
        string button = accept ? "ConfirmationConfirm" : "ConfirmationCancel";
        Wait(() => dialog.FindFirstDescendant(c => c.ByAutomationId(button)), button).AsButton().Invoke();
    }

    private static void CompareGroupFourRecords(string dir, bool seed,
        SortedDictionary<string, SortedDictionary<string, string>> before,
        SortedDictionary<string, SortedDictionary<string, string>> after, List<string> differences)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(dir, "record-diff.json")));
        var legacy = document.RootElement;
        var unsupported = legacy.GetProperty("unsupported_files").EnumerateArray().Select(x => x.GetString()!).ToHashSet();
        var expected = legacy.GetProperty("changes").EnumerateArray().Select(row =>
            (File: row.GetProperty("file").GetString()!, Key: row.GetProperty("key").GetString()!,
             Bytes: row.GetProperty("after") is { ValueKind: JsonValueKind.Object } value ? value.GetProperty("hex").GetString() : null))
            .Where(row => !seed || row.File == "ledgers/acas/stockctl.dat").ToDictionary(row => (row.File, row.Key), row => row.Bytes);
        string supplement = Path.Combine(dir, "record-diff.bdb.json");
        var supplemented = new HashSet<string>(StringComparer.Ordinal);
        if (File.Exists(supplement))
        {
            using var additional = JsonDocument.Parse(File.ReadAllText(supplement));
            foreach (var file in additional.RootElement.EnumerateObject())
            {
                if (!unsupported.Remove(file.Name))
                    throw new InvalidDataException($"補完対象外のファイル：{file.Name}");
                supplemented.Add(file.Name);
                foreach (var record in file.Value.EnumerateObject())
                    expected.Add((file.Name, record.Name), record.Value.GetString());
            }
        }
        if (seed && expected.Count != 2)
            differences.Add($"業務用の在庫品目マスター：証跡に2件必要（実際 {expected.Count}件）");
        var changed = new HashSet<(string File, string Key)>();
        if (!seed)
            foreach (string file in before.Keys.Union(after.Keys))
                foreach (string key in (before.GetValueOrDefault(file)?.Keys.AsEnumerable() ?? []).Union(after.GetValueOrDefault(file)?.Keys.AsEnumerable() ?? []))
                    if (!string.Equals(before.GetValueOrDefault(file)?.GetValueOrDefault(key), after.GetValueOrDefault(file)?.GetValueOrDefault(key), StringComparison.OrdinalIgnoreCase))
                        changed.Add((file, key));
        var complete = supplemented.SelectMany(file =>
            (after.GetValueOrDefault(file)?.Keys.AsEnumerable() ?? []).Select(key => (File: file, Key: key)));
        foreach (var key in expected.Keys.Union(changed.Where(x => !unsupported.Contains(x.File))).Union(complete))
        {
            string? actual = after.GetValueOrDefault(key.File)?.GetValueOrDefault(key.Key);
            if (!expected.TryGetValue(key, out string? wanted)) differences.Add($"レガシー証跡にない更新：{key.File}/{key.Key}");
            else if (!seed && !changed.Contains(key)) differences.Add($"必要な更新なし：{key.File}/{key.Key}");
            else if (!string.Equals(wanted, actual, StringComparison.OrdinalIgnoreCase))
                differences.Add($"論理レコード相違：{key.File}/{key.Key}");
        }
        foreach (string file in changed.Select(x => x.File).Where(unsupported.Contains).Distinct().Order())
            differences.Add($"レガシーで論理レコード未採取：{file}");
    }
}
