using Acas.Core.Programs.Sales;

namespace Acas.Tests.Sales;

public sealed class SalesReportValuesTests
{
    [Theory]
    [InlineData(31, '0')]
    [InlineData(1025, ' ')]
    public void ProofRejectsAmountsBeyondComparisonLimits(int length, char padding)
    {
        const string localized = "未転記売上取引検証帳票\n事業者\n2026年11月23日\n税区分別集計　現金売上　掛売請求書　貸方伝票\n" +
            "税区分1　税率20.00％　0.00　20.00　0.00";
        string legacy = "Unapplied Sales Transaction Report\n" + "事業者".PadRight(122) + "23/11/2026\nVat Code 1   ";
        const string amounts = "20.00%   0.00   20.00   0.00";
        Assert.Null(SalesReportValues.Difference(legacy + amounts, localized));
        Assert.Equal("帳票の項目形式が比較定義と異なります。",
            SalesReportValues.Difference(legacy + new string(padding, length) + amounts, localized));
    }
}
