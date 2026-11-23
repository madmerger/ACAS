using System.Globalization;
using System.Text;

namespace Acas.Core.Programs.Sales;

public sealed partial class SalesScreens
{
    private MenuScreen CustomerMenu() => new("得意先保守",
    [
        Link("SalesCustomerCreate", "得意先登録", () => CustomerEditor(null), 1),
        Link("SalesCustomerUpdate", "得意先変更", () => CustomerLookup("得意先変更", "SalesUpdateCustomerCode", CustomerEditor), 2),
        Link("SalesCustomerDelete", "得意先削除", () => CustomerLookup("得意先削除", "SalesDeleteCustomerCode", CustomerRemoval), 3),
        Link("SalesCustomerPrint", "得意先一覧印刷", () => CustomerReportOptions("得意先一覧印刷", "SalesCustomerPrint"), 4),
        Link("SalesCustomerDisplay", "得意先表示", () => CustomerLookup("得意先表示", "SalesDisplayCustomerCode", CustomerDisplay), 5),
        Link("SalesCustomerBack", "売掛元帳に戻る", MainMenu, 9)
    ]);

    private Screen CustomerLookup(string title, string id, Func<SalesCustomer, Screen> open) => Form(title,
        [new TextField(id, "得意先番号", MaxLength: 7)], "検索", values =>
        {
            string code = values.Text(id).Trim();
            return code.Length == 0 ? CustomerMenu() : open(sales.GetCustomer(code));
        });

    private Screen CustomerEditor(SalesCustomer? customer)
    {
        var d = customer?.Details ?? sales.CustomerDefaults();
        string title = customer == null ? "得意先登録" : "得意先変更";
        List<Field> fields = [];
        if (customer == null) fields.Add(new TextField("SalesNewCustomerCode", "得意先番号（検査数字を除く）", MaxLength: 6));
        fields.AddRange(
        [
            new TextField("SalesCustomerName", "得意先名", d.Name, 30),
            new TextField("SalesCustomerAddress1", "住所1", d.Address1, 48),
            new TextField("SalesCustomerAddress2", "住所2", d.Address2, 48),
            new TextField("SalesDeliveryName", "配送先名", d.DeliveryName, 30),
            new TextField("SalesDeliveryAddress1", "配送先住所1", d.DeliveryAddress1, 48),
            new TextField("SalesDeliveryAddress2", "配送先住所2", d.DeliveryAddress2, 48),
            new TextField("SalesCustomerNote1", "備考1", d.Note1, 48),
            new TextField("SalesCustomerNote2", "備考2", d.Note2, 48),
            new TextField("SalesCustomerPhone", "電話", d.Phone, 13),
            new TextField("SalesCustomerExtension", "内線", d.Extension, 4),
            new TextField("SalesCustomerFax", "ファクス", d.Fax, 13),
            new TextField("SalesCustomerEmail", "メールアドレス", d.Email, 30),
            Toggle("SalesCustomerLateCharges", "延滞料を請求", d.LateCharges),
            IntegerField("SalesCustomerMinCharge", "延滞料の対象最低残高", d.MinimumLateCharge, 4),
            Toggle("SalesCustomerDunning", "督促状を発行", d.Dunning),
            IntegerField("SalesCustomerMaxCharge", "延滞料上限", d.MaximumLateCharge, 4),
            IntegerField("SalesCustomerCreditDays", "支払期限（日数）", d.CreditDays, 2),
            Toggle("SalesCustomerEmailInvoice", "請求書をメール送付", d.EmailInvoice),
            Toggle("SalesCustomerEmailStatement", "明細書をメール送付", d.EmailStatement),
            Toggle("SalesCustomerEmailLetters", "督促状をメール送付", d.EmailLetters),
            IntegerField("SalesCustomerCreditLimit", "与信限度額", d.CreditLimit, 7),
            AmountField("SalesCustomerDiscount", "値引率", d.Discount, 5)
        ]);
        return Form(title, fields, "保存内容を確認", v =>
        {
            var details = new CustomerDetails(
                v.Text("SalesCustomerName"), v.Text("SalesCustomerAddress1"), v.Text("SalesCustomerAddress2"),
                v.Text("SalesCustomerPhone"), v.Text("SalesCustomerExtension"), v.Text("SalesCustomerEmail"), v.Text("SalesCustomerFax"),
                v.Text("SalesDeliveryName"), v.Text("SalesDeliveryAddress1"), v.Text("SalesDeliveryAddress2"),
                v.Text("SalesCustomerNote1"), v.Text("SalesCustomerNote2"),
                v.Choice("SalesCustomerLateCharges") == "1", v.Choice("SalesCustomerDunning") == "1",
                v.Choice("SalesCustomerEmailInvoice") == "1", v.Choice("SalesCustomerEmailStatement") == "1",
                v.Choice("SalesCustomerEmailLetters") == "1", Integer(v, "SalesCustomerCreditDays", "支払期限", 0, 99),
                Decimal(v, "SalesCustomerDiscount", "値引率", 99.99m),
                Integer(v, "SalesCustomerMinCharge", "延滞料の対象最低残高", 0, 9999),
                Integer(v, "SalesCustomerMaxCharge", "延滞料上限", 0, 9999),
                Integer(v, "SalesCustomerCreditLimit", "与信限度額", 0, 9999999));
            return Confirm(title, "得意先情報を保存しますか。", "保存", () =>
                CustomerDisplay(customer == null
                    ? sales.CreateCustomer(v.Text("SalesNewCustomerCode"), details)
                    : sales.UpdateCustomer(customer.Code, details)), () => CustomerEditor(customer));
        });
    }

    private Screen CustomerRemoval(SalesCustomer customer) => Form("得意先削除",
        [new ChoiceField("SalesCustomerRemovalAction", "得意先の扱い",
            [new("0", "休眠にする"), new("1", "完全に削除する")], "0")],
        "確認", values =>
        {
            bool delete = values.Choice("SalesCustomerRemovalAction") == "1";
            string action = delete ? "削除" : "休眠";
            return Confirm("得意先削除", $"{customer.Code}　{customer.Details.Name}を{action}にしますか。", "確定",
                () => { sales.CloseCustomer(customer.Code, delete); return CustomerMenu(); },
                () => CustomerRemoval(customer));
        });

    private static TableScreen CustomerDisplay(SalesCustomer customer)
    {
        var d = customer.Details;
        return new("得意先表示", "SalesCustomerDetail", ["項目", "内容"],
        [
            new(["得意先番号", customer.Code]), new(["得意先名", d.Name]), new(["状態", customer.Active ? "稼働中" : "休眠中"]),
            new(["住所1", d.Address1]), new(["住所2", d.Address2]), new(["電話", d.Phone]), new(["内線", d.Extension]),
            new(["ファクス", d.Fax]), new(["メールアドレス", d.Email]), new(["配送先名", d.DeliveryName]),
            new(["配送先住所1", d.DeliveryAddress1]), new(["配送先住所2", d.DeliveryAddress2]),
            new(["備考1", d.Note1]), new(["備考2", d.Note2]), new(["支払期限（日数）", d.CreditDays.ToString(CultureInfo.InvariantCulture)]),
            new(["残高", SalesLedger.Amount(customer.Balance)]), new(["未消込額", SalesLedger.Amount(customer.Unapplied)]),
            new(["最終請求日", SalesLedger.ShowDate(customer.LastInvoice)]), new(["最終入金日", SalesLedger.ShowDate(customer.LastPayment)])
        ]);
    }

    private static TableRow CustomerRow(SalesCustomer c) => new(
        [c.Code, c.Details.Name, SalesLedger.Amount(c.Balance), SalesLedger.Amount(c.Unapplied)], () => CustomerDisplay(c),
        [c.Code, c.Details.Name, c.Balance, c.Unapplied]);

    private Screen CustomerReportOptions(string title, string prefix, bool alphabetical = false, bool turnover = false)
    {
        if (turnover) sales.KeepReport("prt-1", "");
        return Form(title,
        [
            new TextField(prefix + "Code", "得意先番号の一致条件", MaxLength: 6),
            new ChoiceField(prefix + "Status", "状態", Statuses, ""),
            IntegerField(prefix + "Credit", "支払期限（日数）", 0, 2),
            new ChoiceField(prefix + "CreditOperator", "支払期限の比較", Comparisons, ""),
            IntegerField(prefix + "Activity", "請求回数", 0, 5),
            new ChoiceField(prefix + "ActivityOperator", "請求回数の比較", Comparisons, ""),
            IntegerField(prefix + "Average", "平均請求額", 0, 5),
            new ChoiceField(prefix + "AverageOperator", "平均請求額の比較", Comparisons, ""),
            IntegerField(prefix + "Overdue", "経過日数", 0, 5),
            new ChoiceField(prefix + "OverdueOperator", "経過日数の比較", Comparisons, ""),
            new DateField(prefix + "Entered", "登録日"),
            new ChoiceField(prefix + "EnteredOperator", "登録日の比較", Comparisons, "")
        ], "帳票を作成", v =>
        {
            string pattern = v.Text(prefix + "Code").ToUpperInvariant();
            if (pattern.Length > 6) throw new SalesRuleException("得意先番号の一致条件は6文字以内で入力してください。");
            string? status = v.Choice(prefix + "Status");
            int credit = Integer(v, prefix + "Credit", "支払期限", 0, 99);
            int activity = Integer(v, prefix + "Activity", "請求回数", 0, 99999);
            int average = Integer(v, prefix + "Average", "平均請求額", 0, 99999);
            int overdue = Integer(v, prefix + "Overdue", "経過日数", 0, 99999);
            int processingDate = sales.SystemRecord().I("Run-Date");
            int? entered = v.Date(prefix + "Entered") is { } date ? SalesLedger.EncodeDate(date) : null;
            var rows = sales.Customers().Where(c => pattern.Select((ch, i) => ch is '_' or ' ' || ch == c.Code[i]).All(b => b) &&
                (string.IsNullOrEmpty(status) || c.Active == (status == "1")) &&
                Compare(c.Details.CreditDays, credit, v.Choice(prefix + "CreditOperator")) &&
                Compare(c.InvoiceActivity, activity, v.Choice(prefix + "ActivityOperator")) &&
                Compare(c.Average, average, v.Choice(prefix + "AverageOperator")) &&
                Compare(Math.Max(0, processingDate - c.LastInvoice - c.Details.CreditDays), overdue, v.Choice(prefix + "OverdueOperator")) &&
                (entered == null || Compare(c.Created, entered.Value, v.Choice(prefix + "EnteredOperator"))));
            if (alphabetical) rows = rows.OrderBy(c => c.Details.Name, StringComparer.Ordinal);
            var report = new StringBuilder().AppendLine(title).AppendLine(SalesLedger.ShowDate(processingDate))
                .AppendLine(turnover ? "得意先番号　得意先名　売上高" : "得意先番号　得意先名　住所　残高");
            foreach (var c in rows) report.AppendLine(turnover
                ? $"{c.Code}　{c.Details.Name}　{SalesLedger.Amount(c.Turnover)}"
                : $"{c.Code}　{c.Details.Name}　{c.Details.Address1}　{c.Details.Address2}　{SalesLedger.Amount(c.Balance)}");
            return ShowReport(title, "prt-1", report.ToString());
        });
    }

    private static bool Compare(int x, int y, string? op) => op switch { "L" => x < y, "E" => x == y, "G" => x > y, _ => true };
}
