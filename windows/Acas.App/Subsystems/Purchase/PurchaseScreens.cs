using System.Globalization;
using Acas.App.Subsystems.Purchase;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Purchase;

[assembly: SubsystemScreensAttribute<PurchaseScreens>(40)]

namespace Acas.App.Subsystems.Purchase;

internal sealed partial class PurchaseScreens : ISubsystemScreens
{
    private const string MainTitle = "買掛元帳";
    private PurchaseLedger _ledger = null!;
    private bool _opened;

    public MenuItem CreateNavigation(Db database)
    {
        _ledger = new PurchaseLedger(database);
        return new MenuItem("PurchaseNavigation", MainTitle, Children: Tree(MainItems()),
            Open: () => _opened ? MainMenu() : ProcessingDate());
    }

    private MenuItem[] Tree(IEnumerable<MenuItem> items) => items.Select(item => item with
    {
        Id = item.Id + "Navigation",
        Children = item.Children is null ? null : Tree(item.Children),
        Open = item.Open is { } open ? () => _opened || item.Id == "PurchaseMenuA" ? open() : ProcessingDate(open) : null
    }).ToArray();

    private MenuScreen MainMenu() => new(MainTitle, MainItems());

    private MenuItem[] MainItems() =>
    [
        Letter("A", "エー", "処理日入力", () => ProcessingDate()),
        Letter("B", "ビー", "仕入先マスター管理", SupplierMenu, SupplierItems()),
        Letter("C", "シー", "買掛残高・明細照会", Inquiry),
        Letter("D", "ディー", "仕入取引入力", InvoiceEntry),
        Letter("E", "イー", "仕入取引修正", () => FindInvoice(false)),
        Letter("F", "エフ", "仕入取引削除", () => FindInvoice(true)),
        Letter("G", "ジー", "仕入の検証帳票", InvoiceProof),
        Letter("H", "エイチ", "仕入転記", InvoicePost),
        Letter("I", "アイ", "支払入力・消込", PaymentEntry),
        Letter("J", "ジェー", "支払修正", PaymentAmend),
        Letter("K", "ケー", "支払の検証帳票", PaymentProof),
        Letter("L", "エル", "支払転記", PaymentPost),
        Letter("M", "エム", "仕入分析コード管理", AnalysisMenu, AnalysisItems()),
        Letter("N", "エヌ", "仕入分析帳票", AnalysisReport),
        Letter("O", "オー", "仕入日計帳", DayBook),
        Letter("P", "ピー", "買掛金年齢表", AgedCreditors),
        Letter("Q", "キュー", "仕入先名順一覧", () => SupplierReport("仕入先名順一覧", true)),
        Letter("R", "アール", "仕入先別取引帳票", () => SupplierReport("仕入先別取引帳票", turnover: true)),
        Letter("S", "エス", "小切手・送金", ChequeMenu, ChequeItems()),
        Letter("T", "ティー", "買掛・売掛の期間締め", ClosePeriod),
        Letter("U", "ユー", "仕入伝票の固定設定", Invoicing, InvoiceItems()),
        Letter("V", "ブイ", "仕入先ファイル帳票", () => SupplierReport("仕入先ファイル帳票")),
        Letter("X", "エックス", "買掛を閉じる", CloseLedger),
        Letter("Z", "ゼット", "共通設定", OpenSetup)
    ];

    private static MenuItem Letter(string code, string reading, string label, Func<Screen> open, MenuItem[]? children = null) =>
        new("PurchaseMenu" + code, $"{reading}　{label}", Children: children, Open: open);

    private static MenuItem Item(string code, int number, string label, Func<Screen> open) =>
        new("PurchaseMenu" + code, label, number, Open: open);

    private MenuItem[] SupplierItems() =>
    [
        Item("B1", 1, "仕入先登録", () => SupplierEntry(SupplierAction.Register, "仕入先登録")),
        Item("B2", 2, "仕入先変更", () => SupplierEntry(SupplierAction.Change, "仕入先変更")),
        Item("B3", 3, "仕入先削除", () => SupplierEntry(SupplierAction.Remove, "仕入先削除")),
        Item("B4", 4, "仕入先一覧印刷", () => SupplierReport("仕入先一覧印刷")),
        Item("B5", 5, "仕入先表示", () => SupplierEntry(SupplierAction.Show, "仕入先表示")),
        Item("B9", 9, "買掛メニューに戻る", MainMenu)
    ];

    private MenuScreen SupplierMenu() => new("仕入先マスター管理", SupplierItems());

    private Screen ProcessingDate(Func<Screen>? next = null)
    {
        const string title = "買掛元帳の処理日";
        const string field = "PurchaseProcessingDate";
        return new FormScreen(title, [new DateField(field, "処理日", DateTime.Today)], "処理日を確定", values =>
        {
            if (!_ledger.IsConfigured) return Notice(title, "先に共通の初期設定を行ってください。");
            var date = values.Date(field);
            if (date is null || PurchaseLedger.EncodeDate(date.Value) <= 0) return Notice(title, "有効な処理日を指定してください。");
            var system = _ledger.System();
            system.SetN("Run-Date", PurchaseLedger.EncodeDate(date.Value));
            _ledger.SaveSystem(system);
            _opened = true;
            return next?.Invoke() ?? MainMenu();
        });
    }

    private Screen CloseLedger()
    {
        _opened = false;
        return Notice(MainTitle, "買掛元帳を閉じました。");
    }

    private static Screen OpenSetup() => Notice("共通設定", "左側の業務メニューから共通設定を開いてください。");
    private static InformationScreen Notice(string title, string message) => new(title, message);
    private static string Money(decimal amount) => amount.ToString("0.00", CultureInfo.InvariantCulture);
    private static string DateText(DateTime? date) => date?.ToString("yyyy年M月d日", CultureInfo.InvariantCulture) ?? "";
}
