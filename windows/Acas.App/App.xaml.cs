using System.Windows;

namespace Acas.App;

public partial class App : Application
{
    public static string[] Args = Array.Empty<string>();
    protected override void OnStartup(StartupEventArgs e)
    {
        Args = e.Args;
        base.OnStartup(e);
    }
}
