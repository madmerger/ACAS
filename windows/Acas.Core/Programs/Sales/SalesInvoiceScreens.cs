using System.Globalization;

namespace Acas.Core.Programs.Sales;

public sealed partial class SalesScreens
{
    private const string InvoiceMenuTitle = "請求書サブシステム";
    private static readonly Choice[] InvoiceKinds = Enum.GetValues<InvoiceKind>()
        .Select(kind => new Choice(((int)kind).ToString(CultureInfo.InvariantCulture), SalesLedger.InvoiceType(kind))).ToArray();
    private Screen OpenInvoiceMenu() => sales.SystemRecord().I("Next-Invoice") == 0 ? InvoiceSettings() : InvoiceMenu();

    private MenuScreen InvoiceMenu() => new(InvoiceMenuTitle,
    [
        Link("SalesInvoiceFixed", "請求書固定項目設定", InvoiceSettings, 1),
        Link("SalesInvoiceBatch", "請求書入力・一括印刷待ち", () => InvoiceEntry("請求書入力・一括印刷待ち", false), 2),
        Link("SalesInvoiceImmediate", "請求書入力・即時印刷", () => InvoiceEntry("請求書入力・即時印刷", true), 3),
        Link("SalesInvoiceAmend", "請求書修正", () => InvoiceSelect("請求書修正", false), 4),
        Link("SalesInvoiceDelete", "請求書削除", () => InvoiceSelect("請求書削除", true), 5),
        Link("SalesInvoiceDeletionReport", "請求削除帳票", () => ShowReport("請求削除帳票", "prt-1", sales.DeletionReport()), 6),
        Link("SalesInvoicePrint", "請求書印刷", () => InvoicePrint(false), 7),
        Link("SalesInvoicePickingPrint", "配送・出庫票印刷", () => InvoicePrint(true), 8),
        Link("SalesInvoiceBack", "売掛元帳に戻る", MainMenu, 9)
    ]);

    private Screen InvoiceSettings()
    {
        const string title = "請求書固定項目設定";
        var system = sales.SystemRecord();
        string kind = system.St("Extra-Type");
        return Form(title,
        [
            IntegerField("SalesFixedNumber", "次回請求番号", system.I("Next-Invoice"), 8),
            new TextField("SalesFixedDescription", "追加料金・値引きの摘要", system.St("Extra-Desc"), 14),
            new ChoiceField("SalesFixedType", "追加料金・値引きの区分", [new("", "なし"), new("C", "追加料金"), new("D", "値引き")], kind),
            Toggle("SalesFixedPrint", "追加料金・値引きを印刷", system.St("Extra-Print") == "Y"),
            AmountField("SalesFixedRate", "追加料金・値引きの税率", system.N("Extra-Rate"), 5),
            new ChoiceField("SalesFixedLevel", "請求入力レベル", [new("1", "1　簡易"), new("2", "2　詳細")], system.I("Invoicer") == 1 ? "1" : "2"),
            Toggle("SalesFixedStock", "在庫連携", system.St("SL-Stock-Link") == "Y"),
            Toggle("SalesFixedAudit", "在庫の監査記録を作成", system.St("SL-Stock-Audit") == "Y"),
            IntegerField("SalesFixedChargeAccount", "追加料金・値引きの勘定番号", system.I("Extra-Charge-Ac"), 6),
            IntegerField("SalesFixedVatAccount", "税の勘定番号", system.I("Vat-Ac"), 6),
            IntegerField("SalesFixedRetention", "仮請求書の保存日数", system.I("PF-Retention"), 3)
        ], "保存内容を確認", v => Confirm(title, "請求書固定項目を保存しますか。", "保存", () =>
        {
            sales.SaveInvoiceSettings(Integer(v, "SalesFixedNumber", "次回請求番号", 0, 99_999_999),
                v.Text("SalesFixedDescription"), v.Choice("SalesFixedType") ?? "", v.Choice("SalesFixedPrint") == "1",
                Decimal(v, "SalesFixedRate", "追加料金・値引きの税率", 99.99m), v.Choice("SalesFixedLevel") == "1" ? 1 : 2,
                v.Choice("SalesFixedStock") == "1", v.Choice("SalesFixedAudit") == "1",
                Integer(v, "SalesFixedChargeAccount", "追加料金・値引きの勘定番号", 0, 999999),
                Integer(v, "SalesFixedVatAccount", "税の勘定番号", 0, 999999),
                Integer(v, "SalesFixedRetention", "仮請求書の保存日数", 0, 999));
            return InvoiceMenu();
        }, InvoiceSettings));
    }

    private Screen InvoiceEntry(string title, bool immediate, SalesInvoice? existing = null)
    {
        var system = sales.SystemRecord();
        var old = existing?.Input;
        bool own = system.St("Sl-Own-Nos") == "Y";
        List<Field> fields =
        [
            new DateField("SalesInvoiceDate", "請求日", old?.Date ?? SalesLedger.DecodeDate(system.I("Run-Date")) ?? Now.Date),
            new TextField("SalesInvoiceCustomer", "得意先番号", old?.Customer ?? "", 7),
            new TextField("SalesInvoiceReference", "参照番号", old?.Reference ?? "", 10),
            new TextField("SalesInvoiceOrder", "注文番号", old?.Order ?? "", 10),
            new ChoiceField("SalesInvoiceType", "請求書の種類", InvoiceKinds,
                ((int)(old?.Kind ?? InvoiceKind.Account)).ToString(CultureInfo.InvariantCulture))
        ];
        if (own && existing == null) fields.Add(IntegerField("SalesInvoiceNumber", "請求番号", system.I("Next-Invoice"), 8));
        fields.AddRange(
        [
            IntegerField("SalesInvoiceCreditFor", "元の請求番号（貸方伝票のみ）", old?.CreditFor ?? 0, 8),
            new TextField("SalesInvoiceDescription", "摘要", old?.Description ?? "", 32),
            AmountField("SalesInvoiceCarriage", "送料", old?.Carriage ?? 0, 10),
            new TextField("SalesInvoiceCreditDays", "支払期限（日数・空欄の場合は既定値）",
                old?.CreditDays?.ToString(CultureInfo.InvariantCulture) ?? "", 3)
        ]);
        return Form(title, fields, "明細へ進む", v =>
        {
            string code = v.Text("SalesInvoiceCustomer").ToUpperInvariant();
            _ = sales.GetCustomer(code);
            var input = new InvoiceInput(v.Date("SalesInvoiceDate") ?? throw new SalesRuleException("請求日を入力してください。"),
                code, v.Text("SalesInvoiceReference"), v.Text("SalesInvoiceOrder"),
                (InvoiceKind)(v.Choice("SalesInvoiceType")?[0] - '0' ?? 0),
                own && existing == null ? Integer(v, "SalesInvoiceNumber", "請求番号", 0, 99_999_999) : old?.Number,
                Integer(v, "SalesInvoiceCreditFor", "元の請求番号", 0, 99_999_999), v.Text("SalesInvoiceDescription"),
                Decimal(v, "SalesInvoiceCarriage", "送料", 9_999_999.99m),
                string.IsNullOrWhiteSpace(v.Text("SalesInvoiceCreditDays")) ? null :
                    Integer(v, "SalesInvoiceCreditDays", "支払期限", 0, 127));
            return existing == null ? InvoiceLineForm(title, immediate, input, [], null) :
                DraftInvoice(title, immediate, input, existing.Lines, existing.Key);
        });
    }

    private Screen InvoiceLineForm(string title, bool immediate, InvoiceInput input, IReadOnlyList<InvoiceLine> lines,
        string? previous, int? index = null)
    {
        var line = index == null ? null : lines[index.Value];
        var vatCodes = Enumerable.Range(1, 5).Select(i => new Choice(i.ToString(CultureInfo.InvariantCulture),
            $"{i}　税率{SalesLedger.Amount(sales.SystemRecord().N("Vat-Rate-" + i))}％")).ToArray();
        return Form("請求明細入力",
        [
            new TextField("SalesLineProduct", "品目コード", line?.Product ?? "", 13),
            new TextField("SalesLineAnalysis", "分析コード", line?.Analysis ?? "", 2),
            new TextField("SalesLineDescription", "品目名", line?.Description ?? "", 32),
            IntegerField("SalesLineQuantity", "数量", line?.Quantity ?? 1, 5),
            AmountField("SalesLineUnitPrice", "単価", line?.UnitPrice ?? 0, 10),
            AmountField("SalesLineDiscount", "値引率", line?.Discount ?? sales.GetCustomer(input.Customer).Details.Discount, 5),
            new ChoiceField("SalesLineVatCode", "税区分", vatCodes, (line?.VatCode ?? 1).ToString(CultureInfo.InvariantCulture))
        ], "明細を確定", v =>
        {
            var item = new InvoiceLine(v.Text("SalesLineProduct"), v.Text("SalesLineAnalysis"), v.Text("SalesLineDescription"),
                Integer(v, "SalesLineQuantity", "数量", 1, short.MaxValue), Decimal(v, "SalesLineUnitPrice", "単価", 9_999_999.99m),
                Decimal(v, "SalesLineDiscount", "値引率", 99.99m), v.Choice("SalesLineVatCode")?[0] - '0' ?? 1);
            return DraftInvoice(title, immediate, input,
                index is int at ? lines.Select((l, i) => i == at ? item : l).ToArray() : [..lines, item], previous);
        });
    }

    private Screen DraftInvoice(string title, bool immediate, InvoiceInput input, IReadOnlyList<InvoiceLine> lines, string? previous)
    {
        List<MenuItem> items = [];
        if (lines.Count < 40) items.Add(Link("SalesInvoiceAddLine", "明細を追加", () => InvoiceLineForm(title, immediate, input, lines, previous)));
        items.Add(Link("SalesInvoiceDraftLines", "明細一覧", () => new TableScreen("請求明細", "SalesDraftLineTable",
            ["品目コード", "品目名", "数量", "単価", "値引率", "税区分"], lines.Select((line, i) => new TableRow(
                [line.Product, line.Description, line.Quantity.ToString(CultureInfo.InvariantCulture), SalesLedger.Amount(line.UnitPrice),
                 SalesLedger.Amount(line.Discount), line.VatCode.ToString(CultureInfo.InvariantCulture)],
                () => InvoiceLineForm(title, immediate, input, lines, previous, i),
                [line.Product, line.Description, line.Quantity, line.UnitPrice, line.Discount, line.VatCode])).ToArray())));
        if (lines.Count > 0) items.Add(Link("SalesInvoiceSaveDraft", immediate ? "保存して印刷" : "請求を保存", () =>
            Confirm(title, $"{input.Customer}の請求書（明細{lines.Count}行）を{(immediate ? "保存して印刷" : "保存")}しますか。",
                immediate ? "保存して印刷" : "保存", () =>
                {
                    int number = sales.SaveInvoice(input, lines, previous);
                    return immediate ? new ReportScreen("請求書", sales.PrintInvoices(false, false, number, Now)) :
                        new InformationScreen(title, $"請求番号{number:D8}を保存しました。");
                }, () => DraftInvoice(title, immediate, input, lines, previous))));
        items.Add(Link("SalesInvoiceCancelDraft", "入力を取り消す", InvoiceMenu));
        return new MenuScreen(title, items);
    }

    private Screen InvoiceSelect(string title, bool delete) => Form(title,
        [new TextField("SalesFindInvoiceNumber", "請求番号", "00000000", 8)], "検索", v =>
        {
            int number = Integer(v, "SalesFindInvoiceNumber", "請求番号", 0, 99_999_999);
            var records = sales.Invoices().Where(i => i.Number == number).ToArray();
            if (records.Length == 0) return new InformationScreen(title, "請求書が見つかりません。");
            Screen Select(SalesInvoice invoice) => delete
                ? Confirm(title, $"請求番号{invoice.Number:D8}を削除しますか。", "削除",
                    () => { sales.DeleteInvoice(invoice); return InvoiceMenu(); }, () => InvoiceSelect(title, true))
                : InvoiceEntry(title, false, invoice);
            if (records.Length == 1) return Select(records[0]);
            return new TableScreen(title, "SalesFindInvoiceResults", ["請求番号", "得意先番号", "種類", "税込額"],
                records.Select(i => new TableRow([i.Number.ToString("D8", CultureInfo.InvariantCulture), i.Input.Customer,
                    SalesLedger.InvoiceType(i.Input.Kind), SalesLedger.Amount(i.Gross)], () => Select(i))).ToArray());
        });

    private Screen InvoicePrint(bool picking)
    {
        string title = picking ? "配送・出庫票印刷" : "請求書印刷";
        sales.KeepReport(picking ? "prt-3" : "prt-2", "");
        return Form(title,
            [new ChoiceField("SalesPrintMode", "印刷方法", [new("P", "通常印刷"), new("R", "再印刷")], "P")],
            "印刷を確認", v => Confirm(title, "印刷対象の帳票を作成しますか。", "作成",
                () => new ReportScreen(title, sales.PrintInvoices(v.Choice("SalesPrintMode") == "R", picking, printedAt: Now)), () => InvoicePrint(picking)));
    }

    private Screen InvoiceProof()
    {
        const string title = "売上検証帳票";
        string report = sales.InvoiceProof();
        return report.Length == 0 ? new InformationScreen(title, "検証対象の売上取引がありません。") :
            ShowReport(title, "prt-1", report);
    }
}
