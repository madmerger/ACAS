using Acas.App.Subsystems.Sales;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Sales;

[assembly: SubsystemScreensAttribute<SalesRegistration>(30)]

namespace Acas.App.Subsystems.Sales;

internal sealed class SalesRegistration : ISubsystemScreens
{
    public MenuItem CreateNavigation(Db database) => new SalesScreens(new SalesLedger(database)).Navigation();
}
