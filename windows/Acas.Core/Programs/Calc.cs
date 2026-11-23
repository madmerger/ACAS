using System.Globalization;
using System.Text.Json;
using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>計算ロジック (maps09 チェックディジット / maps04 日付 / VAT 丸め / 売掛年齢区分 / 在庫平均原価)。
/// 各 Line* はレガシー計算ドライバ (calc-drivers/drv*.cbl) の出力行と同じ書式の文字列を返す。</summary>
public static class Calc
{
    private const string Alpha = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-";

    /// <summary>maps09: 得意先/仕入先コード 6 桁のチェックディジット。算出不能 (範囲外文字) は null。</summary>
    public static int? Maps09(string code)
    {
        code = code.PadRight(6).Substring(0, 6);
        int suma = 0;
        for (int a = 1; a <= 6; a++)
        {
            int q = Alpha.IndexOf(code[a - 1]) + 1;
            if (q == 0) { suma = 0; break; }
            suma += q * (8 - a);
        }
        if (suma == 0) return null;
        return (11 - suma % 11) % 10;      // PIC 9 への転記で上位桁が落ちる (10→0, 11→1)
    }

    /// <summary>maps09 "V" (検証): コード 7 桁目が正しいチェックディジットか。</summary>
    public static bool Maps09Verify(string code7) =>
        code7.Length >= 7 && char.IsDigit(code7[6]) && Maps09(code7) == code7[6] - '0';

    /// <summary>PIC 9(i)V9(d) への数字転記 (符号なし・上位桁あふれ切捨て・下位切捨て)。</summary>
    private static decimal Num(string s, int i, int d, bool signed = false)
    {
        decimal.TryParse(s.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture, out var v);
        bool neg = v < 0; v = Math.Abs(v);
        decimal sc = (decimal)Math.Pow(10, d);
        v = Math.Truncate(v * sc) / sc % (decimal)Math.Pow(10, i);
        return signed && neg ? -v : v;
    }

    /// <summary>VAT 額 (sl910): (正味 × 税率) / 100 を小数 2 桁へ四捨五入。PIC 9(6)V99 (符号なし)。</summary>
    public static decimal Vat(decimal net, decimal rate) =>
        Math.Round(net * rate / 100m, 2, MidpointRounding.AwayFromZero) % 1000000m;

    /// <summary>売掛年齢区分 (sl110): 経過日数 → 0 / 30 / 60 / 90。</summary>
    public static int AgeBucket(int days) => days < 30 ? 0 : days < 60 ? 30 : days < 90 ? 60 : 90;

    /// <summary>在庫平均原価 (st020): 金額 ÷ 数量 を小数 4 桁へ四捨五入。数量 0 は 0。</summary>
    public static decimal AvgCost(decimal value, decimal qty) =>
        qty == 0 ? 0 : Math.Round(value / qty, 4, MidpointRounding.AwayFromZero);

    public static string Line09(string code)
    {
        code = code.PadRight(6).Substring(0, 6);
        var cd = Maps09(code);
        return $"{code} {cd ?? 0} {(cd == null ? "N" : "Y")}";
    }

    public static string Line04(string date)
    {
        date = date.PadRight(10).Substring(0, 10);
        int bin = Common.Maps04(date);
        // maps04 は区切り文字 . , - を / に正規化して返す
        var norm = bin == 0 ? date : date.Replace('.', '/').Replace(',', '/').Replace('-', '/');
        return $"{date}|{bin.ToString(CultureInfo.InvariantCulture),10}|{norm}";
    }

    public static string LineVat(string net, string rate)
    {
        var v = Vat(Num(net, 7, 2), Num(rate, 2, 2));
        return $"{(net + "," + rate).PadRight(60)}|{v.ToString("000000.00", CultureInfo.InvariantCulture)}";
    }

    public static string LineAge(int days) =>
        $"{days.ToString(CultureInfo.InvariantCulture).PadRight(60)}|{AgeBucket(days):00}";

    public static string LineAvg(string value, string qty)
    {
        var v = AvgCost(Num(value, 8, 2, true), Num(qty, 6, 0, true));
        return $"{(value + "," + qty).PadRight(60)}|{v.ToString("0.0000", CultureInfo.InvariantCulture),12}";
    }

    /// <summary>シナリオ台帳の CALC ケースを実行して (ドライバ出力行, 日本語の結果要約) を返す。対象ドライバが無ければ null。</summary>
    public static (string Line, string Summary)? Run(JsonElement c)
    {
        var progs = c.GetProperty("programs");
        if (progs.GetArrayLength() == 0) return null;
        var inp = c.GetProperty("input_data");
        string S(string k) { var e = inp.GetProperty(k); return e.ValueKind == JsonValueKind.String ? e.GetString()! : e.GetRawText(); }
        switch (progs[0].GetString())
        {
            case "drv09": { var l = Line09(S("code")); return (l, $"チェックディジット={l[7]} 判定={(l[9] == 'Y' ? "有効" : "無効")}"); }
            case "drv04":
            {
                var l = Line04(S("date")); int bin = int.Parse(l.Split('|')[1]);
                return (l, bin == 0 ? "日付不正 (通算日=0)" : $"日付有効 通算日={bin} 正規化={l.Split('|')[2].Trim()}");
            }
            case "drvvat": { var l = LineVat(S("net"), S("rate")); return (l, $"VAT額={decimal.Parse(l.Split('|')[1], CultureInfo.InvariantCulture):0.00}"); }
            case "drvage": { var l = LineAge(int.Parse(S("days"))); return (l, $"年齢区分={int.Parse(l.Split('|')[1])}日"); }
            case "drvavg": { var l = LineAvg(S("value"), S("qty")); return (l, $"平均原価={l.Split('|')[1].Trim()}"); }
        }
        return null;
    }

    /// <summary>レガシー実測の出力行 (runs/&lt;証跡&gt;/00-output.txt の最初の非空行)。</summary>
    public static string? LegacyLine(JsonElement c, string evidenceRoot)
    {
        var ev = c.GetProperty("legacy_result").GetProperty("evidence");
        if (ev.GetArrayLength() == 0) return null;
        var p = Path.Combine(evidenceRoot, ev[0].GetString()!.Replace('/', Path.DirectorySeparatorChar), "00-output.txt");
        if (!File.Exists(p)) return null;
        return File.ReadAllText(p).Split('\n').Select(x => x.TrimEnd('\r')).FirstOrDefault(x => x.Trim().Length > 0);
    }
}
