using Acas.App.Subsystems.Integration;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Integration;
using Acas.Core.Programs.Irs;

[assembly: SubsystemScreensAttribute<IntegrationScreens>(61)]

namespace Acas.App.Subsystems.Integration;

public sealed class IntegrationScreens : ISubsystemScreens
{
    public IntegrationScreens() : this(null, null) { }

    public IntegrationScreens(TransferDestination? destination, Action<IrsReport>? onReport)
    {
        this.destination = destination;
        this.onReport = onReport;
    }

    private readonly TransferDestination? destination;
    private readonly Action<IrsReport>? onReport;
    public MenuItem CreateNavigation(Db database) => CreateNavigation(database, DateTime.Today);

    public MenuItem CreateNavigation(Db database, DateTime date)
    {
        var sales = Menu(database, TransferLedger.Sales, date);
        var purchases = Menu(database, TransferLedger.Purchases, date);
        MenuItem[] items =
        [
            new("IntegrationSalesMenu", "Ｂ　売掛元帳", Open: () => Start(sales, database, TransferLedger.Sales, date)),
            new("IntegrationPurchaseMenu", "Ｃ　買掛元帳", Open: () => Start(purchases, database, TransferLedger.Purchases, date))
        ];
        return new("IntegrationNavigation", "元帳連携", Children:
            [new("IntegrationSalesNavigation", items[0].Label, Open: items[0].Open),
             new("IntegrationPurchaseNavigation", items[1].Label, Open: items[1].Open)],
            Open: () => new MenuScreen("元帳連携", items));
    }

    private FormScreen Start(MenuScreen menu, Db database, TransferLedger ledger, DateTime date) =>
        new(menu.Title + "の処理日", [new DateField("IntegrationRunDate", "処理日", date)], "次へ", v =>
            v.Date("IntegrationRunDate") is DateTime selected ? Menu(database, ledger, selected) :
                new InformationScreen(menu.Title, "処理日を指定してください。"));

    private MenuScreen Menu(Db database, TransferLedger ledger, DateTime date)
    {
        bool sales = ledger == TransferLedger.Sales;
        var transfer = new LedgerTransfer(database);
        string title = sales ? "売掛元帳" : "買掛元帳";
        return new(title,
            [new(sales ? "IntegrationSalesPost" : "IntegrationPurchasePost", sales ? "Ｇ　請求書の転記" : "Ｈ　請求書の転記",
                Open: () => Post(database, transfer, title, date, ledger)),
             new(sales ? "IntegrationSalesClose" : "IntegrationPurchaseClose", sales ? "Ｕ　期末処理" : "Ｔ　期末処理",
                Open: () => Close(database, transfer, title, date, ledger))]);
    }

    private ConfirmationScreen Post(Db database, LedgerTransfer service, string title, DateTime date, TransferLedger ledger)
    {
        string name = title + "の請求書転記";
        return new(name, "転記対象の請求書を処理しますか。", "転記する", () => Guard(name, () =>
        {
            string? setting = Environment.GetEnvironmentVariable("ACAS_IRS");
            var target = destination ?? (IrsBookkeeping.UsesSharedTransferDirectory(setting)
                ? TransferDestination.Shared : TransferDestination.Dedicated);
            var report = service.TransferInvoices(ledger, date, target);
            onReport?.Invoke(report);
            return new ReportScreen(report.Title, report.Body, () => Menu(database, ledger, date));
        }), () => Menu(database, ledger, date));
    }

    private Screen Close(Db db, LedgerTransfer service, string title, DateTime date, TransferLedger ledger)
    {
        const string name = "期末処理";
        var back = () => Menu(db, ledger, date);
        return new ConfirmationScreen(name,
            $"{title}の期末に実行してください。すべてのデータのバックアップを確認して続行しますか。",
            "続行", () => Guard(name, () =>
            {
                var options = service.ClosingWarning(ledger);
                var fields = new List<Field> { new PasswordField("IntegrationClosingPassword", "暗証番号", 4) };
                if (options.HasUnpostedInvoices)
                    fields.Add(new ChoiceField("IntegrationClosingUnposted", "請求書が未転記でも処理する",
                        [new("N", "いいえ"), new("Y", "はい")], "N"));
                if (options.RequiresQuarterChoice)
                    fields.Add(new ChoiceField("IntegrationQuarterEnd", "四半期末として処理する",
                        [new("N", "いいえ"), new("Y", "はい")], "N"));
                return new FormScreen(name, fields, "期末処理を実行", v => Guard(name, () =>
                {
                    service.ClosePeriod(ledger, date, v.Text("IntegrationClosingPassword"),
                        !options.HasUnpostedInvoices || v.Choice("IntegrationClosingUnposted") == "Y",
                        options.RequiresQuarterChoice && v.Choice("IntegrationQuarterEnd") == "Y");
                    return new InformationScreen(name, "期末処理が完了しました。");
                }));
            }), back);
    }

    private static Screen Guard(string title, Func<Screen> action)
    {
        try { return action(); }
        catch (IrsException ex) { return new InformationScreen(title, ex.Message); }
    }
}
