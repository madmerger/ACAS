using Acas.Core;

namespace Acas.Tests;

public sealed class CalculationTests
{
    [Theory]
    [InlineData("drv09", "K9P34Y", "", "検査数字＝2　判定：有効")]
    [InlineData("drv09", "日本", "", "検査数字＝0　判定：無効")]
    [InlineData("drv04", "29/02/2023", "", "日付不正（通算日＝0）")]
    [InlineData("drv04", "01-01-1601", "", "日付有効　通算日＝1　正規化＝01/01/1601")]
    [InlineData("drvvat", "100.00", "20.00", "消費税額＝20.00")]
    [InlineData("drvage", "90", "", "経過日数区分＝90日")]
    [InlineData("drvavg", "1000.00", "3", "平均原価＝333.3333")]
    public void 計算の結果を和文で表示する(string kind, string first, string second, string expected) =>
        Assert.Equal(expected, Calculations.Summary(kind, Calculations.Run(kind, first, second)));
}
