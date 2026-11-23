namespace Acas.Tests.Irs;

public class ReportComparisonTests
{
    [Theory]
    [InlineData(" \r\n先頭 \r\n\r\n末尾  \r\n  ", "先頭\n\n末尾", null)]
    [InlineData("甲\n\n乙", "甲\n乙", "2,3")]
    [InlineData("甲\n末尾", "甲", "2")]
    [InlineData(" \r\n ", "", null)]
    public void 証跡帳票の空行と末尾空白を従来どおりに比較する(string expected, string actual, string? difference)
        => Assert.Equal(difference, ReportComparison.Difference(expected, actual));

    [Fact]
    public void 証跡帳票の相違診断は先頭20件と総数を返す()
    {
        string expected = string.Concat(Enumerable.Repeat("甲\n", 30));
        Assert.Equal(string.Join(",", Enumerable.Range(1, 20)) + " ほか（全30行）",
            ReportComparison.Difference(expected, "乙"));
    }
}
