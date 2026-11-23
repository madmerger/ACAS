using System.Globalization;
using System.IO;
using Acas.Core;
using Acas.Core.Programs.Irs;
using Microsoft.Win32;

namespace Acas.App.Subsystems.Irs;

public sealed partial class IrsScreens
{
    private Screen PostingMenu(IrsBookkeeping books) => Form("仕訳転記",
        [new ChoiceField("IrsPostingMode", "処理方法",
            [new("99", "99　既定勘定の表示"), new("88", "88　仕訳の追加"),
             new("77", "77　既存転記の消去"), new("66", "66　売掛・買掛の連携仕訳を取り込む")])],
        "次へ", v => v.Choice("IrsPostingMode") switch
        {
            "99" => DefaultsList(books, false),
            "88" => SelectPostingDefault(books),
            "77" => Form("既存転記の消去", [new PasswordField("IrsResetPostingPassword", "暗証番号", 4)],
                "認証", values =>
                {
                    string password = values.Text("IrsResetPostingPassword");
                    if (!books.CheckPassword(password)) throw new IrsException("暗証番号が一致しません。");
                    return new ConfirmationScreen("既存転記の消去", "既存の仕訳と当期残高を消去します。バックアップを確認してください。",
                        "消去", () => Guard("既存転記の消去", () =>
                        {
                            books.ResetPostings(password);
                            return SelectPostingDefault(books);
                        }), () => PostingMenu(books));
                }),
            "66" => new ConfirmationScreen("連携仕訳の取り込み", "連携元で確定した仕訳を取り込みますか。",
                "取り込む", () => Guard("連携仕訳の取り込み", () =>
                {
                    int count = books.ImportPostings(clear: true,
                        shared: IrsBookkeeping.UsesSharedTransferDirectory(Environment.GetEnvironmentVariable("ACAS_IRS")));
                    return new InformationScreen("連携仕訳の取り込み", $"{count}件の仕訳を取り込みました。");
                }), () => PostingMenu(books)),
            _ => PostingMenu(books)
        });

    private FormScreen SelectPostingDefault(IrsBookkeeping books)
    {
        var defaults = books.Defaults().Where(d => d.Account != 0).ToArray();
        return Form("既定勘定の選択", [new ChoiceField("IrsPostingDefault", "既定勘定",
            defaults.Select(d => new Choice(Code(d.Slot, 2), $"{Code(d.Slot, 2)}　{Code(d.Account)}　{d.Name}")).ToArray())],
            "次へ", v =>
            {
                var choice = defaults.FirstOrDefault(d => Code(d.Slot, 2) == v.Choice("IrsPostingDefault"))
                    ?? throw new IrsException("既定勘定を選択してください。");
                return new ConfirmationScreen("既定勘定の確認", $"{Code(choice.Account)}　{choice.Name} を使用しますか。",
                    "使用する", () => PostingEntry(books, choice), () => SelectPostingDefault(books));
            });
    }

    private FormScreen PostingEntry(IrsBookkeeping books, IrsDefault selected) => Form("仕訳入力",
        [new ChoiceField("IrsPostingSide", "相手勘定の借方・貸方", [new("DR", "借方"), new("CR", "貸方")], "DR"),
         new DateField("IrsPostingDate", "転記日", books.Configuration().Date),
         Text("IrsPostingAccount", "相手勘定コード", "", 5),
         Text("IrsPostingLegend", "摘要", "", 32),
         Text("IrsPostingAmount", "税抜金額", "", 11),
         Text("IrsPostingTax", "付加価値税額（空欄なら自動計算）", "", 11)],
        "転記", v =>
        {
            string tax = v.Text("IrsPostingTax").Trim();
            var item = books.Post(selected.Slot, v.Choice("IrsPostingSide") == "DR",
                Date(v, "IrsPostingDate"), Number(v.Text("IrsPostingAccount"), 99999),
                Amount(v.Text("IrsPostingAmount")), v.Text("IrsPostingLegend"), tax == "" ? null : Amount(tax));
            return new MenuScreen("仕訳転記",
                [new("IrsPostingContinue", "同じ既定勘定で続ける", Open: () => PostingEntry(books, selected)),
                 new("IrsPostingJournal", $"転記 {Code(item.Number)} の確認", Open: () => JournalTable(books.Journal(), "転記一覧", "IrsPostingGrid")),
                 new("IrsPostingFinish", "処理方法へ戻る", Open: () => PostingMenu(books))]);
        });

    private Screen TrialBalance(IrsBookkeeping books) => Form("試算表",
        [new ChoiceField("IrsTrialBalanceLevel", "集計方法", [new("S", "要約"), new("D", "明細")], "S"),
         new ChoiceField("IrsTrialBalanceZeros", "残高がゼロの勘定を含める", YesNo, "N")],
        "帳票を作成", v => Report(books, books.TrialBalance(v.Choice("IrsTrialBalanceLevel") == "D",
            v.Choice("IrsTrialBalanceZeros") == "Y"), () => TrialBalance(books)));

    private Screen Audit(IrsBookkeeping books) => Form("監査証跡",
        [new ChoiceField("IrsAuditType", "帳票の種類", [new("A", "監査報告"), new("L", "元帳明細"), new("D", "付加価値税日計帳")], "A"),
         new ChoiceField("IrsAuditOrder", "表示順", [new("1", "取引区分順"), new("2", "日付順"), new("3", "伝票番号順")], "3")],
        "帳票を作成", v => Report(books, books.AuditReport(v.Choice("IrsAuditType") ?? "A",
            v.Choice("IrsAuditOrder") ?? "3"), () => Audit(books)));

    private Screen FinalAccounts(IrsBookkeeping books) => Form("決算書作成",
        [new ChoiceField("IrsFinalComparison", "比較対象", Enumerable.Range(0, 5).Select(i =>
            new Choice(Code(i, 1), i == 0 ? "比較なし" : $"{i}期前")).ToArray(), "0")], "帳票を作成",
        v => Report(books, books.FinalAccounts(Number(v.Choice("IrsFinalComparison") ?? "", 4)), () => FinalAccounts(books)));

    private static FormScreen FinalSettings(IrsBookkeeping books)
    {
        var headings = books.Headings();
        var fields = new List<Field>();
        foreach (var line in headings)
        {
            var slot = Code(line.Slot, 2);
            string label = line.Slot <= 14 ? "損益計算書" : "貸借対照表";
            fields.Add(Text("IrsFinalHeading" + slot, $"{label}の見出し {slot}", line.Title, 24));
            fields.Add(new ChoiceField("IrsFinalSign" + slot, $"表示符号 {slot}",
                [new("", "指定なし"), new("+", "そのまま"), new("-", "反転")], line.Sign));
        }
        return Form("決算書の見出し設定", fields, "保存", v =>
        {
            books.SaveHeadings(headings.Select(h =>
            {
                var slot = Code(h.Slot, 2);
                return h with { Title = v.Text("IrsFinalHeading" + slot), Sign = v.Choice("IrsFinalSign" + slot) ?? "" };
            }));
            return Done("決算書の見出し設定");
        });
    }

    private Screen Amendments(IrsBookkeeping books) => JournalTable(books.Journal(), "転記修正", "IrsAmendmentGrid",
        row => Form("転記修正", [new DateField("IrsAmendPostingDate", "転記日", row.Date),
             Text("IrsAmendPostingLegend", "摘要", row.Legend, 32)], "保存", v =>
        {
            books.AmendPosting(row.Number, Date(v, "IrsAmendPostingDate"), v.Text("IrsAmendPostingLegend"));
            return Amendments(books);
        }));

    private Screen Analysis(IrsBookkeeping books)
    {
        var entries = books.Analysis();
        return Form("分析帳票", [new DateField("IrsAnalysisFrom", "開始日", books.Configuration().Start),
             new DateField("IrsAnalysisTo", "終了日", books.Configuration().End)], "帳票を作成", v =>
        {
            DateTime start = Date(v, "IrsAnalysisFrom"), end = Date(v, "IrsAnalysisTo");
            if (end < start) throw new IrsException("終了日は開始日以降を選択してください。");
            return Report(books, books.JournalReport("分析帳票", entries.Where(e => e.Date >= start && e.Date <= end)),
                () => Analysis(books));
        });
    }

    private Screen Rebuild(IrsBookkeeping books) => Form("勘定残高の再計算",
        [new PasswordField("IrsRebuildPassword", "バックアップ確認後に入力する暗証番号", 4)], "認証", v =>
        {
            string password = v.Text("IrsRebuildPassword");
            if (!books.CheckPassword(password)) throw new IrsException("暗証番号が一致しません。");
            return new ConfirmationScreen("勘定残高の再計算", "既存の転記から勘定残高を再計算しますか。",
                "再計算", () => Guard("勘定残高の再計算", () =>
                {
                    books.Rebuild(password);
                    return Done("勘定残高の再計算");
                }), () => Root(books));
        });

    private static TableScreen JournalTable(IReadOnlyList<IrsJournalEntry> journal, string title, string id,
        Func<IrsJournalEntry, Screen>? open = null) =>
        new(title, id, ["転記番号", "日付", "借方", "貸方", "摘要", "金額", "付加価値税"],
            journal.Select(row => new TableRow([Code(row.Number), row.Date?.ToString("yyyy年M月d日") ?? "",
                Code(row.Debit), Code(row.Credit), row.Legend, row.Amount.ToString("0.00", CultureInfo.InvariantCulture),
                row.Tax.ToString("0.00", CultureInfo.InvariantCulture)], open is null ? null : () => open(row),
                [row.Number, row.Date ?? DateTime.MinValue, row.Debit, row.Credit, row.Legend, row.Amount, row.Tax])).ToArray());

    private Screen Export(IrsBookkeeping books) => new ConfirmationScreen("科目表の書き出し",
        "現在の科目表をファイルに保存します。既存のファイルを指定すると上書きします。続けますか。", "続ける",
        () => Form("科目表の書き出し", [new ChoiceField("IrsExportFormat", "ファイル形式",
            [new("T", "固定長テキスト"), new("C", "コンマ区切り")], "T")], "保存先を選択", v =>
            {
                bool csv = v.Choice("IrsExportFormat") == "C";
                var dialog = new SaveFileDialog
                {
                    Title = "科目表の保存先", FileName = "科目表", DefaultExt = csv ? ".csv" : ".txt",
                    Filter = csv ? "コンマ区切り文書 (*.csv)|*.csv" : "テキスト文書 (*.txt)|*.txt"
                };
                if (dialog.ShowDialog() != true) return AccountsMenu(books);
                try { File.WriteAllBytes(dialog.FileName, books.ExportAccounts(csv)); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                { throw new IrsException("科目表を保存できませんでした。"); }
                return Done("科目表の書き出し");
            }), () => AccountsMenu(books));

    private Screen Import(IrsBookkeeping books) => new ConfirmationScreen("科目表の取り込み",
        "固定長テキストから科目表を取り込み、既存の科目表を置き換えます。バックアップを確認してください。", "取り込み元を選択",
        () => Guard("科目表の取り込み", () =>
        {
            var dialog = new OpenFileDialog { Title = "科目表の取り込み元", Filter = "テキスト文書 (*.txt)|*.txt" };
            if (dialog.ShowDialog() != true) return AccountsMenu(books);
            try
            {
                using var input = File.OpenRead(dialog.FileName);
                if (input.Length > 5 * 1024 * 1024) throw new IrsException("科目表のファイルが大きすぎます。");
                byte[] bytes = new byte[(int)input.Length];
                input.ReadExactly(bytes);
                return new InformationScreen("科目表の取り込み", $"{books.ImportAccounts(bytes)}件の科目を取り込みました。");
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            { throw new IrsException("科目表を読み込めませんでした。"); }
        }), () => AccountsMenu(books));
}
