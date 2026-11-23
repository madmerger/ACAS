using System.Diagnostics;
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

    [Fact]
    public void ジャンクション配下の未作成データベースを拒否する()
    {
        if (!OperatingSystem.IsWindows()) return;
        var directory = Directory.CreateTempSubdirectory();
        var junction = Path.Combine(directory.FullName, "junction");
        try
        {
            var target = directory.CreateSubdirectory("target");
            var directPath = Path.Combine(target.FullName, "acas.db");
            Assert.Equal(directPath, LocalDatabasePath.Resolve(directPath));

            using var process = Process.Start(new ProcessStartInfo("cmd.exe", "/d /c mklink /J junction target")
            {
                WorkingDirectory = directory.FullName,
                UseShellExecute = false
            })!;
            process.WaitForExit();
            Assert.Equal(0, process.ExitCode);
            Assert.True(File.GetAttributes(junction).HasFlag(FileAttributes.ReparsePoint));

            var path = Path.Combine(junction, "acas.db");
            Assert.False(File.Exists(path));
            Assert.Throws<ArgumentException>(() => LocalDatabasePath.Resolve(path));
        }
        finally
        {
            if (Directory.Exists(junction)) Directory.Delete(junction);
            directory.Delete(true);
        }
    }
}
