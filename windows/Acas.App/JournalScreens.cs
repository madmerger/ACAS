using System.Globalization;
using Acas.Core;
using Acas.Core.Engine;

namespace Acas.App;

internal sealed partial class AccountingScreens
{
    private static readonly Choice[] PostingSides = [new("CR", "貸方に入力科目を置く"), new("DR", "借方に入力科目を置く")];
    private static readonly Choice[] TaxCalculations = [new("", "手入力または税額なし"), new("P", "税抜金額から計算"), new("M", "税込金額から計算")];

    private Screen JournalMenu()
    {
        _journal.Open();
        return new MenuScreen("仕訳入力",
        [
            new("NewJournalBatch", "新規バッチ登録", 1, Open: () => JournalHeaderForm()),
            new("JournalBack", "総勘定元帳に戻る", 9, Open: GeneralMenu)
        ]);
    }

    private Screen JournalHeaderForm(JournalHeader? draft = null, string? error = null)
    {
        if (_settings.Read() is not { } system) return Setup();
        int number = draft?.Number ?? system.I("Next-Batch");
        var defaults = _settings.DefaultAccounts().Where(a => a.Code != 0)
            .Select(a => new Choice(a.Number.ToString(), $"{a.Number}　{a.Code:0000.00}"))
            .Append(new Choice("33", "33　一時的な既定勘定")).ToArray();
        var fields = new List<Field>
        {
            new ChoiceField("JournalDefault", "既定勘定", defaults, (draft?.Default.Number ?? 33).ToString()),
            new TextField("JournalTemporaryCode", "一時的な既定勘定のコード", draft?.Default.Number == 33 ? draft.Default.Code.ToString("0000.00") : "", 7),
            new TextField("JournalTemporaryReference", "一時的な既定勘定の取引区分", draft?.Default.Number == 33 ? draft.Default.Reference : "", 2),
            new ChoiceField("JournalTemporaryTax", "一時的な既定勘定の税区分", Taxes, draft?.Default.Number == 33 ? draft.Default.Tax : "N"),
            new ChoiceField("JournalSide", "仕訳方向", PostingSides, draft?.Debit == true ? "DR" : "CR")
        };
        bool divisions = system.S("P-C") is "P" or "B";
        if (divisions) fields.Add(new TextField("JournalDivision", "既定勘定の部門コード", (draft?.Division ?? 0).ToString("00"), 2));
        fields.AddRange([
            new DateField("JournalDate", "処理日", draft?.Date ?? SystemSettings.Date(system, "Run-Date")),
            new TextField("JournalCycle", "会計期間", (draft?.Cycle ?? system.I("Cyclea")).ToString(), 2),
            new TextField("JournalItems", "照合用件数", (draft?.Items ?? 0).ToString(), 2),
            new TextField("JournalGross", "照合用総額", (draft?.Gross ?? 0).ToString("0.00"), 12)
        ]);
        bool vat = system.S("Vat") == "Y";
        if (vat) fields.Add(new TextField("JournalTax", "照合用税額", (draft?.Tax ?? 0).ToString("0.00"), 12));
        fields.Add(new TextField("JournalDescription", "摘要", draft?.Description ?? "", 24));

        return new FormScreen($"新規バッチ登録　{number:00000}", fields, "明細へ進む", values =>
        {
            int division = 0;
            decimal tax = 0;
            if (!Number(values.Choice("JournalDefault"), out int defaultNumber) ||
                (divisions && !Number(values.Text("JournalDivision"), out division)) ||
                values.Date("JournalDate") is not { } date || !Number(values.Text("JournalCycle"), out int cycle) ||
                !Number(values.Text("JournalItems"), out int items) || !JournalAmount(values.Text("JournalGross"), out decimal gross) ||
                (vat && !JournalAmount(values.Text("JournalTax"), out tax)))
                return JournalHeaderForm(draft, JournalMessage(JournalError.Header));

            var account = _settings.DefaultAccounts().FirstOrDefault(a => a.Number == defaultNumber);
            if (defaultNumber == 33 && JournalAmount(values.Text("JournalTemporaryCode"), out var code))
                account = new DefaultAccount(33, code, values.Text("JournalTemporaryReference").ToUpperInvariant(),
                    values.Choice("JournalTemporaryTax") ?? "");
            if (account == null) return JournalHeaderForm(draft, JournalMessage(JournalError.Default));
            var header = new JournalHeader(number, account, division, values.Choice("JournalSide") == "DR",
                date, cycle, items, gross, tax, values.Text("JournalDescription"));
            var status = _journal.Check(header);
            return status == JournalError.None ? JournalLines(header, []) : JournalHeaderForm(header, JournalMessage(status));
        }, () => new ConfirmationScreen("バッチ登録の中止", "明細を登録せず終了しますか。", "中止する",
            () => _journal.CancelSetup(number) == JournalError.None ? GeneralMenu() : JournalHeaderForm(),
            () => JournalHeaderForm(draft)), Error: error);
    }

    private Screen JournalLines(JournalHeader header, IReadOnlyList<JournalLine> lines)
    {
        var items = new List<Acas.Core.MenuItem>
        {
            new("JournalLineAdd", "明細を追加", Open: () => JournalLineForm(header, lines)),
            new("JournalLineReview", "明細を確認・修正", Open: () => JournalLineReview(header, lines)),
            new("JournalSave", "バッチを保存", Open: () => new ConfirmationScreen("バッチの保存",
                $"バッチ {header.Number:00000} に明細を {lines.Count} 件保存しますか。", "保存",
                () =>
                {
                    var status = _journal.Save(header, lines);
                    return status == JournalError.None ? JournalMenu() : new InformationScreen("バッチの保存", JournalMessage(status));
                }, () => JournalLines(header, lines))),
            new("JournalDiscard", "バッチを破棄", Open: () => new ConfirmationScreen("バッチの破棄", "入力した明細を破棄しますか。", "破棄",
                () => { _journal.Discard(header); return JournalMenu(); }, () => JournalLines(header, lines)))
        };
        return new MenuScreen($"仕訳明細　{header.Number:00000}（{lines.Count}件）", items);
    }

    private Screen JournalLineReview(JournalHeader header, IReadOnlyList<JournalLine> lines) => new TableScreen(
        "仕訳明細一覧", "JournalLineList", ["番号", "日付", "入力科目", "部門", "金額", "摘要"],
        lines.Select((l, i) => new Acas.Core.TableRow(
            [(i + 1).ToString(), l.Date.ToString("yyyy年M月d日"), l.Account.Number, l.Account.Division.ToString("00"),
                l.Amount.ToString("N2"), l.Description],
            () => JournalLineForm(header, lines, i, l))).ToArray(), Back: () => JournalLines(header, lines));

    private Screen JournalLineForm(JournalHeader header, IReadOnlyList<JournalLine> lines, int? index = null,
        JournalLine? draft = null, string? error = null)
    {
        var system = _settings.Read();
        bool divisions = system?.S("P-C") is "P" or "B";
        bool vat = header.Default.Tax is "I" or "O";
        var fields = new List<Field>
        {
            new DateField("JournalLineDate", "日付", draft?.Date ?? lines.LastOrDefault()?.Date ?? header.Date),
            new TextField("JournalLineAccount", "入力科目の勘定コード", draft is null ? "" : $"{draft.Account.Ledger:0000}.{draft.Account.Sub:00}", 7)
        };
        if (divisions) fields.Add(new TextField("JournalLineDivision", "部門コード", (draft?.Account.Division ?? 0).ToString("00"), 2));
        fields.Add(new TextField("JournalLineAmount", "金額", (draft?.Amount ?? 0).ToString("0.00"), 11));
        if (vat)
        {
            fields.Add(new ChoiceField("JournalLineTaxRate", "税率", Enumerable.Range(1, 3)
                .Select(i => new Choice(i.ToString(), $"税率 {i}　{system?.N("Vat-Rate-" + i):0.00}％")).ToArray(), (draft?.Rate ?? 1).ToString()));
            fields.Add(new ChoiceField("JournalLineTaxCalculation", "税額の計算方法", TaxCalculations, draft?.Calculation ?? ""));
            fields.Add(new TextField("JournalLineTaxAmount", "税額（自動計算する場合は空欄）", draft?.Tax?.ToString("0.00") ?? "", 11));
        }
        fields.Add(new TextField("JournalLineDescription", "摘要", draft?.Description ?? "", 32));

        return new FormScreen(index == null ? "仕訳明細の追加" : "仕訳明細の修正", fields, index == null ? "追加" : "変更", values =>
        {
            int division = 0, rate = 1;
            decimal? tax = null;
            if (vat && values.Text("JournalLineTaxAmount") is { Length: > 0 } taxText)
            {
                if (!JournalAmount(taxText, out var value)) return JournalLineForm(header, lines, index, draft, JournalMessage(JournalError.Line));
                tax = value;
            }
            if (values.Date("JournalLineDate") is not { } date || !JournalAmount(values.Text("JournalLineAccount"), out decimal code) ||
                code is < 1000 or >= 9999 || (divisions && !Number(values.Text("JournalLineDivision"), out division)) ||
                !JournalAmount(values.Text("JournalLineAmount"), out decimal amount) ||
                (vat && !Number(values.Choice("JournalLineTaxRate"), out rate)))
                return JournalLineForm(header, lines, index, draft, JournalMessage(JournalError.Line));

            var account = new AccountCode((int)code, (int)(code * 100) % 100, division);
            var line = new JournalLine(date, account, amount, values.Text("JournalLineDescription"), rate,
                vat ? values.Choice("JournalLineTaxCalculation") ?? "" : "", tax);
            var status = _journal.Check(header, line);
            if (status != JournalError.None) return JournalLineForm(header, lines, index, line, JournalMessage(status));
            var updated = index is int i ? lines.Select((l, n) => n == i ? line : l) : lines.Append(line);
            return JournalLines(header, updated.ToArray());
        }, () => JournalLines(header, lines), error);
    }

    private static bool JournalAmount(string value, out decimal parsed) =>
        decimal.TryParse(value, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out parsed) &&
        Cob.Trunc(parsed, 2) == parsed;

    private static string JournalMessage(JournalError status) => status switch
    {
        JournalError.Default => "既定勘定と部門コードを確認してください。",
        JournalError.Cycle => "会計期間は現在または次の期間を指定してください。",
        JournalError.Number or JournalError.ExistingRecord => "バッチ番号が現在の登録状態と一致しません。新規バッチ登録からやり直してください。",
        JournalError.Line => "明細の日付、勘定科目、金額、税額と摘要を確認してください。",
        _ => "バッチの設定内容を確認してください。"
    };
}
