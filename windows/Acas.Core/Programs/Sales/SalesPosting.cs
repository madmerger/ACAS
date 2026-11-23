using System.Globalization;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed partial class SalesLedger
{
    public const string PostingStageFile = Prefix + "openitm2.dat";
    private const string SalesTotalsKey = "00000004";
    private static readonly string[] InvoiceAmounts =
        ["net", "extra", "carriage", "vat", "discount", "extraVat", "carriageVat", "deductAmount", "deductVat"];

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
