using System.Globalization;
using System.Text;
using Acas.Core;
using Acas.Core.Programs.Purchase;

namespace Acas.App.Subsystems.Purchase;

internal sealed partial class PurchaseScreens
{
    private Screen ChequeDue()
    {
        const string title = "支払予定生成";
        return new FormScreen(title, [Text("ChequeAge", "支払対象の経過日数", _ledger.System().I("Age-To-Pay").ToString("00"), 2)],
            "確認", values =>
            {
                if (!OpenItemsAvailable()) return Notice(title, "未決済明細ファイルがありません。");
                if (!Number(values, "ChequeAge", out int age) || age is < 0 or > 99)
                    return Notice(title, "経過日数を確認してください。");
                return new ConfirmationScreen(title, "既存の支払予定を置き換えますか。", "生成", () => _ledger.CreatePaymentSchedule(age)
                    ? ScheduledPaymentReport(title) : Notice(title, "経過日数または台帳の状態を確認してください。"), ChequeMenu);
            });
    }

    private Screen ChequeAmend()
    {
        const string title = "支払予定修正";
        return new FormScreen(title,
            [Text("ChequeSupplier", "仕入先コード", "", 7), Text("ChequeNumber", "支払予定番号", "01", 2)], "照会", values =>
            {
                string code = values.Text("PurchaseChequeSupplier").Trim().ToUpperInvariant();
                if (!Number(values, "ChequeNumber", out int number) || _ledger.ScheduledPayments()?.FirstOrDefault(
                        payment => payment.Supplier == code && payment.Number == number) is not { } payment)
                    return Notice(title, "支払予定が見つかりません。");
                return new FormScreen(title, payment.Lines.Select(line => (Field)Text("ChequeLine" + line.Slot,
                    $"明細 {line.Slot}・伝票 {line.Folio} の支払額", Money(line.Amount), 10)).ToArray(), "変更を確認", inputs =>
                {
                    var amounts = new Dictionary<int, decimal>();
                    foreach (var line in payment.Lines)
                    {
                        if (!Amount(inputs, "ChequeLine" + line.Slot, out decimal amount))
                            return Notice(title, "支払額を確認してください。");
                        amounts.Add(line.Slot, amount);
                    }
                    return new ConfirmationScreen(title, "支払予定を保存しますか。", "保存",
                        () => Notice(title, _ledger.AmendPaymentSchedule(code, number, amounts)
                            ? "支払予定を保存しました。" : "金額または支払予定の状態を確認してください。"), ChequeMenu);
                });
            });
    }

    private Screen ChequeGenerate()
    {
        const string title = "小切手データ生成";
        if (!_ledger.PaymentDataAvailable) return Notice(title, "処理するデータがありません。");
        return new FormScreen(title, [Text("FirstChequeNumber", "最初の小切手番号", "", 8),
            new DateField("PurchaseChequeDate", "支払日", _ledger.ProcessingDate)], "確認", values =>
        {
            if (!Number(values, "FirstChequeNumber", out int number) || values.Date("PurchaseChequeDate") is not { } date)
                return Notice(title, "小切手番号と支払日を確認してください。");
            return new ConfirmationScreen(title, "小切手データと支払予定日を更新しますか。", "生成",
                () => Notice(title, _ledger.GenerateChequeData(number, date)
                    ? "小切手データを生成しました。" : "支払予定の状態を確認してください。"), ChequeMenu);
        });
    }

    private Screen ChequeRegister()
    {
        const string title = "小切手・銀行振込台帳印刷";
        return new FormScreen(title, [], "確認", _ =>
            new ConfirmationScreen(title, "未決済明細を更新します。続行しますか。", "続行", () =>
            {
                if (_ledger.ApplyChequeRegister() is not { } payments)
                    return Notice(title, "処理する支払予定がないか、台帳の状態が変わりました。");
                var body = new StringBuilder();
                int limit = Math.Max(7, _ledger.System().I("Page-Lines"));
                int page = 0, lines = 0;
                Heading();
                foreach (var payment in payments)
                {
                    if (lines + 2 > limit) Heading();
                    body.AppendLine($"{payment.Supplier}　{SupplierNameForDisplay(payment.Supplier)}　{DateText(payment.Date)}");
                    body.AppendLine(payment.BankTransfer
                        ? $"振込　銀行番号 {payment.SortCode:000000}　口座番号 {payment.Account:00000000}　{Money(payment.Gross)}"
                        : $"小切手番号 {payment.Cheque}　{Money(payment.Gross)}");
                    lines += 2;
                }
                if (lines == limit) Heading();
                body.AppendLine($"合計　{Money(payments.Sum(payment => payment.Gross))}");
                return _ledger.Report(title, body.ToString(), ChequeMenu);

                void Heading()
                {
                    if (page > 0) body.Append('\f');
                    body.Append(ReportHeading(title)).AppendLine($"ページ {++page}");
                    body.AppendLine("仕入先コード　仕入先名　支払日").AppendLine("小切手番号・振込先　支払額");
                    lines = 6;
                }
            }, ChequeMenu));
    }

    private Screen RemittanceReport()
    {
        const string title = "送金案内";
        if (_ledger.Remittances() is not { Count: > 0 } remittances) return ChequeMenu();
        var body = new StringBuilder();
        var system = _ledger.System();
        string format = system.I("Date-Form") switch { 2 => "MM/dd/yyyy", 3 => "yyyy/MM/dd", _ => "dd/MM/yyyy" };
        foreach (var remittance in remittances)
        {
            if (body.Length > 0) body.Append('\f');
            string name = remittance.Name == "PL902 Missing data" ? "仕入先不明" : PurchaseLedger.DisplaySupplierName(remittance.Name);
            body.AppendLine(title).AppendLine($"宛先　{name}");
            foreach (string address in remittance.Address.Where(address => address.Length > 0 && address != "PL902 Missing data"))
                body.AppendLine(address);
            body.AppendLine($"差出人　{system.St("Usera")}");
            for (int line = 1; line <= 4; line++)
                if (system.St($"Address-{line}") is { Length: > 0 } address) body.AppendLine(address);
            body.AppendLine($"仕入先コード　{remittance.Supplier}");
            if (DateTime.TryParseExact(remittance.Date, format, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
                body.AppendLine($"支払日　{DateText(date)}");
            body.AppendLine("請求書番号　伝票番号　支払額");
            foreach (var detail in remittance.Lines)
                body.AppendLine($"{detail.Reference}　{detail.Folio}　{Money(detail.Amount)}");
            body.AppendLine(remittance.Method == "BACS" ? "銀行振込" : $"小切手番号　{remittance.Method}");
            body.AppendLine($"合計　{Money(remittance.Amount)}");
        }
        return _ledger.Report(title, body.ToString(), ChequeMenu);
    }
}
