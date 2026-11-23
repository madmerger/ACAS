using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed record CustomerDetails(string Name, string Address1, string Address2, string Phone, string Extension,
    string Email, string Fax, string DeliveryName, string DeliveryAddress1, string DeliveryAddress2,
    string Note1, string Note2, bool LateCharges, bool Dunning, bool EmailInvoice, bool EmailStatement, bool EmailLetters,
    int CreditDays, decimal Discount, int MinimumLateCharge, int MaximumLateCharge, int CreditLimit);

public sealed record SalesCustomer(string Code, CustomerDetails Details, bool Active, decimal Balance, decimal Unapplied,
    int Created, int LastInvoice, int LastPayment, int InvoiceActivity, int Average, decimal Turnover)
{
    internal string DisplayName => SalesLedger.CustomerDisplayName(Details.Name);
}

public sealed partial class SalesLedger
{
    private static readonly Layout CustomerLayout = new Layout()
        .X("key", 7).X("name", 30).X("address1", 48).X("address2", 48).X("phone", 13)
        .X("extension", 4).X("email", 30).X("fax", 13).N9("active", 1).N9("late", 1).N9("dunning", 1)
        .N9("emailInvoice", 1).N9("emailStatement", 1).N9("emailLetters", 1).N9("delivery", 1).N9("notes", 1)
        .Fill(3).N9("credit", 2).Comp("discount", 2, 2).BShort("min").BShort("max").BLong("limit")
        .BLong("activity").BLong("lastInvoice").BLong("lastPayment").BLong("average")
        .BLong("paymentActivity").BLong("paymentAverage").BLong("paymentWorst").BLong("created")
        .C3("balance", 8, 2).C3("last", 8, 2).Group(4, (l, i) => l.C3("quarter" + i, 8, 2))
        .C3("unapplied", 8, 2).Fill(10);

    private static readonly Layout DeliveryLayout = new Layout()
        .X("key", 8).X("name", 30).X("address1", 48).X("address2", 48);

    private const string CodeAlphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-";
    private const string UnknownCustomerName = "*** Customer Unknown ***";

    private const string UnknownCustomerDisplayName = "得意先不明";
    internal static string CustomerDisplayName(string name) => name == UnknownCustomerName ? UnknownCustomerDisplayName : name;

    public static string MakeCustomerCode(string value)
    {
        var code = value.ToUpperInvariant();
        if (code.Length != 6 || code.Any(c => !CodeAlphabet.Contains(c)))
            throw new SalesRuleException("得意先番号は半角英数字またはハイフンの6文字で入力してください。");
        int sum = code.Select((c, i) => (CodeAlphabet.IndexOf(c) + 1) * (7 - i)).Sum();
        return code + (11 - sum % 11) % 10;
    }

    public CustomerDetails CustomerDefaults()
    {
        var sys = SystemRecord();
        return new("", "", "", "", "", "", "", "", "", "", "", "", sys.I("SL-Charges") == 1,
            sys.I("SL-Dunning") == 1, false, false, false, sys.I("SL-Credit"), sys.N("SL-Disc"),
            sys.I("SL-Min"), sys.I("SL-Max"), sys.I("SL-Limit"));
    }

    public SalesCustomer GetCustomer(string code) => ReadCustomer(CustomerRecord(code));
    public IReadOnlyList<SalesCustomer> Customers() => db.Scan(CustomerFile)
        .Where(row => row.Data.Length == CustomerLayout.Size)
        .Select(row => ReadCustomer(CustomerLayout.From(row.Data))).ToArray();

    public SalesCustomer CreateCustomer(string code, CustomerDetails details) => db.Atomic(() =>
    {
        string key = MakeCustomerCode(code);
        var sys = SystemRecord();
        var row = CustomerLayout.New();
        row.Set("key", key);
        row.SetN("active", 1);
        row.SetN("created", sys.I("Run-Date"));
        var related = ApplyCustomer(row, details, sys);
        if (!db.Write(CustomerFile, key, row.B)) throw new SalesRuleException("得意先番号は登録済みです。");
        db.Create(DeliveryFile);
        SaveDelivery(key, related);
        if (sys.St("Sales-Ledger") != "Y")
        {
            sys.Set("Sales-Ledger", "Y");
            sys.SetN("File-Status-12", 1);
            sys.SetN("File-Status-14", 1);
            SaveSystem(sys);
        }
        return ReadCustomer(row);
    });

    public SalesCustomer UpdateCustomer(string code, CustomerDetails details) => db.Atomic(() =>
    {
        var row = CustomerRecord(code);
        string key = row.St("key");
        var related = ApplyCustomer(row, details, SystemRecord());
        if (!db.Rewrite(CustomerFile, key, row.B)) throw new SalesRuleException("得意先が見つかりません。");
        SaveDelivery(key, related);
        return ReadCustomer(row);
    });

    public void CloseCustomer(string code, bool permanently) => db.Atomic(() =>
    {
        var row = CustomerRecord(code);
        string key = row.St("key");
        if (row.N("balance") != 0 || row.N("unapplied") != 0)
            throw new SalesRuleException("残高または未消込額がある得意先は削除できません。");
        if (permanently)
        {
            db.Delete(CustomerFile, key);
            db.Delete(DeliveryFile, "D" + key);
            db.Delete(DeliveryFile, "N" + key);
        }
        else
        {
            row.SetN("active", 0);
            db.Rewrite(CustomerFile, key, row.B);
        }
        return true;
    });

    private Rec CustomerRecord(string code) => code.Length == 7 &&
        db.Read(CustomerFile, code.ToUpperInvariant()) is { } data && data.Length == CustomerLayout.Size
        ? CustomerLayout.From(data) : throw new SalesRuleException("得意先が見つかりません。");

    private SalesCustomer ReadCustomer(Rec row)
    {
        string key = row.St("key");
        var delivery = ReadDelivery("D" + key, row.I("delivery"));
        var notes = ReadDelivery("N" + key, row.I("notes"));
        var details = new CustomerDetails(GetText(row, "name"), GetText(row, "address1"), GetText(row, "address2"),
            GetText(row, "phone"), GetText(row, "extension"), GetText(row, "email"), GetText(row, "fax"),
            delivery == null ? "" : GetText(delivery, "name"), delivery == null ? "" : GetText(delivery, "address1"),
            delivery == null ? "" : GetText(delivery, "address2"), notes == null ? "" : GetText(notes, "address1"),
            notes == null ? "" : GetText(notes, "address2"), row.I("late") == 1, row.I("dunning") == 1,
            row.I("emailInvoice") == 1, row.I("emailStatement") == 1, row.I("emailLetters") == 1,
            row.I("credit"), row.N("discount"), row.I("min"), row.I("max"), row.I("limit"));
        return new(key, details, row.I("active") == 1, row.N("balance"), row.N("unapplied"), row.I("created"),
            row.I("lastInvoice"), row.I("lastPayment"), row.I("activity"), row.I("average"),
            Enumerable.Range(1, 4).Sum(i => row.N("quarter" + i)));
    }

    private Rec? ReadDelivery(string key, int flag) => flag == 1 &&
        db.Read(DeliveryFile, key) is { } data && data.Length == DeliveryLayout.Size ? DeliveryLayout.From(data) : null;

    private static (Rec? Delivery, Rec? Notes) ApplyCustomer(Rec row, CustomerDetails value, Rec sys)
    {
        SetText(row, "name", value.Name, "得意先名");
        SetText(row, "address1", value.Address1, "住所1");
        SetText(row, "address2", value.Address2, "住所2");
        SetText(row, "phone", value.Phone, "電話");
        SetText(row, "extension", value.Extension, "内線");
        SetText(row, "email", value.Email, "メールアドレス");
        SetText(row, "fax", value.Fax, "ファクス");
        if (value.CreditDays is < 0 or > 99 || value.Discount is < 0 or > 99.99m ||
            value.MinimumLateCharge is < 0 or > 9999 || value.MaximumLateCharge is < 0 or > 9999 ||
            value.CreditLimit is < 0 or > 9999999)
            throw new SalesRuleException("取引条件の数値が有効な範囲にありません。");

        var delimiter = sys.S("SL-Delim")[0];
        if (delimiter is ' ' or '\0') delimiter = '\\';
        ValidateAddress(row.S("address1") + row.S("address2"), delimiter);
        Rec? delivery = null, notes = null;
        if (value.DeliveryName.Length + value.DeliveryAddress1.Length + value.DeliveryAddress2.Length > 0)
        {
            delivery = PrepareDelivery("D" + row.St("key"), value.DeliveryName, value.DeliveryAddress1, value.DeliveryAddress2);
            ValidateAddress(delivery.S("address1") + delivery.S("address2"), delimiter);
        }
        if (value.Note1.Length + value.Note2.Length > 0)
            notes = PrepareDelivery("N" + row.St("key"), "", value.Note1, value.Note2);
        foreach (var (field, flag) in new (string, bool)[]
        {
            ("late", value.LateCharges), ("dunning", value.Dunning), ("emailInvoice", value.EmailInvoice),
            ("emailStatement", value.EmailStatement), ("emailLetters", value.EmailLetters),
            ("delivery", delivery != null), ("notes", notes != null)
        }) row.SetN(field, flag ? 1 : 0);
        row.SetN("credit", value.CreditDays);
        row.SetN("discount", value.Discount);
        row.SetN("min", value.MinimumLateCharge);
        row.SetN("max", value.MaximumLateCharge);
        row.SetN("limit", value.CreditLimit);
        return (delivery, notes);
    }

    private static void ValidateAddress(string address, char delimiter)
    {
        if (address.IndexOf(delimiter) is < 0 or > 30 || address.Count(c => c == delimiter) > 4)
            throw new SalesRuleException($"住所の区切り文字「{delimiter}」は1～4個、最初の30文字以内に入れてください。");
    }

    private static Rec PrepareDelivery(string key, string name, string first, string second)
    {
        var record = DeliveryLayout.New();
        record.Set("key", key);
        SetText(record, "name", name, "配送先名");
        SetText(record, "address1", first, "住所・備考1");
        SetText(record, "address2", second, "住所・備考2");
        return record;
    }

    private void SaveDelivery(string key, (Rec? Delivery, Rec? Notes) related)
    {
        foreach (var (prefix, data) in new[] { ("D", related.Delivery), ("N", related.Notes) })
            if (data == null) db.Delete(DeliveryFile, prefix + key);
            else db.Put(DeliveryFile, prefix + key, data.B);
    }
}
