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

    public bool TryClose() => _ledger.FlushPostingFlags();

    private Screen CloseLedger()
    {
        if (!TryClose()) return Notice(MainTitle, "買掛元帳の終了状態を保存できませんでした。");
        _opened = false;
        return Notice(MainTitle, "買掛元帳を閉じました。");
    }

    private Screen OpenSetup()
    {
        const string title = "共通設定・事業者情報";
        if (!_ledger.IsConfigured) return Notice(title, "事業者の初期設定が必要です。");
        var system = _ledger.System();
        var textFields = new (string Name, string Label, int Width)[]
        {
            ("Usera", "事業者名", 32), ("Address-1", "住所１", 24), ("Address-2", "住所２", 24),
            ("Address-3", "住所３", 24), ("Address-4", "住所４", 24),
            ("Post-Code", "郵便番号", 12), ("Country", "国", 24), ("VAT-Reg-Number", "税登録番号", 11)
        };
        List<Field> fields = textFields.Select(field =>
            (Field)new TextField("PurchaseSetup" + field.Name, field.Label, system.St(field.Name), field.Width)).ToList();
        fields.Add(new DateField("PurchaseSetupStartDate", "期間開始日", PurchaseLedger.DecodeDate(system.I("Start-Date"))));
        fields.Add(new DateField("PurchaseSetupEndDate", "期間終了日", PurchaseLedger.DecodeDate(system.I("End-Date"))));
        fields.Add(new TextField("PurchaseSetupPageLines", "帳票の一ページ当たりの行数",
            system.I("Page-Lines").ToString(CultureInfo.InvariantCulture), 3));
        for (int i = 1; i <= 5; i++)
            fields.Add(new TextField($"PurchaseSetupTax{i}", $"税率 {i}", Money(system.N($"Vat-Rate-{i}")), 5));
        return new FormScreen(title, fields, "確認", values =>
        {
            var next = system.Clone();
            foreach (var (name, label, width) in textFields)
            {
                string value = values.Text("PurchaseSetup" + name);
                if (!PurchaseLedger.FitsRecord(value, width)) return Notice(title, $"{label}を確認してください。");
                next.Set(name, value);
            }
            var start = values.Date("PurchaseSetupStartDate");
            var end = values.Date("PurchaseSetupEndDate");
            if (start is null || end is null || end < start || PurchaseLedger.EncodeDate(start.Value) <= 0)
                return Notice(title, "開始日と終了日を確認してください。");
            if (!Number(values, "SetupPageLines", out int lines) || lines is < 7 or > 255)
                return Notice(title, "帳票の行数を確認してください。");
            next.SetN("Start-Date", PurchaseLedger.EncodeDate(start.Value));
            next.SetN("End-Date", PurchaseLedger.EncodeDate(end.Value));
            next.SetN("Page-Lines", lines);
            for (int i = 1; i <= 5; i++)
            {
                if (!Amount(values, $"SetupTax{i}", out decimal rate) || rate is < 0 or > 99.99m)
                    return Notice(title, "税率を確認してください。");
                next.SetN($"Vat-Rate-{i}", rate);
            }
            return new ConfirmationScreen(title, "事業者情報を保存しますか。", "保存", () =>
            {
                _ledger.SaveSystem(next);
                return MainMenu();
            }, OpenSetup);
        });
    }
    private static InformationScreen Notice(string title, string message) => new(title, message);
    private static string Money(decimal amount) => amount.ToString("0.00", CultureInfo.InvariantCulture);
    private static string DateText(DateTime? date) => date?.ToString("yyyy年M月d日", CultureInfo.InvariantCulture) ?? "";
}
