using System.Globalization;

namespace Acas.Core.Programs.Sales;

public sealed partial class SalesScreens(SalesLedger sales, Func<DateTime>? clock = null)
{
    private const string Title = "売掛元帳";
    private static readonly Choice[] YesNo = [new("1", "はい"), new("0", "いいえ")];
    private static readonly Choice[] Statuses = [new("", "すべて"), new("1", "稼働中"), new("0", "休眠中")];
    private static readonly Choice[] Comparisons = [new("", "指定しない"), new("L", "未満"), new("E", "等しい"), new("G", "超える")];

    private DateTime Now => (clock ?? (() => DateTime.Now))();
    private static MenuItem Link(string id, string label, Func<Screen> action, int? number = null,
        IReadOnlyList<MenuItem>? children = null) => new(id, label, number, children, () => Protect(label, action));

    private static Screen Protect(string title, Func<Screen> action)
    {
        try { return action(); }
        catch (SalesRuleException ex) { return new InformationScreen(title, ex.Message); }
    }

    private static FormScreen Form(string title, IReadOnlyList<Field> fields, string submit, Func<FormValues, Screen> action) =>
        new(title, fields, submit, values => Protect(title, () => action(values)));
    private static ConfirmationScreen Confirm(string title, string message, string label, Func<Screen> yes, Func<Screen> no) =>
        new(title, message, label, () => Protect(title, yes), no);

    private static IReadOnlyList<MenuItem> Tree(IEnumerable<MenuItem> items) => items.Select(i =>
        i with { Id = i.Id + "Navigation", Children = i.Children == null ? null : Tree(i.Children) }).ToArray();

    public MenuItem Navigation() => Link("SalesNavigation", $"Ｂ　{Title}", () => StartOfDay("SalesStartDate"),
        children: Tree(MainMenu().Items.Where(i => i.Id != "SalesExit")));

    public MenuScreen MainMenu() => new(Title,
    [
        Top('Ａ', "Date", "処理日入力", () => StartOfDay("SalesProcessingDate")),
        Top('Ｂ', "Customers", "得意先保守", CustomerMenu, CustomerMenu().Items.Where(i => i.Number != 9).ToArray()),
        Top('Ｃ', "Enquiry", "売掛残高・明細照会", Enquiry),
        Top('Ｄ', "SalesEntry", "売上取引入力", () => InvoiceEntry("売上取引入力", false)),
        Top('Ｅ', "SalesAmend", "売上取引修正", () => InvoiceSelect("売上取引修正", false)),
        Top('Ｆ', "SalesProof", "売上検証帳票", InvoiceProof),
        Top('Ｇ', "SalesPost", "売上転記", SalesPost),
        Top('Ｈ', "PaymentEntry", "入金入力・消込", PaymentEntry),
        Top('Ｉ', "PaymentAmend", "入金修正", PaymentAmend),
        Top('Ｊ', "PaymentProof", "入金検証帳票", PaymentProof),
        Top('Ｋ', "PaymentPost", "入金転記", PaymentPost),
        Top('Ｌ', "Analysis", "売上分析コード管理", AnalysisMenu, AnalysisMenu().Items.Where(i => i.Number != 9).ToArray()),
        Top('Ｍ', "AnalysisReport", "売上分析帳票", () => sales.SalesAnalysisReport() is { } report
            ? new ReportScreen("売上分析帳票", report, MainMenu) : MainMenu()),
        Top('Ｎ', "DayBook", "売上日計帳", DayBook),
        Top('Ｏ', "Statements", "得意先明細書", () => OpenItemReport("得意先明細書")),
        Top('Ｐ', "Reminders", "督促状", () => OpenItemReport("督促状")),
        Top('Ｑ', "AgedDebtors", "売掛金年齢表", () => OpenItemReport("売掛金年齢表")),
        Top('Ｒ', "Alphabetical", "得意先名順一覧", () => CustomerReportOptions("得意先名順一覧", "SalesAlphabetical", true)),
        Top('Ｓ', "Turnover", "得意先別売上帳票", () => CustomerReportOptions("得意先別売上帳票", "SalesTurnover", false, true)),
        Top('Ｔ', "Invoicing", "請求書サブシステム", OpenInvoiceMenu, InvoiceMenu().Items.Where(i => i.Number != 9).ToArray()),
        Top('Ｕ', "Cycle", "期間締め", Cycle),
        Top('Ｖ', "Dump", "得意先ファイル帳票", () => CustomerReportOptions("得意先ファイル帳票", "SalesDump")),
        Top('Ｘ', "Exit", "売掛を閉じる", () => new InformationScreen("業務メニュー", "左側のメニューから操作を選択してください。")),
        Top('Ｚ', "Setup", "共通設定", Setup)
    ]);

    private static MenuItem Top(char key, string id, string title, Func<Screen> action, IReadOnlyList<MenuItem>? children = null) =>
        new("Sales" + id, $"{key}　{title}", Children: children, Open: () => Protect(title, action));

    private Screen StartOfDay(string id) => Form("売掛処理日入力",
        [new DateField(id, "処理日", Now.Date)], "確定", values =>
        {
            sales.SetProcessingDate(values.Date(id) ?? throw new SalesRuleException("処理日を入力してください。"));
            return MainMenu();
        });

    private Screen Setup()
    {
        var system = sales.SystemRecord();
        string Text(string field) => SalesLedger.GetText(system, field);
        string Number(string field) => system.I(field).ToString(CultureInfo.InvariantCulture);
        return new TableScreen("共通設定", "SalesSetupSettings", ["項目", "内容"],
        [
            new(["事業者名", Text("Usera")]),
            .. Enumerable.Range(1, 4).Select(i => new TableRow([$"住所{i}", Text("Address-" + i)])),
            new(["郵便番号", Text("Post-Code")]),
            new(["国・地域", Text("Country")]),
            new(["日付形式", system.I("Date-Form") switch { 1 => "日・月・年", 2 => "月・日・年", 3 => "年・月・日", _ => "未設定" }]),
            new(["期首", SalesLedger.ShowDate(system.I("Start-Date"))]),
            new(["期末", SalesLedger.ShowDate(system.I("End-Date"))]),
            new(["印刷行数", Number("Page-Lines")]),
            .. Enumerable.Range(1, 5).Select(i => new TableRow([$"税率{i}", SalesLedger.Amount(system.N("Vat-Rate-" + i))])),
            new(["税登録番号", Text("VAT-Reg-Number")]),
            new(["税登録番号を印刷", system.St("SL-VAT-Printed") == "Y" ? "はい" : "いいえ"]),
            new(["現在の処理期", Number("Cyclea")]),
            new(["現在の四半期", Number("Current-Quarter")]),
            new(["処理期間区分", Number("Period")]),
            new(["データファイル方式", Number("File-System-Used")]),
            new(["複製ファイル方式", Number("File-Duplicates-In-Use")])
        ]);
    }

    private Screen Enquiry()
    {
        const string title = "売掛残高・明細照会";
        if (!sales.HasOpenItems()) return Missing(title, "売掛明細");
        return CustomerLookup(title, "SalesEnquiryCode", customer => new TableScreen(
            $"{title}　{customer.Code}　{customer.DisplayName}　残高 {SalesLedger.Amount(customer.Balance)}　未消込額 {SalesLedger.Amount(customer.Unapplied)}",
            "SalesEnquiryEntries", ["番号", "日付", "種類", "摘要", "金額", "入金額", "残高", "状態"],
            sales.OpenItems(customer.Code).Select(item => new TableRow(
            [
                item.Number.ToString("D8", CultureInfo.InvariantCulture), SalesLedger.ShowDate(item.Date),
                SalesLedger.OpenItemType(item.Type), item.Description, SalesLedger.Amount(item.Amount),
                SalesLedger.Amount(item.Paid), SalesLedger.Amount(item.Outstanding),
                item.Closed ? "消込済み" : item.Held ? "保留" : "未消込"
            ])).ToArray()));
    }

    private Screen SalesPost()
    {
        const string title = "売上転記";
        if (!sales.HasFile("invoice.dat")) return Missing(title, "転記先の売掛明細");
        bool unprinted = sales.ExtractSalesForPosting();
        string message = unprinted ? "未印刷の請求書を除き、抽出済みの売上取引を転記しますか。"
            : "抽出済みの売上取引を転記しますか。";
        return Confirm(title, message, "転記する", () => new ReportScreen(title, sales.PostSales()), MainMenu);
    }

    private Screen OpenItemReport(string title)
    {
        if (!sales.HasOpenItems()) return Missing(title, "売掛明細");
        List<Field> fields = [new DateField("SalesReportAsOf", "基準日", Now.Date),
            new TextField("SalesReportCustomerPattern", "得意先番号の条件（空欄は全件）", MaxLength: 6)];
        if (title == "督促状")
        {
            var sys = sales.SystemRecord();
            fields.AddRange([
                AmountField("SalesReminderMinimum", "最低残高", 0, 9),
                IntegerField("SalesReminderLow", "第一段階の日数", sys.I("SL-Days-1"), 2),
                IntegerField("SalesReminderMedium", "第二段階の日数", sys.I("SL-Days-2"), 2),
                IntegerField("SalesReminderHigh", "第三段階の日数", sys.I("SL-Days-3"), 2)
            ]);
        }
        return Form(title, fields, "作成", values =>
        {
            DateTime date = values.Date("SalesReportAsOf") ?? throw new SalesRuleException("基準日を入力してください。");
            string pattern = values.Text("SalesReportCustomerPattern");
            if (title != "督促状") return ShowReport(title, "prt-1", sales.Statements(date, pattern, title == "売掛金年齢表"));
            return new ReportScreen(title, sales.Reminders(date, pattern,
                Decimal(values, "SalesReminderMinimum", "最低残高", 999999.99m),
                Integer(values, "SalesReminderLow", "第一段階の日数", 0, 99),
                Integer(values, "SalesReminderMedium", "第二段階の日数", 0, 99),
                Integer(values, "SalesReminderHigh", "第三段階の日数", 0, 99)));
        });
    }

    private static InformationScreen Missing(string title, string subject) => new(title, $"{subject}ファイルがありません。");

    private Screen DayBook()
    {
        var report = sales.InvoiceDayBook(Now.Date);
        return report == null ? MainMenu() : ShowReport("売上日計帳", "prt-1", report);
    }

    private Screen Cycle()
    {
        const string title = "期間締め";
        return Confirm(title, "処理日が期間末日で、全データのバックアップが済んでいることを確認してください。",
            "確認", () =>
            {
                if (!sales.HasOpenItems()) return Missing(title, "売掛明細");
                var sys = sales.SystemRecord();
                List<Field> fields = [new PasswordField("SalesCyclePassword", "期間締めのパスワード", 4)];
                bool askQuarter = sys.I("Period") is not (3 or 13);
                bool unposted = sys.I("S-Flag-I") == 1 || sys.I("P-Flag-I") == 1;
                if (askQuarter) fields.Add(Toggle("SalesCycleQuarter", "四半期を締める", false));
                if (unposted) fields.Add(Toggle("SalesCycleUnposted", "未転記の請求書があっても実行する", false));
                return Form(title, fields, "期間締めを実行", values =>
                {
                    sales.CloseCycle(values.Text("SalesCyclePassword"), askQuarter && values.Choice("SalesCycleQuarter") == "1",
                        unposted && values.Choice("SalesCycleUnposted") == "1", Now.Date);
                    return new InformationScreen(title, "期間締めが完了しました。");
                });
            }, MainMenu);
    }

    private Screen ShowReport(string title, string spool, string body)
    {
        sales.KeepReport(spool, body);
        return new ReportScreen(title, body);
    }

    private static ChoiceField Toggle(string id, string title, bool value) => new(id, title, YesNo, value ? "1" : "0");
    private static TextField IntegerField(string id, string title, int value, int length) =>
        new(id, title, value.ToString(CultureInfo.InvariantCulture), length);
    private static TextField AmountField(string id, string title, decimal value, int length) =>
        new(id, title, SalesLedger.Amount(value), length);
    private static int Integer(FormValues values, string id, string label, int min, int max)
    {
        if (int.TryParse(values.Text(id).Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out int value) &&
            value >= min && value <= max) return value;
        throw new SalesRuleException($"{label}は{min}～{max}の整数で入力してください。");
    }

    private static decimal Decimal(FormValues values, string id, string label, decimal max)
    {
        if (decimal.TryParse(values.Text(id).Trim(), NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out decimal value) &&
            value >= 0 && value <= max && decimal.Round(value, 2) == value) return value;
        throw new SalesRuleException($"{label}は0～{max}で、小数点以下2桁以内で入力してください。");
    }
}
