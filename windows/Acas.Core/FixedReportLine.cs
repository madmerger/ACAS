using System.Text;

namespace Acas.Core;

internal static class FixedReportLine
{
    internal static string Format(params (int Column, string Value)[] cells)
    {
        var line = new StringBuilder();
        int column = 0;
        for (int i = 0; i < cells.Length; i++)
        {
            var (start, value) = cells[i];
            int end = i + 1 < cells.Length ? cells[i + 1].Column : 132;
            line.Append(' ', start - column);
            column = start;
            foreach (char c in value)
            {
                int width = c <= 'ÿ' ? 1 : 2;
                if (column + width > end) break;
                line.Append(c);
                column += width;
            }
        }
        return line.ToString().TrimEnd();
    }
}
