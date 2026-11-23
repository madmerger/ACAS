namespace Acas.Core.Programs.Sales;

public sealed partial class SalesScreens
{
    private const string PaymentTitle = "入金入力・消込";

    private Screen PaymentEntry()
    {
        if (!sales.HasOpenItems()) return Missing(PaymentTitle, "売掛明細");
        if (sales.SystemRecord().I("S-Flag-I") == 1)
            return new InformationScreen(PaymentTitle, "売上取引を転記してから入金してください。");
        return PaymentCustomer([]);
    }

    private Screen PaymentCustomer(IReadOnlyList<SalesPaymentInput> draft) =>
        CustomerLookup(PaymentTitle, "SalesPaymentCustomer", customer => PaymentDetails(customer, draft));

    private Screen PaymentDetails(SalesCustomer customer, IReadOnlyList<SalesPaymentInput> draft)
    {
        const decimal maximum = 999_999.99m;
        var reserved = draft.Where(p => p.Customer == customer.Code).SelectMany(p => p.Allocations)
            .Where(a => a.Amount != 0).Select(a => a.Invoice).ToHashSet();
        var invoices = sales.PaymentInvoices(customer.Code).Where(item => !reserved.Contains(item.Number)).ToArray();
        var processingDate = SalesLedger.DecodeDate(sales.SystemRecord().I("Run-Date")) ?? Now.Date;
        List<Field> fields =
        [
            new DateField("SalesPaymentDate", "入金日", processingDate),
            AmountField("SalesPaymentAmount", "入金額", 0, 9)
        ];
        if (customer.Unapplied > 0)
            fields.Add(Toggle("SalesPaymentFromUnapplied", $"未消込残高（{SalesLedger.Amount(customer.Unapplied)}）から振替", true));
        foreach (var item in invoices)
        {
            fields.Add(AmountField("SalesPaymentAllocation" + item.Number,
                $"請求書 {item.Number} の消込額（残高 {SalesLedger.Amount(item.Outstanding)}）", 0, 9));
            if (item.LateCharge != 0)
                fields.Add(Toggle("SalesPaymentWaive" + item.Number,
                    $"請求書 {item.Number} の早期支払値引き（{SalesLedger.Amount(item.LateCharge)}）を適用", true));
        }
        return Form($"{PaymentTitle}　{customer.Code}　{customer.Details.Name}", fields, "バッチに追加", values =>
        {
            var date = values.Date("SalesPaymentDate") ?? throw new SalesRuleException("入金日を入力してください。");
            decimal amount = Decimal(values, "SalesPaymentAmount", "入金額", maximum);
            if (amount == 0) throw new SalesRuleException("入金額を入力してください。");
            var allocations = invoices.Select(item => new PaymentAllocation(item.Number,
                Decimal(values, "SalesPaymentAllocation" + item.Number, "消込額", maximum),
                item.LateCharge != 0 && values.Choice("SalesPaymentWaive" + item.Number) == "1"))
                .Where(a => a.Amount != 0).ToArray();
            if (allocations.Sum(a => a.Amount) > amount) throw new SalesRuleException("消込額の合計が入金額を超えています。");
            return PaymentDraft([.. draft, new(customer.Code, date, amount,
                customer.Unapplied > 0 && values.Choice("SalesPaymentFromUnapplied") == "1", allocations)]);
        });
    }

    private Screen PaymentDraft(IReadOnlyList<SalesPaymentInput> draft)
    {
        List<MenuItem> actions = [];
        if (draft.Count < 999) actions.Add(Link("SalesPaymentContinue", "続けて入金を入力する", () => PaymentCustomer(draft)));
        actions.Add(Link("SalesPaymentSave", "入金バッチを保存する", () =>
            Confirm(PaymentTitle, $"{draft.Count}件、合計 {SalesLedger.Amount(draft.Sum(p => p.Amount))} の入金を保存しますか。",
                "保存", () =>
                {
                    int batch = sales.RecordPaymentBatch(draft);
                    return new InformationScreen(PaymentTitle, $"入金バッチ {batch} を保存しました。");
                }, () => PaymentDraft(draft))));
        return new MenuScreen(PaymentTitle, actions);
    }
}
