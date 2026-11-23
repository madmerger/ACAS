using Acas.App.Subsystems.Stock;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Stock;

[assembly: SubsystemScreensAttribute<StockScreens>(40)]

namespace Acas.App.Subsystems.Stock;

internal sealed class StockScreens : ISubsystemScreens
{
    public MenuItem CreateNavigation(Db database) => new StockScreenModel(database, () => DateTime.Now).Navigation();
}
