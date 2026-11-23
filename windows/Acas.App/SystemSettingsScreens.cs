using System.Globalization;
using Acas.Core;
using Acas.Core.Engine;

namespace Acas.App;

internal sealed partial class AccountingScreens
{
    private Screen SettingsMenu() => new MenuScreen("システム設定",
    [
        new("SettingsCompany", "会社・期間設定", Open: () => Settings()),
        new("SettingsOperating", "運用環境設定", Open: () => OperatingSettings()),
        new("SettingsLedger", "総勘定元帳の設定", Open: () => GeneralLedgerSettings()),
        new("SettingsSubledgers", "補助台帳の設定", Open: SubledgerSettingsMenu),
        new("SettingsPrint", "設定内容の印刷", Open: SettingsReportMenu)
    ]);

    private sealed record SubledgerField(string Key, string Label, int Width, decimal Maximum = 0, string? Options = null);

    private static readonly SubledgerField[] PayableSettings =
    [
        new("PL-Delim", "住所区切り", 1), new("PL-Stock-Link", "買掛と在庫の連携", 1, Options: "YN"),
        new("BL-Next-Batch", "次回バッチ番号", 5, short.MaxValue), new("BL-Pay-Ac", "支払勘定", 6, 999999),
        new("BL-Purch-Ac", "仕入元帳勘定", 6, 999999), new("P-Creditors", "買掛金勘定", 6, 999999)
    ];

    private static readonly SubledgerField[] ReceivableSettings =
    [
        new("SL-Dunning", "督促状", 1, Options: "10"), new("SL-Charges", "延滞料", 1, Options: "10"),
        new("SL-Credit", "支払期限（日）", 2, 99), new("SL-Disc", "標準値引率", 5, 99.99m),
        new("SL-Min", "延滞対象最低残高", 4, 9999), new("SL-Max", "延滞料上限", 4, 9999),
        new("SL-Limit", "標準与信限度額", 7, 9999999), new("SL-Delim", "住所区切り", 1),
        new("SL-Own-Nos", "請求書番号を手入力", 1, Options: "YN"), new("SL-Late-Per", "延滞料率", 5, 99.99m),
        new("First-Sl-Batch", "次回バッチ番号", 5, short.MaxValue),
        new("SL-Stock-Link", "売掛と在庫の連携", 1, Options: "YN"),
        new("SL-Pay-Ac", "入金勘定", 6, 999999), new("SL-Sales-Ac", "売上元帳勘定", 6, 999999),
        new("S-Debtors", "売掛金勘定", 6, 999999),
        new("SL-Comp-Head-Inv", "請求書の社名印刷", 1, Options: "YN"),
        new("SL-Comp-Head-Stat", "取引明細書の社名印刷", 1, Options: "YN"),
        new("SL-Comp-Head-Lets", "督促状の社名印刷", 1, Options: "YN"),
        new("SL-Comp-Head-Pick", "納品書の社名印刷", 1, Options: "YN")
    ];

    private static readonly SubledgerField[] InventorySettings =
    [
        new("Stk-Debug", "デバッグ", 1, Options: "10"), new("Stk-Manu-Used", "製造管理", 1, Options: "10"),
        new("Stk-OE-Used", "受注管理", 1, Options: "10"), new("Stk-Audit-Used", "在庫監査", 1, Options: "10"),
        new("Stk-Mov-Audit", "在庫移動監査", 1, Options: "10"),
        new("Stk-Period-Cur", "当期区分", 1, Options: "MQW"),
        new("Stk-Period-dat", "累計区分", 1, Options: "YMQ"),
        new("Stk-Averaging", "平均原価", 1, Options: "10"), new("Stk-Activity-Rep-Run", "活動帳票作成済み", 1, Options: "10"),
        new("Stk-Audit-No", "在庫監査番号", 3, byte.MaxValue)
    ];

    private Screen SubledgerSettingsMenu() => new MenuScreen("補助台帳の設定",
    [
        new("ConfigurePayables", "買掛元帳の設定", Open: () => SubledgerSettings("買掛元帳の設定", 2, PayableSettings)),
        new("ConfigureReceivables", "売掛元帳の設定", Open: () => SubledgerSettings("売掛元帳の設定", 3, ReceivableSettings)),
        new("ConfigureInventory", "在庫管理の設定", Open: () => SubledgerSettings("在庫管理の設定", 4, InventorySettings))
    ]);

    private Screen SubledgerSettings(string title, int ledger, SubledgerField[] fields, Rec? draft = null, string? error = null)
    {
        var system = draft ?? _settings.Read();
        if (system is null || system.I($"Level-{ledger}") != 1)
            return new InformationScreen(title, "この台帳を有効にした会社を登録してください。");
        return new FormScreen(title, fields.Select(f =>
        {
            string id = "Subledger-" + f.Key;
            if (f.Options is { } options)
            {
                string value = system.S(f.Key);
                value = options.Contains(value, StringComparison.Ordinal) ? value : options == "MQW" ? "M" : options == "YMQ" ? "Y" : options[1].ToString();
                return (Field)new ChoiceField(id, f.Label, options.Select(ch => new Choice(ch.ToString(), ch switch
                {
                    'M' => "月次", 'Q' => "四半期", 'W' => "週次", 'Y' when options == "YMQ" => "年次",
                    '1' or 'Y' => "使用する", _ => "使用しない"
                })).ToArray(), value);
            }
            string text = f.Maximum == 0 ? system.St(f.Key) :
                system.N(f.Key).ToString(f.Maximum == 99.99m ? "0.00" : "0", CultureInfo.InvariantCulture);
            return new TextField(id, f.Label, text, f.Width);
        }).ToArray(), "確認へ", values =>
        {
            var updated = system.Clone();
            foreach (var f in fields)
            {
                string id = "Subledger-" + f.Key;
                if (f.Options is { } options)
                {
                    string? selected = values.Choice(id);
                    if (selected is null || selected.Length != 1 || !options.Contains(selected, StringComparison.Ordinal))
                        return SubledgerSettings(title, ledger, fields, updated, f.Label + "を確認してください。");
                    if (f.Key is "PL-Stock-Link" or "SL-Stock-Link" && system.I("Level-4") != 1) selected = "N";
                    updated.Set(f.Key, selected);
                }
                else if (f.Maximum == 0)
                {
                    string text = values.Text(id);
                    if (text.Length > f.Width || text.Any(ch => ch is < ' ' or > 'ÿ'))
                        return SubledgerSettings(title, ledger, fields, updated, f.Label + "を確認してください。");
                    updated.Set(f.Key, string.IsNullOrWhiteSpace(text) ? "\\" : text);
                }
                else
                {
                    var style = f.Maximum == 99.99m ? NumberStyles.AllowDecimalPoint : NumberStyles.None;
                    if (!decimal.TryParse(values.Text(id), style, CultureInfo.InvariantCulture, out var amount) || amount < 0 || amount > f.Maximum)
                        return SubledgerSettings(title, ledger, fields, updated, f.Label + "を確認してください。");
                    updated.SetN(f.Key, amount);
                }
            }
            return new ConfirmationScreen(title, "入力した設定を保存しますか。", "保存", () =>
            {
                database.Put(SystemSettings.SystemFile, "00000001", updated.B);
                return new InformationScreen(title, "設定を保存しました。");
            }, () => SubledgerSettings(title, ledger, fields, updated));
        }, SubledgerSettingsMenu, error);
    }

    private Screen OperatingSettings(OperatingParameters? draft = null, string? error = null)
    {
        if ((draft ?? _settings.ReadOperatingParameters()) is not { } parameters) return Setup();
        return new FormScreen("運用環境設定",
        [
            new ChoiceField("SystemHost", "利用形態", [new("0", "単独利用"), new("1", "複数利用")], parameters.Host.ToString()),
            new ChoiceField("OperatingSystem", "旧環境の区分",
                [new("1", "旧型ディスク環境"), new("2", "ウィンドウズ"), new("3", "マック"),
                    new("4", "旧型ワークステーション"), new("5", "ユニックス"), new("6", "リナックス")],
                parameters.System.ToString()),
            new ChoiceField("DataCapture", "旧環境の入力方式",
                [new("0", "標準表示"), new("1", "グラフィック表示"), new("2", "ウィジェット表示")],
                parameters.Capture.ToString())
        ], "確認へ", values =>
        {
            if (!Number(values.Choice("SystemHost"), out int host) ||
                !Number(values.Choice("OperatingSystem"), out int system) ||
                !Number(values.Choice("DataCapture"), out int capture) || (host == 1 && system == 1))
                return OperatingSettings(parameters, "利用形態と旧環境の区分を確認してください。");
            var updated = parameters with { Host = host, System = system, Capture = capture };
            return system is 3 or 5 or 6 ? PrintQueueSettings(updated) : ConfirmOperatingSettings(updated);
        }, SettingsMenu, error);
    }

    private Screen PrintQueueSettings(OperatingParameters parameters, string? error = null) => new FormScreen(
        "旧環境の印刷先設定",
        [
            new TextField("Queue1", "共通の印刷先", parameters.Queue1, 48),
            new TextField("Queue2", "総勘定元帳の印刷先", parameters.Queue2, 48),
            new TextField("Queue3", "買掛元帳の印刷先", parameters.Queue3, 48)
        ], "確認へ", values =>
        {
            var updated = parameters with { Queue1 = values.Text("Queue1"), Queue2 = values.Text("Queue2"), Queue3 = values.Text("Queue3") };
            return string.IsNullOrWhiteSpace(updated.Queue1) ? PrintQueueSettings(updated, "共通の印刷先を入力してください。")
                : ConfirmOperatingSettings(updated);
        }, () => OperatingSettings(parameters), error);

    private Screen ConfirmOperatingSettings(OperatingParameters parameters) => new ConfirmationScreen(
        "運用環境設定", "旧環境の設定を保存しますか。このアプリからの印刷先は印刷ダイアログで指定します。", "保存",
        () => _settings.SaveOperatingParameters(parameters) ? new InformationScreen("運用環境設定", "設定を保存しました。")
            : OperatingSettings(parameters, "入力内容を確認してください。"),
        () => OperatingSettings(parameters));

    private Screen SettingsReportMenu() => new MenuScreen("設定内容の印刷",
    [
        new("CreateSettingsReport", "設定帳票を作成する", Open: () => new ConfirmationScreen(
            "設定内容の印刷", "現在のシステム設定を帳票にしますか。", "帳票を作成",
            () => LedgerReport("システム設定帳票", _settings.PrintSettings(), SettingsReportMenu), SettingsReportMenu)),
        new("SettingsReportBack", "システム設定へ戻る", Open: SettingsMenu)
    ]);
}
