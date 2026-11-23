using Acas.Core;

namespace Acas.App;

internal sealed partial class AccountingScreens
{
    private Screen SettingsMenu() => new MenuScreen("システム設定",
    [
        new("SettingsCompany", "会社・期間設定", Open: () => Settings()),
        new("SettingsOperating", "運用環境設定", Open: () => OperatingSettings()),
        new("SettingsLedger", "総勘定元帳の設定", Open: () => GeneralLedgerSettings()),
        new("SettingsPrint", "設定内容の印刷", Open: SettingsReportMenu)
    ]);

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
