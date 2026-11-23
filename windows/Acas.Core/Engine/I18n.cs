using System.Text;

namespace Acas.Core.Engine;

/// <summary>レガシー英語文言 → 日本語文言の対応表 (Resources/i18n.tsv)。</summary>
public static class I18n
{
    private static readonly Dictionary<string, string> Map = Load();

    private static Dictionary<string, string> Load()
    {
        var d = new Dictionary<string, string>(StringComparer.Ordinal);
        using var s = typeof(I18n).Assembly.GetManifestResourceStream("Acas.Core.Resources.i18n.tsv");
        if (s == null) return d;
        using var r = new StreamReader(s, Encoding.UTF8);
        string? line;
        while ((line = r.ReadLine()) != null)
        {
            if (line.Length == 0 || line[0] == '#') continue;
            int t = line.IndexOf('\t');
            if (t <= 0) continue;
            d[line.Substring(0, t).Trim()] = line.Substring(t + 1).TrimEnd();
        }
        return d;
    }

    public static IReadOnlyDictionary<string, string> Table => Map;

    /// <summary>原文に対応する日本語。先頭の空白は保持する。未登録は null。</summary>
    public static string? T(string text)
    {
        var core = text.Trim();
        if (core.Length == 0) return text;
        if (!Map.TryGetValue(core, out var ja)) return null;
        return new string(' ', text.Length - text.TrimStart().Length) + Align(core, ja);
    }

    /// <summary>入力欄の括弧 [ ] の桁位置を原文と同じに揃える (入力値は原文と同じ桁に表示されるため)。</summary>
    public static string Align(string en, string ja)
    {
        if (en.IndexOf('[') < 0 && en.IndexOf(']') < 0) return ja;
        var e = Split(en); var j = Split(ja);
        if (e.Count != j.Count) return ja;
        var sb = new StringBuilder();
        for (int i = 0; i < e.Count; i++)
        {
            if (i % 2 == 1) { sb.Append(e[i]); continue; }
            if (i == e.Count - 1) { sb.Append(j[i]); break; }
            var seg = e[i].Trim().Length == 0 ? e[i] : j[i].TrimEnd();
            int w = Width(seg);
            sb.Append(w <= e[i].Length ? seg + new string(' ', e[i].Length - w) : seg);
        }
        return sb.ToString();
    }
    private static List<string> Split(string s)
    {
        var r = new List<string>(); int st = 0;
        for (int i = 0; i < s.Length; i++)
            if (s[i] == '[' || s[i] == ']') { r.Add(s.Substring(st, i - st)); r.Add(s[i].ToString()); st = i + 1; }
        r.Add(s.Substring(st));
        return r;
    }

    /// <summary>対応表の検査: 括弧位置が揃わない (日本語が長すぎる) 行を返す。</summary>
    public static List<string> Misaligned()
    {
        var bad = new List<string>();
        foreach (var (en, ja) in Map)
        {
            var a = Align(en, ja); int ce = 0, cj = 0; var pe = new List<int>(); var pj = new List<int>();
            foreach (var ch in en) { if (ch == '[' || ch == ']') pe.Add(ce); ce++; }
            foreach (var ch in a) { if (ch == '[' || ch == ']') pj.Add(cj); cj += IsWide(ch) ? 2 : 1; }
            if (!pe.SequenceEqual(pj)) bad.Add(en);
        }
        return bad;
    }

    public static string Tr(string text, Lang lang) => lang == Lang.Ja ? (T(text) ?? text) : text;

    public static bool NeedsTranslation(string text)
    {
        int letters = 0;
        foreach (var c in text) if (c is >= 'A' and <= 'Z' or >= 'a' and <= 'z') letters++;
        return letters >= 2;
    }

    public static bool IsWide(char c) =>
        c >= 0x1100 && (c <= 0x115F || (c >= 0x2E80 && c <= 0xA4CF) || (c >= 0xAC00 && c <= 0xD7A3) ||
                        (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFE30 && c <= 0xFE6F) || (c >= 0xFF00 && c <= 0xFF60) || (c >= 0xFFE0 && c <= 0xFFE6));

    public static int Width(string s) { int w = 0; foreach (var c in s) w += IsWide(c) ? 2 : 1; return w; }

    public static string Fit(string ja, int cells)
    {
        int w = Width(ja);
        return w >= cells ? ja : ja + new string(' ', cells - w);
    }
}
