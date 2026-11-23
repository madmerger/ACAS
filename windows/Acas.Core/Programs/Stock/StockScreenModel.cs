using Acas.Core.Engine;

namespace Acas.Core.Programs.Stock;

/// <summary>在庫（ST）の画面遷移。stock.cbl のメニューと st000〜st050 の入力を型付き画面モデルで構成する。</summary>
public sealed class StockScreenModel(Db db, Func<DateTime> clock)
{
    public const string MainTitle = "在庫管理メニュー";
    public const string MaintenanceTitle = "在庫品目マスター管理";
    public const string MovementsTitle = "在庫入出庫メニュー";
    public const string ReportsTitle = "在庫帳票メニュー";

    private StockService? _service;

    /// <summary>現在の業務セッション（在庫管理を開くたびに作り直す）。</summary>
    public StockService Service => _service ??= new StockService(db, clock);

    public MenuItem Navigation() => new("StockNavigation", "在庫管理", Open: Start);

    /// <summary>在庫管理の起動: システムレコードを読み直し、処理日入力から始める。</summary>
    public Screen Start()
    {
        _service = new StockService(db, clock);
        return StartOfDay();
    }

    // ───────── stock.cbl / st000 ─────────

    public Screen StartOfDay() => new FormScreen("在庫管理　処理日入力",
        [new DateField("StockRunDate", "処理日", Service.ToDayDate)], "決定", v =>
        {
            if (v.Date("StockRunDate") is not DateTime d)
                return Error("在庫管理　処理日入力", StockMessages.ST005, StartOfDay, StartOfDay);
            Service.SetDate(d);
            return MainMenu();
        });

    public Screen MainMenu() => new MenuScreen(MainTitle,
    [
        new("StockDateEntry", "A　処理日入力", Open: StartOfDay),
        new("StockMaintenance", "B　在庫品目マスター管理", Open: MaintenanceMenu),
        new("StockMovements", "C　在庫入出庫", Open: MovementsMenu),
        new("StockReports", "D　在庫帳票", Open: ReportsMenu),
        new("StockEndOfCycle", "E　期間締め処理", Open: ActivityReset),
        new("StockExit", "X　システムメニューへ戻る", Open: Exit),
        new("StockCompression", "Y　在庫ファイル圧縮", Open: Compression),
        new("StockSystemSetUp", "Z　システム設定", Open: SystemSetUp),
    ]);

    /// <summary>メインメニューの選択文字と項目 ID（F〜W は該当なしでメニューに留まる）。</summary>
    public static readonly IReadOnlyDictionary<char, string> MainMenuKeys = new Dictionary<char, string>
    {
        ['A'] = "StockDateEntry", ['B'] = "StockMaintenance", ['C'] = "StockMovements", ['D'] = "StockReports",
        ['E'] = "StockEndOfCycle", ['X'] = "StockExit", ['Y'] = "StockCompression", ['Z'] = "StockSystemSetUp",
    };

    private Screen Exit()
    {
        Service.SaveSystem();
        return new InformationScreen("システムメニュー", "在庫管理を終了しました。左側のメニューから業務を選択してください。");
    }

    private Screen SystemSetUp()
    {
        Service.SaveSystem();
        return new InformationScreen("システム設定", "在庫管理の設定内容を保存しました。システム設定は左側のメニューから開いてください。");
    }

    private static Screen Error(string title, string message, Func<Screen> retry, Func<Screen> back) =>
        new ConfirmationScreen(title, message, "再入力", retry, back);

    private static ChoiceField YesNo(string id, string label) =>
        new(id, label, [new Choice("N", "いいえ"), new Choice("Y", "はい")], "N");

    // ───────── st010 在庫品目マスター管理 ─────────

    public Screen MaintenanceMenu()
    {
        if (!Service.StockFileExists) return CreateForm();
        return new MenuScreen(MaintenanceTitle,
        [
            new("StockItemCreate", "在庫品目の登録", 1, Open: CreateForm),
            new("StockItemAmend", "在庫品目の変更", 2, Open: AmendStart),
            new("StockItemDelete", "在庫品目の削除", 3, Open: DeleteForm),
            new("StockItemRenumber", "在庫品目の付番変更", 4, Open: RenumberForm),
            new("StockItemDisplay", "在庫品目の照会", 5, Open: DisplayList),
            new("StockItemPrint", "在庫ファイル一覧表の印刷", 6, Open: PrintStockFile),
            new("StockMaintenanceBack", "在庫管理メニューへ戻る", 9, Open: MainMenu),
        ]);
    }

    private static IReadOnlyList<Field> ItemFields(Rec? r, bool withKey)
    {
        string S(string f) => r?.St(f) ?? "";
        string N(string f, string pic) => r == null ? "" : Fmt.E(r.N(f), pic).Trim();
        var fields = new List<Field>();
        if (withKey) fields.Add(new TextField("StockKey", "品目番号", S("Stock-Key"), 13));
        fields.AddRange(
        [
            new TextField("StockAbrev", "略号", S("Stock-Abrev-Key"), 7),
            new TextField("StockDesc", "品名", S("Stock-Desc"), 32),
            new TextField("StockSupplier1", "主仕入先", S("Stock-Supplier-P1"), 7),
            new TextField("StockSupplier2", "第二仕入先", S("Stock-Supplier-P2"), 7),
            new TextField("StockSupplier3", "第三仕入先", S("Stock-Supplier-P3"), 7),
            new TextField("StockLocation", "保管場所", S("Stock-Location"), 10),
            new TextField("StockSaCode", "売上分析コード", S("Stock-SA-Code"), 3),
            new TextField("StockPaCode", "仕入分析コード", S("Stock-PA-Code"), 3),
            new ChoiceField("StockServices", "役務専用品目", [new Choice("N", "いいえ"), new Choice("Y", "はい")], S("Stock-Services-Flag") == "Y" ? "Y" : "N"),
            new TextField("StockRetail", "売価", N("Stock-Retail", "zzzzzz9.99"), 10),
            new TextField("StockCost", "原価", N("Stock-Cost", "zzzzzz9.9999"), 12),
            new TextField("StockHeld", "在庫数量", N("Stock-Held", "zzzzz9"), 6),
            new TextField("StockValue", "在庫評価額", N("Stock-Value", "zzzzzzzz9.99"), 12),
            new TextField("StockReorderPoint", "発注点", N("Stock-ReOrder-Pnt", "zzzzzz9"), 6),
            new TextField("StockStdReorder", "標準発注量", N("Stock-Std-ReOrder", "zzzzzz9"), 6),
        ]);
        return fields;
    }

    private static bool SingleByte(string text) => text.All(c => c <= 'ÿ');

    private string? ApplyItem(Rec r, FormValues v)
    {
        if (new[] { "StockAbrev", "StockDesc", "StockSupplier1", "StockSupplier2", "StockSupplier3", "StockLocation", "StockSaCode", "StockPaCode" }
            .Any(id => !SingleByte(v.Text(id)))) return StockMessages.SingleByteOnly;
        foreach (var (id, f) in new[] { ("StockAbrev", "Stock-Abrev-Key"), ("StockDesc", "Stock-Desc"), ("StockSupplier1", "Stock-Supplier-P1"),
            ("StockSupplier2", "Stock-Supplier-P2"), ("StockSupplier3", "Stock-Supplier-P3"), ("StockLocation", "Stock-Location"),
            ("StockSaCode", "Stock-SA-Code"), ("StockPaCode", "Stock-PA-Code") })
        {
            string text = v.Text(id).Trim();
            r.Set(f, id is "StockDesc" or "StockLocation" ? text : text.ToUpperInvariant());
        }
        foreach (var f in new[] { "Stock-Supplier-P1", "Stock-Supplier-P2", "Stock-Supplier-P3" })
            if (r.St(f).Length > 0 && !Service.SupplierExists(r.St(f))) return StockMessages.ST101;
        r.Set("Stock-Services-Flag", v.Choice("StockServices") == "Y" ? "Y" : "N");
        if (!StockService.TryAmount(v.Text("StockRetail"), 2, out var retail) || !StockService.TryAmount(v.Text("StockCost"), 4, out var cost))
            return StockMessages.InvalidAmount;
        if (!StockService.TryAmount(v.Text("StockValue"), 2, out var value, 1_000_000_000m)) return StockMessages.InvalidAmount;
        if (!StockService.TryQuantity(v.Text("StockHeld"), out var held, out var negativeHeld, out var heldError) || negativeHeld)
            return heldError ?? StockMessages.ST207;
        if (!StockService.TryQuantity(v.Text("StockReorderPoint"), out var rp, out var neg1, out var e1) || neg1) return e1 ?? StockMessages.ST207;
        if (!StockService.TryQuantity(v.Text("StockStdReorder"), out var sr, out var neg2, out var e2) || neg2) return e2 ?? StockMessages.ST207;
        r.SetN("Stock-Retail", retail);
        r.SetN("Stock-Cost", cost);
        r.SetN("Stock-ReOrder-Pnt", rp);
        r.SetN("Stock-Std-ReOrder", sr);
        r.SetN("Stock-Held", held);
        if (r.St("Stock-Services-Flag") == "Y")
            foreach (var f in new[] { "Stock-Held", "Stock-On-Order", "Stock-Back-Ordered", "Stock-ReOrder-Pnt", "Stock-Std-ReOrder" }) r.SetN(f, 0);
        if (r.St("Stock-Services-Flag") == "Y") value = 0;
        else if (Service.System.I("Stk-Averaging") == 1 && value == 0 && held != 0 && cost != 0)
            value = Cob.Round((held + (Service.System.I("Stk-Manu-Used") == 1 ? r.N("Stock-Work-in-Progress") : 0)) * cost, 2);
        r.SetN("Stock-Value", value);
        return null;
    }

    public Screen CreateForm() => new FormScreen("在庫品目登録", ItemFields(null, true), "登録", v =>
    {
        var r = Layouts.Stock.New();
        r.Set("Stock-Key", v.Text("StockKey").Trim().ToUpperInvariant());
        string? err = SingleByte(v.Text("StockKey")) ? ApplyItem(r, v) ?? Service.Create(r) : StockMessages.SingleByteOnly;
        return err != null ? Error("在庫品目登録", err, CreateForm, MaintenanceMenu)
            : new ConfirmationScreen("在庫品目登録", "品目「" + r.St("Stock-Key") + "」を登録しました。続けて登録しますか。", "続けて登録", CreateForm, MaintenanceMenu);
    });

    private Screen AmendStart() => Service.AnalysisUsable()
        ? KeyForm("在庫品目変更", "StockAmendKey", item => new FormScreen("在庫品目変更", ItemFields(item, false), "更新", v =>
            {
                string? err = ApplyItem(item, v);
                if (err == null) Service.Rewrite(item);
                return err != null ? Error("在庫品目変更", err, AmendStart, MaintenanceMenu) : AmendStart();
            }))
        : new InformationScreen(MaintenanceTitle, StockMessages.ST112);

    private Screen KeyForm(string title, string id, Func<Rec, Screen> next) => new FormScreen(title,
        [new TextField(id, "品目番号（空欄でメニューへ戻る）", "", 13)], "次へ", v =>
        {
            if (v.Text(id).Trim().Length == 0) return MaintenanceMenu();
            var item = Service.ReadKey(v.Text(id).Trim());
            return item == null ? Error(title, StockMessages.ST214, () => KeyForm(title, id, next), MaintenanceMenu) : next(item);
        });

    private Screen DeleteForm() => KeyForm("在庫品目削除", "StockDeleteKey", item =>
        new ConfirmationScreen("在庫品目削除", "品目「" + item.St("Stock-Key") + "　" + item.St("Stock-Desc") + "」を削除しますか。", "削除する", () =>
        {
            string? err = Service.Delete(item);
            return err != null ? Error("在庫品目削除", err, DeleteForm, MaintenanceMenu) : DeleteForm();
        }, DeleteForm));

    private Screen RenumberForm() => new FormScreen(MaintenanceTitle,
    [
        new TextField("StockRenumberKey", "現在の品目番号（空欄でメニューへ戻る）", "", 13),
        new TextField("StockRenumberNewKey", "新しい品目番号", "", 13),
        new TextField("StockRenumberNewAbrev", "新しい略号（空欄は変更なし）", "", 7),
    ], "付番変更", v =>
    {
        if (v.Text("StockRenumberKey").Trim().Length == 0) return MaintenanceMenu();
        var item = Service.ReadKey(v.Text("StockRenumberKey").Trim());
        string? err = item == null ? StockMessages.ST214 : null;
        err ??= Service.Renumber(item!, v.Text("StockRenumberNewKey"), v.Text("StockRenumberNewAbrev"));
        return err != null ? Error(MaintenanceTitle, err, RenumberForm, MaintenanceMenu) : RenumberForm();
    });

    private Screen DisplayList() => new TableScreen("在庫品目照会", "StockItemList",
        ["略号", "品目番号", "品名", "保管場所", "在庫数", "原価", "在庫金額", "発注残"],
        Service.Items().Select(r => new TableRow(
        [
            r.St("Stock-Abrev-Key"), r.St("Stock-Key"), r.St("Stock-Desc"), r.St("Stock-Location"),
            Fmt.E(r.N("Stock-Held"), "zzz,zz9-").Trim(), Fmt.E(r.N("Stock-Cost"), "zzzzzz9.9999").Trim(),
            Fmt.E(r.N("Stock-Value"), "zz,zzz,zz9.99").Trim(), Fmt.E(r.N("Stock-On-Order"), "zzz,zz9").Trim(),
        ], () => DetailForm(r.St("Stock-Key")))).ToList(), "登録されている在庫品目はありません。");

    private Screen DetailForm(string key)
    {
        var r = Service.ReadKey(key);
        if (r == null) return DisplayList();
        return new ReportScreen("在庫品目照会", string.Join(Environment.NewLine, new[]
        {
            "品目番号　" + r.St("Stock-Key"), "略号　" + r.St("Stock-Abrev-Key"), "品名　" + r.St("Stock-Desc"),
            "仕入先　" + string.Join("・", new[] { r.St("Stock-Supplier-P1"), r.St("Stock-Supplier-P2"), r.St("Stock-Supplier-P3") }.Where(x => x.Length > 0)),
            "保管場所　" + r.St("Stock-Location"), "売価　" + Fmt.E(r.N("Stock-Retail"), "zzzzzz9.99").Trim(),
            "原価　" + Fmt.E(r.N("Stock-Cost"), "zzzzzz9.9999").Trim(), "在庫数　" + r.N("Stock-Held"),
            "在庫金額　" + Fmt.E(r.N("Stock-Value"), "zz,zzz,zz9.99").Trim(), "発注点　" + r.N("Stock-ReOrder-Pnt"),
            "標準発注量　" + r.N("Stock-Std-ReOrder"), "発注残　" + r.N("Stock-On-Order"), "入荷待ち　" + r.N("Stock-Back-Ordered"),
            "当期入庫　" + r.N("Stock-Adds"), "当期出庫　" + r.N("Stock-Deducts"),
        }), DisplayList);
    }

    private Screen PrintStockFile()
    {
        var report = StockReports.StockFile(Service, Service.Items().ToList());
        LastReport = report;
        Service.Spool(report);
        return new InformationScreen(MaintenanceTitle, "在庫ファイル一覧表を出力しました。帳票一覧から確認できます。");
    }

    /// <summary>最後に出力した帳票（同一性検証で prt-1 と比較する）。</summary>
    public StockReport? LastReport { get; private set; }

    // ───────── st020 在庫入出庫 ─────────

    public Screen MovementsMenu() => new MenuScreen(MovementsTitle,
    [
        new("StockAdditions", "在庫の入庫入力", 1, Open: () => NumberForm(MovementKind.Addition, [])),
        new("StockDeductions", "在庫の出庫入力", 2, Open: () => NumberForm(MovementKind.Deduction, [])),
        new("StockBarcodeAdditions", "バーコードによる入庫入力", 3, Open: () => NumberForm(MovementKind.Barcode, [])),
        new("StockOrders", "発注情報の記録", 4, Open: () => OrderNumberForm([])),
        new("StockAuditReports", "月末監査帳票の出力", 5, Open: AuditReports),
        new("StockMovementsBack", "在庫管理メニューへ戻る", 9, Open: MainMenu),
    ]);

    private static string MovementTitle(MovementKind k) => k switch
    {
        MovementKind.Addition => "在庫入庫入力",
        MovementKind.Deduction => "在庫出庫入力",
        _ => "バーコード入庫入力",
    };

    private Screen NumberForm(MovementKind kind, List<MovementLine> lines)
    {
        string title = MovementTitle(kind);
        return new FormScreen(title,
            [new TextField("StockMovementNumber", kind == MovementKind.Barcode ? "品目番号（空欄で終了）" : "品目番号または略号（空欄で終了）", "", 13)], "次へ", v =>
            {
                string input = v.Text("StockMovementNumber");
                if (input.Trim().Length == 0) return FinishMovements(kind, lines);
                Rec? item;
                string? err;
                if (kind == MovementKind.Barcode) { item = Service.ReadKey(input.Trim()); err = item == null ? StockMessages.ST214 : null; }
                else item = Service.Find(input, out err);
                if (item == null) return Error(title, err!, () => NumberForm(kind, lines), () => FinishMovements(kind, lines));
                if (kind == MovementKind.Barcode) return Apply(kind, lines, Service.Barcode(item));
                return QuantityForm(kind, lines, item);
            });
    }

    private Screen QuantityForm(MovementKind kind, List<MovementLine> lines, Rec item)
    {
        string title = MovementTitle(kind);
        string info = item.St("Stock-Key") + "　" + item.St("Stock-Desc") + "（在庫数 " + Fmt.E(item.N("Stock-Held"), "zzz,zz9-").Trim()
            + "・在庫金額 " + Fmt.E(item.N("Stock-Value"), "zz,zzz,zz9.99").Trim() + "）";
        var fields = new List<Field> { new TextField("StockMovementQuantity", "数量（取消はマイナス記号を末尾に付加）\n" + info, "", 7) };
        if (kind == MovementKind.Addition) fields.Add(new TextField("StockMovementPrice", "単価", "", 10));
        return new FormScreen(title, fields, "確定", v =>
        {
            if (!StockService.TryQuantity(v.Text("StockMovementQuantity"), out var qty, out var reverse, out var err))
                return Error(title, err!, () => QuantityForm(kind, lines, item), () => NumberForm(kind, lines));
            if (qty == 0) return NumberForm(kind, lines);
            if (kind == MovementKind.Deduction) return Apply(kind, lines, Service.Deduction(item, qty, reverse));
            if (!StockService.TryAmount(v.Text("StockMovementPrice"), 2, out var price))
                return Error(title, StockMessages.InvalidAmount, () => QuantityForm(kind, lines, item), () => NumberForm(kind, lines));
            if (price == 0) return Error(title, StockMessages.PriceRequired, () => QuantityForm(kind, lines, item), () => NumberForm(kind, lines));
            return Apply(kind, lines, Service.Addition(item, qty, reverse, price));
        });
    }

    private Screen Apply(MovementKind kind, List<MovementLine> lines, MovementResult result)
    {
        string title = MovementTitle(kind);
        if (!result.Ok) return Error(title, result.Error!, () => NumberForm(kind, lines), () => FinishMovements(kind, lines));
        lines.Add(result.Line!);
        if (result.Warnings.Count > 0)
            return new ConfirmationScreen(title, string.Join(Environment.NewLine, result.Warnings), "続けて入力", () => NumberForm(kind, lines), () => FinishMovements(kind, lines));
        return NumberForm(kind, lines);
    }

    private Screen FinishMovements(MovementKind kind, List<MovementLine> lines)
    {
        var report = StockReports.Movements(Service, kind, lines);
        if (report != null) { LastReport = report; Service.Spool(report); }
        return MovementsMenu();
    }

    /// <summary>メニュー 4（発注情報）。レガシーは見出しに月末処理の題名を表示するため、同じ題名を使う。</summary>
    private const string OrderTitle = "在庫月末処理";

    private Screen OrderNumberForm(List<Rec> done) => new FormScreen(OrderTitle,
        [new TextField("StockOrderNumber", "品目番号または略号（空欄で終了）", "", 13)], "次へ", v =>
        {
            if (v.Text("StockOrderNumber").Trim().Length == 0) return FinishOrders(done);
            var item = Service.Find(v.Text("StockOrderNumber"), out var err);
            if (item != null && item.St("Stock-Services-Flag") == "Y") err = StockMessages.ST217;
            return err != null ? Error(OrderTitle, err, () => OrderNumberForm(done), () => FinishOrders(done)) : OrderForm(item!, done);
        });

    private Screen FinishOrders(List<Rec> done)
    {
        var report = StockReports.Orders(Service, done);
        if (report != null) { LastReport = report; Service.Spool(report); }
        return MovementsMenu();
    }

    private Screen OrderForm(Rec item, List<Rec> done)
    {
        DateTime? D(string f) => item.N(f) == 0 ? null : StockDates.FromBin(item.N(f));
        return new FormScreen(OrderTitle,
        [
            new TextField("StockOrderQuantity", "発注数量　" + item.St("Stock-Key") + "　" + item.St("Stock-Desc"), Fmt.E(item.N("Stock-On-Order"), "zzzzzz9").Trim(), 6),
            new DateField("StockOrderDate", "注文日", D("Stock-Order-Date")),
            new DateField("StockOrderDue", "納期", D("Stock-Order-Due")),
            new TextField("StockBackOrdered", "入荷待ち数量", Fmt.E(item.N("Stock-Back-Ordered"), "zzzzzz9").Trim(), 6),
        ], "記録", v =>
        {
            decimal back = 0;
            string? err = !StockService.TryQuantity(v.Text("StockOrderQuantity"), out var qty, out var n1, out var e1) || n1 ? e1 ?? StockMessages.ST207
                : !StockService.TryQuantity(v.Text("StockBackOrdered"), out back, out var n2, out var e2) || n2 ? e2 ?? StockMessages.ST207
                : null;
            err ??= Service.Order(item, qty, v.Date("StockOrderDate"), v.Date("StockOrderDue"), back);
            if (err != null) return Error(OrderTitle, err, () => OrderForm(item, done), () => OrderNumberForm(done));
            done.Add(item);
            return OrderNumberForm(done);
        });
    }

    private Screen AuditReports()
    {
        if (!Service.AuditUsed) return new InformationScreen(MovementsTitle, StockMessages.AuditNotUsed);
        var reports = StockReports.Audit(Service, Service.AuditRecords());
        foreach (var r in reports) Service.Spool(r);
        LastReport = reports[^1];
        Service.MarkAuditReported();
        return new ConfirmationScreen(MovementsTitle, "月末監査帳票（入庫監査表・出庫監査表）を出力しました。監査ファイルを削除しますか。", "削除する",
            () => { Service.DeleteAudit(); return MovementsMenu(); }, MovementsMenu);
    }

    // ───────── st030 在庫帳票 ─────────

    private static readonly string[] ReportNames = ["在庫評価表", "在庫受払表", "発注点割れ一覧表", "在庫履歴表", "在庫一覧表"];
    private static readonly string[] ReportIds = ["StockValuationReport", "StockActivityReport", "StockReorderReport", "StockHistoryReport", "StockListReport"];

    public Screen ReportsMenu() => new MenuScreen(ReportsTitle,
        Enumerable.Range(1, 5).Select(i => new MenuItem(ReportIds[i - 1], ReportNames[i - 1] + "の出力", i, Open: () => ReportForm(i)))
            .Append(new MenuItem("StockReportsBack", "在庫管理メニューへ戻る", 9, Open: MainMenu)).ToList());

    private Screen ReportForm(int kind)
    {
        string title = ReportNames[kind - 1];
        return new FormScreen(title,
        [
            new TextField("StockReportFromKey", "開始品目番号", "", 13), new TextField("StockReportToKey", "終了品目番号", "", 13),
            new TextField("StockReportFromAbrev", "開始略号", "", 7), new TextField("StockReportToAbrev", "終了略号", "", 7),
        ], "出力", v =>
        {
            string fk = v.Text("StockReportFromKey").Trim().ToUpperInvariant(), tk = v.Text("StockReportToKey").Trim().ToUpperInvariant();
            string fa = v.Text("StockReportFromAbrev").Trim().ToUpperInvariant(), ta = v.Text("StockReportToAbrev").Trim().ToUpperInvariant();
            string? err = null;
            bool byKey = fk.Length + tk.Length > 0, byAbrev = fa.Length + ta.Length > 0;
            if (byKey && byAbrev) err = StockMessages.ST304;
            else if (fk.Length > 0 && tk.Length > 0 && string.CompareOrdinal(fk, tk) > 0) err = StockMessages.ST307;
            else if (fa.Length > 0 && ta.Length > 0 && string.CompareOrdinal(fa, ta) > 0) err = StockMessages.ST308;
            if (err != null) return Error(title, err, () => ReportForm(kind), ReportsMenu);
            static bool In(string v, string from, string to) =>
                (from.Length == 0 || string.CompareOrdinal(v, from) >= 0) && (to.Length == 0 || string.CompareOrdinal(v, to) <= 0);
            var items = Service.Items().Where(r => byKey ? In(r.St("Stock-Key"), fk, tk) : !byAbrev || In(r.St("Stock-Abrev-Key"), fa, ta)).ToList();
            if (items.Count == 0) return Error(title, StockMessages.ST302, () => ReportForm(kind), ReportsMenu);
            var report = StockReports.Analysis(Service, kind, items);
            LastReport = report;
            Service.Spool(report);
            return new ReportScreen(title, report.Japanese, ReportsMenu);
        });
    }

    // ───────── st040 期間締め / st050 圧縮 ─────────

    private const string ResetTitle = "在庫期間締め";

    private Screen ActivityReset() => new FormScreen(ResetTitle,
        [YesNo("StockResetPeriod", "当期の入出庫合計を消去する"), YesNo("StockResetYear", "年間の入出庫履歴を消去する")], "実行", v =>
        {
            bool period = v.Choice("StockResetPeriod") == "Y", year = v.Choice("StockResetYear") == "Y";
            if (!period && !year) return MainMenu();
            if (!Service.ActivityReportRun) return new InformationScreen(ResetTitle, StockMessages.NotReported);
            return new ConfirmationScreen(ResetTitle, (period ? "当期の入出庫合計" : "") + (period && year ? "と" : "") + (year ? "年間の入出庫履歴" : "")
                + "を全品目で消去します。よろしいですか。", "消去する", () =>
                {
                    int n = Service.ResetActivity(period, year);
                    return new InformationScreen(ResetTitle, n + " 件の在庫品目を締めました。");
                }, MainMenu);
        });

    private const string CompressionTitle = "在庫ファイル圧縮";

    private Screen Compression() => new ConfirmationScreen(CompressionTitle,
        "在庫ファイルを再構築し、在庫金額を在庫数×原価で再計算します。事前にバックアップを取得してください。実行しますか。", "圧縮する", () =>
        {
            int n = Service.Compress();
            return new InformationScreen(CompressionTitle, n + " 件の在庫品目で在庫ファイルを再構築しました。");
        }, MainMenu);
}
