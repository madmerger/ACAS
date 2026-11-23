using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Acas.App.Subsystems.Integration;
using Acas.App.Subsystems.Irs;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Integration;
using Acas.Core.Programs.Irs;

internal sealed class Scenario(Db db, DateTime date, JsonElement item)
{
    private readonly IrsBookkeeping books = new(db, () => date);
    private readonly string id = item.GetProperty("id").GetString()!;
    private readonly JsonElement runner = item.GetProperty("runner");
    private readonly string[] path = item.GetProperty("menu_path").EnumerateArray().Select(x => x.GetString()!).ToArray();
    private Screen current = null!;
    public IrsReport? Report { get; private set; }

    public void Replay(string[] references)
    {
        if (runner.GetProperty("app").GetString() == "acas")
        {
            ReplayIntegration(references);
            return;
        }
        var navigation = new IrsScreens().CreateNavigation(books);
        Show(navigation.Open!());
        if (path.Length == 0)
        {
            Require(references, "S Y S T E M   M E N U", "簡易記帳", typeof(MenuScreen));
            return;
        }
        if (id is "IRS-090" or "INT-400" or "INT-401")
        {
            if (id == "INT-401" && runner.GetProperty("irs_path").GetString() != "ledgers/acas")
                throw new InvalidOperationException("連携元の設定が証跡と一致しません。");
            if (current is MenuScreen) Open("IrsConfigurationMenu", 1);
            Configure(references);
            if (current is not InformationScreen { Message: "処理が完了しました。" })
                throw new InvalidOperationException("設定を保存できませんでした。");
            Show(navigation.Open());
            Require(references, "S Y S T E M   M E N U", "簡易記帳", typeof(MenuScreen));
            return;
        }
        if (id == "IRS-091")
        {
            SetupAccounts();
            Require(references, "Default Accounts Amendments", "既定勘定変更", typeof(TableScreen));
            return;
        }
        if (id == "IRS-400")
        {
            Post();
            Require(references, "Transaction Posting", "仕訳転記", typeof(MenuScreen));
            return;
        }
        Open(path[0] switch
        {
            "A" => "IrsRebuildMenu", "X" => "IrsExitMenu", _ => RootOptions[int.Parse(path[0], CultureInfo.InvariantCulture)]
        }, int.TryParse(path[0], out int number) ? number : null);
        if (path[0] == "2" && current is ConfirmationScreen initial)
            Show(initial.Cancel());
        if (path.Length == 1)
        {
            var (anchor, title, type) = path[0] switch
            {
                "1" => ("SYSTEM FILE SET-UP", "システム設定・保守", typeof(FormScreen)),
                "2" => ("Accounts File Utilities", "勘定科目表", typeof(MenuScreen)),
                "3" => ("Default File Utilities", "既定勘定", typeof(MenuScreen)),
                "4" => ("Transaction Posting", "仕訳転記", typeof(FormScreen)),
                "5" => ("Trial Balance", "試算表", typeof(FormScreen)),
                "6" => ("Posting  Reports", "監査証跡", typeof(FormScreen)),
                "7" => ("Final Accounts Production", "決算書作成", typeof(FormScreen)),
                "8" or "9" => ("S Y S T E M   M E N U", "簡易記帳", typeof(MenuScreen)),
                "A" => ("Fixup Accounts File", "勘定残高の再計算", typeof(FormScreen)),
                "X" => ("S Y S T E M   M E N U", "簡易記帳", typeof(InformationScreen)),
                _ => throw new InvalidOperationException("対応する簡易記帳メニューがありません。")
            };
            Require(references, anchor, title, type);
            return;
        }
        var options = path[0] == "2" ? AccountOptions : DefaultOptions;
        var option = options[int.Parse(path[1], CultureInfo.InvariantCulture) - 1];
        Open(option.Id, int.Parse(path[1], CultureInfo.InvariantCulture));
        if (current is ReportScreen screen)
        {
            var report = path[0] == "2" ? books.AccountReport() : books.DefaultReport();
            if (screen.Body != report.Body) throw new InvalidOperationException("画面の帳票本文が一致しません。");
            Report = report;
        }
        Require(references, option.Anchor, option.Title, option.Type);
    }

    private void ReplayIntegration(string[] references)
    {
        var destination = runner.TryGetProperty("irs_path", out var setting) && setting.GetString() == "ledgers/acas"
            ? TransferDestination.Shared : TransferDestination.Dedicated;
        var integration = new IntegrationScreens(destination, report => Report = report);
        Show(integration.CreateNavigation(db, date).Open!());
        bool sales = path[0] == "B";
        string ledger = sales ? "Sales" : "Purchase";
        Open("Integration" + ledger + "Menu", captionPrefix: path[0]);
        Submit();
        bool close = path[1] is "U" or "T";
        Open("Integration" + ledger + (close ? "Close" : "Post"), captionPrefix: path[1]);
        if (close)
        {
            Require(references, "Confirm end of Cycle Processing", "期末処理", typeof(ConfirmationScreen));
            return;
        }
        Confirm();
        if (current is not ReportScreen) throw new InvalidOperationException("転記帳票に到達しません: " + Describe());
        Show(((ReportScreen)current).Back!());
        Require(references, ledger + " Ledger System Menu", sales ? "売掛元帳" : "買掛元帳", typeof(MenuScreen));
    }

    private string[] Input() => runner.GetProperty("steps").EnumerateArray()
        .Where(s => s.TryGetProperty("text", out _)).Select(s => s.GetProperty("text").GetString()!).ToArray();

    private void Configure(string[] references)
    {
        string[] fields = Input().Single(s => s.Contains('\t')).TrimEnd('\r').Split('\t');
        Submit(("IrsRunDate", date));
        var client = books.Configuration().Client;
        var previousVat = references.Select(screen => Regex.Match(screen, @"VAT Rate  - \[(\d{4})\]")).Last(match => match.Success);
        string tax = (decimal.Parse(previousVat.Groups[1].Value, CultureInfo.InvariantCulture) / 100).ToString(CultureInfo.InvariantCulture);
        Submit(("IrsOperator", fields[0]), ("IrsTaxRate", tax),
            ("IrsClient", fields[2] + (fields[2].Length < client.Length ? client[fields[2].Length..] : "")),
            ("IrsAddressFirst", fields[3]), ("IrsAddressSecond", fields[4]),
            ("IrsAddressThird", fields[5]), ("IrsAddressFourth", fields[6]), ("IrsPeriodStart", ParseDate(fields[7])),
            ("IrsPeriodEnd", ParseDate(fields[8])), ("IrsPlatform", fields[9]), ("IrsPrinter", fields[10]));
    }

    private void SetupAccounts()
    {
        Open("IrsAccountsMenu", 2);
        if (current is ConfirmationScreen opening) Show(opening.Cancel());
        Open("IrsAccountCreate", 1);
        Submit(("IrsKeepAccounts", "N"));
        Confirm();
        var input = Input();
        var accounts = input.Single(s => s.EndsWith("00000\r", StringComparison.Ordinal)).Split('\r');
        for (int i = 0; i < accounts.Length && accounts[i] != "00000"; i += 4)
            Submit(("IrsAccountCode", accounts[i]), ("IrsAccountName", accounts[i + 2]), ("IrsAccountCategory", accounts[i + 3]));
        Show(new IrsScreens().CreateNavigation(books).Open!());
        Open("IrsDefaultsMenu", 3);
        Open("IrsDefaultCreate", 1);
        Submit(("IrsKeepDefaults", "N"));
        Submit();
        var defaults = input[^1].Split('\r');
        Submit(("IrsDefaultSlot01Account", defaults[0]), ("IrsDefaultSlot01Code", defaults[1]), ("IrsDefaultSlot01Tax", defaults[2]),
            ("IrsDefaultSlot30Account", defaults[4]), ("IrsDefaultSlot31Account", defaults[5]), ("IrsDefaultSlot32Account", defaults[6]));
    }

    private void Post()
    {
        var input = Input();
        Open("IrsPostingMenu", 4);
        Submit(("IrsPostingMode", input[1].Trim()));
        Submit();
        Confirm();
        Submit(("IrsPostingDefault", input[3].Trim()));
        Confirm();
        Submit(("IrsPostingSide", input[5].Trim()), ("IrsPostingDate", ParseDate(input[6].Trim())),
            ("IrsPostingAccount", input[7].Trim()), ("IrsPostingLegend", input[8].TrimEnd('\r')),
            ("IrsPostingAmount", input[9].Trim()), ("IrsPostingTax", input[10].Trim()));
    }

    private static DateTime ParseDate(string text) =>
        DateTime.ParseExact(text, ["dd/MM/yy", "dd/MM/yyyy"], CultureInfo.InvariantCulture, DateTimeStyles.None);

    private void Show(Screen next)
    {
        current = next;
        IEnumerable<string> labels = next switch
        {
            MenuScreen menu => menu.Items.Select(i => i.Label),
            FormScreen form => form.Fields.SelectMany(f => f is ChoiceField c
                ? c.Options.Select(o => o.Label).Prepend(f.Label) : [f.Label]).Append(form.SubmitLabel),
            ConfirmationScreen confirmation => [confirmation.Message, confirmation.ConfirmLabel],
            InformationScreen information => [information.Message],
            TableScreen table => table.Columns.Append(table.EmptyMessage),
            _ => []
        };
        var untranslated = labels.Prepend(next.Title).FirstOrDefault(label =>
            !Regex.IsMatch(label, @"^\d{2}　\d{5}　") && !Regex.IsMatch(label, @"^\d{5}　.+ を使用しますか。$") &&
            Regex.IsMatch(label, "[A-Za-z]{2,}"));
        if (untranslated is not null) throw new InvalidOperationException("画面の未翻訳文言: " + untranslated);
    }

    private void Open(string itemId, int? number = null, string? captionPrefix = null)
    {
        if (current is not MenuScreen menu) throw new InvalidOperationException("メニューに到達しません: " + Describe());
        var option = menu.Items.SingleOrDefault(i => i.Id == itemId && i.Number == number);
        if (option?.Open is null) throw new InvalidOperationException("メニュー項目が見つかりません: " + itemId);
        if (captionPrefix is not null && !option.Label.Normalize(NormalizationForm.FormKC).StartsWith(captionPrefix + " ", StringComparison.Ordinal))
            throw new InvalidOperationException("メニュー番号が一致しません: " + itemId);
        Show(option.Open());
    }

    private void Confirm()
    {
        if (current is not ConfirmationScreen confirmation) throw new InvalidOperationException("確認に到達しません: " + Describe());
        Show(confirmation.Confirm());
    }

    private void Submit(params (string Key, object? Value)[] entries)
    {
        if (current is not FormScreen form) throw new InvalidOperationException("入力画面に到達しません: " + Describe());
        var values = form.Fields.ToDictionary(f => f.Id, f => f switch
        {
            TextField text => (object?)text.Value, DateField dateField => dateField.Value, ChoiceField choice => choice.Value, _ => ""
        });
        foreach (var (key, value) in entries)
        {
            if (!values.ContainsKey(key)) throw new InvalidOperationException("入力項目が見つかりません: " + key);
            values[key] = value;
        }
        Show(form.Submit(new FormValues(values)));
    }

    private string Describe() => current.Title + (current is InformationScreen information ? " / " + information.Message : "");

    private void Require(string[] reference, string anchor, string title, Type type)
    {
        if (reference.Length == 0 || !reference[^1].Contains(anchor, StringComparison.Ordinal))
            throw new InvalidOperationException("最終証跡に照合文言がありません: " + anchor);
        if (current.Title != title || current.GetType() != type)
            throw new InvalidOperationException($"画面遷移の相違: 旧「{title}」 新「{Describe()}」");
    }

    private static readonly string[] RootOptions = ["", "IrsConfigurationMenu", "IrsAccountsMenu", "IrsDefaultsMenu",
        "IrsPostingMenu", "IrsTrialBalanceMenu", "IrsAuditMenu", "IrsFinalMenu", "IrsAmendmentMenu", "IrsAnalysisMenu"];

    private static readonly (string Id, string Anchor, string Title, Type Type)[] AccountOptions =
    [
        ("IrsAccountCreate", "Chart of Accounts Setup", "科目表登録", typeof(FormScreen)),
        ("IrsAccountAmend", "Chart of Accounts Amendments", "科目表変更", typeof(FormScreen)),
        ("IrsAccountList", "Incomplete Records System", "科目表表示", typeof(TableScreen)),
        ("IrsAccountPrint", "first time you are running IRS", "勘定科目表", typeof(ReportScreen)),
        ("IrsAccountExport", "This process will export", "科目表の書き出し", typeof(ConfirmationScreen)),
        ("IrsAccountImport", "This process will import", "科目表の取り込み", typeof(ConfirmationScreen))
    ];

    private static readonly (string Id, string Anchor, string Title, Type Type)[] DefaultOptions =
    [
        ("IrsDefaultCreate", "Default Accounts Setup", "既定勘定登録", typeof(FormScreen)),
        ("IrsDefaultAmend", "Default Accounts Amendments", "既定勘定変更", typeof(TableScreen)),
        ("IrsDefaultList", "Default Accounts Display", "既定勘定表示", typeof(TableScreen)),
        ("IrsDefaultPrint", "Default File Utilities", "転記の既定勘定", typeof(ReportScreen)),
        ("IrsFinalSettingsMenu", "Finished Accounts Setup", "決算書の見出し設定", typeof(FormScreen))
    ];
}
