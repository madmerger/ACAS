using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed partial class SalesLedger
{
    public const string PostingStageFile = Prefix + "openitm2.dat";
    private const string SalesTotalsKey = "00000004";
    private static readonly string[] InvoiceAmounts =
        ["net", "extra", "carriage", "vat", "discount", "extraVat", "carriageVat", "deductAmount", "deductVat"];

    public string PostSales() => db.Atomic(() =>
    {
        var system = SystemRecord();
        if (system.I("File-Status-18") != 1 || !db.Exists(PostingStageFile))
            throw new SalesRuleException("抽出済みの売上取引がありません。");
        int quarter = system.I("Current-Quarter");
        if (quarter is < 1 or > 4) throw new SalesRuleException("四半期の設定を確認してください。");
        var totals = ReadSalesTotals();
        var nominal = new List<(int Date, string Legend, decimal Net, decimal Vat)>();
        var report = new StringBuilder("売上転記帳票\n").AppendLine(GetText(system, "Usera"))
            .AppendLine(ShowDate(system.I("Run-Date")))
            .AppendLine("番号　日付　得意先番号　得意先名　区分　転記前残高　転記後残高　早期支払値引額　税抜額　税額　税込額");
        var byKind = new (decimal Net, decimal Vat)[3];
        decimal totalDeductions = 0;
        int deductionCount = 0;
        bool missingCustomer = false;
        db.Create(OpenItemFile);
        foreach (var (_, data) in db.Scan(PostingStageFile))
        {
            var item = DecodePostingItem(data);
            int type = item.I("type");
            if (type is < 1 or > 3) throw new SalesRuleException("抽出済みの売上取引の区分が不正です。");
            string code = item.S("customer");
            int date = item.I("date");
            int number = item.I("number");
            var customerData = db.Read(CustomerFile, code);
            if (customerData != null && customerData.Length != CustomerLayout.Size)
                throw new SalesRuleException("得意先ファイルのレコード長が一致しません。");
            var customer = customerData == null ? CustomerLayout.New() : CustomerLayout.From(customerData);
            if (customerData == null)
            {
                missingCustomer = true;
                customer.Set("key", code);
                customer.Set("name", "*** Customer Unknown ***");
            }
            decimal vatForNominal = item.N("vat") + item.N("carriageVat") + item.N("extraVat");
            decimal vat = vatForNominal + item.N("deductVat");
            decimal net = item.N("net") + item.N("extra") + item.N("carriage") + item.N("discount") + item.N("deductAmount");
            decimal goods = item.N("net") + item.N("extra");
            decimal oldBalance = customer.N("balance") - customer.N("unapplied");
            byKind[type - 1].Net += net;
            byKind[type - 1].Vat += vat;
            nominal.Add((date, number.ToString(CultureInfo.InvariantCulture) + " : " + customer.S("name"), net, vatForNominal));

            string turnover = "quarter" + quarter;
            customer.SetN(turnover, customer.N(turnover) + goods);
            if (type is 1 or 2)
            {
                decimal count = customer.N("activity");
                customer.SetN("activity", count + 1);
                customer.SetN("average", (count * customer.N("average") + goods) / (count + 1));
                customer.SetN("lastInvoice", date);
            }
            if (type != 2) customer.SetN("lastPayment", date);
            if (type != 1) customer.SetN("balance", customer.N("balance") + net + vat);
            decimal deductions = 0;
            if (type == 3)
            {
                deductions = ApplySalesCredit(item, Math.Abs(net + vat), ref deductionCount);
                customer.SetN("balance", customer.N("balance") - deductions);
                decimal count = customer.N("activity");
                decimal accumulated = count * customer.N("average");
                if (accumulated != 0) customer.SetN("average", (accumulated + goods) / count);
            }
            totalDeductions += deductions;
            if (customer.I("active") == 0) customer.SetN("active", 1);
            NormalizeCustomerBalance(customer);
            db.Put(CustomerFile, code, customer.B);
            if (!db.Write(OpenItemFile, OpenItemKey(code, number), item.B))
                throw new SalesRuleException("同じ得意先と番号の売掛明細が既にあります。");
            decimal newBalance = customer.N("balance") - customer.N("unapplied");
            string name = customerData == null ? "得意先不明" : GetText(customer, "name");
            report.AppendLine($"{number}　{ShowDate(date)}　{code}　{name}　{OpenItemType(type)}　{Amount(oldBalance)}　" +
                $"{Amount(newBalance)}　{Amount(deductions)}　{Amount(net)}　{Amount(vat)}　{Amount(net + vat)}");
        }

        for (int i = 0; i < byKind.Length; i++)
            report.AppendLine($"{OpenItemType(i + 1)}合計　{Amount(byKind[i].Net)}　{Amount(byKind[i].Vat)}　{Amount(byKind[i].Net + byKind[i].Vat)}");
        report.AppendLine($"早期支払値引額合計　{Amount(totalDeductions)}");
        totals.SetN("total6", totals.N("total6") + totalDeductions);
        UpdatePostingDeductions(deductionCount, totalDeductions);
        if (system.I("Level-1") == 1) WriteSalesPostingBatches(system, nominal);

        decimal unapplied = 0;
        foreach (var (key, data) in db.Scan(OpenItemFile))
        {
            var item = DecodePostingItem(data);
            if (item.I("type") != 3 || item.I("closed") == 1) continue;
            decimal outstanding = InvoiceAmounts.Sum(item.N) + item.N("paid");
            item.SetN("closed", 1);
            item.SetN("paid", item.N("paid") - outstanding);
            db.Rewrite(OpenItemFile, key, item.B);
            unapplied += outstanding;
        }
        report.AppendLine($"未消込貸方伝票繰越額　{Amount(unapplied)}");
        if (missingCustomer) report.AppendLine("転記時に登録されていない得意先がありました。");
        totals.SetN("total7", totals.N("total7") + unapplied);
        db.Put(SystemFile, SalesTotalsKey, totals.B);
        db.Recreate(PostingStageFile);
        system.SetN("File-Status-18", 0);
        system.SetN("File-Status-19", 1);
        system.SetN("S-Flag-I", 2);
        system.SetN("S-Flag-A", 1);
        system.Set("Oi-3-Flag", "Y");
        SaveSystem(system);
        string body = report.ToString();
        db.AddSpool("prt-1", body);
        return body;
    });

    private decimal ApplySalesCredit(Rec credit, decimal available, ref int deductionCount)
    {
        available -= credit.N("paid");
        decimal deductions = 0;
        string code = credit.S("customer");
        int specified = credit.I("creditFor");
        var items = db.Scan(OpenItemFile, code).TakeWhile(row => row.Key.StartsWith(code, StringComparison.Ordinal)).ToArray();
        var preferred = items.Where(row => DecodePostingItem(row.Data).I("number") == specified);
        var remaining = items.Where(row => DecodePostingItem(row.Data).I("number") != specified);
        foreach (var (key, data) in preferred.Concat(remaining))
        {
            if (available <= 0) break;
            var item = DecodePostingItem(data);
            if (item.I("type") != 2 || item.I("closed") == 1) continue;
            decimal outstanding = InvoiceAmounts.Sum(item.N) - item.N("paid");
            if (outstanding < 0) continue;
            if (outstanding == 0)
            {
                item.SetN("closed", 1);
                db.Rewrite(OpenItemFile, key, item.B);
                continue;
            }
            decimal waived = item.I("date") + item.I("deductDays") + 1 > credit.I("date")
                ? item.N("deductAmount") + item.N("deductVat") : 0;
            decimal allocated = Math.Min(outstanding - waived, available);
            decimal residual = outstanding - waived - allocated;
            if (allocated > 0)
            {
                item.SetN("paid", item.N("paid") + allocated);
                item.SetN("pc", item.N("pc") + allocated);
                credit.SetN("paid", credit.N("paid") + allocated);
                available -= allocated;
            }
            if (residual == 0)
            {
                item.SetN("closed", 1);
                if (waived > 0)
                {
                    item.SetN("deductAmount", 0);
                    item.SetN("deductVat", 0);
                    deductions += waived;
                    deductionCount++;
                }
            }
            db.Rewrite(OpenItemFile, key, item.B);
        }
        if (available == 0) credit.SetN("closed", 1);
        return deductions;
    }

    private static Rec DecodePostingItem(byte[] data) => data.Length == OpenItemLayout.Size
        ? OpenItemLayout.From(data) : throw new SalesRuleException("売掛明細ファイルのレコード長が一致しません。");

    private static string OpenItemKey(string customer, int number) =>
        customer + "/" + Convert.ToHexString(BitConverter.GetBytes(number));

    private static void NormalizeCustomerBalance(Rec customer)
    {
        decimal balance = customer.N("balance");
        if (balance >= 0) return;
        customer.SetN("unapplied", customer.N("unapplied") - balance);
        customer.SetN("balance", 0);
    }

    private void UpdatePostingDeductions(int count, decimal amount)
    {
        if (amount == 0 || db.Read(ValueFile, "Szd") is not { } details) return;
        AddPostingValue(ReadPostingValue(details), -count, -amount);
        if (db.Read(ValueFile, "Sz ") is { } group)
            AddPostingValue(ReadPostingValue(group), -count, -amount);
    }

    private static readonly Layout IrsPostingLayout = new Layout()
        .N9("batch", 5).N9("number", 5).X("code", 2).X("date", 8).N9("debit", 5).N9("credit", 5)
        .N9("net", 7, 2).X("legend", 32).N9("vatAccount", 2).X("vatSide", 2).N9("vat", 7, 2);

    private void WriteSalesPostingBatches(Rec system, IReadOnlyList<(int Date, string Legend, decimal Net, decimal Vat)> entries)
    {
        const string batchFile = Prefix + "batch.dat";
        bool irs = system.St("Irs-Instead") == "Y";
        string postFile = Prefix + (irs ? "postings2irs.dat" : "posting.dat");
        db.Create(postFile);
        int posted = 0;
        int sequential = irs ? db.Count(postFile) : 0;
        int next = system.I("Postings") + 1;
        do
        {
            int batchNumber = system.I("Next-Batch");
            var batch = Layouts.Batch.New();
            batch.SetN("ledger", 3);
            batch.SetN("batch-nos", batchNumber);
            batch.SetN("bcycle", system.I("Cyclea"));
            batch.SetN("entered", system.I("Run-Date"));
            batch.Set("description", "Sales Ledger Invoices");
            batch.Set("convention", "CR");
            batch.Set("batch-def-code", "SL");
            batch.Set("batch-def-vat", "O");
            batch.SetN("batch-start", next);
            system.SetN("Next-Batch", batchNumber + 1);
            int items = Math.Min(entries.Count - posted, 99);
            decimal sumNet = 0, sumVat = 0;
            for (int i = 1; i <= items; i++)
            {
                var entry = entries[posted++];
                string date = DecodeDate(entry.Date)?.ToString("dd/MM/yy", CultureInfo.InvariantCulture) ?? "";
                var record = irs ? IrsPostingLayout.New() : Layouts.Posting.New();
                record.SetN("batch", batchNumber);
                if (irs)
                {
                    record.SetN("number", i);
                    record.Set("code", "SL");
                    record.Set("date", date);
                    record.SetN("debit", system.I("S-Debtors"));
                    record.SetN("credit", system.I("SL-Sales-Ac"));
                    SetLeadingAmount(record, "net", entry.Net);
                    record.Set("legend", entry.Legend);
                    record.SetN("vatAccount", 32);
                    record.Set("vatSide", "CR");
                    SetLeadingAmount(record, "vat", entry.Vat);
                }
                else
                {
                    record.SetN("post-number", i);
                    record.Set("post-code", "SL");
                    record.Set("post-date", date);
                    record.SetN("post-dr", system.I("S-Debtors"));
                    record.SetN("post-cr", system.I("SL-Sales-Ac"));
                    record.SetN("post-amount", entry.Net);
                    record.Set("post-legend", entry.Legend);
                    record.SetN("vat-ac", system.I("Vat-Ac"));
                    record.Set("post-vat-side", "CR");
                    record.SetN("vat-amount", entry.Vat);
                }
                string key = (irs ? ++sequential : next).ToString("D8", CultureInfo.InvariantCulture);
                if (!db.Write(postFile, key, record.B)) throw new SalesRuleException("会計転記の番号が重複しています。");
                next++;
                sumNet = Math.Abs(sumNet + entry.Net);
                sumVat = Math.Abs(sumVat + entry.Vat);
            }
            batch.SetN("items", items);
            batch.SetN("input-gross", sumNet);
            batch.SetN("actual-gross", sumNet);
            batch.SetN("input-vat", sumVat);
            batch.SetN("actual-vat", sumVat);
            if (!db.Write(batchFile, batch.S("ledger") + batch.S("batch-nos"), batch.B))
                throw new SalesRuleException("売掛の会計バッチ番号が重複しています。");
            system.SetN("Postings", next);
            if (items < 99) break;
            next++;
        } while (posted <= entries.Count);
    }

    private static void SetLeadingAmount(Rec record, string field, decimal amount)
    {
        record.SetN(field, amount);
        if (amount < 0) record.B[record.L.F[field].Off] += 0x40;
    }

    public bool ExtractSalesForPosting() => db.Atomic(() =>
    {
        var system = SystemRecord();
        if (!db.Exists(InvoiceFile)) throw new SalesRuleException("請求書ファイルがありません。");
        db.Create(ValueFile);
        if (system.I("File-Status-15") == 0) InitializePostingAnalysis(system);
        CheckAnalysisLength(db.Scan(AnalysisFile));
        db.Create(PostingStageFile);
        int sequence = db.Count(PostingStageFile);
        var totals = ReadSalesTotals();
        int? skippedNumber = null;
        bool unprinted = false;
        var special = new (int Count, decimal Amount)[4];
        foreach (var (key, data) in db.Scan(InvoiceFile))
        {
            if (data.Length != InvoiceSize) throw new SalesRuleException("請求書のレコード長が一致しません。");
            var header = InvoiceHeader.From(data);
            int number = header.I("number");
            if (number == skippedNumber) continue;
            if (header.I("line") != 0)
            {
                var detail = InvoiceDetail.From(data);
                if (detail.St("update") is "Z" or "z" || detail.S("product").StartsWith('/')) continue;
                string code = "S" + detail.S("analysis");
                decimal amount = detail.N("net") * (detail.I("type") == 3 ? -1 : 1);
                var value = EnsurePostingValue(code);
                AddPostingValue(value, 1, amount);
                if (code[2] == ' ' || db.Read(ValueFile, code[..2] + " ") is not { } parent) continue;
                AddPostingValue(ReadPostingValue(parent), 1, amount);
                detail.Set("update", "Z");
                db.Rewrite(InvoiceFile, key, detail.B);
                continue;
            }

            bool analysed = header.St("update") is "Z" or "z";
            bool applied = header.St("status") is "Z" or "z";
            if (analysed && applied) continue;
            int type = header.I("type");
            if (type == 4 || header.St("status") == "P" || header.St("printed") != "L")
            {
                if (type != 4) unprinted = true;
                skippedNumber = number;
                continue;
            }
            int sign = type == 3 ? -1 : 1;
            if (!applied)
            {
                var item = OpenItemLayout.New();
                item.Set("customer", header.S("customer"));
                item.Set("description", header.S("order"));
                foreach (string name in new[] { "number", "date", "type", "pc", "deductDays", "creditFor" })
                    item.SetN(name, header.N(name));
                foreach (string name in InvoiceAmounts) item.SetN(name, sign * header.N(name));
                db.Put(PostingStageFile, (++sequence).ToString("D10", CultureInfo.InvariantCulture), item.B);
                if (type is 2 or 3)
                {
                    string field = type == 2 ? "total3" : "total4";
                    totals.SetN(field, totals.N(field) + InvoiceAmounts.Sum(header.N));
                }
                header.Set("status", "Z");
                header.Set("applied", "A");
            }
            if (!analysed)
            {
                Accumulate(type == 1 ? 1 : 0, header.N("vat") + header.N("extraVat") + header.N("carriageVat"));
                Accumulate(2, header.N("carriage"));
                Accumulate(3, header.N("deductAmount"));
                header.Set("update", "Z");
            }
            db.Rewrite(InvoiceFile, key, header.B[..InvoiceSize]);

            void Accumulate(int index, decimal amount)
            {
                if (amount != 0)
                    special[index] = (special[index].Count + 1, special[index].Amount + sign * amount);
            }
        }
        string[] codes = ["Svo", "Svp", "Szc", "Szd"];
        for (int i = 0; i < codes.Length; i++)
        {
            string code = codes[i];
            var (count, amount) = special[i];
            AddPostingValue(EnsurePostingValue(code), count, amount);
            if (db.Read(ValueFile, code[..2] + " ") is { } parent)
                AddPostingValue(ReadPostingValue(parent), count, amount);
        }
        db.Put(SystemFile, SalesTotalsKey, totals.B);
        system.SetN("File-Status-18", 1);
        SaveSystem(system);
        return unprinted;
    });

    private Rec ReadSalesTotals() => db.Read(SystemFile, SalesTotalsKey) switch
    {
        null => SalesTotalsLayout.New(),
        { Length: 1024 } data => SalesTotalsLayout.From(data),
        _ => throw new SalesRuleException("売掛集計のレコード長が一致しません。")
    };

    private void InitializePostingAnalysis(Rec system)
    {
        db.Recreate(AnalysisFile);
        db.Delete(AnalysisDefinition, "1");
        (string Code, string Description, string Print)[] defaults =
        [
            ("Sv ", "VAT Control", ""), ("Pv ", "VAT Control", ""),
            ("Pvi", "VAT Input Invoices/CN's", ""), ("Pvj", "VAT Input Receipts", ""),
            ("Sz ", "Computer Control", ""), ("Pz ", "Computer Control", ""),
            ("Pza", "Purchase Carriage Charges", "P&P"), ("Pzb", "Purchase Late Charges", "LCG"),
            ("Szc", "Sales Carriage Charges", "P&P"), ("Szd", "Sales Late Charges", "LCG"),
            ("Svo", "VAT Output Invoices/CN's", ""), ("Svp", "VAT Output Receipts", ""),
            ("Pa ", "Default Group", ""), ("Pa1", "Default Purchases", ""),
            ("Sa ", "Default Group", ""), ("Sa1", "Default Sales", "")
        ];
        foreach (var (code, description, print) in defaults)
        {
            var record = NewPostingAnalysis(code, description, print);
            if (db.Read(ValueFile, code) == null) db.Write(ValueFile, code, NewPostingValue(record).B);
        }
        system.SetN("File-Status-15", 1);
    }

    private Rec NewPostingAnalysis(string code, string description, string print)
    {
        var row = AnalysisLayout.New();
        row.Set("ledger", code[..1]);
        row.Set("code", code[1..]);
        row.Set("description", description);
        row.Set("print", print);
        db.Write(AnalysisFile, code, row.B);
        return row;
    }

    private static Rec NewPostingValue(Rec analysis)
    {
        var value = AnalysisValueLayout.New();
        analysis.B.CopyTo(value.B, 0);
        return value;
    }

    private static Rec ReadPostingValue(byte[] data) => data.Length == AnalysisValueLayout.Size
        ? AnalysisValueLayout.From(data) : throw new SalesRuleException("分析実績ファイルのレコード長が一致しません。");

    private Rec EnsurePostingValue(string code)
    {
        if (db.Read(ValueFile, code) is { } value) return ReadPostingValue(value);
        string parentCode = code[..2] + " ";
        Rec analysis;
        if (db.Read(AnalysisFile, code) is { } found) analysis = AnalysisLayout.From(found);
        else
        {
            analysis = NewPostingAnalysis(code, "Emergency Name", "");
            if (code != parentCode && db.Read(AnalysisFile, parentCode) == null)
                NewPostingAnalysis(parentCode, "Emergency Name", "");
        }
        if (code != parentCode && db.Read(AnalysisFile, parentCode) is { } parent &&
            db.Read(ValueFile, parentCode) == null)
            db.Write(ValueFile, parentCode, NewPostingValue(AnalysisLayout.From(parent)).B);
        return NewPostingValue(analysis);
    }

    private void AddPostingValue(Rec value, int count, decimal amount)
    {
        value.SetN("countCurrent", value.N("countCurrent") + count);
        value.SetN("countYear", value.N("countYear") + count);
        value.SetN("valueCurrent", value.N("valueCurrent") + amount);
        value.SetN("valueYear", value.N("valueYear") + amount);
        db.Put(ValueFile, value.S("code"), value.B);
    }
}
