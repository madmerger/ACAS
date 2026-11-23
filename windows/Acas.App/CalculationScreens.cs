using Acas.Core;
using Acas.Core.Engine;

[assembly: SubsystemScreensAttribute<Acas.App.CalculationScreens>(70)]

namespace Acas.App;

internal sealed class CalculationScreens : ISubsystemScreens
{
    private static readonly (string Kind, string Id, string Title, string First, string? Second)[] Options =
    [
        ("drv09", "CalcCheckDigit", "検査数字", "取引先コード", null),
        ("drv04", "CalcDate", "日付の検証", "日付（日／月／年）", null),
        ("drvvat", "CalcTax", "消費税額", "税抜額", "税率（百分率）"),
        ("drvage", "CalcAge", "経過日数区分", "経過日数", null),
        ("drvavg", "CalcAverage", "平均原価", "金額", "数量")
    ];

    public Acas.Core.MenuItem CreateNavigation(Db database) => new("MenuCalculations", "計算", Open: OpenMenu);

    private static Screen OpenMenu() => new MenuScreen("計算", Options.Select(option =>
        new Acas.Core.MenuItem(option.Id, option.Title, Open: () => Form(option))).ToArray());

    private static Screen Form((string Kind, string Id, string Title, string First, string? Second) option,
        string first = "", string second = "", string? error = null)
    {
        List<Field> fields = [new TextField("CalcFirst", option.First, first)];
        if (option.Second is not null) fields.Add(new TextField("CalcSecond", option.Second, second));
        return new FormScreen(option.Title, fields, "計算する", values =>
        {
            string a = values.Text("CalcFirst"), b = option.Second is null ? "" : values.Text("CalcSecond");
            try
            {
                return new InformationScreen(option.Title, Calculations.Summary(option.Kind, Calculations.Run(option.Kind, a, b)));
            }
            catch (Exception e) when (e is FormatException or OverflowException)
            {
                return Form(option, a, b, "数値の入力を確認してください。");
            }
        }, OpenMenu, error);
    }
}
