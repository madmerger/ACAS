using System.Text;

namespace Acas.Core.Engine;

/// <summary>COBOL 数字編集項目 (PIC ZZ,ZZ9.99- 等) の書式化。</summary>
public static class PicEdit
{
    private static string Expand(string pic)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < pic.Length; i++)
        {
            char c = char.ToUpperInvariant(pic[i]);
            if (i + 1 < pic.Length && pic[i + 1] == '(')
            {
                int e = pic.IndexOf(')', i);
                int n = int.Parse(pic.Substring(i + 2, e - i - 2));
                sb.Append(c, n); i = e;
            }
            else sb.Append(c);
        }
        return sb.ToString();
    }

    public static string Format(decimal v, string picture)
    {
        var pic = Expand(picture);
        bool neg = v < 0;
        // 後置符号
        string trail = "";
        if (pic.EndsWith("CR") || pic.EndsWith("DB")) { trail = neg ? pic.Substring(pic.Length - 2) : "  "; pic = pic.Substring(0, pic.Length - 2); }
        else if (pic.EndsWith("-")) { trail = neg ? "-" : " "; pic = pic.Substring(0, pic.Length - 1); }
        else if (pic.EndsWith("+")) { trail = neg ? "-" : "+"; pic = pic.Substring(0, pic.Length - 1); }
        // 浮動挿入文字 (先頭の - + £ $ が2個以上)
        char floatCh = '\0';
        if (pic.Length > 0 && pic[0] is '-' or '+' or '$' or '£')
        {
            int cnt = 0; foreach (var c in pic) if (c == pic[0]) cnt++;
            if (cnt >= 2) floatCh = pic[0];
        }
        char lead = '\0';
        if (floatCh == '\0' && pic.Length > 0 && pic[0] is '-' or '+' or '$' or '£') { lead = pic[0]; pic = pic.Substring(1); }
        int dp = pic.IndexOf('.');
        if (dp < 0) dp = pic.IndexOf('V');
        string ip = dp < 0 ? pic : pic.Substring(0, dp), fp = dp < 0 ? "" : pic.Substring(dp + 1);
        bool showPoint = dp >= 0 && pic[dp] == '.';
        int intDigits = 0, decDigits = 0;
        foreach (var c in ip) if (c is '9' or 'Z' or '*' || (c == floatCh && floatCh != '\0')) intDigits++;
        if (floatCh != '\0') intDigits--;
        foreach (var c in fp) if (c is '9' or 'Z' or '*') decDigits++;
        decimal a = Math.Abs(v);
        decimal scale = 1; for (int i = 0; i < decDigits; i++) scale *= 10;
        var all = ((long)decimal.Truncate(a * scale)).ToString().PadLeft(intDigits + decDigits, '0');
        all = all.Substring(all.Length - (intDigits + decDigits));
        string id = all.Substring(0, intDigits), dd = all.Substring(intDigits);
        // 整数部: 右から埋める
        var outc = new char[ip.Length];
        int di = id.Length - 1;
        for (int i = ip.Length - 1; i >= 0; i--)
        {
            char c = ip[i];
            if (c is '9' or 'Z' or '*' || c == floatCh && floatCh != '\0') outc[i] = di >= 0 ? id[di--] : '0';
            else if (c == 'B') outc[i] = ' ';
            else outc[i] = c; // , / 0
        }
        // ゼロサプレス
        int firstSig = -1;
        for (int i = 0; i < ip.Length; i++)
        {
            char c = ip[i];
            bool digitPos = c is '9' or 'Z' or '*' || (c == floatCh && floatCh != '\0');
            if (!digitPos) continue;
            if (c == '9' || outc[i] != '0') { firstSig = i; break; }
        }
        if (firstSig < 0) firstSig = ip.Length;
        char fill = ip.Contains('*') ? '*' : ' ';
        for (int i = 0; i < firstSig; i++) outc[i] = fill;
        var sb = new StringBuilder(new string(outc));
        if (floatCh != '\0')
        {
            char sign = floatCh == '-' ? (neg ? '-' : ' ') : floatCh == '+' ? (neg ? '-' : '+') : floatCh;
            int p = Math.Max(0, firstSig - 1);
            if (p < sb.Length) sb[p] = sign;
        }
        bool allZeroSuppressed = firstSig >= ip.Length && fp.Length > 0 && !fp.Contains('9') && a == 0;
        if (showPoint) sb.Append(allZeroSuppressed ? ' ' : '.');
        int k = 0;
        foreach (var c in fp)
        {
            if (c is '9' or 'Z' or '*') { sb.Append(allZeroSuppressed ? fill : dd[k]); k++; }
            else sb.Append(c);
        }
        string res = sb.ToString();
        if (lead != '\0') res = (lead == '-' ? (neg ? "-" : " ") : lead == '+' ? (neg ? "-" : "+") : lead.ToString()) + res;
        return res + trail;
    }
}
