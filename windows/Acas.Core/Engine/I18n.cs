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
        return new string(' ', text.Length - text.TrimStart().Length) + ja;
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
