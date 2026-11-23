using Acas.Core.Engine;

namespace Acas.Tests;

public class PictureEditingTests
{
    [Theory]
    [InlineData("09", "05")]
    [InlineData("Z09", " 05")]
    [InlineData("/9", "/5")]
    [InlineData("Z/9", " /5")]
    [InlineData("09.09", "05.05")]
    [InlineData("Z0Z9", " 0 5")]
    [InlineData("Z,9", "  5")]
    public void 固定挿入文字とゼロ抑制を区別する(string picture, string expected)
    {
        Assert.Equal(expected, PicEdit.Format(5.56m, picture));
    }

    [Theory]
    [InlineData("Z0Z", "   ")]
    [InlineData("Z0Z.ZZ", " 0 .56")]
    [InlineData("Z0Z.99", " 0 .56")]
    public void 表示上の値が全桁ゼロの場合に挿入文字も抑制する(string picture, string expected)
    {
        Assert.Equal(expected, PicEdit.Format(0.56m, picture));
    }
}
