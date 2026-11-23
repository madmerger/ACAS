using Acas.Core.Engine;

namespace Acas.Tests;

public class LocalDatabasePathTests
{
    [Theory]
    [InlineData(@"\\example.invalid\share\acas.db")]
    [InlineData("//example.invalid/share/acas.db")]
    [InlineData(@"\\?\UNC\example.invalid\share\acas.db")]
    public void 共有パスを拒否する(string path)
    {
        Assert.Throws<ArgumentException>(() => LocalDatabasePath.Resolve(path));
    }

    [Fact]
    public void ローカルファイルへのパスを受け付ける()
    {
        if (!OperatingSystem.IsWindows()) return;
        var path = Path.Combine(Path.GetTempPath(), "acas-dev", "acas.db");
        Assert.Equal(Path.GetFullPath(path), LocalDatabasePath.Resolve(path));
    }
}
