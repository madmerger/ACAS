using Acas.Core.Engine;

namespace Acas.Core.Programs.Stock;

/// <summary>在庫帳票の生成（st010 ea200 / st020 入出庫・監査帳票）。</summary>
public static class StockReports
{
    private const string St010Id = "ST010 (3.01.37)";
    private const string St020Id = "ST020 (3.01.29)";
    private const string Dash132 = "------------------------------------------------------------------------------------------------------------------------------------";

    private static string Time(DateTime now) => now.ToString("HH:mm");

    private static string St020Heading(string title, int page) => Fmt.X(St020Id, 55) + Fmt.X(title, 69) + "Page " + Fmt.E(page, "zz9");

    private static string St020Line2(StockService s, string batch, DateTime now) =>
        Fmt.X(s.UserName, 61) + Fmt.X(batch, 55) + Fmt.X(StockDates.ToSystemForm(s.ToDay, s.DateForm), 10) + " " + Time(now);

    private static string DataLine(string date, string key, string desc, decimal qty, string price, decimal value, string tail = "") =>
        Fmt.X(date, 11) + Fmt.X(key, 14) + Fmt.X(desc, 32) + Fmt.E(qty, "zzzzzz9-") + price + Fmt.E(value, "zzzzz,zz9.99-") + tail;

    private static string Price(decimal price) => Fmt.E(price, "zzzzzz9.99-");

    /// <summary>入庫・出庫明細表（入力した明細ごと 1 行）。明細が無ければ null。</summary>
    public static StockReport? Movements(StockService s, MovementKind kind, IReadOnlyList<MovementLine> lines)
    {
        if (lines.Count == 0) return null;
        bool add = kind != MovementKind.Deduction;
        string title = add ? "Stock Addition Report" : "Stock Deduction Report";
        string date = StockDates.ToSystemForm(s.ToDay, s.DateForm);
        var now = s.Now();
        var legacy = new List<string>
        {
            St020Heading(title, 1), St020Line2(s, "", now), "",
            new string(' ', 78) + "Change in",
            "Proc. Date " + "Stock Number  Description                         Qty    " + (add ? "Price" : "     ") + "    Stock Value    "
                + (add ? "Order Date    Date Due     Order Status" : ""),
            "",
        };
        foreach (var l in lines)
        {
            string tail = "";
            if (add && (l.OrderDate != 0 || l.OrderDue != 0))
                tail = "   " + Fmt.X(StockDates.BinToSystemForm(l.OrderDate, s.DateForm), 13) + Fmt.X(StockDates.BinToSystemForm(l.OrderDue, s.DateForm), 13);
            legacy.Add(DataLine(date, l.Key, l.Desc, l.Qty, add ? Price(l.Price) : new string(' ', 11), l.Value, tail));
        }
        string jpTitle = add ? "入庫明細表" : "出庫明細表";
        var head = new[] { jpTitle + "　" + s.UserName, "処理日 " + date + "　出力 " + Time(now) };
        var rows = lines.Select(l => add
            ? new[] { "品目番号 " + l.Key, "品名 " + l.Desc, "数量 " + Fmt.E(l.Qty, "zzz,zz9-").Trim(), "単価 " + Price(l.Price).Trim(), "金額 " + Fmt.E(l.Value, "zzzzz,zz9.99-").Trim() }
            : new[] { "品目番号 " + l.Key, "品名 " + l.Desc, "数量 " + Fmt.E(l.Qty, "zzz,zz9-").Trim(), "金額 " + Fmt.E(l.Value, "zzzzz,zz9.99-").Trim() });
        return new StockReport(jpTitle, legacy, Fmt.Table(jpTitle, head, rows));
    }

    /// <summary>月末監査帳票（入庫監査・出庫監査の 2 帳票）。</summary>
    public static IReadOnlyList<StockReport> Audit(StockService s, IReadOnlyList<Rec> audit)
    {
        var adds = audit.Where(a => a.I("Audit-Type") is 1 or 4).ToList();
        var deds = audit.Where(a => a.I("Audit-Type") is 2 or 3 or 5).ToList();
        decimal totalAdds = adds.Sum(a => a.N("Audit-Stock-Value-Change"));
        decimal totalDeds = deds.Sum(a => a.N("Audit-Stock-Value-Change"));
        return [AuditReport(s, "Additions Stock Audit Report", "入庫監査表", adds, totalAdds, totalDeds),
                AuditReport(s, "Deductions Stock Audit Report", "出庫監査表", deds, totalAdds, totalDeds)];
    }

    private static string Total(string label, decimal v) => new string(' ', 56) + Fmt.X(label, 18) + Fmt.E(v, "zzz,zzz,zz9.99") + (v < 0 ? "-" : "");

    private static StockReport AuditReport(StockService s, string title, string jpTitle, List<Rec> recs, decimal adds, decimal deds)
    {
        var now = s.Now();
        string batch = "Batch " + Fmt.E(s.System.N("Stk-Audit-No"), "zz9");
        var legacy = new List<string>
        {
            St020Heading(title, 1), St020Line2(s, batch, now), "",
            "Proc. Date " + "Stock Number  Description                         Qty    " + "Price" + "    Stock Value    " + "Source/Inv.no.",
            "",
        };
        foreach (var a in recs)
            legacy.Add(DataLine(a.St("Audit-Process-Date"), a.St("Audit-Stock-Key"), a.St("Audit-Desc"), a.N("Audit-Transaction-Qty"),
                Price(a.N("Audit-Unit-Cost")), a.N("Audit-Stock-Value-Change"), "    " + Fmt.E(a.N("Audit-Invoice-PO"), "zzzzzzz9")));
        legacy.AddRange(["", "", Total("Total Additions", adds), Total("Total Deductions", deds),
            new string(' ', 74) + "--------------", Total("Total Changes", adds + deds), new string(' ', 74) + "=============="]);
        var head = new[] { jpTitle + "　" + s.UserName, "監査番号 " + s.System.N("Stk-Audit-No") + "　処理日 " + StockDates.ToSystemForm(s.ToDay, s.DateForm) + "　出力 " + Time(now) };
        var rows = recs.Select(a => new[] { "処理日 " + a.St("Audit-Process-Date"), "品目番号 " + a.St("Audit-Stock-Key"), "品名 " + a.St("Audit-Desc"),
            "数量 " + Fmt.E(a.N("Audit-Transaction-Qty"), "zzz,zz9-").Trim(), "金額 " + Fmt.E(a.N("Audit-Stock-Value-Change"), "zzzzz,zz9.99-").Trim() });
        var foot = new[] { "入庫合計 " + Fmt.E(adds, "zz,zzz,zz9.99-").Trim(), "出庫合計 " + Fmt.E(deds, "zz,zzz,zz9.99-").Trim(), "増減合計 " + Fmt.E(adds + deds, "zz,zzz,zz9.99-").Trim() };
        return new StockReport(jpTitle, legacy, Fmt.Table(jpTitle, head, rows, foot));
    }

    /// <summary>st010 ea200: 在庫ファイル一覧表。</summary>
    public static StockReport StockFile(StockService s, IReadOnlyList<Rec> items)
    {
        var now = s.Now();
        int pageLines = s.System.I("Page-Lines");
        var legacy = new List<string>();
        int lineCnt = 99, page = 0;
        void Heads()
        {
            if (lineCnt <= pageLines) return;
            page++;
            if (page != 1) legacy.Add("\f");
            legacy.Add(Fmt.X(St010Id, 16) + new string(' ', 41) + "Stock File Report" + new string(' ', 50) + "Page " + Fmt.E(page, "zz9"));
            legacy.Add(Fmt.X(s.UserName, 40) + new string(' ', 76) + Fmt.X(StockDates.ToSystemForm(s.ToDay, s.DateForm), 10) + " " + Time(now));
            legacy.Add("");
            legacy.Add("<------ Stock ------> Supplier  Location     Unit      Unit        Value    Number <- ReOrder -> <------- Date ------>  Quantity On");
            legacy.Add("Abrev   Number         Number               Price      Cost        in Stk   in Stk  Point    Qty   Ordered     Due      Order  B/Ord");
            lineCnt = 5;
        }
        foreach (var r in items)
        {
            Heads();
            bool services = r.St("Stock-Services-Flag") == "Y";
            string cost = Fmt.E(r.N("Stock-Cost"), "zzzzzz9.9999");
            if (cost.EndsWith("00")) cost = cost[..^2] + "  ";
            string line5 = Fmt.X(r.St("Stock-Abrev-Key"), 8) + Fmt.X(r.St("Stock-Key"), 14) + Fmt.X(r.St("Stock-Supplier-P1"), 8)
                + Fmt.X(r.St("Stock-Location"), 11) + Fmt.E(r.N("Stock-Retail"), "zzzzzz9.99") + cost
                + (services ? new string(' ', 12 + 7 + 7 + 8) : Fmt.E(r.N("Stock-Value"), "zzzzz,zz9.99") + Fmt.E(r.N("Stock-Held"), "zzzzzz9")
                    + Fmt.E(r.N("Stock-ReOrder-Pnt"), "zzzzzz9") + Fmt.E(r.N("Stock-Std-ReOrder"), "zzzzzz9") + " ")
                + Fmt.X(StockDates.BinToSystemForm(r.N("Stock-Order-Date"), s.DateForm), 11) + Fmt.X(StockDates.BinToSystemForm(r.N("Stock-Order-Due"), s.DateForm), 10)
                + (services ? "" : Fmt.E(r.N("Stock-On-Order"), "zzzzzz9") + Fmt.E(r.N("Stock-Back-Ordered"), "zzzzzz9"));
            string vars = "";
            if (r.St("Stock-Supplier-P2").Length > 0 || r.St("Stock-Supplier-P3").Length > 0)
            {
                vars = "Secondary Suppliers";
                if (r.St("Stock-Supplier-P2").Length > 0) vars += " 1: " + r.S("Stock-Supplier-P2");
                if (r.St("Stock-Supplier-P3").Length > 0) vars += " 2: " + r.S("Stock-Supplier-P3");
                vars += "  ";
            }
            if (r.St("Stock-SA-Code").Length > 0) vars += "SA Code: " + r.S("Stock-SA-Group") + "  ";
            if (r.St("Stock-PA-Code").Length > 0) vars += "PA Code: " + r.S("Stock-PA-Group");
            if (r.N("Stock-Pre-Sales") != 0) vars += " Pre Sales :" + Fmt.E(r.N("Stock-Pre-Sales"), "zzzzz9");
            if (lineCnt > 5) { legacy.Add(Dash132); legacy.Add(line5); }
            else { legacy.Add(""); legacy.Add(line5); }
            legacy.Add(new string(' ', 5) + "Description: " + Fmt.X(r.St("Stock-Desc"), 32) + new string(' ', 5) + Fmt.X(vars, 77));
            lineCnt += 3;
            if (!services && (r.N("Stock-Construct-Bundle") != 0 || r.N("Stock-Under-Construction") != 0 || r.N("Stock-Work-in-Progress") != 0 || r.St("Stock-Construct-Item").Length > 0))
            {
                legacy.Add("Construction Bundle :" + Fmt.E(r.N("Stock-Construct-Bundle"), "zzzzz9") + " WIP :" + Fmt.E(r.N("Stock-Work-in-Progress"), "zzzzz9")
                    + " Under Construction :" + Fmt.E(r.N("Stock-Under-Construction"), "zzzzz9") + " For Constructed Item : " + r.S("Stock-Construct-Item"));
                lineCnt++;
            }
            if (services) { legacy.Add("Services only Product"); lineCnt++; }
        }
        if (lineCnt > pageLines - 3) { lineCnt += 60; Heads(); }
        legacy.AddRange(["", "", " Total Stock Records " + items.Count]);

        var head = new[] { "在庫ファイル一覧表　" + s.UserName, "処理日 " + StockDates.ToSystemForm(s.ToDay, s.DateForm) + "　出力 " + Time(now) };
        var rows = items.Select(r => new[] { "略号 " + r.St("Stock-Abrev-Key"), "品目番号 " + r.St("Stock-Key"), "品名 " + r.St("Stock-Desc"),
            "保管場所 " + r.St("Stock-Location"), "売価 " + Fmt.E(r.N("Stock-Retail"), "zzzzzz9.99").Trim(), "原価 " + Fmt.E(r.N("Stock-Cost"), "zzzzzz9.9999").Trim(),
            "在庫金額 " + Fmt.E(r.N("Stock-Value"), "zzzzz,zz9.99").Trim(), "在庫数 " + Fmt.E(r.N("Stock-Held"), "zzzzzz9").Trim(),
            "発注点 " + Fmt.E(r.N("Stock-ReOrder-Pnt"), "zzzzzz9").Trim(), "発注量 " + Fmt.E(r.N("Stock-Std-ReOrder"), "zzzzzz9").Trim() });
        return new StockReport("在庫ファイル一覧表", legacy, Fmt.Table("在庫ファイル一覧表", head, rows, ["在庫品目数 " + items.Count]));
    }

    /// <summary>st030: 帳票メニュー 1〜5（範囲指定済みの品目で日本語帳票を作成）。</summary>
    public static StockReport Analysis(StockService s, int kind, IReadOnlyList<Rec> items)
    {
        string title = kind switch { 1 => "在庫評価表", 2 => "在庫受払表", 3 => "発注点割れ一覧表", 4 => "在庫履歴表", _ => "在庫一覧表" };
        int month = int.Parse(s.ToDay.Substring(3, 2));
        IEnumerable<Rec> sel = kind == 3 ? items.Where(r => r.St("Stock-Services-Flag") != "Y" && r.N("Stock-Held") <= r.N("Stock-ReOrder-Pnt")) : items;
        string Q(Rec r, string f) => Fmt.E(r.N(f), "zzzzzz9-").Trim();
        var rows = sel.Select(r => kind switch
        {
            1 => new[] { "品目番号 " + r.St("Stock-Key"), "品名 " + r.St("Stock-Desc"), "在庫数 " + Q(r, "Stock-Held"),
                "原価 " + Fmt.E(r.N("Stock-Cost"), "zzzzzz9.9999").Trim(), "在庫金額 " + Fmt.E(r.N("Stock-Value"), "zzzzz,zz9.99").Trim() },
            2 => new[] { "品目番号 " + r.St("Stock-Key"), "品名 " + r.St("Stock-Desc"), "当期入庫 " + Q(r, "Stock-Adds"), "当期出庫 " + Q(r, "Stock-Deducts"),
                "年間入庫 " + Fmt.E(Enumerable.Range(1, 12).Sum(m => r.N("Stock-TD-Adds-" + m)), "zzzzzz9").Trim(),
                "年間出庫 " + Fmt.E(Enumerable.Range(1, 12).Sum(m => r.N("Stock-TD-Deds-" + m)), "zzzzzz9").Trim() },
            3 => new[] { "品目番号 " + r.St("Stock-Key"), "品名 " + r.St("Stock-Desc"), "在庫数 " + Q(r, "Stock-Held"), "発注残 " + Q(r, "Stock-On-Order"),
                "発注点 " + Q(r, "Stock-ReOrder-Pnt"), "標準発注量 " + Q(r, "Stock-Std-ReOrder") },
            4 => new[] { "品目番号 " + r.St("Stock-Key"), "品名 " + r.St("Stock-Desc") }
                .Concat(Enumerable.Range(1, 12).Select(m => m + "月 入" + Q(r, "Stock-TD-Adds-" + m) + "／出" + Q(r, "Stock-TD-Deds-" + m))).ToArray(),
            _ => new[] { "略号 " + r.St("Stock-Abrev-Key"), "品目番号 " + r.St("Stock-Key"), "品名 " + r.St("Stock-Desc"), "保管場所 " + r.St("Stock-Location"),
                "在庫数 " + Q(r, "Stock-Held"), "売価 " + Fmt.E(r.N("Stock-Retail"), "zzzzzz9.99").Trim() },
        }).ToList();
        var head = new[] { title + "　" + s.UserName, "処理日 " + StockDates.ToSystemForm(s.ToDay, s.DateForm) + "　当月 " + month + "月" };
        var foot = new List<string> { "対象品目数 " + rows.Count };
        if (kind == 1) foot.Add("在庫金額合計 " + Fmt.E(sel.Sum(r => r.N("Stock-Value")), "zzz,zzz,zz9.99").Trim());
        return new StockReport(title, [], Fmt.Table(title, head, rows, foot));
    }

    /// <summary>メニュー 4: 発注更新明細表（記録した品目ごとに発注数・入荷待ち・注文日・納期）。</summary>
    public static StockReport? Orders(StockService s, IReadOnlyList<Rec> items)
    {
        if (items.Count == 0) return null;
        const string title = "発注更新明細表";
        var head = new[] { title + "　" + s.UserName, "処理日 " + StockDates.ToSystemForm(s.ToDay, s.DateForm) };
        var rows = items.Select(r => new[] { "品目番号 " + r.St("Stock-Key"), "品名 " + r.St("Stock-Desc"),
            "発注数 " + Fmt.E(r.N("Stock-On-Order"), "zzzzzz9").Trim(), "入荷待ち " + Fmt.E(r.N("Stock-Back-Ordered"), "zzzzzz9").Trim(),
            "注文日 " + StockDates.BinToSystemForm(r.N("Stock-Order-Date"), s.DateForm), "納期 " + StockDates.BinToSystemForm(r.N("Stock-Order-Due"), s.DateForm) }).ToList();
        return new StockReport(title, [], Fmt.Table(title, head, rows, ["対象品目数 " + rows.Count]));
    }
}
