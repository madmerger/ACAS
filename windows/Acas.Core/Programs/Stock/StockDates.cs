namespace Acas.Core.Programs.Stock;

/// <summary>maps04 相当の日付変換（通算日 = 1600/12/31 からの日数）とシステム日付書式。</summary>
public static class StockDates
{
    public static readonly DateTime Epoch = new(1600, 12, 31);

    public static string ToUk(DateTime date) => date.ToString("dd/MM/yyyy", System.Globalization.CultureInfo.InvariantCulture);

    public static int ToBin(DateTime date) => (int)(date.Date - Epoch).TotalDays;

    public static DateTime FromBin(decimal bin) => Epoch.AddDays((double)bin);

    /// <summary>dd/mm/yyyy → 通算日。不正なら 0。</summary>
    public static int UkToBin(string text)
    {
        var a = text.PadRight(10)[..10].Replace('.', '/').Replace(',', '/').Replace('-', '/');
        if (a.Count(ch => ch == '/') != 2) return 0;
        string dd = a[..2], mm = a.Substring(3, 2), yyyy = a.Substring(6, 4);
        if (!dd.All(char.IsAsciiDigit) || !mm.All(char.IsAsciiDigit) || !yyyy.All(char.IsAsciiDigit)) return 0;
        int d = int.Parse(dd), m = int.Parse(mm), y = int.Parse(yyyy);
        if (m < 1 || m > 12 || y < 1601 || d < 1 || d > DateTime.DaysInMonth(y, m)) return 0;
        return ToBin(new DateTime(y, m, d));
    }

    /// <summary>zz060/zz070: UK 形式をシステムの日付書式 (1=UK, 2=USA, 3=Intl) へ。</summary>
    public static string ToSystemForm(string uk, int dateForm)
    {
        if (uk.Trim().Length == 0) return "";
        if (dateForm == 2) return uk.Substring(3, 2) + "/" + uk[..2] + uk[5..];
        if (dateForm == 3) return uk.Substring(6, 4) + "/" + uk.Substring(3, 2) + "/" + uk[..2];
        return uk;
    }

    public static string BinToSystemForm(decimal bin, int dateForm) =>
        bin == 0 ? "" : ToSystemForm(ToUk(FromBin(bin)), dateForm);
}
