using System.Globalization;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Purchase;

namespace Acas.App.Subsystems.Purchase;

internal sealed partial class PurchaseScreens
{
    private enum SupplierAction { Register, Change, Remove, Show }

    private static readonly (string Name, string Id, string Label, int Width)[] SupplierText =
    [
        ("name", "Name", "仕入先名", 30), ("address1", "AddressFirst", "住所の前半", 48),
        ("address2", "AddressSecond", "住所の後半", 48), ("phone", "Phone", "電話番号", 13),
        ("extension", "Extension", "内線", 4), ("fax", "Fax", "ファクス番号", 13),
        ("email", "Email", "電子メール", 30)
    ];

    private static readonly (string Name, string Id, string Label, int Width, decimal Limit)[] SupplierNumbers =
    [
        ("sort", "BankSort", "銀行支店番号", 6, 999999), ("account", "BankAccount", "銀行口座番号", 8, 99999999),
        ("credit", "CreditPeriod", "支払猶予日数", 2, 99), ("limit", "CreditLimit", "与信限度額", 7, 9999999),
        ("discount", "Discount", "割引率", 5, 99.99m)
    ];

    private Screen SupplierEntry(SupplierAction action, string title) => new FormScreen(title,
        [new TextField("PurchaseSupplierCode", "仕入先コード", MaxLength: action == SupplierAction.Register ? 6 : 7)],
        "検索", values =>
        {
            string code = values.Text("PurchaseSupplierCode").Trim().ToUpperInvariant();
            if (action == SupplierAction.Register)
            {
                string? key = PurchaseLedger.SupplierKey(code);
                if (key is null) return Notice(title, "仕入先コードは半角英数字またはハイフンで六文字入力してください。");
                if (_ledger.GetSupplier(key) != null) return Notice(title, "その仕入先コードはすでに登録されています。");
                return EditSupplier(title, _ledger.NewSupplier(key), true, "", "");
            }
            if (_ledger.GetSupplier(code) is not { } record) return Notice(title, "仕入先が見つかりません。");
            var (first, second) = _ledger.Notes(code);
            return action switch
            {
                SupplierAction.Change => EditSupplier(title, record, false, first, second),
                SupplierAction.Remove => RemoveSupplier(title, record),
                _ => ShowSupplier(title, record, first, second)
            };
        });

    private Screen EditSupplier(string title, Rec record, bool create, string firstNote, string secondNote, string? error = null)
    {
        string key = record.St("key");
        var fields = new List<Field>
        {
            new ChoiceField("PurchaseSupplierSelectedCode", error ?? "仕入先コード", [new Choice(key, key)], key)
        };
        fields.AddRange(SupplierText.Select(x => new TextField("PurchaseSupplier" + x.Id, x.Label, SupplierTextForDisplay(record, x.Name), x.Width)));
        fields.AddRange(SupplierNumbers.Select(x => new TextField("PurchaseSupplier" + x.Id, x.Label,
            x.Name == "discount" ? record.N(x.Name).ToString("0.00", CultureInfo.InvariantCulture) :
            record.N(x.Name).ToString(new string('0', x.Width), CultureInfo.InvariantCulture), x.Width)));
        fields.Add(new TextField("PurchaseSupplierNoteFirst", "備考の前半", firstNote, 48));
        fields.Add(new TextField("PurchaseSupplierNoteSecond", "備考の後半", secondNote, 48));
        return new FormScreen(title, fields, "保存内容を確認", values =>
        {
            var next = record.Clone();
            foreach (var x in SupplierText)
            {
                string value = values.Text("PurchaseSupplier" + x.Id);
                if (x.Name == "name" && value == SupplierTextForDisplay(record, x.Name)) continue;
                if (!PurchaseLedger.FitsRecord(value, x.Width)) return Notice(title, $"{x.Label}に台帳へ保存できない文字が含まれています。");
                next.Set(x.Name, value);
            }
            foreach (var x in SupplierNumbers)
            {
                string value = values.Text("PurchaseSupplier" + x.Id);
                if (!decimal.TryParse(value, x.Name == "discount" ? NumberStyles.AllowDecimalPoint : NumberStyles.None,
                    CultureInfo.InvariantCulture, out decimal number) || number > x.Limit)
                    return Notice(title, $"{x.Label}を確認してください。");
                next.SetN(x.Name, number);
            }
            string first = values.Text("PurchaseSupplierNoteFirst"), second = values.Text("PurchaseSupplierNoteSecond");
            if (!PurchaseLedger.FitsRecord(first, 48) || !PurchaseLedger.FitsRecord(second, 48))
                return Notice(title, "備考に台帳へ保存できない文字が含まれています。");
            if (!_ledger.ValidAddress(next.St("address1"), next.St("address2")))
                return EditSupplier(title, next, create, first, second, "住所の区切りと一行目の長さを確認してください。");
            return new ConfirmationScreen(title, $"仕入先「{key}」を保存しますか。", "保存",
                () => Notice(title, _ledger.SaveSupplier(next, create, first, second) ? "仕入先を保存しました。" : "仕入先を保存できませんでした。"),
                () => EditSupplier(title, next, create, first, second));
        });
    }

    private Screen RemoveSupplier(string title, Rec record)
    {
        if (!PurchaseLedger.CanRemove(record)) return Notice(title, "残高がある仕入先は削除または休止できません。");
        const string actionId = "PurchaseSupplierRemovalAction";
        return new FormScreen(title, [new ChoiceField(actionId, "処理", [new Choice("deactivate", "休止"), new Choice("remove", "完全に削除")])],
            "確認", values =>
            {
                string? action = values.Choice(actionId);
                if (action is null) return Notice(title, "処理を選択してください。");
                bool deactivate = action == "deactivate";
                string verb = deactivate ? "休止" : "削除";
                string code = record.St("key");
                return new ConfirmationScreen(title, $"仕入先「{code}」を{verb}しますか。", verb,
                    () => Notice(title, _ledger.RemoveSupplier(code, deactivate) ? $"仕入先を{verb}しました。" : $"仕入先を{verb}できませんでした。"),
                    () => RemoveSupplier(title, record));
            });
    }

    private static Screen ShowSupplier(string title, Rec record, string first, string second)
    {
        List<TableRow> rows = [new(["仕入先コード", record.St("key")]), new(["状態", record.I("status") == 0 ? "休止" : "有効"])];
        rows.AddRange(SupplierText.Select(x => new TableRow([x.Label, SupplierTextForDisplay(record, x.Name)])));
        rows.AddRange(SupplierNumbers.Select(x => new TableRow([x.Label, record.N(x.Name).ToString(CultureInfo.InvariantCulture)])));
        rows.Add(new(["備考の前半", first]));
        rows.Add(new(["備考の後半", second]));
        rows.Add(new(["現在残高", Money(record.N("current"))]));
        rows.Add(new(["未消込残高", Money(record.N("unapplied"))]));
        rows.Add(new(["最終請求日", DateText(PurchaseLedger.DecodeDate(record.I("lastInvoice")))]));
        rows.Add(new(["最終支払日", DateText(PurchaseLedger.DecodeDate(record.I("lastPayment")))]));
        return new TableScreen(title, "PurchaseSupplierDetails", ["項目", "内容"], rows);
    }

    private static string SupplierTextForDisplay(Rec record, string field) =>
        field == "name" ? PurchaseLedger.DisplaySupplierName(record.St(field)) : record.St(field);

    private string SupplierNameForDisplay(string key, string missing = "") =>
        _ledger.GetSupplier(key) is { } supplier ? SupplierTextForDisplay(supplier, "name") : missing;
}
