using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Acas.App;
using Acas.Core;
using Acas.Core.Engine;

namespace Acas.Verify;

public static class GroupOneVerification
{
    public static Outcome Run(Scenario scenario, string evidence, GroupOnePlan plan)
    {
        const string source = "新画面モデル";
        try
        {
            using var database = new Db();
            database.LoadBaseline(scenario.Baseline);
            var before = database.Snapshot();
            var model = new AccountingScreens(database);
            var navigation = model.Navigation().Concat(SubsystemScreens.Load(typeof(AccountingScreens).Assembly, database))
                .SelectMany(item => item.Children?.Prepend(item) ?? [item])
                .ToDictionary(item => item.Id);
            Screen screen = model.Start();
            MenuScreen? currentMenu = null;
            var inputs = new Dictionary<string, object?>();
            var observations = new List<string>();
            var differences = new List<string>();
            foreach (var action in plan.Actions)
            {
                switch (action.Type)
                {
                    case ActionType.Check:
                        if (!Observe(navigation, screen, action, observations))
                            differences.Add($"画面：{action.Id} {action.Value} を確認できません（{screen.Title}）。" +
                                (screen is FormScreen { Error: { } error } && action.Id == "Status" ? $"表示：{error}" : ""));
                        break;
                    case ActionType.Text or ActionType.Choice or ActionType.DateText:
                        var field = (screen as FormScreen)?.Fields.SingleOrDefault(field => field.Id == action.Id);
                        if (field is not (TextField or PasswordField) && action.Type == ActionType.Text ||
                            field is not ChoiceField && action.Type == ActionType.Choice ||
                            field is not DateField && action.Type == ActionType.DateText)
                            throw new InvalidOperationException($"該当する入力欄がありません：{action.Id}（{screen.Title}）");
                        if (field is ChoiceField choice && choice.Options.All(option => option.Value != action.Value))
                            throw new InvalidOperationException($"指定した選択肢がありません：{action.Id}／{action.Value}");
                        inputs[action.Id] = action.Type == ActionType.DateText
                            ? DateTime.TryParseExact(action.Value, "dd/MM/yyyy", CultureInfo.InvariantCulture,
                                DateTimeStyles.None, out var date) ? date : null
                            : action.Value;
                        break;
                    case ActionType.RejectChoice:
                        if (screen is not FormScreen form ||
                            form.Fields.FirstOrDefault(field => field.Id == action.Id) is not ChoiceField options ||
                            options.Options.Any(option => option.Value == action.Value))
                            differences.Add($"画面：{action.Id} で不正値「{action.Value}」を拒否できません。");
                        else observations.Add($"{action.Id}：不正値「{action.Value}」は選択できません。");
                        break;
                    case ActionType.Key or ActionType.Close:
                        differences.Add($"実画面での操作が必要です：{action.Type} {action.Id}。");
                        break;
                    default:
                        if (action.Type == ActionType.Tree) currentMenu = null;
                        screen = action is { Type: ActionType.Menu, Id: "ScreenMenuBack" } && currentMenu is not null
                            ? currentMenu : Move(navigation, screen, action, inputs);
                        if (screen is MenuScreen menu) currentMenu = menu;
                        inputs.Clear();
                        break;
                }
            }
            return Compare(scenario, evidence, plan, before, database, observations, differences, source);
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or IOException or JsonException)
        {
            return Outcome.Compare(scenario, false, "", e.Message, source);
        }
    }

    private static Screen Move(IReadOnlyDictionary<string, MenuItem> navigation, Screen screen, ScreenAction action,
        Dictionary<string, object?> inputs) => action.Type switch
    {
        ActionType.Tree when navigation.TryGetValue(action.Id, out var item) && item.Open != null => item.Open(),
        ActionType.Menu when screen is FormScreen { Back: { } back } && action.Id == "FormBack" => back(),
        ActionType.Menu when screen is MenuScreen menu &&
            menu.Items.FirstOrDefault(item => item.Id == action.Id)?.Open is { } open => open(),
        ActionType.Confirm when screen is ConfirmationScreen confirm => confirm.Confirm(),
        ActionType.Cancel when screen is ConfirmationScreen cancel => cancel.Cancel(),
        ActionType.TableRow when screen is TableScreen table && table.Id == action.Id &&
            table.Rows.FirstOrDefault(row => row.Cells[0] == action.Value)?.Open is { } open => open(),
        ActionType.Submit when screen is FormScreen form => form.Submit(new FormValues(
            form.Fields.ToDictionary(field => field.Id, field => inputs.TryGetValue(field.Id, out var value) ? value :
                field switch
                {
                    TextField text => text.Value,
                    PasswordField => "",
                    DateField date => date.Value,
                    ChoiceField choice => choice.Value,
                    _ => null
                }))),
        _ => throw new InvalidOperationException($"画面操作が見つかりません：{action.Type} {action.Id}（{screen.Title}）")
    };

    private static bool Observe(IReadOnlyDictionary<string, MenuItem> navigation, Screen screen, ScreenAction action,
        List<string> observations)
    {
        string? actual = (action.Id, screen) switch
        {
            ("Status", FormScreen form) => form.Error,
            ("ScreenTitle", _) => screen.Title,
            ("ScreenMessage", InformationScreen info) => info.Message,
            ("Confirmation", ConfirmationScreen confirm) => confirm.Message,
            ("ReportDocument", ReportScreen report) when !string.IsNullOrWhiteSpace(report.Body) => report.Body,
            (_, TableScreen table) when table.Id == action.Id => string.Join("\n", table.Rows.Select(row => string.Join(" ", row.Cells))),
            (_, FormScreen form) => form.Fields.FirstOrDefault(field => field.Id == action.Id)?.Label,
            (_, MenuScreen menu) => menu.Items.FirstOrDefault(item => item.Id == action.Id)?.Caption,
            _ => null
        };
        actual ??= navigation.GetValueOrDefault(action.Id)?.Caption;
        if (actual is null || !actual.Contains(action.Value, StringComparison.Ordinal)) return false;
        observations.Add(action.Value.Length == 0 ? $"{screen.Title}：{action.Id}" : $"{action.Id}：{action.Value}");
        return true;
    }

    public static Outcome Compare(Scenario scenario, string evidence, GroupOnePlan plan,
        SortedDictionary<string, SortedDictionary<string, string>> before, Db database,
        List<string> observations, List<string> differences, string source)
    {
        var targets = scenario.LegacyTargets;
        string Content(string relative) => File.ReadAllText(Scenario.EvidencePath(evidence, relative), Encoding.Latin1);
        if (!targets.GetProperty("screen_text").EnumerateArray().Any(path =>
            Content(path.GetString()!).Contains(plan.LegacyScreen, StringComparison.OrdinalIgnoreCase)))
            differences.Add($"画面証跡：旧画面に確認点「{plan.LegacyScreen}」が見つかりません。");

        string diffPath = Scenario.EvidencePath(evidence, targets.GetProperty("keyed_record_diff").GetString()!);
        using var legacy = JsonDocument.Parse(File.ReadAllText(diffPath));
        var expected = legacy.RootElement.GetProperty("changes").EnumerateArray().ToDictionary(
            change => (change.GetProperty("file").GetString()!, change.GetProperty("key").GetString()!),
            change => (Before: Hex(change.GetProperty("before")), After: Hex(change.GetProperty("after"))));
        if (scenario.Id == "GL-035" && legacy.RootElement.GetProperty("unsupported_files").EnumerateArray()
            .Any(file => file.GetString() == LedgerReports.FinalFile))
        {
            string run = Path.GetDirectoryName(diffPath)!;
            string oldBefore = Path.Combine(run, "before-files", LedgerReports.FinalFile);
            string oldAfter = Path.Combine(run, "files", LedgerReports.FinalFile);
            try
            {
                if (File.Exists(oldBefore)) throw new InvalidDataException("実行前にも決算ファイルが存在します。");
                foreach (var (key, data) in ReadIndexedEvidence(File.ReadAllBytes(oldAfter), 9, 45))
                    expected.Add((LedgerReports.FinalFile, key), (null, Convert.ToHexString(data).ToLowerInvariant()));
            }
            catch (Exception ex) when (ex is IOException or InvalidDataException)
            {
                differences.Add($"旧決算ファイルを比較できません：{ex.Message}");
            }
        }
        if (scenario.Id == "SYS-001")
        {
            const string analysis = "ledgers/acas/analysis.dat", values = "ledgers/acas/value.dat";
            string run = Path.GetDirectoryName(diffPath)!;
            try
            {
                if (new[] { analysis, values }.Any(file => File.Exists(Path.Combine(run, "before-files", file))) ||
                    File.Exists(Path.Combine(run, "files", values)))
                    throw new InvalidDataException("初回作成の分析証跡とファイル構成が異なります。");
                foreach (var (key, data) in ReadIndexedEvidence(File.ReadAllBytes(Path.Combine(run, "files", analysis)), 3, 66))
                {
                    expected.Add((analysis, key), (null, Convert.ToHexString(data.AsSpan(0, 36)).ToLowerInvariant()));
                    expected.Add((values, key), (null, Convert.ToHexString(data).ToLowerInvariant()));
                }
            }
            catch (Exception ex) when (ex is IOException or InvalidDataException)
            {
                differences.Add($"旧分析初期化ファイルを比較できません：{ex.Message}");
            }
        }
        var actual = Changes(before, database.Snapshot());
        foreach (var ((file, key), change) in expected)
        {
            if (!actual.Remove((file, key), out var found)) differences.Add($"レコード差分なし：{file} {key}");
            else if (change != found)
            {
                differences.Add($"レコード内容：{file} {key} の前後バイト列が異なります。");
                if (scenario.Id == "SYS-001")
                {
                    if (change.Before != found.Before) differences.Add($"実行前：{ByteDifferences(change.Before, found.Before)}");
                    if (change.After != found.After) differences.Add($"実行後：{ByteDifferences(change.After, found.After)}");
                }
            }
        }
        foreach (var (file, key) in actual.Keys)
            differences.Add($"想定外のレコード差分：{file} {key}");

        var oldReports = targets.GetProperty("report_files").EnumerateArray()
            .Select(path => ComparableReport(scenario.Id, Content(path.GetString()!), legacy: true))
            .Distinct(StringComparer.Ordinal).ToArray();
        var newReports = database.Spool().Select(report => ComparableReport(scenario.Id, report.Body, legacy: false)).ToArray();
        if (oldReports.Length != newReports.Length)
            differences.Add($"帳票数：旧 {oldReports.Length}／新 {newReports.Length}（旧証跡の同一内容コピーを除く）。");
        else if (!newReports.Order(StringComparer.Ordinal).SequenceEqual(oldReports.Order(StringComparer.Ordinal)))
        {
            differences.Add("帳票本文：正規化後のテキストが異なります。");
            if (oldReports.Length == 1 && scenario.Id is "SYS-001" or "SYS-004" or "SYS-010" or "GL-035")
            {
                string[] oldLines = oldReports[0].Split('\n', '\f'), newLines = newReports[0].Split('\n', '\f');
                for (int i = 0; i < Math.Max(oldLines.Length, newLines.Length); i++)
                {
                    string? oldLine = oldLines.ElementAtOrDefault(i), newLine = newLines.ElementAtOrDefault(i);
                    if (oldLine != newLine) differences.Add($"帳票 {i + 1} 行：旧「{oldLine}」／新「{newLine}」");
                }
            }
        }
        return Outcome.Compare(scenario, differences.Count == 0, string.Join("\n", observations),
            string.Join("\n", differences), source);
    }

    private static string? Hex(JsonElement record) =>
        record.ValueKind == JsonValueKind.Null ? null : record.GetProperty("hex").GetString();

    private static string ComparableReport(string id, string report, bool legacy)
    {
        if (id is "SYS-001" or "SYS-004" or "SYS-010")
            return SettingsReport(report, legacy);
        if (id == "GL-035")
            return FinancialReport(report, legacy);
        bool chart = id is "GL-033" or "GL-206";
        bool detail = id is "GL-034" or "GL-225";
        bool structured = id == "GL-226";
        bool batch = id == "GL-221";
        if (!chart && !detail && !structured && !batch) return Normalize(report);
        var pages = report.Replace("\r", "", StringComparison.Ordinal).TrimEnd('\n', '\f').Split('\f');
        return string.Join('\f', pages.Select(page =>
        {
            var lines = page.TrimStart('\n').Split('\n').Select(line => line.TrimEnd()).ToArray();
            if (lines.Length < (chart ? 3 : 4)) return page;
            var first = lines[0];
            var second = lines[1];
            string pageNumber = Regex.Match(chart && legacy ? second : first,
                legacy ? @"Page\s*-?\s*(\d+)" : @"(\d+)ページ").Groups[1].Value;
            string date = Regex.Match(chart && legacy ? first : second, @"\b\d{2,4}/\d{2}/\d{2,4}\b").Value;
            if (pageNumber.Length == 0 || date.Length == 0) return page;
            string metadata;
            if (batch)
            {
                string cycle = Regex.Match(second, legacy ? @"Cycle\s*-\s*(\d+)" : @"会計期間\s*(\d+)").Groups[1].Value;
                if (cycle.Length == 0) return page;
                metadata = cycle;
            }
            else
            {
                metadata = legacy ? second[..Math.Min(second.Length, 32)].TrimEnd() :
                    second[..second.LastIndexOf(date, StringComparison.Ordinal)].TrimEnd();
            }
            int column = Array.FindIndex(lines, line => line.StartsWith(
                legacy ? chart ? "---Level---" : batch ? "Ledger" : "Account" :
                    chart ? "階層" : batch ? "台帳" : "勘定", StringComparison.Ordinal));
            if (column < 2) return page;
            if (detail)
            {
                var quarters = Regex.Matches(lines[column], legacy ? @"Quarter (\d+)" : @"第(\d+)四半期")
                    .Select(match => match.Groups[1].Value).ToArray();
                if (quarters.Length != 2) return page;
                metadata += "\n" + string.Join(",", quarters);
            }
            string[] rows = lines.Skip(column + (chart ? 1 : 2)).SkipWhile(string.IsNullOrWhiteSpace)
                .Reverse().SkipWhile(string.IsNullOrWhiteSpace).Reverse().ToArray();
            if (legacy)
                for (int i = 0; i < rows.Length; i++)
                {
                    if (chart && rows[i].Length > 57)
                    {
                        var name = rows[i].Length > 76 ? rows[i][76..] : "";
                        string placement = rows[i][57..Math.Min(76, rows[i].Length)].Trim() switch
                        {
                            "Direct Income" => "直接収益", "Direct Costs" => "直接原価", "Sundry Income" => "雑収益",
                            "Indirect Cost" => "間接原価", "Fixed Assets" => "固定資産", "Current Asset" => "流動資産",
                            "Current Liab." => "流動負債", "Capital A/Cs" => "資本", var value => value
                        };
                        rows[i] = (rows[i][..57] + placement.PadRight(19) + name).TrimEnd();
                    }
                    if (detail || structured)
                        rows[i] = Regex.Replace(rows[i], @"^ {20}[Tt] o t a l.{0,2}", "                    合計".PadRight(29));
                }
            if (detail || structured)
                for (int i = 0; i < rows.Length; i++)
                    if (rows[i].TrimStart().StartsWith("合計", StringComparison.Ordinal))
                        rows[i] = Normalize(rows[i]);
            return pageNumber + "\n" + date + "\n" + metadata + "\n" + string.Join('\n', rows);
        }));
    }

    private static string FinancialReport(string report, bool legacy)
    {
        var lines = report.Replace("\r", "", StringComparison.Ordinal).TrimEnd('\n').Split('\n');
        if (legacy)
        {
            void Replace(int row, int col, int width, string label, string replacement)
            {
                var line = lines[row].PadRight(col + width);
                if (line.Substring(col, width).TrimEnd() != label) return;
                int columns = replacement.Sum(c => c <= 'ÿ' ? 1 : 2);
                lines[row] = line[..col] + replacement + new string(' ', width - columns) + line[(col + width)..];
            }
            for (int row = 0; row < lines.Length; row++)
            {
                Replace(row, 32, 43, "Profit & Loss Account    For the period to", "損益計算書　対象期間末日");
                Replace(row, 42, 22, "Balance Sheet  as at", "貸借対照表");
                Replace(row, 90, 28, "<--------Last  Year-------->", "<--------前期-------->");
                Replace(row, 50, 40, "<--------This  Year-------->", "<--------当期-------->");
                foreach (var (label, replacement) in new (string, string)[]
                {
                    ("Sales Income", "収益"), ("Direct Costs", "直接原価"), ("Sundry Income", "雑収益"),
                    ("Indirect Costs", "間接原価"), ("Fixed Assets", "固定資産"), ("Current Assets", "流動資産"),
                    ("Current Liabilities", "流動負債"), ("Shareholders Funds", "資本"),
                    ("Gross Profit", "売上総利益"), ("Net Profit", "当期純利益"), ("Net Current Value", "正味流動資産")
                })
                    Replace(row, 0, 20, label, replacement);
                if (row == lines.Length - 5) Replace(row, 20, 30, "Net Profit", "当期純利益");
            }
        }
        return string.Join('\n', lines.Select(line => line.TrimEnd()));
    }

    private static string SettingsReport(string report, bool legacy)
    {
        var pages = report.Replace("\r", "", StringComparison.Ordinal).TrimEnd('\n').Split('\f');
        if (!legacy) return string.Join('\f', pages.Select(page => string.Join('\n', page.Split('\n').Select(line => line.TrimEnd()))));
        if (pages.Length != 2) return report;
        var first = pages[0].Split('\n');
        var second = pages[1].Split('\n');
        if (first.Length != 51 || second.Length < 26) return report;
        void Change(string[] page, int row, int start, int width, params (string Old, string New)[] options)
        {
            string line = page[row - 1].PadRight(start + width);
            string part = line.Substring(start, width).TrimEnd();
            foreach (var (old, replacement) in options)
                if (part == old)
                {
                    int columns = replacement.Sum(c => c <= 'ÿ' ? 1 : 2);
                    page[row - 1] = line[..start] + replacement + new string(' ', Math.Max(0, width - columns)) + line[(start + width)..];
                    return;
                }
        }
        void Header(string[] page)
        {
            Change(page, 1, 126, 4, ("Page", "頁"));
            Change(page, 1, 50, 33, ("S Y S T E M   P A R A M E T E R S", "システム設定帳票"));
            Change(page, 1, 0, 16, ("SYS002 (3.01.39)", "設定"));
        }
        void Section(string[] page, int row, string left, string jpLeft, string right, string jpRight, int col = 24)
        {
            Change(page, row, 80, 16, (right, jpRight));
            Change(page, row, col, 40 - col, (left, jpLeft));
        }
        void R(int row, int end, params (string, string)[] labels) => Change(first, row, 70, end - 70, labels);
        void Y(string[] page, int row, int start) => Change(page, row, start, 7, ("Yes", "はい"), ("No", "いいえ"));
        Header(first);
        Header(second);
        Section(first, 3, "User  Parameters", "利用者設定", "G/L   Parameters", "総勘定元帳設定");
        Section(first, 21, "ACAS  Parameters", "運用環境設定", "P/L   Parameters", "買掛元帳設定");
        Section(first, 34, "Inv.  Parameters", "請求書設定", "S/L   Parameters", "売掛元帳設定");
        Section(second, 3, "Stock Parameters", "在庫管理設定", "O/E   Parameters", "受注管理設定");
        Section(second, 15, "Payroll Parameters", "給与設定", "RDMBS Parameters", "データベース設定", 22);
        R(6, 120, ("Neither P/C or Branches Selected", "部門・拠点なし"), ("Profit-Centres Selected", "部門を使用"), ("Branches Selected", "拠点を使用"));
        R(7, 120, ("Only for Revenue Accounts", "収益勘定のみ"), ("For all Accounts", "全勘定"));
        R(8, 120, ("P-C / Branches Grouped on 1st Digit", "先頭桁で区分"), ("P-C / Branches not Grouped", "先頭桁で区分しない"));
        R(9, 120, ("Comparative Figures Required", "比較情報 はい"), ("Comparative Figures not Required", "比較情報 いいえ"));
        R(10, 120, ("Alphabetic Ledger Index Selected", "二次索引 はい"), ("Alphabetic Ledger Index not Selected", "二次索引 いいえ"));
        R(12, 120, ("Min. Validation During Data Entry", "最小限の入力検証"), ("Full Validation During Data Entry", "完全な入力検証"));
        R(13, 120, ("Transaction Archiving Selected", "締め時に仕訳を保管"), ("Transactions Deleted at End of Cycle", "締め時に仕訳を削除"));
        R(14, 110, ("Sales Range most Significant Digit is -", "売掛勘定番号の先頭桁"), ("No Reserved Sales Range", "売掛勘定番号の先頭桁なし"));
        R(15, 110, ("Purchase Range Most Signif.  Digit is -", "買掛勘定番号の先頭桁"), ("No Reserved Purchase Range", "買掛勘定番号の先頭桁なし"));
        R(16, 120, ("Auto VAT Posting Selected", "消費税を自動計算"), ("Manual VAT Posting Selected", "消費税を手計算"));
        R(17, 91, ("Cycles per Quarter -", "四半期内の会計期間数"));
        R(18, 91, ("Next Batch Number  -", "次回バッチ番号"));
        Y(first, 19, 96);
        R(19, 96, ("Using IRS instead of GL -", "簡易記帳との連携"));
        R(24, 98, ("Address Delimiter", "住所区切り"));
        R(25, 94, ("Next Batch Number", "次回バッチ番号"));
        R(26, 91, ("Next Folio Number", "次回伝票番号"));
        R(27, 93, ("Pay      Account", "支払勘定"));
        R(28, 93, ("Ledger   Account", "仕入元帳勘定"));
        R(29, 93, ("Creditor Account", "買掛金勘定"));
        Y(first, 30, 96);
        R(30, 96, ("Stock Control Link", "在庫連携"));
        R(37, 120, ("Computer Generated Invoice Numbers Selected", "請求書番号を自動採番"), ("Manually Entered Invoice Numbers Selected", "請求書番号を手入力"));
        R(38, 120, ("Dunning Letters not Selected", "督促状 いいえ"), ("Dunning Letters Selected", "督促状 はい"));
        R(39, 120, ("Late Charges not Selected", "延滞料 いいえ"), ("Late Charges Selected", "延滞料 はい"));
        Change(first, 40, 87, 4, ("Days", "日"));
        R(40, 84, ("Credit Period", "支払期限"));
        R(41, 92, ("Standard Credit Limit", "標準与信限度額"));
        R(42, 93, ("Standard Discount is", "標準値引率"));
        R(43, 94, ("Min. Late Balance", "延滞対象最低残高"));
        R(44, 94, ("Max. Late Charge", "延滞料上限"));
        R(45, 93, ("Late Charge Rate", "延滞料率"));
        R(46, 98, ("Address Delimiter", "住所区切り"));
        R(47, 94, ("Next Batch Number", "次回バッチ番号"));
        Y(first, 48, 96);
        R(48, 96, ("Stock Control Link", "在庫連携"));
        R(49, 93, ("Pay      Account", "入金勘定"));
        R(50, 93, ("Ledger   Account", "売上元帳勘定"));
        R(51, 93, ("Debtors  Account", "売掛金勘定"));
        Change(first, 14, 42, 9, ("VAT Reg:", "税番号"));
        Change(first, 11, 27, 43, ("UK Format", "日・月・年"), ("USA Format", "月・日・年"), ("Intl Format", "年・月・日"));
        Change(first, 24, 27, 43, ("Single User", "単独利用"), ("Multi-User", "複数利用"));
        Change(first, 25, 27, 43, ("Linuxe User", "Linux"), ("Linux", "Linux"), ("Windows", "Windows"), ("Dos", "DOS"), ("Unix", "Unix"), ("OS/2", "OS/2"));
        Change(first, 26, 27, 43, ("Using (Free) Open Source Version of ACAS", "公開版"), ("Using Commercial Version of ACAS", "商用版"));
        Change(first, 27, 27, 43, ("Cobol/Dup Mode Not Used", "旧データファイル／重複処理 いいえ"),
            ("Cobol/Dup Mode Used", "旧データファイル／重複処理 はい"), ("Rdbms/Dup Mode Not Used", "データベース／重複処理 いいえ"),
            ("Rdbms/Dup Mode Used", "データベース／重複処理 はい"));
        Y(first, 43, 27);
        foreach (var (row, old, updated) in new (int, string, string)[]
        {
            (6,"Name","会社名"), (7,"Address","住所1"), (11,"Date Format","日付順"), (12,"Period Start","期首日"), (13,"       End","期末日"),
            (14,"VAT    Rate 1/4.","税率1/4"), (15,"       Rate 2/5.","税率2/5"), (16,"       Rate 3.","税率3"),
            (17,"Current Quarter","四半期"), (18,"Current Cycle","会計期間"), (19,"Print Lines","印刷行数"), (24,"Environment","利用形態"),
            (25,"Op. System","旧環境の区分"), (26,"System version","版"), (28,"Path to IRS","簡易記帳のパス"),
            (29,"Path to Ledgers","台帳のパス"), (30,"Prt Spool Name 1","共通の印刷先"), (31,"Prt Spool Name 2","総勘定元帳印刷先"),
            (32,"Prt Spool Name 3","買掛元帳の印刷先"), (37,"Next Inv. Number","次回請求書番号"),
            (40,"Inv. Data Level","請求書入力段階"), (42,"VAT Account","消費税勘定"), (43,"Print VAT Nunber","税登録番号印刷"),
            (47,"Proforma Retent.","仮請求書保管期間"),
            (48,"Company Heads Print on Delivery notes:","納品書の社名印刷"), (49,"Company Heads Print on Invoices      :","請求書の社名印刷"),
            (50,"Company Heads Print on Statements    :","取引明細書の社名印刷"), (51,"Company Heads Print on Late Letters  :","督促状の社名印刷")
        })
            Change(first, row, 10, row >= 48 ? 39 : 17, (old, updated));
        Y(second, 6, 94);
        Change(second, 6, 70, 24, ("O/Entry in Use", "受注管理"));
        foreach (int row in new[] { 6, 7, 8, 9, 12, 18 }) Y(second, row, 27);
        foreach (int row in new[] { 10, 11 })
            Change(second, row, 27, 43, ("Monthly", "月次"), ("Quarterly", "四半期"), ("Yearly", "年次"), ("NOT SET", "未設定"));
        foreach (var (row, old, updated) in new (int, string, string)[]
        {
            (6,"Debug Mode","デバッグ"), (7,"Manufacturing","製造管理"), (8,"Audit in Use","在庫監査"),
            (9,"Movement Audits","移動監査"), (10,"Current Period","在庫当期区分"), (11,"To Date Period","在庫累計区分"),
            (12,"Stock Averaging","平均原価"), (13,"Current Audit No","在庫監査番号"),
            (18,"Payroll in Use","給与計算"), (23,"File Statuses","ファイル状態")
        })
            Change(second, row, 10, 17, (old, updated));
        Change(second, 20, 24, 16, ("System Paramters", "システム状態"));
        Change(second, 25, 51, 30, ("End of System Parameter Report", "システム設定帳票 終わり"));
        return string.Join('\n', first.Select(line => line.TrimEnd())) + "\f" + string.Join('\n', second.Select(line => line.TrimEnd()));
    }

    private static string ByteDifferences(string? expected, string? actual)
    {
        if (expected is null || actual is null) return "一方にのみレコードがあります。";
        byte[] old = Convert.FromHexString(expected), current = Convert.FromHexString(actual);
        var offsets = Enumerable.Range(0, Math.Min(old.Length, current.Length)).Where(i => old[i] != current[i]);
        return $"旧 {old.Length}／新 {current.Length} バイト、差の位置（0 起点）：{string.Join(", ", offsets)}";
    }

    private static Dictionary<string, byte[]> ReadIndexedEvidence(byte[] file, int keySize, int recordSize)
    {
        const int pageSize = 4096;
        if (file.Length != 2 * pageSize || BinaryPrimitives.ReadUInt32LittleEndian(file.AsSpan(12)) != 0x00053162 ||
            BinaryPrimitives.ReadUInt32LittleEndian(file.AsSpan(16)) != 9 ||
            BinaryPrimitives.ReadUInt32LittleEndian(file.AsSpan(20)) != pageSize ||
            file[pageSize + 25] != 5)
            throw new InvalidDataException("単一リーフの Berkeley DB B-tree ではありません。");
        var page = file.AsSpan(pageSize);
        int entries = BinaryPrimitives.ReadUInt16LittleEndian(page[20..]);
        if (entries == 0 || entries % 2 != 0 || entries > (pageSize - 26) / 2)
            throw new InvalidDataException("索引件数が不正です。");
        var result = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        for (int index = 0; index < entries; index += 2)
        {
            var key = IndexedEntry(page, entries, index, keySize);
            var data = IndexedEntry(page, entries, index + 1, recordSize);
            if (!data.StartsWith(key) || !result.TryAdd(Encoding.ASCII.GetString(key), data.ToArray()))
                throw new InvalidDataException("レコードキーが不正です。");
        }
        return result;
    }

    private static ReadOnlySpan<byte> IndexedEntry(ReadOnlySpan<byte> page, int entries, int index, int length)
    {
        int offset = BinaryPrimitives.ReadUInt16LittleEndian(page[(26 + index * 2)..]);
        if (offset < 26 + entries * 2 || offset + 3 + length > page.Length ||
            BinaryPrimitives.ReadUInt16LittleEndian(page[offset..]) != length || page[offset + 2] != 1)
            throw new InvalidDataException("レコード形式が不正です。");
        return page.Slice(offset + 3, length);
    }

    private static string Normalize(string report) =>
        string.Join(' ', report.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    private static Dictionary<(string File, string Key), (string? Before, string? After)> Changes(
        SortedDictionary<string, SortedDictionary<string, string>> before,
        SortedDictionary<string, SortedDictionary<string, string>> after)
    {
        var result = new Dictionary<(string File, string Key), (string? Before, string? After)>();
        foreach (string file in before.Keys.Union(after.Keys))
        {
            var previous = before.GetValueOrDefault(file) ?? [];
            var current = after.GetValueOrDefault(file) ?? [];
            foreach (string key in previous.Keys.Union(current.Keys))
            {
                string? a = previous.GetValueOrDefault(key), b = current.GetValueOrDefault(key);
                if (a != b) result.Add((file, key), (a, b));
            }
        }
        return result;
    }
}
