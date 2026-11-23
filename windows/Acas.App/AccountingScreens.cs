using System.Globalization;
using Acas.Core;
using Acas.Core.Engine;
using NavigationItem = Acas.Core.MenuItem;

namespace Acas.App;

internal sealed partial class AccountingScreens(Db database)
{
    private readonly SystemSettings _settings = new(database);
    private readonly GeneralLedger _ledger = new(database);
    private readonly LedgerReports _ledgerReports = new(database);
    private readonly JournalEntry _journal = new(database);
    private readonly JournalBatches _batches = new(database);
    private static readonly Choice[] YesNo = [new("Y", "使用する"), new("N", "使用しない")];
    private static readonly Choice[] Types = [new("0", "見出し"), new("1", "明細"), new("9", "特別")];
    private static readonly Choice[] Levels = Enumerable.Range(1, 4).Select(i => new Choice(i.ToString(), i.ToString())).ToArray();
    private static readonly string[] Classes = ["直接収益", "直接原価", "雑収益", "間接原価", "固定資産", "流動資産", "流動負債", "資本"];
    private static readonly Choice[] Placements = Enumerable.Range('A', 26)
        .Select(i => new Choice(((char)i).ToString(), $"{Classes[PlacementIndex((char)i)]}・区分 {i - 'A' + 1}"))
        .ToArray();
    private static readonly Choice[] Taxes = [new("I", "税込"), new("O", "税別"), new("N", "対象外")];

    public IReadOnlyList<NavigationItem> Navigation() =>
    [
        new("MenuGeneral", "総勘定元帳", Children:
        [
            new("MenuGeneralDate", "処理日入力", Open: () => EnterGeneral(RunDate)),
            new("MenuChart", "勘定科目管理", Open: () => EnterGeneral(ChartMenu)),
            new("MenuDefaults", "既定勘定の管理", Open: () => EnterGeneral(DefaultsMenu)),
            new("MenuJournalEntry", "仕訳入力", Open: () => EnterGeneral(JournalMenu)),
            new("MenuJournalProof", "仕訳の検証・修正", Open: () => EnterGeneral(JournalProofMenu)),
            new("MenuBatchStatus", "バッチ状況帳票", Open: () => EnterGeneral(BatchStatusMenu)),
            new("MenuJournalPost", "仕訳転記", Open: () => EnterGeneral(JournalPostMenu)),
            new("MenuJournalClose", "会計期間の締め", Open: () => EnterGeneral(JournalCloseMenu)),
            new("MenuTrialBalance", "試算表", Open: () => EnterGeneral(TrialBalanceMenu)),
            new("MenuArchivedLedger", "元帳印刷", Open: () => EnterGeneral(ArchivedLedgerMenu)),
            new("MenuFinancialStatements", "決算書印刷", Open: () => EnterGeneral(FinancialStatements)),
            new("MenuGeneralSettings", "共通設定", Open: SettingsMenu)
        ], Open: () => EnterGeneral(RunDate)),
        new("MenuSettings", "システム設定", Children:
        [
            new("MenuCompanySetup", "会社の初期登録", Open: () => _settings.Read() == null ? Setup() : Settings()),
            new("MenuCompanyParameters", "会社・期間設定", Open: () => Settings()),
            new("MenuOperatingParameters", "運用環境設定", Open: () => OperatingSettings()),
            new("MenuGeneralLedgerParameters", "総勘定元帳の設定", Open: () => GeneralLedgerSettings()),
            new("MenuSettingsReport", "設定内容の印刷", Open: SettingsReportMenu)
        ], Open: SettingsMenu)
    ];

    public Screen Start() => _settings.Read() == null ? Setup() :
        new InformationScreen("業務メニュー", "左側のメニューから操作を選択してください。");

    private Screen Setup(string name = "", CompanySetup? model = null, string? error = null)
    {
        return new FormScreen("会社の初期登録",
        [
            new TextField("CompanyName", "会社名", name, 32),
            new PasswordField("PeriodPassword", "締め処理用の暗証文字（半角英字４文字）", 4),
            Toggle("EnableGeneral", "総勘定元帳", model?.General ?? true),
            Toggle("EnablePurchasing", "買掛元帳", model?.Purchasing ?? true),
            Toggle("EnableSales", "売掛元帳", model?.Sales ?? true),
            Toggle("EnableInvoicing", "請求書発行", model?.Invoicing ?? true),
            Toggle("EnableStock", "在庫管理", model?.Stock ?? true),
            Toggle("EnableOrders", "受注管理", model?.Orders ?? true)
        ], "確認へ", values =>
        {
            var draft = new CompanySetup(values.Text("CompanyName"), values.Text("PeriodPassword"),
                Enabled(values, "EnableGeneral"), Enabled(values, "EnableSales"), Enabled(values, "EnablePurchasing"),
                Enabled(values, "EnableInvoicing"), Enabled(values, "EnableStock"), Enabled(values, "EnableOrders"));
            return new ConfirmationScreen("会社の初期登録", $"「{draft.Name}」を新規登録しますか。", "登録",
                () => _settings.Initialize(draft, DateTime.Today) ? Settings() :
                    Setup(draft.Name, draft with { PeriodPassword = "" }, "会社名と暗証文字を確認してください。"),
                () => Setup(draft.Name, draft with { PeriodPassword = "" }));
        }, Error: error);
    }

    private Screen Settings(CompanyParameters? draft = null, string? error = null)
    {
        if (_settings.Read() is not { } system) return Setup();
        var contact = draft?.Contact ?? new CompanyContact(system.St("Address-1"), system.St("Address-2"),
            system.St("Address-3"), system.St("Address-4"), system.St("Post-Code"), system.St("Country"), system.St("VAT-Reg-Number"));
        return new FormScreen("会社・期間設定",
        [
            new TextField("ParameterName", "会社名", draft?.Name ?? system.St("Usera"), 32),
            new TextField("Address1", "住所１", contact.Address1, 24),
            new TextField("Address2", "住所２", contact.Address2, 24),
            new TextField("Address3", "住所３", contact.Address3, 24),
            new TextField("Address4", "住所４", contact.Address4, 24),
            new TextField("PostalCode", "郵便番号", contact.PostCode, 12),
            new TextField("Country", "国", contact.Country, 24),
            new TextField("TaxRegistration", "税登録番号", contact.TaxRegistration, 11),
            new DateField("PeriodStart", "期首日", draft?.Start ?? SystemSettings.Date(system, "Start-Date")),
            new DateField("PeriodEnd", "期末日", draft?.End ?? SystemSettings.Date(system, "End-Date")),
            new TextField("CurrentCycle", "現在の会計期間", (draft?.Cycle ?? system.I("Cyclea")).ToString(), 2),
            new TextField("CyclePeriod", "周期区分（３：月次、６：隔週、１３：週次）", (draft?.Period ?? system.I("Period")).ToString(), 2),
            new TextField("PageLines", "帳票の１ページあたりの行数", (draft?.PageLines ?? system.I("Page-Lines")).ToString(), 2),
            new ChoiceField("DateFormat", "保存データの日付順",
                [new("1", "日・月・年"), new("2", "月・日・年"), new("3", "年・月・日")],
                (draft?.DateFormat ?? Math.Clamp(system.I("Date-Form"), 1, 3)).ToString()),
            Toggle("SalesStockLink", "売掛と在庫の連携", draft?.SalesStockLink ?? system.S("SL-Stock-Link") == "Y")
        ], "確認へ", values =>
        {
            if (values.Date("PeriodStart") is not { } start || values.Date("PeriodEnd") is not { } end ||
                !Number(values.Text("CurrentCycle"), out int cycle) || !Number(values.Text("CyclePeriod"), out int period) ||
                !Number(values.Text("PageLines"), out int lines) || !Number(values.Choice("DateFormat"), out int format))
                return Settings(draft, "日付と数値の入力内容を確認してください。");
            var parameters = new CompanyParameters(values.Text("ParameterName"), start, end,
                cycle, period, lines, format, Enabled(values, "SalesStockLink"),
                new(values.Text("Address1"), values.Text("Address2"), values.Text("Address3"), values.Text("Address4"),
                    values.Text("PostalCode"), values.Text("Country"), values.Text("TaxRegistration")));
            if (lines < 29) return Settings(parameters with { PageLines = 48 }, "帳票の行数は２９以上を指定してください。");
            return new ConfirmationScreen("会社・期間設定", "入力した設定を保存しますか。", "保存",
                () => _settings.SaveParameters(parameters) ? new InformationScreen("会社・期間設定", "設定を保存しました。") :
                    Settings(parameters, "設定内容を確認してください。"),
                () => Settings(parameters));
        }, SettingsMenu, error);
    }

    private Screen EnterGeneral(Func<Screen> open)
    {
        if (_settings.Read() is not { } system) return Setup();
        if (system.I("Cyclea") == 0) return Settings();
        if (system.I("Level-1") != 1) return new InformationScreen("総勘定元帳", "総勘定元帳は使用しない設定です。");
        return open();
    }

    private Screen RunDate() => RunDate(null);

    private FormScreen RunDate(string? error) => new("総勘定元帳・処理日入力",
        [new DateField("RunDate", "処理日", DateTime.Today)], "確定",
        values => values.Date("RunDate") is { } date && _settings.SetRunDate(date)
            ? GeneralMenu() : RunDate("有効な処理日を入力してください。"), Error: error);

    private Screen GeneralMenu() => new MenuScreen("総勘定元帳",
    [
        new("GeneralDate", "処理日入力", Open: RunDate),
        new("GeneralChart", "勘定科目管理", Open: ChartMenu),
        new("GeneralDefaults", "既定勘定の管理", Open: DefaultsMenu),
        new("GeneralJournalEntry", "仕訳入力", Open: JournalMenu),
        new("GeneralJournalProof", "仕訳の検証・修正", Open: JournalProofMenu),
        new("GeneralBatchStatus", "バッチ状況帳票", Open: BatchStatusMenu),
        new("GeneralJournalPost", "仕訳転記", Open: JournalPostMenu),
        new("GeneralJournalClose", "会計期間の締め", Open: JournalCloseMenu),
        new("GeneralTrialBalance", "試算表", Open: TrialBalanceMenu),
        new("GeneralArchivedLedger", "元帳印刷", Open: ArchivedLedgerMenu),
        new("GeneralFinancialStatements", "決算書印刷", Open: FinancialStatements),
        new("GeneralSettings", "共通設定", Open: SettingsMenu)
    ]);

    private Screen ChartMenu()
    {
        var system = _settings.Read();
        int first = system?.S("P-C") is "P" or "B" ? 2 : 1;
        int display = first + (system?.S("Ledger-2nd-Index") == "Y" ? 3 : 2);
        return new MenuScreen("勘定科目管理",
        [
            new("ChartAdd", "科目登録", first, Open: () => AccountForm(null)),
            new("ChartEdit", "科目変更・削除", first + 1, Open: () => AccountLookup(true)),
            new("ChartList", "科目一覧表示", display, Open: () => AccountLookup(false)),
            new("ChartBack", "総勘定元帳に戻る", 9, Open: GeneralMenu)
        ]);
    }

    private Screen AccountLookup(bool edit, string? error = null) => new FormScreen(
        edit ? "科目変更・削除" : "科目一覧表示",
        edit ? CodeFields(null) : [new TextField("StartAccount", "照会を開始する勘定コード", "", 6)],
        edit ? "検索" : "表示", values =>
        {
            if (edit)
            {
                if (ReadCode(values) is { } code && _ledger.Find(code) is { } account)
                    return new MenuScreen("科目変更・削除",
                    [
                        new("UpdateAccount", "選択した科目を変更", Open: () => AccountForm(account, true)),
                        new("DeleteAccount", "選択した科目を削除", Open: () => DeleteAccount(account)),
                        new("AccountLookupBack", "検索に戻る", Open: () => AccountLookup(true))
                    ]);
                return AccountLookup(true, "指定された勘定科目は存在しません。");
            }
            var start = values.Text("StartAccount");
            if (start.Length > 0 && !Number(start, out _)) return AccountLookup(false, "勘定コードは数字で入力してください。");
            return Accounts(start.PadLeft(6, '0'));
        }, ChartMenu, error);

    private Screen Accounts(string start) => new TableScreen("勘定科目一覧", "AccountList",
        ["勘定コード", "部門", "科目名", "種類", "配置", "階層", "残高"],
        _ledger.Accounts().Where(a => string.CompareOrdinal(a.Code.Number, start) >= 0)
            .Select(a => new Acas.Core.TableRow([a.Code.Number, a.Code.Division.ToString("00"), a.Name,
                Kind(a.Type), a.Placement == ' ' ? "" : Classes[PlacementIndex(a.Placement)],
                a.Level.ToString(), a.Balance.ToString("N2")])).ToArray());

    private Screen AccountForm(Account? draft, bool edit = false, string? error = null)
    {
        var fields = edit ? new List<Field>() : CodeFields(draft?.Code).ToList();
        fields.AddRange([
            new TextField("AccountName", "科目名", draft?.Name ?? "", 24),
            new ChoiceField("AccountType", "種類", Types, (draft?.Type ?? 0).ToString()),
            new ChoiceField("AccountPlacement", "配置", Placements, draft is { Placement: >= 'A' and <= 'Z' } ? draft.Placement.ToString() : "A"),
            new ChoiceField("AccountLevel", "階層", Levels, Math.Clamp(draft?.Level ?? 1, 1, 4).ToString())
        ]);
        return new FormScreen(edit ? "科目変更" : "科目登録", fields, edit ? "変更" : "登録", values =>
        {
            var code = edit ? draft?.Code : ReadCode(values);
            if (code == null || _settings.Read() is not { } system ||
                !Number(values.Choice("AccountType"), out int type) || !Number(values.Choice("AccountLevel"), out int level))
                return AccountForm(draft, edit, "勘定コードと入力内容を確認してください。");
            var account = new Account(code.Value, values.Text("AccountName"), type, values.Choice("AccountPlacement")![0], level);
            var result = edit ? _ledger.Amend(system, account) : _ledger.Register(system, account);
            return result == AccountError.None
                ? new InformationScreen(edit ? "科目変更" : "科目登録", edit ? "科目を変更しました。" : "科目を登録しました。")
                : AccountForm(account, edit, AccountMessage(result));
        }, ChartMenu, error);
    }

    private Screen DeleteAccount(Account account) => new ConfirmationScreen("勘定科目の削除",
        $"「{account.Name}」を削除しますか。", "削除", () =>
        {
            var result = _ledger.Delete(account.Code);
            return new InformationScreen("勘定科目の削除", result == AccountError.None ? "科目を削除しました。" : AccountMessage(result));
        }, () => AccountLookup(true));

    private IReadOnlyList<Field> CodeFields(AccountCode? code)
    {
        var fields = new List<Field>
        {
            new TextField("LedgerCode", "勘定番号", code?.Ledger.ToString("0000") ?? "", 4),
            new TextField("SubCode", "補助番号", code?.Sub.ToString("00") ?? "00", 2)
        };
        if (_settings.Read()?.S("P-C") is "P" or "B")
            fields.Add(new TextField("DivisionCode", "部門コード", code?.Division.ToString("00") ?? "00", 2));
        return fields;
    }

    private AccountCode? ReadCode(FormValues values)
    {
        if (!Number(values.Text("LedgerCode"), out int ledger) || !Number(values.Text("SubCode"), out int sub))
            return null;
        int division = 0;
        if (_settings.Read()?.S("P-C") is "P" or "B" && !Number(values.Text("DivisionCode"), out division)) return null;
        return new AccountCode(ledger, sub, division);
    }

    private Screen DefaultsMenu() => new MenuScreen("既定勘定の管理",
    [
        new("DefaultsEdit", "既定勘定修正", 2, Open: () => DefaultAccounts(true)),
        new("DefaultsList", "既定勘定表示", 3, Open: () => DefaultAccounts(false)),
        new("DefaultsBack", "総勘定元帳に戻る", 9, Open: GeneralMenu)
    ]);

    private Screen DefaultAccounts(bool edit) => new TableScreen("既定勘定一覧", "DefaultAccountList",
        ["番号", "勘定コード", "取引区分", "税区分"], _settings.DefaultAccounts()
            .Select(a => new Acas.Core.TableRow([a.Number.ToString(), a.Code.ToString("0000.00"), a.Reference, Taxes.FirstOrDefault(t => t.Value == a.Tax)?.Label ?? ""],
                edit ? () => EditDefault(a) : null)).ToArray());

    private Screen EditDefault(DefaultAccount account, string? error = null) => new FormScreen("既定勘定修正",
    [
        new TextField("DefaultAccountCode", "勘定コード", account.Code.ToString("0000.00"), 7),
        new TextField("DefaultAccountReference", "取引区分", account.Reference, 2),
        new ChoiceField("DefaultAccountTax", "税区分", Taxes, account.Tax.Length == 0 ? "N" : account.Tax)
    ], "保存", values =>
    {
        return decimal.TryParse(values.Text("DefaultAccountCode"), NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out decimal code)
            && _settings.AmendDefault(account with { Code = code, Reference = values.Text("DefaultAccountReference"), Tax = values.Choice("DefaultAccountTax") ?? "" })
            ? DefaultAccounts(true) : EditDefault(account, "既定勘定の入力内容を確認してください。");
    }, () => DefaultAccounts(true), error);

    private static int PlacementIndex(char ch) => ch < 'E' ? 0 : ch < 'I' ? 1 : ch < 'K' ? 2 : ch < 'O' ? 3 : ch < 'R' ? 4 : ch < 'U' ? 5 : ch < 'W' ? 6 : 7;
    private static string Kind(int t) => t switch { 0 => "見出し", 1 => "明細", 2 => "売掛", 3 => "買掛", 9 => "特別", _ => "不明" };
    private static bool Enabled(FormValues values, string id) => values.Choice(id) == "Y";
    private static ChoiceField Toggle(string id, string label, bool value) => new(id, label, YesNo, value ? "Y" : "N");
    private static bool Number(string? text, out int value) => int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out value);

    private static string AccountMessage(AccountError error) => error switch
    {
        AccountError.ReservedCode => "９９９９は予約済みです。",
        AccountError.TradeCode => "売掛・買掛の予約範囲は指定できません。",
        AccountError.InvalidDivision => "登録済みの部門コードを指定してください。",
        AccountError.InvalidName => "科目名は既存データで保存できる文字と桁数で入力してください。",
        AccountError.InvalidType => "種類の指定が無効です。",
        AccountError.InvalidPlacement => "配置の指定が無効です。",
        AccountError.InvalidLevel => "階層は１～４の範囲で指定してください。",
        AccountError.MissingHeader => "上位の見出し勘定がありません。",
        AccountError.MissingAccount => "指定された勘定科目は存在しません。",
        AccountError.Duplicate => "指定された勘定科目はすでに登録されています。",
        AccountError.NonzeroBalance => "残高がゼロでない勘定科目は削除できません。",
        _ => "勘定番号は１０００以上を指定してください。"
    };
}
