using System.Globalization;
using System.IO;
using System.Windows;

namespace Acas.App;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var japanese = CultureInfo.GetCultureInfo("ja-JP");
        CultureInfo.CurrentCulture = japanese;
        CultureInfo.CurrentUICulture = japanese;
        try
        {
            var options = e.Args;
            var database = options.Length == 2 && options[0] == "--database" ? options[1] : null;
            MainWindow = new MainWindow(database);
            MainWindow.Show();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or Microsoft.Data.Sqlite.SqliteException)
        {
            MessageBox.Show("会計データを開けませんでした。保存先とアクセス権を確認してください。", "起動エラー",
                MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }
}
