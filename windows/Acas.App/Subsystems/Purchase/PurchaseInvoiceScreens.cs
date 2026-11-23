using System.Globalization;
using Acas.Core;
using Acas.Core.Programs.Purchase;

namespace Acas.App.Subsystems.Purchase;

internal sealed partial class PurchaseScreens
{
    private static readonly Choice[] InvoiceTypes = [new("1", "領収"), new("2", "掛仕入"), new("3", "貸方票")];
    private static readonly Choice[] TaxCodes = [new("0", "非課税"), new("1", "税区分一"), new("2", "税区分二"), new("3", "税区分三")];

    private static TextField Text(string id, string label, string value, int width) => new("Purchase" + id, label, value, width);
    private static bool Number(FormValues values, string id, out int result) =>
        int.TryParse(values.Text("Purchase" + id), NumberStyles.None, CultureInfo.InvariantCulture, out result);
    private static bool Amount(FormValues values, string id, out decimal result) =>
        decimal.TryParse(values.Text("Purchase" + id), NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out result) &&
        decimal.Round(result, 2) == result;

    private Screen InvoiceEntry() => InvoiceHeaderForm("仕入取引入力", null);

    private Screen InvoiceHeaderForm(string title, PurchaseInvoice? original)
    {
        string folio = original?.Folio ?? _ledger.NextFolio;
        return new FormScreen(title,
        [
            new DateField("PurchaseInvoiceDate", "仕入日", original?.Date ?? _ledger.ProcessingDate),
            Text("InvoiceSupplier", "仕入先コード", original?.Supplier ?? "", 7),
            Text("InvoiceOrder", "注文番号", original?.Order ?? "", 10),
            Text("InvoiceReference", "請求書番号", original?.Reference ?? "", 10),
            new ChoiceField("PurchaseInvoiceType", "取引区分", InvoiceTypes, (original?.Type ?? 2).ToString(CultureInfo.InvariantCulture))
        ], "明細へ", values =>
        {
            var date = values.Date("PurchaseInvoiceDate");
            if (date is null || PurchaseLedger.EncodeDate(date.Value) <= 0) return Notice(title, "仕入日を確認してください。");
            string code = values.Text("PurchaseInvoiceSupplier").Trim().ToUpperInvariant();
            if (_ledger.GetSupplier(code) is not { } supplier) return Notice(title, "仕入先が見つかりません。");
            string order = values.Text("PurchaseInvoiceOrder"), reference = values.Text("PurchaseInvoiceReference");
            if (!PurchaseLedger.FitsRecord(order, 10) || !PurchaseLedger.FitsRecord(reference, 10))
                return Notice(title, "注文番号または請求書番号に台帳へ保存できない文字が含まれています。");
            if (!int.TryParse(values.Choice("PurchaseInvoiceType"), out int type)) return Notice(title, "取引区分を選択してください。");
            var invoice = new PurchaseInvoice(folio, code, date.Value, order, reference, type, original?.Lines ?? [],
                original?.CreditDays ?? (type == 2 ? supplier.I("credit") : 0), original?.Discount ?? 0,
                original?.DiscountDays ?? 0, original?.Carriage ?? 0, original?.CarriageTax ?? 0,
                CreditFolio: type == 3 ? original?.CreditFolio ?? 0 : 0);
            return type == 3 ? CreditTarget(title, invoice, original == null) : EditInvoiceLines(title, invoice, original == null);
        });
    }

    private Screen CreditTarget(string title, PurchaseInvoice invoice, bool create) => new FormScreen(title,
        [Text("CreditFolio", "貸方の対象となる掛仕入伝票番号（指定なしは０）",
            invoice.CreditFolio.ToString(CultureInfo.InvariantCulture), 8)], "明細へ", values =>
        {
            if (!Number(values, "CreditFolio", out int number) || number is < 0 or >= 99999999)
                return Notice(title, "対象の伝票番号を確認してください。");
            var next = invoice with { CreditFolio = number };
            if (number == 0) return EditInvoiceLines(title, next, create);
            string folio = number.ToString("00000000", CultureInfo.InvariantCulture);
            if (folio == invoice.Folio) return Notice(title, "貸方票自身を対象にできません。");
            if (_ledger.Invoice(folio) is not { } target)
                return new ConfirmationScreen(title,
                    "対象の伝票が見つかりません。同じ仕入先の掛仕入伝票であることを確認して続けますか。", "続ける",
                    () => EditInvoiceLines(title, next, create, true), () => CreditTarget(title, next, create));
            if (target.Type != 2 || target.Supplier != invoice.Supplier)
                return Notice(title, "同じ仕入先の掛仕入伝票を指定してください。");
            return EditInvoiceLines(title, next, create);
        });

    private Screen EditInvoiceLines(string title, PurchaseInvoice invoice, bool create, bool acceptMissingCreditTarget = false) => new MenuScreen(title,
    [
        new("PurchaseInvoiceAddLine", "明細を追加", Open: () => InvoiceLineForm(title, invoice, create, invoice.Lines.Count, acceptMissingCreditTarget)),
        new("PurchaseInvoiceViewLines", "明細の確認・修正", Open: () => new TableScreen(title, "PurchaseInvoiceLines",
            ["分析コード", "摘要", "税抜額", "税額"], invoice.Lines.Select((line, index) => new TableRow(
                [line.Code, CleanDescription(line.Description), Money(line.Net), Money(line.Tax)],
                () => InvoiceLineForm(title, invoice, create, index, acceptMissingCreditTarget),
                [line.Code, line.Description, line.Net, line.Tax])).ToArray())),
        new("PurchaseInvoiceTotals", "合計・保存へ", Open: () => InvoiceTotals(title, invoice, create, acceptMissingCreditTarget))
    ]);

    private static string CleanDescription(string text) => text.Replace("\0", "");

    private Screen InvoiceLineForm(string title, PurchaseInvoice invoice, bool create, int index, bool acceptMissingCreditTarget)
    {
        if (index >= 40) return Notice(title, "明細は四十件まで登録できます。");
        var line = index < invoice.Lines.Count ? invoice.Lines[index] : null;
        return new FormScreen(title,
        [
            Text("LineAnalysis", "分析コード", line?.Code ?? "", 2),
            Text("LineNet", "税抜額", line is null ? "" : Money(line.Net), 10),
            new ChoiceField("PurchaseLineTaxCode", "税区分", TaxCodes, (line?.TaxCode ?? 0).ToString(CultureInfo.InvariantCulture)),
            Text("LineTax", "税額（空欄なら計算）", line is null ? "" : Money(line.Tax), 9)
        ], "明細を確定", values =>
        {
            string code = values.Text("PurchaseLineAnalysis");
            if (string.IsNullOrWhiteSpace(code) || !PurchaseLedger.FitsRecord(code, 2)
                || !Amount(values, "LineNet", out decimal net) || net is <= 0 or > 9999999.99m
                || !int.TryParse(values.Choice("PurchaseLineTaxCode"), out int taxCode))
                return Notice(title, "分析コード、税抜額、税区分を確認してください。");
            var analysis = _ledger.Analysis(code);
            if (analysis is null && !_ledger.HasInvalidAnalysisLength) return Notice(title, "分析コードが見つかりません。");
            decimal vat = decimal.Round(net * _ledger.TaxRate(taxCode) / 100, 2, MidpointRounding.AwayFromZero);
            if (!string.IsNullOrWhiteSpace(values.Text("PurchaseLineTax")) && !Amount(values, "LineTax", out vat))
                return Notice(title, "税額を確認してください。");
            if (vat > 999999.99m) return Notice(title, "税額が上限を超えています。");
            var lines = invoice.Lines.ToList();
            var next = new PurchaseLine(code.PadRight(2), net, taxCode, vat, analysis?.St("description") ?? "");
            if (index == lines.Count) lines.Add(next);
            else lines[index] = next;
            return EditInvoiceLines(title, invoice with { Lines = lines }, create, acceptMissingCreditTarget);
        });
    }

    private Screen InvoiceTotals(string title, PurchaseInvoice invoice, bool create, bool acceptMissingCreditTarget)
    {
        if (invoice.Lines.Count == 0) return Notice(title, "明細を一件以上追加してください。");
        var fields = new List<Field>
        {
            Text("InvoiceCarriage", "送料", Money(invoice.Carriage), 10),
            Text("InvoiceCarriageTax", "送料の税額（空欄なら計算）", create ? "" : Money(invoice.CarriageTax), 9)
        };
        if (invoice.Type == 2)
        {
            fields.Add(Text("InvoiceCreditDays", "支払猶予日数", invoice.CreditDays.ToString("00"), 2));
            fields.Add(Text("InvoiceDiscount", "早期支払割引額", Money(invoice.Discount), 6));
            fields.Add(Text("InvoiceDiscountDays", "割引適用日数", invoice.DiscountDays.ToString("00"), 2));
        }
        return new FormScreen(title, fields, "保存内容を確認", values =>
        {
            int credit = 0, discountDays = 0;
            decimal discount = 0;
            if (!Amount(values, "InvoiceCarriage", out decimal carriage) ||
                (invoice.Type == 2 && (!Number(values, "InvoiceCreditDays", out credit) ||
                    !Amount(values, "InvoiceDiscount", out discount) || !Number(values, "InvoiceDiscountDays", out discountDays))))
                return Notice(title, "送料、支払猶予日数、早期支払割引を確認してください。");
            decimal tax = decimal.Round(carriage * _ledger.TaxRate(1) / 100, 2, MidpointRounding.AwayFromZero);
            if (!string.IsNullOrWhiteSpace(values.Text("PurchaseInvoiceCarriageTax")) && !Amount(values, "InvoiceCarriageTax", out tax))
                return Notice(title, "送料の税額を確認してください。");
            var next = invoice with { CreditDays = credit, DiscountDays = discount == 0 ? 0 : discountDays,
                Discount = discount, Carriage = carriage, CarriageTax = tax };
            return new ConfirmationScreen(title, $"伝票「{invoice.Folio}」、合計 {Money(next.Total)} を保存しますか。", "保存",
                () => Notice(title, _ledger.SaveInvoice(next, create, acceptMissingCreditTarget)
                    ? "仕入取引を保存しました。" : "入力内容または台帳の状態を確認してください。"),
                () => EditInvoiceLines(title, invoice, create, acceptMissingCreditTarget));
        });
    }

    private Screen FindInvoice(bool delete)
    {
        string title = delete ? "仕入取引削除" : "仕入取引修正";
        if (delete && !_ledger.InvoiceFileAvailable) return Notice(title, "仕入伝票ファイルがありません。");
        return new FormScreen(title, [Text("InvoiceFolio", "伝票番号", "", 8)], "検索", values =>
        {
            if (!Number(values, "InvoiceFolio", out int number) || number is < 1 or > 99999999)
                return Notice(title, "伝票番号を確認してください。");
            string folio = number.ToString("00000000", CultureInfo.InvariantCulture);
            if (_ledger.Invoice(folio) is not { } invoice) return Notice(title, "仕入伝票が見つかりません。");
            if (invoice.Posted) return Notice(title, "転記済みの仕入伝票は変更・削除できません。");
            if (!delete) return InvoiceHeaderForm(title, invoice);
            return new ConfirmationScreen(title, $"伝票「{folio}」、合計 {Money(invoice.Total)} を削除しますか。", "削除",
                () => Notice(title, _ledger.DeleteInvoice(folio) ? "仕入伝票を削除しました。" : "仕入伝票を削除できませんでした。"),
                () => FindInvoice(true));
        });
    }

    private MenuItem[] InvoiceItems() =>
    [
        Item("U1", 1, "伝票の固定設定を変更", InvoiceSettings),
        Item("U2", 2, "仕入取引入力", InvoiceEntry),
        Item("U3", 3, "仕入取引修正", () => FindInvoice(false)),
        Item("U4", 4, "仕入取引削除", () => FindInvoice(true)),
        Item("U5", 5, "仕入の検証帳票", InvoiceProof),
        Item("U9", 9, "買掛メニューに戻る", MainMenu)
    ];

    private MenuScreen InvoiceMenu() => new("仕入伝票メニュー", InvoiceItems());
    private Screen Invoicing() => _ledger.System().I("Next-Folio") == 0 ? InvoiceSettings() : InvoiceMenu();

    private Screen InvoiceSettings()
    {
        const string title = "仕入伝票の固定設定";
        var system = _ledger.System();
        var fields = new List<Field> { Text("NextFolio", "次の伝票番号", system.I("Next-Folio").ToString("00000000"), 8) };
        if (_ledger.GeneralLedgerEnabled) fields.Add(Text("TaxAccount", "税勘定コード", system.I("Vat-Ac").ToString("000000"), 6));
        return new FormScreen(title, fields, "確認", values =>
        {
            int account = 0;
            bool hasAccount = fields.Count == 2;
            if (!Number(values, "NextFolio", out int folio) || folio is < 1 or > 99999999 ||
                (hasAccount && (!Number(values, "TaxAccount", out account) || account > 999999)))
                return Notice(title, "伝票番号と税勘定コードを確認してください。");
            return new ConfirmationScreen(title, "固定設定を保存しますか。", "保存",
                () => _ledger.SaveInvoiceSettings(folio, hasAccount ? account : null) ? InvoiceMenu() : Notice(title, "設定を保存できませんでした。"),
                InvoiceSettings);
        });
    }

    private Screen InvoiceProof()
    {
        const string title = "仕入の検証帳票";
        if (!_ledger.InvoicesPending) return Notice(title, "検証する仕入取引がありません。");
        return new FormScreen(title, [], "帳票を作成", _ => InvoiceJournal(title, _ledger.Invoices().Where(invoice => !invoice.Posted).ToArray()));
    }

    private Screen DayBook()
    {
        const string title = "仕入日計帳";
        if (!_ledger.InvoiceFileAvailable) return Notice(title, "仕入伝票ファイルがありません。");
        return new FormScreen(title, [], "帳票を作成", _ => InvoiceJournal(title, _ledger.Invoices().Where(invoice => invoice.Posted).ToArray()));
    }

    private Screen InvoicePost()
    {
        const string title = "仕入転記";
        if (!_ledger.InvoicesPending) return Notice(title, "転記する仕入取引がありません。");
        return new FormScreen(title, [], "転記内容を確認", _ => new ConfirmationScreen(title, "仕入取引を転記しますか。", "転記", () =>
        {
            var balances = _ledger.Suppliers().ToDictionary(record => record.St("key"),
                record => record.N("current") - record.N("unapplied"), StringComparer.Ordinal);
            var posted = _ledger.PostInvoices();
            return posted is null ? Notice(title, "未対応の取引、または台帳の状態により転記できません。") : InvoiceJournal(title, posted, balances);
        }, MainMenu));
    }

    private Screen InvoiceJournal(string title, IReadOnlyList<PurchaseInvoice> invoices, Dictionary<string, decimal>? balances = null)
    {
        bool posting = balances != null;
        int page = 0, line = 0, pageSize = Math.Max(12, _ledger.System().I("Page-Lines"));
        var body = new System.Text.StringBuilder();
        NewPage();
        foreach (var invoice in invoices)
        {
            if (!posting && line > pageSize) NewPage();
            decimal sign = invoice.Type == 3 ? -1 : 1;
            string supplier = _ledger.GetSupplier(invoice.Supplier)?.St("name") ?? "仕入先不明";
            body.AppendLine($"{invoice.Folio.TrimStart('0')}　{DateText(invoice.Date)}　{invoice.Supplier}　{supplier}　{InvoiceTypes[invoice.Type - 1].Label}");
            if (balances != null)
            {
                decimal previous = balances.GetValueOrDefault(invoice.Supplier);
                decimal next = previous + (invoice.Type == 1 ? 0 : sign * invoice.Total);
                balances[invoice.Supplier] = next;
                body.AppendLine($"前残高 {Money(previous)}　新残高 {Money(next)}");
            }
            else
                body.AppendLine($"商品額 {Money(sign * invoice.Net)}");
            body.AppendLine($"税抜額 {Money(sign * (invoice.Net + invoice.Carriage))}　税額 {Money(sign * (invoice.Tax + invoice.CarriageTax))}　合計 {Money(sign * invoice.Total)}");
            line += posting ? 1 : 2;
            if (posting && line > pageSize) NewPage();
            if (!posting)
            {
                foreach (var item in invoice.Lines)
                {
                    body.AppendLine($"分析 {item.Code.TrimEnd()}　金額 {Money(sign * item.Net)}　税区分 {item.TaxCode}");
                    if (++line > pageSize) NewPage();
                }
                if (line > pageSize - 2) NewPage();
                if (invoice.Discount != 0)
                {
                    body.AppendLine($"早期支払割引 {Money(invoice.Type == 2 ? -invoice.Discount : invoice.Discount)}");
                    line++;
                }
                if (invoice.Carriage != 0)
                {
                    body.AppendLine($"送料 {Money(sign * invoice.Carriage)}　税区分 {(invoice.CarriageTax == 0 ? 0 : 1)}");
                    line++;
                }
            }
        }
        if (!posting || line > pageSize - 7) NewPage(summary: !posting);
        if (!posting)
            body.AppendLine("商品額　送料　税抜額　税額　合計　早期支払割引");
        for (int type = 1; type <= 3; type++)
        {
            var rows = invoices.Where(invoice => invoice.Type == type).ToArray();
            decimal sign = type == 3 ? -1 : 1;
            body.Append($"{InvoiceTypes[type - 1].Label}合計　");
            if (!posting)
                body.Append($"商品額 {Money(sign * rows.Sum(invoice => invoice.Net))}　送料 {Money(sign * rows.Sum(invoice => invoice.Carriage))}　");
            body.Append($"税抜額 {Money(sign * rows.Sum(invoice => invoice.Net + invoice.Carriage))}　税額 {Money(sign * rows.Sum(invoice => invoice.Tax + invoice.CarriageTax))}　合計 {Money(sign * rows.Sum(invoice => invoice.Total))}");
            if (!posting)
                body.Append($"　早期支払割引 {Money((type == 2 ? -1 : 1) * rows.Sum(invoice => invoice.Discount))}");
            body.AppendLine();
        }
        if (!posting)
        {
            body.AppendLine("税額照合　領収　掛仕入　貸方票");
            for (int code = 1; code <= 3; code++)
            {
                body.Append($"税区分 {code}　税率 {Money(_ledger.TaxRate(code))}％");
                for (int type = 1; type <= 3; type++)
                {
                    var rows = invoices.Where(invoice => invoice.Type == type);
                    var tax = rows.Sum(invoice => invoice.Lines.Where(item => item.TaxCode == code).Sum(item => item.Tax)
                        + (code == 1 ? invoice.CarriageTax : 0));
                    body.Append($"　{Money(type == 3 ? -tax : tax)}");
                }
                body.AppendLine();
            }
        }
        return _ledger.Report(title, body.ToString());

        void NewPage(bool summary = false)
        {
            if (page != 0) body.Append('\f');
            page++;
            line = 5;
            body.Append(ReportHeading(title)).AppendLine($"ページ {page}");
            if (!summary)
                body.AppendLine("伝票番号　仕入日　仕入先コード　仕入先名　区分")
                    .AppendLine((posting ? "前残高　新残高" : "商品額") + "　税抜額　税額　合計");
        }
    }
}
