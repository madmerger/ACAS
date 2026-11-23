using System.Globalization;
using System.Text;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Purchase;

namespace Acas.App.Subsystems.Purchase;

internal sealed partial class PurchaseScreens
{
    private static readonly Choice[] SupplierStatus = [new("", "すべて"), new("1", "有効"), new("0", "休止")];
    private static readonly Choice[] Comparisons = [new("", "指定なし"), new("<", "未満"), new("=", "等しい"), new(">", "超過")];

    private Screen SupplierReport(string title, bool alphabetical = false, bool turnover = false)
    {
        return new FormScreen(title,
        [
            new ChoiceField("PurchaseSupplierReportStatus", "仕入先の状態", SupplierStatus, ""),
            new TextField("PurchaseSupplierReportCode", "仕入先コードの先頭", MaxLength: turnover ? 6 : 7),
            new TextField("PurchaseSupplierReportCredit", "支払猶予日数", MaxLength: 2),
            new ChoiceField("PurchaseSupplierReportCreditOperator", "支払猶予日数の比較", Comparisons, ""),
            new TextField("PurchaseSupplierReportActivity", turnover ? "請求件数" : "最終取引からの日数", MaxLength: 5),
            new ChoiceField("PurchaseSupplierReportActivityOperator", turnover ? "請求件数の比較" : "最終取引からの日数の比較", Comparisons, ""),
            new TextField("PurchaseSupplierReportAverage", "平均請求額", MaxLength: 5),
            new ChoiceField("PurchaseSupplierReportAverageOperator", "平均請求額の比較", Comparisons, ""),
            new TextField("PurchaseSupplierReportOverdue", "支払遅延日数", MaxLength: 5),
            new ChoiceField("PurchaseSupplierReportOverdueOperator", "支払遅延日数の比較", Comparisons, ""),
            new DateField("PurchaseSupplierReportCreated", "登録日"),
            new ChoiceField("PurchaseSupplierReportCreatedOperator", "登録日の比較", Comparisons, "")
        ], "帳票を作成", values =>
        {
            string? status = values.Choice("PurchaseSupplierReportStatus");
            string code = values.Text("PurchaseSupplierReportCode").Trim().ToUpperInvariant();
            string[] filters = ["Credit", "Activity", "Average", "Overdue"];
            var criteria = new Dictionary<string, (string? Operator, int Value)>();
            foreach (string filter in filters)
            {
                string? operation = values.Choice("PurchaseSupplierReport" + filter + "Operator");
                int number = 0;
                if (!string.IsNullOrEmpty(operation) && !int.TryParse(values.Text("PurchaseSupplierReport" + filter),
                    NumberStyles.None, CultureInfo.InvariantCulture, out number))
                    return Notice(title, "比較対象の数値を入力してください。");
                criteria.Add(filter, (operation, number));
            }
            var created = values.Date("PurchaseSupplierReportCreated");
            string? createdOperator = values.Choice("PurchaseSupplierReportCreatedOperator");
            if (!string.IsNullOrEmpty(createdOperator) && !created.HasValue) return Notice(title, "登録日を入力してください。");
            int runDate = _ledger.System().I("Run-Date");
            var records = _ledger.Suppliers().Where(record =>
                (string.IsNullOrEmpty(status) || status == record.S("status")) && record.St("key").StartsWith(code, StringComparison.Ordinal) &&
                Matches(record.I("credit"), criteria["Credit"]) &&
                Matches(turnover ? record.I("activity") : runDate - record.I("lastInvoice"), criteria["Activity"]) &&
                Matches(record.I("average"), criteria["Average"]) &&
                (turnover ? record.N("current") <= 0 || Matches(runDate - record.I("lastInvoice"), criteria["Overdue"])
                    : Matches(runDate - record.I("lastInvoice") - record.I("credit"), criteria["Overdue"])) &&
                Matches(record.I("created"), (createdOperator, created.HasValue ? PurchaseLedger.EncodeDate(created.Value) : 0)));
            if (alphabetical) records = records.OrderBy(record => record.St("name"), StringComparer.Ordinal);
            if (turnover) return SupplierTurnoverReport(title, records);
            var report = ReportHeading(title).AppendLine("仕入先コード　仕入先名　状態　支払猶予日数　現在残高　未消込残高");
            foreach (var record in records)
                report.AppendLine($"{record.St("key")}　{record.St("name")}　{(record.I("status") == 1 ? "有効" : "休止")}　{record.I("credit")}　{Money(record.N("current"))}　{Money(record.N("unapplied"))}");
            return _ledger.Report(title, report.ToString());
        });
    }

    private ReportScreen SupplierTurnoverReport(string title, IEnumerable<Rec> records)
    {
        int pageLines = _ledger.System().I("Page-Lines");
        int page = 1, line = 6;
        var body = new StringBuilder();
        AddHeading();
        foreach (var row in records)
        {
            body.AppendLine($"{row.St("key")}　{row.St("name")}")
                .AppendLine($"猶予日数 {Whole(row.N("credit"))}　与信限度 {Whole(row.N("limit"))}　請求件数 {Whole(row.N("activity"))}　平均額 {Whole(row.N("average"))}")
                .AppendLine($"四半期別取引額　１ {Whole(row.N("q1"))}　２ {Whole(row.N("q2"))}　３ {Whole(row.N("q3"))}　４ {Whole(row.N("q4"))}")
                .AppendLine($"現在残高 {Whole(row.N("current") - row.N("unapplied"))}　前回残高 {Whole(row.N("last"))}")
                .AppendLine($"最終仕入日 {DateText(PurchaseLedger.DecodeDate(row.I("lastInvoice")))}　最終支払日 {DateText(PurchaseLedger.DecodeDate(row.I("lastPayment")))}")
                .AppendLine();
            if (++line > pageLines)
            {
                body.Append('\f');
                page++;
                line = 6;
                AddHeading();
            }
        }
        return _ledger.Report(title, body.ToString());

        void AddHeading() => body.Append(ReportHeading(title)).Append("ページ ").AppendLine(page.ToString(CultureInfo.InvariantCulture)).AppendLine();

        static string Whole(decimal value) => decimal.Truncate(value).ToString(CultureInfo.InvariantCulture);
    }

    private static bool Matches(int actual, (string? Operator, int Value) compare) => compare.Operator switch
    {
        "<" => actual < compare.Value,
        "=" => actual == compare.Value,
        ">" => actual > compare.Value,
        _ => true
    };

    private StringBuilder ReportHeading(string title) => new StringBuilder().AppendLine(title)
        .AppendLine(_ledger.System().St("Usera")).Append("処理日　").AppendLine(DateText(_ledger.ProcessingDate)).AppendLine();

    private Screen Inquiry()
    {
        const string title = "買掛残高・明細照会";
        if (!OpenItemsAvailable()) return Notice(title, "未決済明細ファイルがありません。");
        return new TableScreen(title, "PurchaseBalances", ["仕入先コード", "仕入先名", "現在残高", "未消込残高"],
            _ledger.Suppliers().Select(row => new TableRow([row.St("key"), row.St("name"), Money(row.N("current")), Money(row.N("unapplied"))],
                () => ShowSupplier(title, row, "", ""), [row.St("key"), row.St("name"), row.N("current"), row.N("unapplied")])).ToArray());
    }

    private bool OpenItemsAvailable() => _ledger.System().I("File-Status-29") == 1;

    private Screen AnalysisMenu() => new MenuScreen("仕入分析コード管理", AnalysisItems());

    private MenuItem[] AnalysisItems() =>
    [
        Item("M1", 1, "仕入分析コード登録", () => AnalysisForm("仕入分析コード登録", true)),
        Item("M2", 2, "仕入分析コード変更・削除", () => AnalysisForm("仕入分析コード変更・削除", false)),
        Item("M3", 3, "仕入分析コード印刷", () => PrintAnalysis(false)),
        Item("M4", 4, "仕入分析コード全件印刷", () => PrintAnalysis(true)),
        Item("M5", 5, "仕入分析コード表示", ShowAnalysis),
        Item("M9", 9, "買掛メニューに戻る", MainMenu)
    ];

    private Screen AnalysisForm(string title, bool create) => new FormScreen(title,
        [new TextField("PurchaseAnalysisCode", "分析コード", MaxLength: 2)], "開く", values =>
        {
            string code = values.Text("PurchaseAnalysisCode");
            if (string.IsNullOrWhiteSpace(code) || !PurchaseLedger.FitsRecord(code, 2)) return Notice(title, "分析コードを確認してください。");
            if (_ledger.HasInvalidAnalysisLength) return AnalysisFileError(title);
            var existing = _ledger.Analysis(code);
            if (create && existing != null) return Notice(title, "その分析コードはすでに登録されています。");
            if (!create && existing is null) return Notice(title, "分析コードが見つかりません。");
            var record = existing ?? _ledger.NewAnalysis(code);
            return new FormScreen(title,
            [
                new TextField("PurchaseAnalysisAccount", "総勘定元帳の勘定コード", record.S("account"), 6),
                new TextField("PurchaseAnalysisDescription", "摘要", record.St("description"), 24),
                new TextField("PurchaseAnalysisReference", "帳票参照コード", record.St("reference"), 3),
                new ChoiceField("PurchaseAnalysisAction", "処理", create ? [new("save", "保存")] : [new("save", "保存"), new("delete", "削除")], "save")
            ], "確認", details =>
            {
                if (details.Choice("PurchaseAnalysisAction") == "delete")
                    return new ConfirmationScreen(title, "分析コードを削除しますか。", "削除",
                        () => Notice(title, _ledger.DeleteAnalysis(record) ? "分析コードを削除しました。" : "分析コードを削除できませんでした。"), AnalysisMenu);
                string account = details.Text("PurchaseAnalysisAccount");
                string description = details.Text("PurchaseAnalysisDescription");
                string reference = details.Text("PurchaseAnalysisReference");
                if (!int.TryParse(account, NumberStyles.None, CultureInfo.InvariantCulture, out int number) ||
                    number > 999999 || !PurchaseLedger.FitsRecord(description, 24) || !PurchaseLedger.FitsRecord(reference, 3))
                    return Notice(title, "勘定コード、摘要、帳票参照コードを確認してください。");
                record.SetN("account", number);
                record.Set("description", description);
                record.Set("reference", reference);
                return new ConfirmationScreen(title, "分析コードを保存しますか。", "保存",
                    () => Notice(title, _ledger.SaveAnalysis(record, create) ? "分析コードを保存しました。" : "分析コードを保存できませんでした。"), AnalysisMenu);
            });
        });

    private static Screen AnalysisFileError(string title) => Notice(title, "分析ファイルのレコード長が定義と一致しません。");

    private Screen ShowAnalysis()
    {
        const string title = "仕入分析コード表示";
        return new TableScreen(title, "PurchaseAnalysisList", ["分析コード", "勘定コード", "摘要", "帳票参照コード"],
            _ledger.AnalysisRecords(false).Select(row => new TableRow([row.St("code"), row.S("account"), row.St("description"), row.St("reference")])).ToArray());
    }

    private Screen PrintAnalysis(bool all)
    {
        string title = all ? "仕入分析コード全件印刷" : "仕入分析コード印刷";
        return new ConfirmationScreen(title, "分析コードの帳票を作成しますか。", "作成", () =>
        {
            var body = new StringBuilder();
            int line = 5, page = 1;
            bool missingAccount = false;
            bool irs = _ledger.System().S("Irs-Instead") == "Y";
            AddHeading();
            foreach (var row in _ledger.AnalysisRecords(all))
            {
                bool group = row.S("code")[1] == ' ' && row.I("account") == 0;
                if (group)
                {
                    body.AppendLine();
                    if (++line > 70) NewPage();
                }
                else if (row.S("code")[1] != ' ' && row.I("account") == 0)
                    missingAccount = true;
                string ledger = all ? (group ? row.S("system") : "") + "　" : "";
                int account = irs ? row.I("account") : row.I("account") / 100;
                body.AppendLine($"{ledger}{row.St("code")}　{account:000000}　{row.St("description")}　{row.St("reference")}　{(group ? "グループ" : "明細")}");
                if (++line > 70) NewPage();
            }
            if (missingAccount) body.AppendLine("勘定コードにゼロが含まれています。");
            return _ledger.Report(title, body.ToString());

            void NewPage()
            {
                body.Append('\f');
                page++;
                line = 5;
                AddHeading();
            }

            void AddHeading() => body.Append(ReportHeading(title)).Append("ページ ").AppendLine(page.ToString(CultureInfo.InvariantCulture))
                .Append(all ? "元帳　" : "").AppendLine("分析コード　勘定コード　摘要　帳票参照コード　区分");
        }, AnalysisMenu);
    }

    private Screen AnalysisReport() => !_ledger.AnalysisValuesAvailable
        ? Notice("仕入分析帳票", "集計データがありません。") : Unsupported("仕入分析帳票");

    private Screen AgedCreditors() => !OpenItemsAvailable()
        ? Notice("買掛金年齢表", "未決済明細ファイルがありません。") : Unsupported("買掛金年齢表");

    private Screen ClosePeriod() => new FormScreen("買掛・売掛の期間締め",
        [new DateField("PurchaseClosingDate", "締め日", _ledger.ProcessingDate)], "確認", values =>
        {
            if (values.Date("PurchaseClosingDate") is null) return Notice("買掛・売掛の期間締め", "締め日を入力してください。");
            return new ConfirmationScreen("買掛・売掛の期間締め", "締め日は期間末日ですか。すべてのデータをバックアップしましたか。", "続行",
                () => Unsupported("買掛・売掛の期間締め"), MainMenu);
        });

    private MenuScreen ChequeMenu() => new("小切手・送金", ChequeItems());

    private MenuItem[] ChequeItems() =>
    [
        Item("S1", 1, "支払予定生成", ChequeDue),
        Item("S2", 2, "支払予定修正", ChequeAmend),
        Item("S3", 3, "支払予定の検証", ScheduledPaymentProof),
        Item("S4", 4, "小切手データ生成", () => !_ledger.PaymentDataAvailable
            ? Notice("小切手データ生成", "処理するデータがありません。") : Unsupported("小切手データ生成")),
        Item("S5", 5, "小切手・銀行振込台帳印刷", () => new FormScreen("小切手・銀行振込台帳印刷", [], "確認", _ =>
            new ConfirmationScreen("小切手・銀行振込台帳印刷", "未決済明細を更新します。続行しますか。", "続行",
                () => Unsupported("小切手・銀行振込台帳印刷"), ChequeMenu))),
        Item("S6", 6, "送金案内印刷", () => !_ledger.PaymentDataAvailable ? ChequeMenu() : Unsupported("送金案内印刷")),
        Item("S9", 9, "買掛メニューに戻る", MainMenu)
    ];

    private Screen ChequeDue() => new FormScreen("支払予定生成",
        [new TextField("PurchaseChequeAge", "支払対象の経過日数", _ledger.System().I("Age-To-Pay").ToString("00"), 2)],
        "確認", _ => Notice("支払予定生成", !OpenItemsAvailable() ? "未決済明細ファイルがありません。" : "この処理は移植されていません。"));

    private static Screen ChequeAmend() => new FormScreen("支払予定修正",
        [new TextField("PurchaseChequeSupplier", "仕入先コード", MaxLength: 7),
            new TextField("PurchaseChequeNumber", "支払予定番号", MaxLength: 2)], "照会", _ => Unsupported("支払予定修正"));

    private Screen ScheduledPaymentProof()
    {
        const string title = "支払予定の検証";
        if (_ledger.ScheduledPayments() is not { } payments)
            return Notice(title, "支払予定ファイルのレコード長が定義と一致しません。");
        int pageSize = Math.Max(6, _ledger.System().I("Page-Lines"));
        int page = 1, line = 5;
        decimal[] totals = new decimal[4];
        decimal total = 0;
        var report = new StringBuilder();
        AddHeading();
        for (int i = 0; i < payments.Count; i++)
        {
            var payment = payments[i];
            decimal balance = 0;
            bool first = true;
            do
            {
                foreach (var item in payment.Lines)
                {
                    if (first)
                    {
                        report.AppendLine($"{payment.Supplier}/{payment.Number:00}　{_ledger.GetSupplier(payment.Supplier)?.St("name") ?? "仕入先不明"}");
                        first = false;
                    }
                    balance += item.Amount;
                    decimal[] ages = new decimal[4];
                    if (item.Period is 0 or 30 or 60 or 90)
                        totals[item.Period / 30] += ages[item.Period / 30] = item.Amount;
                    report.AppendLine($"{item.Folio}　{(payment.BankTransfer ? "振込" : "小切手")}　{DateText(payment.Date)}　{item.Reference}");
                    report.AppendLine($"当期 {Money(ages[0])}　30日以上 {Money(ages[1])}　60日以上 {Money(ages[2])}　90日以上 {Money(ages[3])}　支払額 {Money(balance)}");
                    if (++line > pageSize)
                    {
                        report.Append('\f');
                        page++;
                        line = 5;
                        AddHeading();
                    }
                }
                if (!payment.Continues || i + 1 == payments.Count || payments[i + 1].Supplier != payment.Supplier) break;
                payment = payments[++i];
            } while (true);
            total += balance;
        }
        report.AppendLine($"合計　当期 {Money(totals[0])}　30日以上 {Money(totals[1])}　60日以上 {Money(totals[2])}　90日以上 {Money(totals[3])}　支払額 {Money(total)}");
        return _ledger.Report(title, report.ToString(), ChequeMenu);

        void AddHeading() => report.Append(ReportHeading(title)).Append("ページ ").AppendLine(page.ToString(CultureInfo.InvariantCulture))
            .AppendLine("伝票番号　支払方法　支払日　請求書番号").AppendLine("当期　30日以上　60日以上　90日以上　支払額");
    }

    private static Screen Unsupported(string title) => Notice(title, "この処理は移植されていません。");
}
