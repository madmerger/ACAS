using System.Globalization;
using System.Text;
using Acas.Core;
using Acas.Core.Programs.Purchase;

namespace Acas.App.Subsystems.Purchase;

internal sealed partial class PurchaseScreens
{
    private const string PaymentInputTitle = "支払入力・消込";
    private const string PaymentAmendTitle = "支払修正";
    private const string PaymentProofTitle = "支払の検証帳票";
    private const string PaymentPostTitle = "支払転記";
    private static readonly Choice[] PaymentTypes = [new("payment", "支払"), new("credit", "未消込残高の使用")];

    private Screen PaymentEntry()
    {
        if (!OpenItemsAvailable()) return Notice(PaymentInputTitle, "未決済明細ファイルがありません。");
        if (_ledger.System().I("P-Flag-I") == 1) return Notice(PaymentInputTitle, "先に仕入を転記してください。");
        return new FormScreen(PaymentInputTitle,
        [
            Text("PaymentSupplier", "仕入先コード", "", 7),
            new DateField("PurchasePaymentDate", "支払日", _ledger.ProcessingDate),
            Text("PaymentAmount", "金額", "", 10),
            new ChoiceField("PurchasePaymentType", "支払区分", PaymentTypes, "payment")
        ], "消込明細へ", values =>
        {
            string supplier = values.Text("PurchasePaymentSupplier").Trim().ToUpperInvariant();
            if (_ledger.GetSupplier(supplier) is not { } account) return Notice(PaymentInputTitle, "仕入先が見つかりません。");
            var date = values.Date("PurchasePaymentDate");
            if (!Amount(values, "PaymentAmount", out decimal amount) || amount is <= 0 or > 9999999.99m || date is null)
                return Notice(PaymentInputTitle, "支払日と金額を確認してください。");
            bool useCredit = values.Choice("PurchasePaymentType") == "credit";
            if (useCredit && amount > account.N("unapplied"))
                return Notice(PaymentInputTitle, "未消込残高を超えています。");
            if (_ledger.PayableInvoices(supplier, date.Value) is not { } lines)
                return Notice(PaymentInputTitle, "未決済明細の形式を確認してください。");
            return new FormScreen(PaymentInputTitle, lines.Select(line => (Field)Text("PaymentApplied" + line.Folio,
                $"伝票 {line.Folio}・{DateText(line.Date)}・消込上限 {Money(line.Balance)}・割引 {Money(line.Discount)}", "", 10)).ToArray(),
                "確認", input =>
                {
                    var allocations = new Dictionary<int, decimal>();
                    foreach (var line in lines)
                    {
                        string id = "PaymentApplied" + line.Folio;
                        if (string.IsNullOrWhiteSpace(input.Text("Purchase" + id))) continue;
                        if (!Amount(input, id, out decimal applied) || applied < 0 || applied > line.Balance)
                            return Notice(PaymentInputTitle, "消込額を確認してください。");
                        if (applied != 0) allocations.Add(line.Folio, applied);
                    }
                    decimal total = allocations.Values.Sum();
                    if (total > amount) return Notice(PaymentInputTitle, "消込額が支払額を超えています。");
                    return new ConfirmationScreen(PaymentInputTitle,
                        $"支払額 {Money(amount)}、消込額 {Money(total)}、未消込額 {Money(amount - total)} を保存しますか。", "保存",
                        () => Notice(PaymentInputTitle, _ledger.SavePayment(supplier, date.Value, amount, useCredit, allocations)
                            ? "支払を保存しました。" : "支払日、金額または台帳の状態を確認してください。"), PaymentEntry);
                });
        });
    }

    private Screen PaymentAmend()
    {
        if (!OpenItemsAvailable()) return Notice(PaymentAmendTitle, "未決済明細ファイルがありません。");
        if (!_ledger.PaymentPending) return Notice(PaymentAmendTitle, "修正する支払がありません。");
        if (_ledger.Payments() is not { } payments) return Notice(PaymentAmendTitle, "未決済明細の形式を確認してください。");
        return new TableScreen(PaymentAmendTitle, "PurchasePaymentsToCancel",
            ["組番号", "仕入先コード", "支払日", "金額", "消込額"],
            payments.Select(payment => new TableRow(
                [$"{payment.Batch}/{payment.Item}", payment.Supplier, DateText(payment.Date), Money(payment.Amount), Money(payment.Applied)],
                () => CancelPayment(payment),
                [$"{payment.Batch}/{payment.Item}", payment.Supplier, DateText(payment.Date), payment.Amount, payment.Applied])).ToArray(),
            "修正する支払がありません。");
    }

    private Screen CancelPayment(PurchasePayment payment)
    {
        Screen Confirm(IReadOnlyDictionary<int, decimal> discounts) => new ConfirmationScreen(PaymentAmendTitle,
            $"組番号 {payment.Batch}/{payment.Item} の支払を取り消しますか。", "支払を取り消す",
            () => Notice(PaymentAmendTitle, _ledger.CancelPayment(payment.Supplier, payment.Folio, discounts)
                ? "支払を取り消しました。" : "割引額または台帳の状態を確認してください。"), PaymentAmend);
        if (payment.Discount == 0) return Confirm(new Dictionary<int, decimal>());
        var lines = payment.Lines.Where(line => line.Discount == 0).ToArray();
        return new FormScreen(PaymentAmendTitle, lines.Select(line => (Field)Text("RestoreDiscount" + line.Folio,
            $"伝票 {line.Folio} に戻す割引額（割引合計 {Money(payment.Discount)}）", "", 6)).ToArray(), "確認", values =>
        {
            var discounts = new Dictionary<int, decimal>();
            foreach (var line in lines)
            {
                string id = "RestoreDiscount" + line.Folio;
                if (string.IsNullOrWhiteSpace(values.Text("Purchase" + id))) continue;
                if (!Amount(values, id, out decimal discount) || discount < 0 || discount > payment.Discount)
                    return Notice(PaymentAmendTitle, "割引額を確認してください。");
                if (discount != 0) discounts.Add(line.Folio, discount);
            }
            return discounts.Values.Sum() == payment.Discount ? Confirm(discounts) :
                Notice(PaymentAmendTitle, "割引額の合計を確認してください。");
        });
    }

    private Screen PaymentProof()
    {
        if (!OpenItemsAvailable()) return Notice(PaymentProofTitle, "未決済明細ファイルがありません。");
        if (!_ledger.PaymentPending) return Notice(PaymentProofTitle, "検証する支払がありません。");
        return _ledger.ProvePayments() is { } payments ? PaymentJournal(PaymentProofTitle, payments, false) :
            Notice(PaymentProofTitle, "未決済明細の形式を確認してください。");
    }

    private Screen PaymentPost()
    {
        if (!_ledger.PaymentPending) return Notice(PaymentPostTitle, "転記待ちの支払がありません。");
        if (!_ledger.PaymentsVerified) return Notice(PaymentPostTitle, "先に支払の検証帳票を作成してください。");
        return new ConfirmationScreen(PaymentPostTitle, "検証済みの支払を転記しますか。", "転記",
            () => _ledger.PostPayments() is { } payments ? PaymentJournal(PaymentPostTitle, payments, true) :
                Notice(PaymentPostTitle, "支払または台帳の状態を確認してください。"), MainMenu);
    }

    private Screen PaymentJournal(string title, IReadOnlyList<PurchasePayment> payments, bool posting)
    {
        var report = new StringBuilder();
        int page = 0, row = 0, limit = Math.Max(7, _ledger.System().I("Page-Lines"));
        WriteHeading();
        foreach (var payment in payments)
        {
            if (row + 2 > limit) WriteHeading();
            string kind = payment.UnappliedCredit ? "未消込残高の使用" : "支払";
            report.AppendLine($"{payment.Batch}/{payment.Item}　{DateText(payment.Date)}　{payment.Supplier}　{kind}　{_ledger.GetSupplier(payment.Supplier)?.St("name")}");
            report.AppendLine($"　支払額 {Money(payment.Amount)}　消込額 {Money(payment.Applied)}　割引 {Money(payment.Discount)}");
            row += 2;
            if (posting)
                Write($"　前残高 {Money(payment.OldBalance ?? 0)}　新残高 {Money(payment.NewBalance ?? 0)}");
            else
                foreach (var line in payment.Lines)
                    Write($"　伝票 {line.Folio}　{DateText(line.Date)}　消込額 {Money(line.Applied)}　未決済残高 {Money(line.Balance)}");
        }
        foreach (bool credit in new[] { false, true })
        {
            var group = payments.Where(payment => payment.UnappliedCredit == credit).ToArray();
            Write(credit ? "未消込残高使用の合計" : "支払合計");
            Write($"　支払額 {Money(group.Sum(payment => payment.Amount))}　消込額 {Money(group.Sum(payment => payment.Applied))}　割引 {Money(group.Sum(payment => payment.Discount))}");
        }
        return _ledger.Report(title, report.ToString());

        void Write(string line)
        {
            if (row >= limit) WriteHeading();
            report.AppendLine(line);
            row++;
        }

        void WriteHeading()
        {
            if (page != 0) report.Append('\f');
            report.Append(ReportHeading(title)).Append("ページ ").AppendLine((++page).ToString(CultureInfo.InvariantCulture));
            row = 4;
        }
    }
}
