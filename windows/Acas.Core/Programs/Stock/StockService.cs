using Acas.Core.Engine;

namespace Acas.Core.Programs.Stock;

/// <summary>在庫（ST）業務ロジック: stock.cbl / st000 / st010 / st020 / st030 / st040 / st050。</summary>
public sealed class StockService
{
    public const string StockFile = "ledgers/acas/stockctl.dat";
    public const string AuditFile = "ledgers/acas/staudit.dat";
    public const string AnalysisFile = "ledgers/acas/analysis.dat";
    public const string SystemFile = "ledgers/acas/system.dat";
    private const string SystemKey = "00000001";
    public const decimal MaxQuantity = 999_998;
    private const decimal MaxValue = 99_999_999.99m;

    private readonly Db _db;
    private readonly Func<DateTime> _now;

    public StockService(Db db, Func<DateTime> now)
    {
        _db = db;
        _now = now;
        var raw = db.Read(SystemFile, SystemKey);
        System = raw == null ? Layouts.System.New() : Layouts.System.From(raw);
        ToDay = StockDates.ToUk(now());
    }

    /// <summary>メモリ上のシステムレコード（stock.cbl は終了時・システム設定呼出時に書き戻す）。</summary>
    public Rec System { get; }

    /// <summary>処理日 (dd/mm/yyyy)。</summary>
    public string ToDay { get; private set; }

    public DateTime ToDayDate => StockDates.FromBin(StockDates.UkToBin(ToDay));
    public DateTime Now() => _now();
    public int DateForm => System.I("Date-Form") is 2 or 3 ? System.I("Date-Form") : 1;
    public string UserName => System.St("Usera");
    public bool AuditUsed => System.I("Stk-Audit-Used") == 1;

    /// <summary>st000: 処理日を設定する。</summary>
    public void SetDate(DateTime date)
    {
        ToDay = StockDates.ToUk(date);
        System.SetN("Run-Date", StockDates.ToBin(date));
    }

    /// <summary>aa070-OverRewrite: システムレコードを書き戻す。</summary>
    public void SaveSystem()
    {
        if (_db.Read(SystemFile, SystemKey) != null) _db.Rewrite(SystemFile, SystemKey, System.B);
    }

    public bool StockFileExists => _db.Exists(StockFile);

    public IEnumerable<Rec> Items() => _db.Scan(StockFile).Select(r => Layouts.Stock.From(r.Data));

    public Rec? ReadKey(string key)
    {
        var raw = _db.Read(StockFile, Fmt.X(key.ToUpperInvariant(), 13));
        return raw == null ? null : Layouts.Stock.From(raw);
    }

    public Rec? ReadAbrev(string abrev)
    {
        string k = Fmt.X(abrev.ToUpperInvariant(), 7);
        return Items().FirstOrDefault(r => r.S("Stock-Abrev-Key") == k);
    }

    /// <summary>入力が 7 桁以内なら略号、それ以外は品目番号で検索する (st020 ba010)。</summary>
    public Rec? Find(string input, out string? error)
    {
        string v = input.Trim().ToUpperInvariant();
        error = null;
        if (v.Length <= 7)
        {
            var r = ReadAbrev(v);
            if (r == null) error = StockMessages.ST203;
            return r;
        }
        var k = ReadKey(v);
        if (k == null) error = StockMessages.ST214;
        return k;
    }

    public const string PurchaseFile = "ledgers/acas/purchled.dat";

    public bool SupplierExists(string code) => _db.Read(PurchaseFile, Fmt.X(code.ToUpperInvariant(), 7)) != null;

    public void Rewrite(Rec item) => _db.Rewrite(StockFile, item.S("Stock-Key"), item.B);

    // ───────── 入出庫 (st020) ─────────

    /// <summary>数量入力 (pic 9(6) + 符号: 空白 または "-")。</summary>
    public static bool TryQuantity(string text, out decimal qty, out bool reverse, out string? error)
    {
        qty = 0; reverse = false; error = null;
        string t = text.TrimStart();
        if (t.EndsWith('-')) { reverse = true; t = t[..^1]; }
        t = t.TrimEnd();
        if (t.Length == 0) t = "0";
        if (!t.All(char.IsAsciiDigit)) { error = StockMessages.ST207; return false; }
        qty = decimal.Parse(t);
        if (qty > MaxQuantity) { error = StockMessages.ST204; return false; }
        return true;
    }

    public static bool TryAmount(string text, int dec, out decimal value)
    {
        value = 0;
        string t = text.Trim().Replace(",", "");
        if (t.Length == 0) return true;
        if (!decimal.TryParse(t, global::System.Globalization.NumberStyles.AllowDecimalPoint, global::System.Globalization.CultureInfo.InvariantCulture, out value)) return false;
        value = Cob.Trunc(value, dec);
        return value < 10_000_000m;
    }

    public MovementResult Addition(Rec item, decimal qty, bool reverse, decimal price, MovementKind kind = MovementKind.Addition)
    {
        if (item.St("Stock-Services-Flag") == "Y") return MovementResult.Fail(StockMessages.ST217);
        decimal signed = reverse ? -qty : qty;
        decimal held = item.N("Stock-Held");
        decimal newQty = held + signed;
        if (newQty > MaxQuantity) return MovementResult.Fail(StockMessages.ST205);
        if (newQty < 0) return MovementResult.Fail(StockMessages.ST206);
        var warnings = new List<string>();
        if (newQty == 0) warnings.Add(StockMessages.ST208);

        item.SetN("Stock-Last-Actual-Cost", price);
        decimal wip = item.N("Stock-Work-in-Progress");
        decimal oldValue = (held + wip) * item.N("Stock-Cost");
        decimal change = signed * price;
        decimal newValue = oldValue + change;
        if (newValue < 0) { newValue = 0; warnings.Add(StockMessages.ST209); }
        if (newValue > MaxValue) { newValue = MaxValue; warnings.Add(StockMessages.ST212); }
        if (newQty != 0) item.SetN("Stock-Cost", Cob.Round(newValue / newQty, 4));

        decimal onOrder = item.N("Stock-On-Order") - qty;
        decimal back = item.N("Stock-Back-Ordered") + onOrder;
        item.SetN("Stock-On-Order", 0);
        item.SetN("Stock-Back-Ordered", Math.Max(0, back));
        var line = new MovementLine(kind, item.St("Stock-Key"), item.St("Stock-Desc"), signed, price, change, item.N("Stock-Order-Date"), item.N("Stock-Order-Due"));
        if (item.N("Stock-Back-Ordered") == 0) { item.SetN("Stock-Order-Date", 0); item.SetN("Stock-Order-Due", 0); }
        AddMonthly(item, "Adds", signed);
        item.SetN("Stock-Value", Cob.Round(newValue, 2));
        item.SetN("Stock-Held", newQty);
        Rewrite(item);
        WriteAudit(item, 1, signed, price, change, reverse);
        return new MovementResult(true, null, warnings, line);
    }

    public MovementResult Deduction(Rec item, decimal qty, bool reverse)
    {
        if (item.St("Stock-Services-Flag") == "Y") return MovementResult.Fail(StockMessages.ST217);
        decimal signed = reverse ? -qty : qty;
        decimal held = item.N("Stock-Held");
        decimal newQty = held - signed;
        if (newQty < 0) return MovementResult.Fail(StockMessages.ST206);
        if (newQty > MaxQuantity) return MovementResult.Fail(StockMessages.ST205);
        var warnings = new List<string>();
        if (newQty == 0) warnings.Add(StockMessages.ST208);
        decimal cost = item.N("Stock-Cost");
        decimal change = signed * cost * -1;
        AddMonthly(item, "Deducts", signed);
        item.SetN("Stock-Held", newQty);
        decimal value = (newQty + item.N("Stock-Work-in-Progress")) * cost;
        if (value > MaxValue) { value = MaxValue; warnings.Add(StockMessages.ST212); }
        item.SetN("Stock-Value", Cob.Round(value, 2));
        Rewrite(item);
        WriteAudit(item, 2, signed, cost, Cob.Round(change, 2), reverse);
        return new MovementResult(true, null, warnings, new MovementLine(MovementKind.Deduction, item.St("Stock-Key"), item.St("Stock-Desc"),
            signed, cost, Cob.Round(change, 2), 0, 0));
    }

    /// <summary>da000: バーコード入庫（数量 1、単価は直近実績原価、無ければ標準原価）。</summary>
    public MovementResult Barcode(Rec item)
    {
        decimal price = item.N("Stock-Last-Actual-Cost") != 0 ? item.N("Stock-Last-Actual-Cost") : Cob.Round(item.N("Stock-Cost"), 2);
        return Addition(item, 1, false, price, MovementKind.Barcode);
    }

    /// <summary>fa000: 発注情報の記録。</summary>
    public string? Order(Rec item, decimal onOrder, DateTime? ordered, DateTime? due, decimal backOrdered)
    {
        if (item.St("Stock-Services-Flag") == "Y") return StockMessages.ST217;
        if (onOrder > MaxQuantity || backOrdered > MaxQuantity) return StockMessages.ST204;
        if (onOrder != 0 && ordered == null) return StockMessages.ST005 + " " + StockMessages.ST250;
        if (onOrder != 0 && due == null) return StockMessages.ST005 + " " + StockMessages.ST251;
        item.SetN("Stock-On-Order", onOrder);
        item.SetN("Stock-Order-Date", ordered is DateTime o ? StockDates.ToBin(o) : 0);
        item.SetN("Stock-Order-Due", due is DateTime d ? StockDates.ToBin(d) : 0);
        item.SetN("Stock-Back-Ordered", backOrdered);
        Rewrite(item);
        return null;
    }

    private void AddMonthly(Rec item, string what, decimal qty)
    {
        int month = int.Parse(ToDay.Substring(3, 2));
        string td = what == "Adds" ? "Stock-TD-Adds-" : "Stock-TD-Deds-";
        item.SetN("Stock-" + what, Math.Max(0, item.N("Stock-" + what) + qty));
        item.SetN(td + month, Math.Max(0, item.N(td + month) + qty));
    }

    private void WriteAudit(Rec item, int type, decimal qty, decimal unitCost, decimal change, bool reverse)
    {
        if (!AuditUsed) return;
        System.SetN("Stk-Activity-Rep-Run", 0);
        if (!_db.Exists(AuditFile)) _db.Create(AuditFile);
        System.SetN("File-Status-10", 1);
        var a = Layouts.StockAudit.New();
        a.SetN("Audit-Type", type);
        a.Set("Audit-Stock-Key", item.S("Stock-Key"));
        a.Set("Audit-Desc", item.S("Stock-Desc"));
        a.Set("Audit-Process-Date", ToDay);
        a.SetN("Audit-Reverse-Transaction", reverse ? 1 : 0);
        a.SetN("Audit-Transaction-Qty", qty);
        a.SetN("Audit-Unit-Cost", unitCost);
        a.SetN("Audit-Stock-Value-Change", change);
        a.SetN("Audit-No", System.N("Stk-Audit-No"));
        _db.Write(AuditFile, (_db.Count(AuditFile) + 1).ToString("D8"), a.B);
    }

    public IReadOnlyList<Rec> AuditRecords() =>
        _db.Exists(AuditFile) ? _db.Scan(AuditFile).Select(r => Layouts.StockAudit.From(r.Data)).ToList() : [];

    /// <summary>メニュー 5: 監査帳票の出力後に実行済みフラグを立てる。</summary>
    public void MarkAuditReported() => System.SetN("Stk-Activity-Rep-Run", 1);

    /// <summary>監査ファイルを再作成し、監査番号を進める。</summary>
    public void DeleteAudit()
    {
        _db.Recreate(AuditFile);
        System.SetN("Stk-Audit-No", System.N("Stk-Audit-No") + 1);
    }

    // ───────── 期間締め (st040) ─────────

    public bool ActivityReportRun => System.I("Stk-Activity-Rep-Run") == 1;

    public int ResetActivity(bool period, bool year)
    {
        int n = 0;
        foreach (var item in Items().ToList())
        {
            if (period)
                foreach (var f in new[] { "Stock-Adds", "Stock-Deducts", "Stock-Wip-Adds", "Stock-Wip-Deds" }) item.SetN(f, 0);
            if (year)
                for (int m = 1; m <= 12; m++)
                    foreach (var f in new[] { "Stock-TD-Adds-", "Stock-TD-Deds-", "Stock-TD-Wip-Adds-", "Stock-TD-Wip-Deds-" }) item.SetN(f + m, 0);
            Rewrite(item);
            n++;
        }
        return n;
    }

    // ───────── 圧縮 (st050) ─────────

    /// <summary>在庫評価額を 保有数 × 原価 で再計算し、ファイルを再構築する。</summary>
    public int Compress()
    {
        var items = Items().ToList();
        foreach (var item in items)
        {
            item.SetN("Stock-Value", Cob.Round(item.N("Stock-Held") * item.N("Stock-Cost"), 2));
            _db.Rewrite(StockFile, item.S("Stock-Key"), item.B);
        }
        return items.Count;
    }

    // ───────── 品目保守 (st010) ─────────

    /// <summary>レガシーは分析ファイル (36 バイト) を開けないと変更処理を中止する (状態 39)。</summary>
    public bool AnalysisUsable()
    {
        if (!_db.Exists(AnalysisFile)) return false;
        var recs = _db.Scan(AnalysisFile);
        return recs.Count > 0 && recs.All(r => r.Data.Length == 36);
    }

    public string? Create(Rec item)
    {
        if (!_db.Exists(StockFile)) _db.Create(StockFile);
        if (item.St("Stock-Key").Length == 0) return StockMessages.ST114;
        if (item.St("Stock-Abrev-Key").Length == 0) return StockMessages.ST102;
        if (ReadKey(item.St("Stock-Key")) != null) return StockMessages.ST116;
        if (item.St("Stock-Abrev-Key").Length > 0 && ReadAbrev(item.St("Stock-Abrev-Key")) != null) return StockMessages.ST113;
        _db.Write(StockFile, item.S("Stock-Key"), item.B);
        return null;
    }

    public string? Delete(Rec item)
    {
        if (item.N("Stock-On-Order") != 0 || item.N("Stock-Held") != 0 || item.N("Stock-Back-Ordered") != 0) return StockMessages.ST107;
        _db.Delete(StockFile, item.S("Stock-Key"));
        return null;
    }

    public string? Renumber(Rec item, string newKey, string newAbrev)
    {
        newKey = newKey.Trim().ToUpperInvariant();
        newAbrev = newAbrev.Trim().ToUpperInvariant();
        if (item.N("Stock-On-Order") != 0 || item.N("Stock-Back-Ordered") != 0) return StockMessages.ST109;
        if (newKey.Length == 0) return StockMessages.ST114;
        if (newKey != item.St("Stock-Key") && ReadKey(newKey) != null) return StockMessages.ST116;
        if (newAbrev.Length > 0 && newAbrev != item.St("Stock-Abrev-Key") && ReadAbrev(newAbrev) != null) return StockMessages.ST113;
        _db.Delete(StockFile, item.S("Stock-Key"));
        item.Set("Stock-Key", newKey);
        if (newAbrev.Length > 0) item.Set("Stock-Abrev-Key", newAbrev);
        _db.Write(StockFile, item.S("Stock-Key"), item.B);
        return null;
    }

    public void Spool(StockReport report) => _db.AddSpool(report.Title, report.Japanese);
}

public enum MovementKind { Addition, Deduction, Barcode }

public sealed record MovementLine(MovementKind Kind, string Key, string Desc, decimal Qty, decimal Price, decimal Value, decimal OrderDate, decimal OrderDue);

public sealed record MovementResult(bool Ok, string? Error, IReadOnlyList<string> Warnings, MovementLine? Line)
{
    public static MovementResult Fail(string error) => new(false, error, [], null);
}
