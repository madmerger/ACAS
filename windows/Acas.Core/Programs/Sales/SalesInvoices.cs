using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public enum InvoiceKind { Receipt = 1, Account = 2, Credit = 3, ProForma = 4 }
public sealed record InvoiceInput(DateTime Date, string Customer, string Reference, string Order,
    InvoiceKind Kind, int? Number, int CreditFor, string Description, decimal Carriage, int? CreditDays);
public sealed record InvoiceLine(string Product, string Analysis, string Description, int Quantity,
    decimal UnitPrice, decimal Discount, int VatCode);
public sealed record SalesInvoice(string Key, int Number, InvoiceInput Input, IReadOnlyList<InvoiceLine> Lines,
    string Status, decimal Net, decimal Vat, decimal Gross);

public sealed partial class SalesLedger
{
    public const string InvoiceFile = Prefix + "invoice.dat";
    private const string DeletedFile = Prefix + "delinvno.dat";
    private const int InvoiceSize = 134;
    private static readonly Layout InvoiceHeader = new Layout()
        .N9("number", 8).X("letter", 1).BChar("line").X("customer", 7).BLong("date").X("order", 10)
        .N9("type", 1).X("ref", 10).X("description", 32).C3("pc", 7, 2).C3("net", 7, 2).C3("extra", 7, 2)
        .C3("carriage", 7, 2).C3("vat", 7, 2).C3("discount", 7, 2).C3("extraVat", 7, 2).C3("carriageVat", 7, 2)
        .X("status", 1).X("picked", 1).X("printed", 1).X("cleared", 1).X("applied", 1).X("deleted", 1)
        .BChar("lines").BChar("deductDays").Comp("deductAmount", 3, 2).Comp("deductVat", 3, 2)
        .BChar("days").BLong("creditFor").X("dayBook", 1).X("update", 1);
    private static readonly Layout InvoiceDetail = new Layout()
        .N9("number", 8).X("letter", 1).BChar("line").X("product", 13).X("analysis", 2).BShort("quantity")
        .N9("type", 1).X("description", 32).C3("net", 7, 2).C3("price", 7, 2).Comp("discount", 2, 2)
        .C3("vat", 7, 2).N9("vatCode", 1).X("update", 1).X("unused", 1).X("padding", InvoiceSize - 80);

    public static string InvoiceType(InvoiceKind kind) => kind switch
    {
        InvoiceKind.Receipt => "現金売上", InvoiceKind.Account => "掛売請求書",
        InvoiceKind.Credit => "貸方伝票", InvoiceKind.ProForma => "仮請求書", _ => "不明"
    };

    public void SaveInvoiceSettings(int number, string description, string kind, bool print, decimal rate,
        int level, bool link, bool audit, int chargeAccount, int vatAccount, int retention)
    {
        if (number is < 0 or > 99_999_999 || kind is not ("" or "C" or "D") || rate is < 0 or > 99.99m ||
            level is < 1 or > 2 || chargeAccount is < 0 or > 999_999 || vatAccount is < 0 or > 999_999 ||
            retention is < 0 or > 999)
            throw new SalesRuleException("請求書固定項目の値を確認してください。");
        var system = SystemRecord();
        system.SetN("Next-Invoice", number);
        SetText(system, "Extra-Desc", description, "追加料金・値引きの摘要");
        system.Set("Extra-Type", kind);
        system.Set("Extra-Print", print ? "Y" : "N");
        system.SetN("Extra-Rate", rate);
        system.SetN("Invoicer", level);
        system.Set("SL-Stock-Link", link ? "Y" : "N");
        system.Set("SL-Stock-Audit", audit ? "Y" : "N");
        system.SetN("Extra-Charge-Ac", chargeAccount);
        system.SetN("Vat-Ac", vatAccount);
        system.SetN("PF-Retention", retention);
        SaveSystem(system);
    }

    public IReadOnlyList<SalesInvoice> Invoices()
    {
        var groups = db.Scan(InvoiceFile).Where(row => row.Data.Length == InvoiceSize && row.Key.Length == 13 &&
            row.Key[8] == '/' && row.Key[10] == '/')
            .GroupBy(row => row.Key[..row.Key.LastIndexOf('/')], StringComparer.Ordinal);
        var invoices = new List<SalesInvoice>();
        foreach (var group in groups)
        {
            var header = group.FirstOrDefault(row => row.Data[9] == 0);
            if (header.Data == null) continue;
            var h = InvoiceHeader.From(header.Data);
            var lines = group.Where(row => row.Data[9] > 0).Select(row => ReadLine(InvoiceDetail.From(row.Data))).ToArray();
            var input = new InvoiceInput(DecodeDate(h.I("date")) ?? Epoch, h.St("customer"), GetText(h, "ref"),
                GetText(h, "order"), (InvoiceKind)h.I("type"), h.I("number"), h.I("creditFor"), GetText(h, "description"),
                h.N("carriage"), h.I("days"));
            decimal net = h.N("net") + h.N("extra") + h.N("carriage") + h.N("deductAmount");
            decimal vat = h.N("vat") + h.N("extraVat") + h.N("carriageVat") + h.N("deductVat");
            invoices.Add(new(header.Key, h.I("number"), input, lines, h.St("status"), net, vat, net + vat));
        }
        return invoices;
    }

    private static InvoiceLine ReadLine(Rec line) => new(GetText(line, "product"), GetText(line, "analysis"),
        GetText(line, "description"), line.I("quantity"), line.N("price"), line.N("discount"), line.I("vatCode"));

    private static string InvoiceKey(int number, string letter, int line) =>
        string.Create(CultureInfo.InvariantCulture, $"{number:D8}/{letter}/{line:D2}");

    public int SaveInvoice(InvoiceInput input, IReadOnlyList<InvoiceLine> lines, string? previousKey = null) => db.Atomic(() =>
    {
        var system = SystemRecord();
        var customer = GetCustomer(input.Customer);
        if (system.St("SL-Stock-Link") == "Y")
            throw new SalesRuleException("在庫連携が有効な環境ではこの操作を実行できません。");
        if (!customer.Active || lines.Count is < 1 or > 40 ||
            input.Kind is < InvoiceKind.Receipt or > InvoiceKind.ProForma || EncodeDate(input.Date) <= 0 ||
            input.Carriage is < 0 or > 9_999_999.99m || input.CreditDays is < 0 or > 127 ||
            input.CreditFor is < 0 or > 99_999_999)
            throw new SalesRuleException("請求情報を確認してください。稼働中の得意先と1～40行の明細が必要です。");
        var previous = previousKey == null ? null : Invoices().FirstOrDefault(i => i.Key == previousKey);
        if (previousKey != null && previous?.Status != "P")
            throw new SalesRuleException("未印刷の請求書だけを変更できます。");
        bool ownNumbers = system.St("Sl-Own-Nos") == "Y";
        var reused = !ownNumbers && previous == null ? db.Scan(DeletedFile).FirstOrDefault() : default;
        int number = previous?.Number ?? (ownNumbers ? input.Number ?? -1 :
            reused.Data is { Length: >= 8 } old ? (int)Cob.ToNum(Encoding.ASCII.GetString(old, 0, 8)) : system.I("Next-Invoice"));
        string letter = previousKey?.Split('/')[1] ?? " ";
        if (number is < 0 or > 99_999_999) throw new SalesRuleException("請求番号は8桁以内で入力してください。");
        string headerKey = InvoiceKey(number, letter, 0);
        if (previous == null && db.Read(InvoiceFile, headerKey) != null)
            throw new SalesRuleException("請求番号が使用されています。");
        if (previous == null && reused.Data == null && system.I("Next-Invoice") == 99_999_999)
            throw new SalesRuleException("次回の請求番号が上限に達しています。");
        var h = InvoiceHeader.New();
        h.SetN("number", number);
        h.Set("letter", letter);
        h.Set("customer", customer.Code);
        h.SetN("date", EncodeDate(input.Date));
        h.SetN("type", (int)input.Kind);
        SetText(h, "order", input.Order, "注文番号");
        SetText(h, "ref", input.Reference, "参照番号");
        SetText(h, "description", input.Description, "摘要");
        h.SetN("lines", lines.Count);
        h.SetN("days", input.CreditDays ?? (input.Kind switch
        {
            InvoiceKind.Account => customer.Details.CreditDays,
            InvoiceKind.ProForma => system.I("PF-Retention"), _ => 0
        }));
        h.SetN("creditFor", input.Kind == InvoiceKind.Credit ? input.CreditFor : 0);
        h.Set("status", "P");

        decimal totalNet = 0, totalVat = 0;
        var details = new List<(string Key, byte[] Data)>();
        foreach (var line in lines)
        {
            if (line.Quantity is < 1 or > short.MaxValue || line.UnitPrice is < 0 or > 9_999_999.99m ||
                line.Discount is < 0 or > 99.99m || line.VatCode is < 1 or > 5)
                throw new SalesRuleException("数量、単価、値引率または税区分が有効な範囲にありません。");
            var detail = InvoiceDetail.New();
            int index = details.Count + 1;
            detail.SetN("number", number);
            detail.Set("letter", letter);
            detail.SetN("line", index);
            detail.SetN("type", (int)input.Kind);
            SetText(detail, "product", line.Product, "品目コード");
            SetText(detail, "analysis", line.Analysis, "分析コード");
            SetText(detail, "description", line.Description, "品目名");
            decimal net = TruncateMoney(line.Quantity * line.UnitPrice * (100 - line.Discount) / 100);
            decimal vat = RoundMoney(net * system.N("Vat-Rate-" + line.VatCode) / 100);
            totalNet += net;
            totalVat += vat;
            if (totalNet > 9_999_999.99m || totalVat > 9_999_999.99m)
                throw new SalesRuleException("明細金額または税額が上限を超えています。");
            detail.SetN("quantity", line.Quantity);
            detail.SetN("net", net);
            detail.SetN("price", line.UnitPrice);
            detail.SetN("discount", line.Discount);
            detail.SetN("vat", vat);
            detail.SetN("vatCode", line.VatCode);
            details.Add((InvoiceKey(number, letter, index), detail.B));
        }
        decimal extra = TruncateMoney(totalNet * system.N("Extra-Rate") / 100);
        if (system.St("Extra-Type") == "D") extra = -extra;
        h.SetN("net", totalNet);
        h.SetN("vat", totalVat);
        h.SetN("extra", extra);
        h.SetN("extraVat", TruncateMoney(extra * system.N("Vat-Rate-1") / 100));
        h.SetN("carriage", input.Carriage);
        h.SetN("carriageVat", RoundMoney(input.Carriage * system.N("Vat-Rate-1") / 100));

        db.Put(InvoiceFile, headerKey, h.B[..InvoiceSize]);
        foreach (var (key, data) in details) db.Put(InvoiceFile, key, data);
        for (int i = details.Count + 1; i <= (previous?.Lines.Count ?? 0); i++)
            db.Delete(InvoiceFile, InvoiceKey(number, letter, i));
        if (previous == null)
        {
            if (reused.Data == null) system.SetN("Next-Invoice", system.I("Next-Invoice") + 1);
            else db.Delete(DeletedFile, reused.Key);
            if (system.I("First-Sl-Inv") == 0) system.SetN("First-Sl-Inv", number);
        }
        system.SetN("File-Status-16", 1);
        system.SetN("File-Status-19", 1);
        system.SetN("S-Flag-I", 1);
        db.Create(Prefix + "openitm3.dat");
        SaveSystem(system);
        return number;
    });

    public void DeleteInvoice(SalesInvoice invoice) => db.Atomic(() =>
    {
        if (db.Read(InvoiceFile, invoice.Key) is not { Length: InvoiceSize } data || data[114] != 'P')
            throw new SalesRuleException("未印刷の請求書だけを削除できます。");
        foreach (var (key, _) in db.Scan(InvoiceFile, invoice.Key).TakeWhile(row => row.Key.StartsWith(invoice.Key[..^2], StringComparison.Ordinal)))
            db.Delete(InvoiceFile, key);
        var entry = new Layout().N9("number", 8).BLong("date").X("customer", 7).New();
        entry.SetN("number", invoice.Number);
        entry.SetN("date", EncodeDate(invoice.Input.Date));
        entry.Set("customer", invoice.Input.Customer);
        db.Put(DeletedFile, entry.S("number"), entry.B);
        return true;
    });

    public string PrintInvoices(bool reprint, bool picking, int? only = null, DateTime? printedAt = null) => db.Atomic(() =>
    {
        var selected = Invoices().Where(i => (only == null || i.Number == only) &&
            (picking || (reprint ? i.Status is "P" or "I" : i.Status == "P"))).ToArray();
        string title = picking ? "配送・出庫票" : "請求書";
        var report = new StringBuilder();
        var system = SystemRecord();
        string time = (printedAt ?? DateTime.Now).ToString("HH:mm", CultureInfo.InvariantCulture);
        foreach (var invoice in selected)
        {
            var customer = GetCustomer(invoice.Input.Customer);
            var h = InvoiceHeader.From(db.Read(InvoiceFile, invoice.Key)!);
            var lines = InvoiceLines(invoice.Key);
            if (report.Length > 0) report.Append('\f');
            report.AppendLine(title).AppendLine(InvoiceType(invoice.Input.Kind))
                .AppendLine($"事業者　{GetText(system, "Usera")}");
            foreach (string field in new[] { "Address-1", "Address-2", "Address-3", "Address-4", "Post-Code", "Country" })
                if (GetText(system, field) is { Length: > 0 } value) report.AppendLine(value);
            report.AppendLine($"請求番号　{invoice.Number}").AppendLine($"日付　{ShowDate(h.I("date"))}　{time}")
                .AppendLine($"得意先　{customer.Code}　{customer.Details.Name}");
            AppendAddress(report, customer.Details.Address1, customer.Details.Address2, system.S("SL-Delim")[0]);
            if (customer.Details.DeliveryAddress1.Length > 0 || customer.Details.DeliveryAddress2.Length > 0)
            {
                report.AppendLine($"配送先　{customer.Details.DeliveryName}");
                AppendAddress(report, customer.Details.DeliveryAddress1, customer.Details.DeliveryAddress2, system.S("SL-Delim")[0]);
            }
            report.AppendLine($"注文番号　{invoice.Input.Order}　参照番号　{invoice.Input.Reference}");
            if (invoice.Input.Kind == InvoiceKind.ProForma) report.AppendLine("これは税務上の正式な請求書ではありません。");
            if (picking)
            {
                report.AppendLine("品目コード　品目名　数量");
                foreach (var line in lines) report.AppendLine($"{GetText(line, "product")}　{GetText(line, "description")}　{line.I("quantity")}");
            }
            else
            {
                bool detailed = system.I("Invoicer") == 2;
                report.AppendLine(detailed ? "品目コード　品目名　数量　単価　値引率　税抜額　税額" : "品目名　税抜額　税額");
                int page = 1;
                int pages = (lines.Length - 1) / 15 + 1;
                report.AppendLine($"ページ　{page}／{pages}");
                for (int index = 0; index < lines.Length; index++)
                {
                    if (index > 0 && index % 25 == 0) report.Append('\f').AppendLine($"ページ　{++page}／{pages}");
                    var line = lines[index];
                    if (detailed)
                        report.Append($"{GetText(line, "product")}　{GetText(line, "description")}　{line.I("quantity")}　{Amount(line.N("price"))}　{(line.N("discount") == 0 ? "" : Amount(line.N("discount")))}　");
                    else report.Append($"{GetText(line, "description")}　");
                    report.AppendLine($"{Amount(line.N("net"))}　{Amount(line.N("vat"))}");
                }
                report.AppendLine($"支払期限（日数）　{h.I("days")}　{Amount(h.N("net"))}　{Amount(h.N("vat"))}");
                if (h.N("deductAmount") != 0)
                    report.AppendLine($"早期支払（{h.I("deductDays")}日以内）　{Amount(h.N("deductAmount"))}　{Amount(h.N("deductVat"))}");
                if (system.St("Extra-Print") != "N" && (h.N("extra") != 0 || h.N("extraVat") != 0))
                    report.AppendLine($"{GetText(system, "Extra-Desc")}　{Amount(h.N("extra"))}　{Amount(h.N("extraVat"))}");
                if (h.N("carriage") != 0 || h.N("carriageVat") != 0)
                    report.AppendLine($"送料　{Amount(h.N("carriage"))}　{Amount(h.N("carriageVat"))}");
                report.AppendLine($"税抜額　{Amount(invoice.Net)}　税額　{Amount(invoice.Vat)}　請求合計　{Amount(invoice.Gross)}");
            }
            report.AppendLine();
            if (picking) h.Set("picked", "P");
            else
            {
                h.Set("status", "I");
                h.Set("printed", "L");
            }
            db.Put(InvoiceFile, invoice.Key, h.B[..InvoiceSize]);
        }
        KeepReport(picking ? "prt-3" : "prt-2", report.ToString());
        return report.Length > 0 ? report.ToString() : "印刷する請求書がありません。";
    });

    private Rec[] InvoiceLines(string key) => db.Scan(InvoiceFile, key)
        .TakeWhile(row => row.Key.StartsWith(key[..^2], StringComparison.Ordinal))
        .Where(row => row.Data.Length == InvoiceSize && row.Data[9] != 0)
        .Select(row => InvoiceDetail.From(row.Data)).ToArray();

    private static void AppendAddress(StringBuilder report, string first, string second, char delimiter)
    {
        var address = first.PadRight(48) + second;
        foreach (string part in address.Split(delimiter, 5, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
            report.AppendLine(part[..Math.Min(part.Length, 31)]);
    }

    public string DeletionReport()
    {
        var rows = db.Scan(DeletedFile).Where(row => row.Data.Length >= 19);
        var report = string.Join("\n", rows.Select(row =>
            $"{row.Key}　{ShowDate(BitConverter.ToInt32(row.Data, 8))}　{Encoding.ASCII.GetString(row.Data, 12, 7)}"));
        return "請求削除帳票\n請求番号　日付　得意先番号\n" +
            (report.Length == 0 ? "対象となる請求書はありません。" : report);
    }

    public string InvoiceProof()
    {
        var invoices = Invoices().Where(i => i.Status is not ("z" or "Z") &&
            i.Input.Kind is >= InvoiceKind.Receipt and <= InvoiceKind.Credit).ToArray();
        if (invoices.Length == 0) return "";
        var system = SystemRecord();
        var report = new StringBuilder("未転記売上取引検証帳票\n").AppendLine(GetText(system, "Usera"))
            .AppendLine(ShowDate(system.I("Run-Date")))
            .AppendLine("請求番号　日付　得意先　種類　商品額　税抜額　税額　税込額");
        var totals = new decimal[3, 7];
        var vatTotals = new decimal[3, 5];
        foreach (var invoice in invoices)
        {
            var c = GetCustomer(invoice.Input.Customer);
            var h = InvoiceHeader.From(db.Read(InvoiceFile, invoice.Key)!);
            int type = (int)invoice.Input.Kind - 1;
            int sign = invoice.Input.Kind == InvoiceKind.Credit ? -1 : 1;
            decimal goods = sign * h.N("net");
            decimal discount = sign * (h.N("discount") + h.N("extra"));
            decimal deduct = sign * h.N("deductAmount");
            decimal carriage = sign * h.N("carriage");
            decimal net = goods + discount + deduct + carriage;
            decimal vat = sign * invoice.Vat;
            decimal gross = net + vat;
            decimal[] amounts = [goods, discount, deduct, carriage, net, vat, gross];
            for (int column = 0; column < amounts.Length; column++) totals[type, column] += amounts[column];
            report.AppendLine($"{invoice.Number}　{ShowDate(h.I("date"))}　{c.Code}　{c.Details.Name}　{InvoiceType(invoice.Input.Kind)}　{Amount(goods)}　{Amount(net)}　{Amount(vat)}　{Amount(gross)}");
            foreach (var line in InvoiceLines(invoice.Key))
            {
                int vatCode = line.I("vatCode");
                report.AppendLine($"分析コード　{GetText(line, "analysis")}　金額　{Amount(sign * line.N("net"))}　税区分　{vatCode}");
                if (vatCode is >= 1 and <= 5) vatTotals[type, vatCode - 1] += sign * line.N("vat");
            }
            vatTotals[type, 0] += sign * (h.N("extraVat") + h.N("carriageVat"));
        }
        report.AppendLine("商品額　値引額　早期支払値引き　送料　税抜額　税額　税込額");
        foreach (var kind in new[] { InvoiceKind.Receipt, InvoiceKind.Account, InvoiceKind.Credit })
        {
            report.AppendLine($"{InvoiceType(kind)}合計　" + string.Join("　", Enumerable.Range(0, 7).Select(column => Amount(totals[(int)kind - 1, column]))));
        }
        report.AppendLine("税区分別集計　現金売上　掛売請求書　貸方伝票");
        int vatCodes = system.N("Vat-Rate-4") == 0 && system.N("Vat-Rate-5") == 0 ? 3 : 5;
        for (int i = 1; i <= vatCodes; i++)
            report.AppendLine($"税区分{i}　税率{Amount(system.N("Vat-Rate-" + i))}％　{Amount(vatTotals[0, i - 1])}　{Amount(vatTotals[1, i - 1])}　{Amount(vatTotals[2, i - 1])}");
        return report.ToString();
    }

    public string? InvoiceDayBook(DateTime today)
    {
        if (!db.Exists(InvoiceFile) || !db.Exists(CustomerFile)) return null;
        var system = SystemRecord();
        var report = new StringBuilder("売上日計帳\n").AppendLine(GetText(system, "Usera"))
            .AppendLine(ShowDate(system.I("Run-Date") > 0 ? system.I("Run-Date") : EncodeDate(today)))
            .AppendLine("請求番号　日付　得意先番号　得意先名　種類　税抜額　税額　税込額");
        var totals = new decimal[4, 7];
        foreach (var invoice in Invoices())
        {
            if (invoice.Status is not ("z" or "Z") || invoice.Input.Kind is < InvoiceKind.Receipt or > InvoiceKind.Credit) continue;
            var h = InvoiceHeader.From(db.Read(InvoiceFile, invoice.Key)!);
            if (h.St("dayBook") == "B") continue;
            var customer = GetCustomer(invoice.Input.Customer);
            int type = (int)invoice.Input.Kind - 1;
            int sign = invoice.Input.Kind == InvoiceKind.Credit ? -1 : 1;
            decimal goods = sign * h.N("net");
            decimal discount = sign * (h.N("discount") + h.N("extra"));
            decimal deduct = sign * h.N("deductAmount");
            decimal carriage = sign * h.N("carriage");
            decimal net = goods + discount + deduct + carriage;
            decimal vat = sign * (h.N("vat") + h.N("extraVat") + h.N("carriageVat"));
            decimal gross = net + vat;
            decimal[] amounts = [goods, discount, deduct, carriage, net, vat, gross];
            for (int i = 0; i < amounts.Length; i++)
            {
                totals[type, i] += amounts[i];
                totals[3, i] += amounts[i];
            }
            report.AppendLine($"{invoice.Number}　{ShowDate(h.I("date"))}　{customer.Code}　{customer.Details.Name}　{InvoiceType(invoice.Input.Kind)}　{Amount(net)}　{Amount(vat)}　{Amount(gross)}");
        }
        report.AppendLine("区分　商品額　値引額　早期支払値引き　送料　税抜額　税額　税込額");
        string[] labels = ["現金売上合計", "掛売請求書合計", "貸方伝票合計", "総合計"];
        for (int i = 0; i < labels.Length; i++)
            report.AppendLine(labels[i] + "　" + string.Join("　", Enumerable.Range(0, 7).Select(column => Amount(totals[i, column]))));
        return report.ToString();
    }
}
