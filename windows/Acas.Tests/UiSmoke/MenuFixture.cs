#if ACAS_UI_SMOKE
using Acas.App.UiSmoke;
using Acas.Core;
using Acas.Core.Engine;

[assembly: SubsystemScreensAttribute<MenuFixture>(10)]

namespace Acas.App.UiSmoke;

internal sealed class MenuFixture : ISubsystemScreens
{
    public MenuItem CreateNavigation(Db database) => new("SmokeRoot", "画面検証", Children:
    [
        new("SmokeNavigation", "業務操作", Open: () => new MenuScreen("業務操作",
        [
            new("SmokeOpenForm", "入力画面", 1, Open: () => new FormScreen("業務入力",
                [new TextField("SmokeInput", "入力内容")], "確定",
                values => new InformationScreen("確認", values.Text("SmokeInput"))))
        ])),
        new("SmokeConfirmation", "操作の確認", Open: () => new ConfirmationScreen("操作の確認", "続行しますか。", "続行",
            () => new InformationScreen("確認", "実行しました。"),
            () => new InformationScreen("取消", "実行しませんでした。")))
    ]);
}
#endif
