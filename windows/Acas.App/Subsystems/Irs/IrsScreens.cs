using System.Globalization;
using Acas.App.Subsystems.Irs;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Irs;

[assembly: SubsystemScreensAttribute<IrsScreens>(60)]

namespace Acas.App.Subsystems.Irs;

public sealed partial class IrsScreens : ISubsystemScreens
{
    private const string RootTitle = "簡易記帳";
    private const string AccountsTitle = "勘定科目表";
    private const string DefaultsTitle = "既定勘定";
    private static readonly Choice[] YesNo = [new("N", "いいえ"), new("Y", "はい")];
    private static readonly Choice[] TaxOptions = [new("N", "対象外"), new("I", "仕入税"), new("O", "売上税")];

    public MenuItem CreateNavigation(Db database) => CreateNavigation(new IrsBookkeeping(database));

    public MenuItem CreateNavigation(IrsBookkeeping books)
    {
        MenuItem[] items = RootItems(books);
        return new("IrsNavigation", RootTitle, Children: items.Select(item =>
            new MenuItem(item.Id + "Navigation", item.Caption, Open: item.Open)).ToArray(),
            Open: () => Guard(RootTitle, () => books.Configured ? new MenuScreen(RootTitle, items) : Configure(books)));
    }

    private MenuItem[] RootItems(IrsBookkeeping books) =>
    [
        new("IrsConfigurationMenu", "システム設定・保守", 1, Open: () => Guard(RootTitle, () => Configure(books))),
        new("IrsAccountsMenu", "勘定科目の設定・保守", 2, Open: () => Guard(AccountsTitle, () => OpenAccounts(books))),
        new("IrsDefaultsMenu", "既定勘定の設定・保守", 3, Open: () => DefaultsMenu(books)),
        new("IrsPostingMenu", "仕訳転記", 4, Open: () => PostingMenu(books)),
        new("IrsTrialBalanceMenu", "試算表", 5, Open: () => TrialBalance(books)),
        new("IrsAuditMenu", "監査証跡", 6, Open: () => Audit(books)),
        new("IrsFinalMenu", "決算書作成", 7, Open: () => FinalAccounts(books)),
        new("IrsAmendmentMenu", "転記修正", 8, Open: () => books.HasJournal
            ? Guard("転記修正", () => Amendments(books)) : MissingJournal(books, "転記修正")),
        new("IrsAnalysisMenu", "分析帳票", 9, Open: () => books.HasJournal
            ? Guard("分析帳票", () => Analysis(books)) : MissingJournal(books, "分析帳票")),
        new("IrsRebuildMenu", "Ａ　勘定残高の再計算", Open: () => Rebuild(books)),
        new("IrsExitMenu", "Ｘ　終了", Open: () => new InformationScreen(RootTitle, "簡易記帳を終了しました。左側の業務メニューを選択してください。"))
    ];

    private Screen Root(IrsBookkeeping books) => new MenuScreen(RootTitle, RootItems(books));

    private ConfirmationScreen MissingJournal(IrsBookkeeping books, string title) =>
        new(title, "転記ファイルを開けません（状態番号35）。", "確認", () => Root(books), () => Root(books));

    private static Screen Guard(string title, Func<Screen> action)
    {
        try { return action(); }
        catch (IrsException ex) { return new InformationScreen(title, ex.Message); }
    }

    private static Screen Done(string title) => new InformationScreen(title, "処理が完了しました。");

    private static FormScreen Form(string title, IReadOnlyList<Field> fields, string submitLabel, Func<FormValues, Screen> submit) =>
        new(title, fields, submitLabel, input => Guard(title, () => submit(input)));

    private static TextField Text(string id, string label, string value, int size) => new(id, label, value, size);

    private static string Code(int value, int width = 5) => value.ToString(new string('0', width), CultureInfo.InvariantCulture);
    private static int Number(string value, int max)
    {
        if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out int result) || result > max)
            throw new IrsException("有効な番号を入力してください。");
        return result;
    }

    private static decimal Amount(string value)
    {
        if (!decimal.TryParse(value, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out decimal amount) || decimal.Round(amount, 2) != amount)
            throw new IrsException("数値は小数点以下二桁以内で入力してください。");
        return amount;
    }

    private static DateTime Date(FormValues values, string id) =>
        values.Date(id) ?? throw new IrsException("日付を選択してください。");

    private static string TaxName(string code) => TaxOptions.FirstOrDefault(x => x.Value == code)?.Label ?? "";
    private static string Category(string code) => code switch
    {
        "A" => "収益", "E" => "費用", "R" => "資産", "U" => "負債",
        "C" => "資本", _ => "その他"
    };

    private static FormScreen Configure(IrsBookkeeping books) => Form("システム設定・保守",
        [new DateField("IrsRunDate", "処理日", books.Configuration().Date),
         new PasswordField("IrsOldPassword", "現在の暗証番号", 4)], "次へ", values =>
        {
            string password = values.Text("IrsOldPassword");
            DateTime date = Date(values, "IrsRunDate");
            if (!books.CheckPassword(password)) throw new IrsException("暗証番号が一致しません。");
            return ConfigurationDetails(books, date, password);
        });

    private static FormScreen ConfigurationDetails(IrsBookkeeping books, DateTime date, string password)
    {
        var settings = books.Configuration();
        return Form("システム設定の詳細",
            [new PasswordField("IrsNewPassword", "新しい暗証番号（空欄のままなら変更なし）", 4),
             Text("IrsOperator", "担当者名", settings.Operator, 24),
             Text("IrsTaxRate", "付加価値税率（％）", settings.Tax.ToString("0.00", CultureInfo.InvariantCulture), 5),
             Text("IrsClient", "依頼主名", settings.Client, 24),
             Text("IrsAddressFirst", "住所１", settings.Address1, 24),
             Text("IrsAddressSecond", "住所２", settings.Address2, 24),
             Text("IrsAddressThird", "住所３", settings.Address3, 24),
             Text("IrsAddressFourth", "住所４", settings.Address4, 24),
             new DateField("IrsPeriodStart", "会計期間の開始日", settings.Start),
             new DateField("IrsPeriodEnd", "会計期間の終了日", settings.End),
             new ChoiceField("IrsPlatform", "旧環境の種別",
                Enumerable.Range(1, 6).Select(n => new Choice(Code(n, 1), $"環境 {n}")).ToArray(),
                settings.Platform == 0 ? null : Code(settings.Platform, 1)),
             Text("IrsPrinter", "印刷先の名称", settings.Printer, 32)],
            "保存", v =>
            {
                string next = v.Text("IrsNewPassword");
                books.Configure(new(date, v.Text("IrsOperator"), Amount(v.Text("IrsTaxRate")), v.Text("IrsClient"),
                    v.Text("IrsAddressFirst"), v.Text("IrsAddressSecond"), v.Text("IrsAddressThird"), v.Text("IrsAddressFourth"),
                    Date(v, "IrsPeriodStart"), Date(v, "IrsPeriodEnd"), Number(v.Choice("IrsPlatform") ?? "", 6),
                    v.Text("IrsPrinter")), password, next == "" ? password : next);
                return Done("システム設定の詳細");
            });
    }

    private Screen OpenAccounts(IrsBookkeeping books) => books.NeedsOpeningBalanceDecision
        ? new ConfirmationScreen("初回の残高確認", "転記ファイルがありません。既存の勘定残高を消去します。この操作は元に戻せません。",
            "残高を消去", () => Guard(AccountsTitle, () => { books.ClearBalances(); return AccountsMenu(books); }),
            () => AccountsMenu(books))
        : AccountsMenu(books);

    private MenuScreen AccountsMenu(IrsBookkeeping books) => new(AccountsTitle,
        [new("IrsAccountCreate", "科目表登録", 1, Open: () => AccountCreate(books)),
         new("IrsAccountAmend", "科目表変更", 2, Open: () => AccountForm(books, true)),
         new("IrsAccountList", "科目表表示", 3, Open: () => Guard(AccountsTitle, () => AccountList(books))),
         new("IrsAccountPrint", "科目表印刷", 4, Open: () => Guard(AccountsTitle, () => Report(books, books.AccountReport(), () => OpenAccounts(books)))),
         new("IrsAccountExport", "科目表の書き出し", 5, Open: () => Export(books)),
         new("IrsAccountImport", "科目表の取り込み", 6, Open: () => Import(books)),
         new("IrsAccountsBack", "簡易記帳メニューへ戻る", 9, Open: () => Root(books))]);

    private Screen AccountCreate(IrsBookkeeping books) => Form("科目表登録",
        [new ChoiceField("IrsKeepAccounts", "既存科目表に追加する", YesNo, "Y")],
        "次へ", v => v.Choice("IrsKeepAccounts") == "N"
            ? new ConfirmationScreen("科目表の置き換え確認", "既存の科目表を置き換えます。この操作は元に戻せません。",
                "置き換える", () => AuthorizeAccountReset(books), () => AccountCreate(books))
            : AccountForm(books, false));

    private static FormScreen AuthorizeAccountReset(IrsBookkeeping books) => Form("科目表の置き換え",
        [new PasswordField("IrsAccountResetPassword", "暗証番号", 4)], "認証", v =>
            books.CheckPassword(v.Text("IrsAccountResetPassword"))
                ? AccountForm(books, false, reset: true)
                : throw new IrsException("暗証番号が一致しません。"));

    private static FormScreen AccountForm(IrsBookkeeping books, bool amend, IrsAccount? current = null, bool reset = false, bool loaded = false)
    {
        string title = amend ? "科目表変更" : "科目表登録";
        List<Field> fields =
        [
            Text("IrsAccountCode", "主勘定コード", current is null ? "" : Code(current.Code), 5),
            Text("IrsSubAccountCode", "補助勘定コード（任意）", current is null || current.SubAccount == 0 ? "" : Code(current.SubAccount), 5)
        ];
        if (!amend || loaded)
        {
            fields.Add(Text("IrsAccountName", "勘定名", current?.Name ?? "", 24));
            fields.Add(new ChoiceField("IrsAccountCategory", "勘定区分",
                Enumerable.Range('A', 26).Select(n => ((char)n).ToString()).Select(key =>
                    new Choice(key, $"区分 {key}　{Category(key)}")).ToArray(), current?.Category));
        }
        return Form(title, fields, amend && !loaded ? "照会" : "保存", v =>
        {
            int code = Number(v.Text("IrsAccountCode"), 99999);
            string subValue = v.Text("IrsSubAccountCode");
            int sub = subValue == "" ? 0 : Number(subValue, 99999);
            if (amend && !loaded)
            {
                var item = books.Accounts().FirstOrDefault(a => a.Code == code && a.SubAccount == sub)
                    ?? throw new IrsException("勘定が見つかりません。");
                return AccountForm(books, true, item, loaded: true);
            }
            if (current is not null && (code != current.Code || sub != current.SubAccount))
                throw new IrsException("変更する勘定コードは照会時から変更できません。");
            books.SaveAccount(code, sub, v.Text("IrsAccountName"), v.Choice("IrsAccountCategory") ?? "", amend, reset);
            return amend ? Done(title) : AccountForm(books, false);
        });
    }

    private static TableScreen AccountList(IrsBookkeeping books) => new("科目表表示", "IrsAccountGrid",
        ["主勘定", "補助勘定", "勘定名", "勘定区分"], books.Accounts().Select(a =>
            new TableRow([Code(a.Code), a.SubAccount == 0 ? "" : Code(a.SubAccount), a.Name, Category(a.Category)],
                () => AccountForm(books, true, a, loaded: true))).ToArray());

    private MenuScreen DefaultsMenu(IrsBookkeeping books) => new(DefaultsTitle,
        [new("IrsDefaultCreate", "既定勘定登録", 1, Open: () => DefaultsSetup(books)),
         new("IrsDefaultAmend", "既定勘定変更", 2, Open: () => Guard(DefaultsTitle, () => DefaultsList(books, true))),
         new("IrsDefaultList", "既定勘定表示", 3, Open: () => Guard(DefaultsTitle, () => DefaultsList(books, false))),
         new("IrsDefaultPrint", "既定勘定印刷", 4, Open: () => Guard(DefaultsTitle, () => Report(books, books.DefaultReport(), () => DefaultsMenu(books)))),
         new("IrsFinalSettingsMenu", "決算書の見出し設定", 5, Open: () => Guard(DefaultsTitle, () => FinalSettings(books))),
         new("IrsDefaultsBack", "簡易記帳メニューへ戻る", 9, Open: () => Root(books))]);

    private Screen DefaultsSetup(IrsBookkeeping books) => Form("既定勘定登録",
        [new ChoiceField("IrsKeepDefaults", "既存の既定勘定に追加する", YesNo, "Y")],
        "次へ", v => v.Choice("IrsKeepDefaults") == "N"
            ? Password("既定勘定の置き換え", "IrsDefaultsPassword", books, () => DefaultsForm(books, books.Defaults(true), true),
                () => DefaultsSetup(books))
            : DefaultsForm(books, books.Defaults(), false));

    private static TableScreen DefaultsList(IrsBookkeeping books, bool amend)
    {
        var entries = books.Defaults();
        return new(amend ? "既定勘定変更" : "既定勘定表示", amend ? "IrsDefaultEditGrid" : "IrsDefaultGrid",
            ["番号", "勘定コード", "勘定名", "取引区分", "付加価値税"], entries.Select(d =>
                new TableRow([Code(d.Slot, 2), d.Account == 0 ? "" : Code(d.Account), d.Name,
                    d.Account == 0 ? "" : d.Code, TaxName(d.Tax)], amend ? () => DefaultsForm(books, [d], false) : null)).ToArray());
    }

    private static FormScreen DefaultsForm(IrsBookkeeping books, IReadOnlyList<IrsDefault> entries, bool reset)
    {
        string Id(int slot) => "IrsDefaultSlot" + Code(slot, 2);
        var fields = new List<Field>();
        foreach (var entry in entries)
        {
            var id = Id(entry.Slot);
            string slot = Code(entry.Slot, 2);
            string label = entry.Slot switch { 30 => "期首残高", 31 => "仕入税勘定", 32 => "売上税勘定", _ => $"既定勘定 {slot}" };
            fields.Add(Text(id + "Account", label + "の勘定コード", entry.Account == 0 ? "" : Code(entry.Account), 5));
            if (entry.Slot >= 30) continue;
            fields.Add(Text(id + "Code", $"取引区分 {slot}", entry.Account == 0 ? "" : entry.Code, 2));
            fields.Add(new ChoiceField(id + "Tax", $"付加価値税 {slot}", TaxOptions, entry.Tax == "0" ? "N" : entry.Tax));
        }
        string title = entries.Count == 1 ? "既定勘定変更" : "既定勘定登録";
        return Form(title, fields, "保存", v =>
        {
            books.SaveDefaults(entries.Select(entry =>
            {
                var id = Id(entry.Slot);
                var account = v.Text(id + "Account");
                return entry with
                {
                    Account = account == "" ? 0 : Number(account, 99999),
                    Code = entry.Slot >= 30 ? entry.Code : v.Text(id + "Code"),
                    Tax = entry.Slot >= 30 ? entry.Tax : v.Choice(id + "Tax") ?? "N"
                };
            }), reset);
            return DefaultsList(books, true);
        });
    }

    private static Screen Password(string title, string id, IrsBookkeeping books, Func<Screen> next, Func<Screen> cancel)
        => Form(title, [new PasswordField(id, "暗証番号", 4)], "認証", v =>
            books.CheckPassword(v.Text(id)) ? next() : new ConfirmationScreen(title, "暗証番号が一致しません。",
                "再入力", () => Password(title, id, books, next, cancel), cancel));

    private static ReportScreen Report(IrsBookkeeping books, IrsReport report, Func<Screen> back)
    {
        books.SaveReport(report);
        return new(report.Title, report.Body, back);
    }
}
