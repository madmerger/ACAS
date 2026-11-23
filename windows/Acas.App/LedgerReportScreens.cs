using Acas.Core;

namespace Acas.App;

internal sealed partial class AccountingScreens
{
    private Screen TrialBalanceMenu()
    {
        var items = new List<MenuItem>
        {
            new("DetailedTrialBalance", "詳細試算表", 1,
                Open: () => LedgerReport("詳細試算表", _ledgerReports.TrialBalance(false), TrialBalanceMenu))
        };
        string? division = _settings.Read()?.S("P-C");
        if (division is "P" or "B")
        {
            string title = division == "B" ? "拠点別試算表" : "部門別試算表";
            items.Add(new("StructuredTrialBalance", title, 2,
                Open: () => LedgerReport(title, _ledgerReports.TrialBalance(true), TrialBalanceMenu)));
        }
        items.Add(new("TrialBalanceBack", "総勘定元帳へ戻る", 9, Open: GeneralMenu));
        return new MenuScreen("試算表", items);
    }

    private Screen ArchivedLedgerMenu() => new MenuScreen("元帳印刷・保管仕訳の並べ替え",
    [
        new("SortArchivedLedger", "保管仕訳を並べ替える", Open: () => new ConfirmationScreen(
            "保管仕訳の並べ替え", "データベース内の保管仕訳を勘定・部門・バッチ・仕訳番号の順に並べ替えます。",
            "並べ替える", () => _batches.SortArchive()
                ? ArchivedLedger()
                : new InformationScreen("元帳印刷", "保管仕訳がありません。"), ArchivedLedgerMenu)),
        new("ArchivedLedgerBack", "総勘定元帳へ戻る", Open: GeneralMenu)
    ]);

    private Screen ArchivedLedger(string account = "", string division = "", string? error = null) =>
        new FormScreen("元帳印刷",
        [
            new TextField("ArchiveAccount", "勘定コード６桁（空欄は全勘定）", account, 6),
            new TextField("ArchiveDivision", "部門コード２桁（空欄は全部門）", division, 2)
        ], "帳票を作成", values =>
        {
            account = values.Text("ArchiveAccount");
            division = values.Text("ArchiveDivision");
            int number = 0, unit = 0;
            if (account.Length != 0 && (account.Length != 6 || !Number(account, out number)) ||
                division.Length != 0 && (division.Length != 2 || !Number(division, out unit)))
                return ArchivedLedger(account, division, "勘定と部門のコードを確認してください。");
            if (number != 0 && (!_batches.ArchivedAccountExists(number, 0) ||
                unit != 0 && !_batches.ArchivedAccountExists(number, unit)))
                return ArchivedLedger(account, division, "指定された勘定または部門がありません。");
            return LedgerReport("保管仕訳元帳", _batches.PrintArchivedLedger(number, unit), ArchivedLedgerMenu);
        }, ArchivedLedgerMenu, error);

    private Screen FinancialStatements()
    {
        const string title = "損益計算書・貸借対照表";
        var date = _settings.Read() is { } system ? SystemSettings.Date(system, "Run-Date") : null;
        return new FormScreen(title, [new DateField("FinancialStatementsDate", "決算書の日付", date)], "確認へ",
            values => values.Date("FinancialStatementsDate") == null ? GeneralMenu() :
                new ConfirmationScreen(title, $"処理日（{date:yyyy年M月d日}）で決算書を作成しますか。", "帳票を作成",
                    () => LedgerReport(title, _ledgerReports.FinancialStatements(), GeneralMenu), FinancialStatements),
            GeneralMenu);
    }

    private static Screen LedgerReport(string title, string? body, Func<Screen> back) =>
        body == null ? new InformationScreen(title, "帳票を作成するためのデータがありません。")
            : new ReportScreen(title, body, back, "戻る");
}
