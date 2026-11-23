using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Stock;

/// <summary>在庫帳票。<see cref="Legacy"/> はレガシー prt-1 と同じ桁位置の比較用、<see cref="Japanese"/> は画面・スプール用。</summary>
public sealed record StockReport(string Title, IReadOnlyList<string> Legacy, string Japanese);

internal static class Fmt
{
    public static string X(string? s, int len) => (s ?? "").PadRight(len)[..len];
    public static string E(decimal v, string pic) => PicEdit.Format(v, pic);
    public static string Z(decimal v, int digits) => v == 0 ? new string(' ', digits) : ((long)Math.Abs(decimal.Truncate(v))).ToString().PadLeft(digits)[^digits..];

    /// <summary>日本語帳票: 見出しと行を縦棒区切りの固定書式にする。</summary>
    public static string Table(string title, IEnumerable<string> head, IEnumerable<string[]> rows, IEnumerable<string>? foot = null)
    {
        var sb = new StringBuilder();
        foreach (var h in head) sb.AppendLine(h);
        sb.AppendLine();
        foreach (var r in rows) sb.AppendLine(string.Join("　", r.Select(c => c.TrimEnd())));
        if (foot != null) { sb.AppendLine(); foreach (var f in foot) sb.AppendLine(f); }
        return sb.ToString().TrimEnd();
    }
}
