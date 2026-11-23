namespace Acas.Core.Programs.Sales;

public sealed partial class SalesScreens
{
    private MenuScreen AnalysisMenu() => new("売上分析コード管理",
    [
        Link("SalesAnalysisCreate", "売上分析コード登録", () => AnalysisEditor(null), 1),
        Link("SalesAnalysisChange", "売上分析コード変更・削除", () => AnalysisLookup(true), 2),
        Link("SalesAnalysisPrint", "売上分析コード印刷", () => PrintAnalysis(false), 3),
        Link("SalesAnalysisPrintAll", "分析コード全件印刷", () => PrintAnalysis(true), 4),
        Link("SalesAnalysisDisplay", "売上分析コード表示", () => AnalysisLookup(false), 5),
        Link("SalesAnalysisBack", "売掛元帳に戻る", MainMenu, 9)
    ]);

    private Screen AnalysisLookup(bool update)
    {
        string title = update ? "売上分析コード変更・削除" : "売上分析コード表示";
        return Form(title, [new TextField("SalesFindAnalysisCode", "分析コード", MaxLength: 2)], "検索", values =>
        {
            string code = values.Text("SalesFindAnalysisCode").TrimEnd();
            var entry = sales.AnalysisCodes().FirstOrDefault(c => c.Code == code)
                ?? throw new SalesRuleException("分析コードが見つかりません。");
            if (!update) return new TableScreen(title, "SalesAnalysisDetail", ["コード", "勘定番号", "分析名", "印刷分類"],
                [new([entry.Code, entry.Account, entry.DisplayDescription, entry.PrintCode])]);
            return new MenuScreen(title,
            [
                Link("SalesAnalysisEditSelected", "変更", () => AnalysisEditor(entry)),
                Link("SalesAnalysisDeleteSelected", "削除", () => Confirm(title, $"{entry.Code}を削除しますか。", "削除", () =>
                {
                    sales.DeleteAnalysis(entry.Code);
                    return AnalysisMenu();
                }, () => AnalysisLookup(true)))
            ]);
        });
    }

    private Screen AnalysisEditor(AnalysisCode? entry)
    {
        string title = entry == null ? "売上分析コード登録" : "売上分析コード変更";
        bool translated = entry != null && entry.DisplayDescription != entry.Description;
        List<Field> fields = [];
        if (entry == null) fields.Add(new TextField("SalesAnalysisCode", "分析コード", MaxLength: 2));
        fields.Add(new TextField("SalesAnalysisAccount", "勘定番号", entry?.Account ?? "000000", 6));
        if (translated)
            fields.Add(new ChoiceField("SalesAnalysisDescriptionAction", $"現在の分析名：{entry!.DisplayDescription}",
                [new("0", "保持する"), new("1", "入力した分析名に変更する")], "0"));
        fields.AddRange(
        [
            new TextField("SalesAnalysisDescription", translated ? "新しい分析名（24バイト以内）" : "分析名",
                translated ? "" : entry?.Description ?? "", 24),
            new TextField("SalesAnalysisPrintCode", "印刷分類", entry?.PrintCode ?? "", 3)
        ]);
        return Form(title, fields, "保存内容を確認", v =>
        {
            string? description = v.Text("SalesAnalysisDescription");
            if (translated && v.Choice("SalesAnalysisDescriptionAction") != "1")
            {
                if (description.Length != 0)
                    throw new SalesRuleException("新しい分析名が入力されています。分析名を変更するか、入力欄を空にしてから保存してください。");
                description = null;
            }
            else if (!translated && entry?.Description == description)
            {
                description = null;
            }
            return Confirm(title, "分析コードを保存しますか。", "保存", () =>
            {
                sales.SaveAnalysis(entry?.Code ?? v.Text("SalesAnalysisCode"), v.Text("SalesAnalysisAccount"),
                    description, v.Text("SalesAnalysisPrintCode"), entry != null);
                return AnalysisMenu();
            }, () => AnalysisEditor(entry));
        });
    }

    private Screen PrintAnalysis(bool all)
    {
        const string title = "売上分析コード帳票";
        try { return ShowReport(title, "prt-1", sales.AnalysisReport(all)); }
        catch (SalesRuleException ex)
        {
            if (all) throw;
            return ShowReport(title, "prt-1", sales.EmptyAnalysisReport() + "\n" + ex.Message);
        }
    }
}
