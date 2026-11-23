using System.Globalization;
using Acas.Core;

namespace Acas.App;

internal sealed partial class AccountingScreens
{
    private Screen JournalProofMenu() => new MenuScreen("仕訳の検証・修正",
    [
        new("EditJournalBatch", "既存バッチの修正", 1, Open: () => FindJournalBatch(false)),
        new("ProofAllBatches", "全バッチ検証帳票", 2,
            Open: () => new ConfirmationScreen("全バッチの検証", "現在の会計期間のバッチを検証しますか。", "検証する",
                () => JournalReport("全バッチ検証帳票", _batches.Proof(null), JournalProofMenu), JournalProofMenu)),
        new("ProofOneBatch", "指定バッチ検証帳票", 3, Open: () => FindJournalBatch(true)),
        new("PrintTransactions", "全仕訳の印刷", 4,
            Open: () => JournalReport("全仕訳一覧", _batches.PrintTransactions(), JournalProofMenu)),
        new("JournalProofBack", "総勘定元帳に戻る", 9, Open: GeneralMenu)
    ]);

    private Screen FindJournalBatch(bool proof, string? entered = null, string? error = null) => new FormScreen(
        proof ? "指定バッチの検証" : "修正するバッチを指定",
        [new TextField("JournalBatchNumber", "バッチ番号", entered ?? "", 5)], proof ? "検証する" : "開く", values =>
        {
            var text = values.Text("JournalBatchNumber");
            if (!Number(text, out int number) || number == 0 || _batches.Find(number) is not { } batch)
                return FindJournalBatch(proof, text, "登録されているバッチ番号を指定してください。");
            return proof ? JournalReport("指定バッチ検証帳票", _batches.Proof(number), JournalProofMenu) : BatchEditMenu(batch);
        }, JournalProofMenu, error);

    private Screen BatchEditMenu(LedgerBatch batch) => new MenuScreen($"バッチの修正　{batch.Number:00000}",
    [
        new("EditBatchHeader", "バッチ情報の修正", Open: () => BatchHeaderEditForm(batch)),
        new("EditBatchEntries", "仕訳明細の修正", Open: () => BatchEntries(batch)),
        new("EditBatchBack", "バッチの指定に戻る", Open: () => FindJournalBatch(false))
    ]);

    private Screen BatchHeaderEditForm(LedgerBatch batch, string? error = null)
    {
        var fields = new List<Field>
        {
            new TextField("BatchEditCycle", "会計期間", batch.Cycle.ToString("00"), 2),
            new TextField("BatchEditItems", "照合用件数", batch.Items.ToString("00"), 2),
            new TextField("BatchEditGross", "照合用総額", batch.InputGross.ToString("0.00", CultureInfo.InvariantCulture), 12)
        };
        bool vat = _settings.Read()?.S("Vat") == "Y";
        if (vat) fields.Add(new TextField("BatchEditTax", "照合用税額", batch.InputTax.ToString("0.00", CultureInfo.InvariantCulture), 12));
        fields.Add(new TextField("BatchEditDescription", "摘要", batch.Description, 24));
        return new FormScreen($"バッチ情報の修正　{batch.Number:00000}", fields, "保存", values =>
        {
            decimal tax = batch.InputTax;
            if (!Number(values.Text("BatchEditCycle"), out var cycle) || !Number(values.Text("BatchEditItems"), out var items) ||
                !JournalAmount(values.Text("BatchEditGross"), out var gross) ||
                (vat && !JournalAmount(values.Text("BatchEditTax"), out tax)))
                return BatchHeaderEditForm(batch, JournalMessage(JournalError.Header));
            string description = values.Text("BatchEditDescription");
            var result = _batches.Amend(batch.Number, cycle, items, gross, tax, description);
            if (result == JournalError.None) return BatchEditMenu(_batches.Find(batch.Number)!);
            return BatchHeaderEditForm(batch with { Cycle = cycle, Items = items, InputGross = gross, InputTax = tax, Description = description },
                JournalMessage(result));
        }, () => BatchEditMenu(batch), error);
    }

    private Screen BatchEntries(LedgerBatch batch) => new TableScreen(
        $"修正する仕訳明細　{batch.Number:00000}", "BatchPostingList", ["番号", "日付", "入力科目", "部門", "税抜額", "税額", "摘要"],
        _batches.Entries(batch.Number).Select(p => new Acas.Core.TableRow(
            [p.Number.ToString(), p.Date, p.Account.Number, p.Account.Division.ToString("00"), p.Amount.ToString("N2"), p.Tax.ToString("N2"), p.Description],
            () => BatchEntryEditForm(batch, p))).ToArray(), Back: () => BatchEditMenu(batch));

    private Screen BatchEntryEditForm(LedgerBatch batch, BatchPosting entry, string? error = null)
    {
        var system = _settings.Read();
        bool divisions = system?.S("P-C") is "P" or "B", autoVat = system?.S("Vat") == "Y";
        var fields = new List<Field>
        {
            new DateField("BatchPostingDate", $"日付（現在の値：{entry.Date}、空欄なら変更なし）"),
            new TextField("BatchPostingAccount", "入力科目の勘定コード", $"{entry.Account.Ledger:0000}.{entry.Account.Sub:00}", 7)
        };
        if (divisions) fields.Add(new TextField("BatchPostingDivision", "部門コード", entry.Account.Division.ToString("00"), 2));
        fields.Add(new TextField("BatchPostingAmount", "金額", entry.Amount.ToString("0.00", CultureInfo.InvariantCulture), 12));
        if (autoVat)
        {
            fields.Add(new ChoiceField("BatchPostingRate", "税率", Enumerable.Range(1, 3)
                .Select(i => new Choice(i.ToString(), $"税率 {i}　{system?.N("Vat-Rate-" + i):0.00}％")).ToArray(), "1"));
            fields.Add(new ChoiceField("BatchPostingCalculation", "税額の計算方法", TaxCalculations, ""));
        }
        fields.Add(new TextField("BatchPostingTax", "税額（自動計算する場合は空欄）", entry.Tax.ToString("0.00", CultureInfo.InvariantCulture), 12));
        fields.Add(new TextField("BatchPostingDescription", "摘要", entry.Description, 32));
        return new FormScreen($"仕訳明細の修正　{entry.Number:00}", fields, "保存", values =>
        {
            int division = 0, rate = 1;
            decimal? tax = null;
            var taxText = values.Text("BatchPostingTax");
            if (taxText.Length > 0 && SignedPostingAmount(taxText, out var parsedTax)) tax = parsedTax;
            if ((taxText.Length != 0 && tax == null) ||
                !JournalAmount(values.Text("BatchPostingAccount"), out var account) || account is < 1000 or >= 9999 ||
                (divisions && !Number(values.Text("BatchPostingDivision"), out division)) ||
                (autoVat && !Number(values.Choice("BatchPostingRate"), out rate)) ||
                !SignedPostingAmount(values.Text("BatchPostingAmount"), out var amount))
                return BatchEntryEditForm(batch, entry, JournalMessage(JournalError.Line));
            var accountCode = new AccountCode((int)account, (int)(account * 100) % 100, division);
            var result = _batches.AmendEntry(batch.Number, entry, values.Date("BatchPostingDate"), accountCode,
                amount, tax, rate, autoVat ? values.Choice("BatchPostingCalculation") ?? "" : "", values.Text("BatchPostingDescription"));
            return result == JournalError.None ? BatchEntries(batch) : BatchEntryEditForm(batch, entry, JournalMessage(result));
        }, () => BatchEntries(batch), error);
    }

    private Screen BatchStatusMenu() => new MenuScreen("バッチ状況帳票",
    [
        new("DisplayBatchStatus", "バッチ状況表示", 1, Open: DisplayBatchStatus),
        new("PrintBatchStatus", "バッチ状況を印刷", 2,
            Open: () => JournalReport("バッチ状況帳票", _batches.PrintStatus(), BatchStatusMenu)),
        new("BatchStatusBack", "総勘定元帳に戻る", 9, Open: GeneralMenu)
    ]);

    private Screen DisplayBatchStatus() => new TableScreen("バッチ状況", "BatchStatusList",
        ["台帳", "バッチ", "状態", "最終処理日", "件数", "照合用総額", "照合用税額", "実績総額", "実績税額"],
        _batches.Current().Select(b => new Acas.Core.TableRow(
            [JournalBatches.LedgerName(b.Ledger), b.Number.ToString("00000"), JournalBatches.StatusName(b),
                b.Activity?.ToString("yyyy年M月d日") ?? "", b.Items.ToString(), b.InputGross.ToString("N2"), b.InputTax.ToString("N2"),
                b.ActualGross.ToString("N2"), b.ActualTax.ToString("N2")],
            SortValues: [b.Ledger, b.Number, b.Status, b.Activity ?? DateTime.MinValue, b.Items, b.InputGross, b.InputTax, b.ActualGross, b.ActualTax])).ToArray(),
        Back: BatchStatusMenu);

    private Screen JournalPostMenu() => new MenuScreen("仕訳転記",
    [
        new("JournalPostConfirm", "仕訳を転記する", Open: JournalPostConfirmation)
    ]);

    private Screen JournalPostConfirmation() => new ConfirmationScreen("仕訳転記",
        "現在の会計期間の照合済みバッチを総勘定元帳へ転記しますか。", "転記する", PostJournal, JournalPostMenu);

    private Screen PostJournal()
    {
        var result = _batches.Post();
        return result.Status switch
        {
            PostingStatus.Posted => JournalReport("仕訳転記帳票", result.Report, GeneralMenu),
            PostingStatus.OpenBatches => DisplayBatchStatus(),
            PostingStatus.MissingFiles => new InformationScreen("仕訳転記", "バッチが作成されていません。"),
            PostingStatus.MissingAccount => new InformationScreen("仕訳転記", "仕訳に指定された勘定科目が見つかりません。転記は行われませんでした。"),
            _ => new InformationScreen("仕訳転記", "転記待ちの仕訳はありません。")
        };
    }

    private Screen JournalCloseMenu() => new MenuScreen("会計期間の締め",
    [
        new("JournalCloseBackup", "締め処理を開始", Open: () => new ConfirmationScreen("会計期間の締め",
            "実行前にデータをバックアップしてください。対象期間の仕訳は削除または保管されます。締め処理を続行しますか。",
            "締め処理を続行", ConfirmJournalClose, JournalCloseMenu)),
        new("JournalCloseBack", "総勘定元帳へ戻る", Open: GeneralMenu)
    ]);

    private Screen ConfirmJournalClose() => _settings.Read()?.S("Arch") == "Y"
        ? new ConfirmationScreen("仕訳の保管", "対象期間の仕訳をデータベース内の保管領域へ移しますか。",
            "保管する", CloseJournal, JournalCloseMenu)
        : CloseJournal();

    private Screen CloseJournal() => _batches.CloseCycle() switch
    {
        ClosingStatus.OpenBatches => new InformationScreen("会計期間の締め", "未照合のバッチがあるため、締め処理は行われませんでした。"),
        ClosingStatus.MissingFiles => new InformationScreen("会計期間の締め", "締め処理に必要なバッチまたは仕訳がありません。"),
        _ => new InformationScreen("会計期間の締めを中断",
            "仕訳レコードと作業レコードの長さが異なるため、圧縮前に中断しました。既に行われた仕訳の削除・保管とバッチの更新は保持され、会計期間は変更されません。")
    };

    private static Screen JournalReport(string title, string? body, Func<Screen> back) => body == null
        ? new InformationScreen(title, "対象のバッチや仕訳がありません。") : new ReportScreen(title, body, back, "戻る");

    private static bool SignedPostingAmount(string text, out decimal amount) =>
        decimal.TryParse(text, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out amount);
}
