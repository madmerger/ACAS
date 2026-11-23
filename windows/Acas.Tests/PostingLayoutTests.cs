using Acas.Core.Engine;

namespace Acas.Tests;

public class PostingLayoutTests
{
    [Fact]
    public void 仕訳レコードは９８バイト()
    {
        Assert.Equal(98, Layouts.Posting.New().B.Length);
        Assert.Equal(new Fld(88, 10, FK.N9, 10, 2, true), Layouts.Posting.F["vat-amount"]);
    }
}
