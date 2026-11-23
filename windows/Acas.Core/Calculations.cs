using System.Globalization;

namespace Acas.Core;

public static class Calculations
{
    private const string Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-";
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;

    public static string Run(string kind, string first, string second = "") => kind switch
    {
        "drv09" => CheckDigit(first),
        "drv04" => DateLine(first),
        "drvvat" => $"{(first + "," + second).PadRight(60)}|{(Math.Round(Number(first, 7, 2) * Number(second, 2, 2) / 100m, 2, MidpointRounding.AwayFromZero) % 1000000m).ToString("000000.00", Invariant)}",
        "drvage" => $"{int.Parse(first, Invariant).ToString(Invariant).PadRight(60)}|{Age(int.Parse(first, Invariant)):00}",
        "drvavg" => $"{(first + "," + second).PadRight(60)}|{Average(Number(first, 8, 2, true), Number(second, 6, 0, true)).ToString("0.0000", Invariant),12}",
        _ => throw new ArgumentException("計算の種類が不明です。", nameof(kind))
    };

    public static string Summary(string kind, string line)
    {
        if (kind == "drv09")
            return $"検査数字＝{line[7]}　判定：{(line[9] == 'Y' ? "有効" : "無効")}";
        var fields = line.Split('|', 3);
        string result = fields[1].Trim();
        return kind switch
        {
            "drv04" when result == "0" => "日付不正（通算日＝0）",
            "drv04" => $"日付有効　通算日＝{result}　正規化＝{fields[2].Trim()}",
            "drvvat" => $"消費税額＝{decimal.Parse(result, Invariant).ToString("0.00", Invariant)}",
            "drvage" => $"経過日数区分＝{int.Parse(result, Invariant)}日",
            "drvavg" => $"平均原価＝{result}",
            _ => throw new ArgumentException("計算の種類が不明です。", nameof(kind))
        };
    }

    private static string CheckDigit(string input)
    {
        string code = input.PadRight(6)[..6];
        int sum = 0;
        for (int i = 0; i < code.Length; i++)
        {
            int position = Alphabet.IndexOf(code[i]) + 1;
            if (position == 0) return $"{code} 0 N";
            sum += position * (7 - i);
        }
        return $"{code} {(11 - sum % 11) % 10} Y";
    }

    private static string DateLine(string input)
    {
        string date = input.PadRight(10)[..10];
        string normalized = date.Replace('.', '/').Replace(',', '/').Replace('-', '/');
        int day = DayNumber(normalized);
        return $"{date}|{day.ToString(Invariant),10}|{(day == 0 ? date : normalized)}";
    }

    private static int DayNumber(string date)
    {
        if (date[2] != '/' || date[5] != '/' || !date[..2].All(char.IsAsciiDigit) ||
            !date[3..5].All(char.IsAsciiDigit) || !date[6..8].All(char.IsAsciiDigit) ||
            !date[8..].All(c => char.IsAsciiDigit(c) || c == ' ')) return 0;
        int day = int.Parse(date[..2], Invariant), month = int.Parse(date[3..5], Invariant);
        int year = int.Parse(date[6..8], Invariant) * 100 + (date[8] - '0') * 10 + date[9] - '0';
        if (year < 1601 || month is < 1 or > 12 || day < 1 || day > DateTime.DaysInMonth(year, month)) return 0;
        return (new DateTime(year, month, day) - new DateTime(1600, 12, 31)).Days;
    }

    private static decimal Number(string input, int integral, int fractional, bool signed = false)
    {
        decimal value = decimal.Parse(input, NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite |
            NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, Invariant);
        decimal modulus = integral switch { 2 => 100m, 6 => 1000000m, 7 => 10000000m, 8 => 100000000m, _ => 1m };
        decimal scale = fractional == 2 ? 100m : 1m;
        decimal magnitude = Math.Truncate(Math.Abs(value) % modulus * scale) / scale;
        return signed && value < 0 ? -magnitude : magnitude;
    }

    private static int Age(int days) => days < 30 ? 0 : days < 60 ? 30 : days < 90 ? 60 : 90;
    private static decimal Average(decimal value, decimal quantity) =>
        quantity == 0 ? 0 : Math.Round(value / quantity, 4, MidpointRounding.AwayFromZero);
}
