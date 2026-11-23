using Acas.Core;
using Acas.Core.Engine;
using Acas.Tests;

[assembly: SubsystemScreensAttribute<SecondSubsystem>(20)]
[assembly: SubsystemScreensAttribute<FirstSubsystem>(10)]

namespace Acas.Tests;

public class SubsystemScreensTests
{
    [Fact]
    public void 宣言された画面を表示順に登録し画面操作に同じデータベースを使う()
    {
        using var database = new Db();
        var entries = SubsystemScreens.Load(typeof(SubsystemScreensTests).Assembly, database);

        Assert.Equal(["TestFirst", "TestSecond"], entries.Select(entry => entry.Id));
        Assert.Empty(database.Spool());
        var screen = Assert.IsType<MenuScreen>(entries[0].Open!());
        var action = Assert.Single(screen.Items);
        Assert.Equal("3　帳票を作成", action.Caption);
        Assert.IsType<ReportScreen>(action.Open!());
        Assert.Equal("検証帳票", Assert.Single(database.Spool()).Name);
    }

    [Fact]
    public void 登録がないアセンブリでは空の一覧を返す()
    {
        using var database = new Db();
        Assert.Empty(SubsystemScreens.Load(typeof(SubsystemScreens).Assembly, database));
    }
}

public sealed class FirstSubsystem : ISubsystemScreens
{
    public MenuItem CreateNavigation(Db database) => new("TestFirst", "検証業務", Open: () =>
        new MenuScreen("検証業務", [new("TestFirstReport", "帳票を作成", 3, Open: () =>
        {
            database.AddSpool("検証帳票", "検証本文");
            return new ReportScreen("検証帳票", "検証本文");
        })]));
}

public sealed class SecondSubsystem : ISubsystemScreens
{
    public MenuItem CreateNavigation(Db database) => new("TestSecond", "第二の業務");
}
