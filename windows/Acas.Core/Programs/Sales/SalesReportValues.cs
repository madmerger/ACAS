using System.Globalization;
using System.Text.RegularExpressions;

namespace Acas.Core.Programs.Sales;

public static class SalesReportValues
{
    private const string Wide = "　";
    private const string Money = @"-?\d[\d,]*\.\d{2}(?:CR)?";

    public static string? Difference(string legacy, string localized)
    {
        string[][] expected;
        string[][] actual;
        try
        {
            if (legacy.Contains("Unapplied Sales Transaction Report", StringComparison.Ordinal))
            {
                expected = LegacyProof(legacy).ToArray();
                actual = LocalizedProof(localized).ToArray();
            }
            else if (legacy.Contains("Credit Terms:", StringComparison.Ordinal))
            {
                expected = LegacyInvoice(legacy).ToArray();
                actual = LocalizedInvoice(localized).ToArray();
            }
            else if (legacy.Contains("Product Analysis Codes", StringComparison.Ordinal))
            {
                expected = EmptyLegacyAnalysis(legacy);
                actual = EmptyLocalizedAnalysis(localized);
            }
            else return "帳票の比較定義がありません。";
        }
        catch (FormatException) { return "帳票の項目形式が比較定義と異なります。"; }
        if (expected.Length == 0) return "証跡の帳票から比較項目を抽出できません。";
        if (expected.Length != actual.Length) return $"帳票の比較行数が相違（証跡 {expected.Length}、移行版 {actual.Length}）。";
        for (int i = 0; i < expected.Length; i++)
            if (!expected[i].SequenceEqual(actual[i], StringComparer.Ordinal))
                return $"帳票の比較行 {i + 1}（{expected[i][0]}）の項目値が相違。";
        return null;
    }

    private static string[] Lines(string body) => body.Replace("\r", "").Replace('\f', '\n')
        .Split('\n', StringSplitOptions.RemoveEmptyEntries).Where(line => line.Trim().Length != 0).ToArray();

    private static string Clip(string value, int start, int count) =>
        start >= value.Length ? "" : value.Substring(start, Math.Min(count, value.Length - start)).Trim();

    private static string Date(string text) => DateTime.ParseExact(text, ["dd/MM/yyyy", "yyyy年MM月dd日"],
        CultureInfo.InvariantCulture).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    private static string Number(string text)
    {
        bool credit = text.EndsWith("CR", StringComparison.Ordinal);
        string amount = credit ? text[..^2] : text;
        decimal value = amount.Length == 0 ? 0 : decimal.Parse(amount, NumberStyles.Number, CultureInfo.InvariantCulture);
        return (credit ? -value : value).ToString("0.##", CultureInfo.InvariantCulture);
    }

    private static string[] Amounts(string text) => Regex.Matches(text, Money).Select(m => Number(m.Value)).ToArray();
    private static string[] Parts(string text) => text.Split(Wide, StringSplitOptions.TrimEntries);

    private static string[][] EmptyLegacyAnalysis(string body)
    {
        var rows = Lines(body);
        if (rows.Length != 3 || body.Contains('\0') ||
            !Regex.IsMatch(rows[0], @"Product Analysis Codes\s+Page\s+1\s*$") ||
            !rows[2].TrimStart().StartsWith("Code    Gl.Nos.", StringComparison.Ordinal)) throw new FormatException();
        return [["表題", Clip(rows[1], 0, 70), Date(Clip(rows[1], 70, 10))]];
    }

    private static string[][] EmptyLocalizedAnalysis(string body)
    {
        var rows = Lines(body);
        if (rows is not [ "売上分析コード帳票", _, _, "コード　勘定番号　分析名　印刷分類　種類",
            "売上分析ファイルのレコード長が一致しません。（状態39）" ]) throw new FormatException();
        return [["表題", rows[1].Trim(), Date(rows[2].Trim())]];
    }

    private static string Kind(string text) => text switch
    {
        "Receipt" or "Receipts" or "現金売上" => "1",
        "Invoice" or "Invoices" or "掛売請求書" => "2",
        "Cr. Note" or "Credit Notes" or "貸方伝票" => "3",
        _ => throw new FormatException()
    };

    private static IEnumerable<string[]> LegacyProof(string body)
    {
        var lines = Lines(body);
        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];
            string text = line.Trim();
            if (line.Contains("Unapplied Sales Transaction Report", StringComparison.Ordinal))
            {
                if (i + 1 >= lines.Length) throw new FormatException();
                string header = lines[++i];
                yield return ["表題", Clip(header, 0, 49), Date(Clip(header, 122, 10))];
            }
            else if (Regex.IsMatch(text, @"^\d+\s+\d{2}/\d{2}/\d{4}\s"))
                yield return ["取引", Number(Clip(line, 0, 9)), Date(Clip(line, 9, 11)), Clip(line, 20, 8),
                    Clip(line, 28, 25), Kind(Clip(line, 58, 14)), .. Amounts(line[72..])];
            else if (Clip(line, 84, 11) == "Vat Code" || Regex.IsMatch(Clip(line, 95, 1), @"^\d$") &&
                Regex.IsMatch(Clip(line, 72, 12), Money))
                yield return ["分析", Clip(line, 58, 6), Number(Clip(line, 72, 12)), Number(Clip(line, 95, 1))];
            else if (text.StartsWith("Total ", StringComparison.Ordinal))
                yield return ["合計", Kind(Clip(line, 13, 18)), .. Amounts(line[31..])];
            else if (text.StartsWith("Vat Code ", StringComparison.Ordinal))
                yield return ["税集計", Number(Clip(line, 9, 1)), .. Amounts(line[10..])];
            else if (!text.StartsWith("Number ", StringComparison.Ordinal) &&
                !text.StartsWith("Goods ", StringComparison.Ordinal) && !text.StartsWith("V.A.T. Reconciliation", StringComparison.Ordinal))
                throw new FormatException();
        }
    }

    private static IEnumerable<string[]> LocalizedProof(string body)
    {
        var lines = Lines(body);
        if (lines.Length < 4 || lines[0] != "未転記売上取引検証帳票") throw new FormatException();
        yield return ["表題", lines[1].Trim(), Date(lines[2].Trim())];
        foreach (string line in lines.Skip(3))
        {
            var p = Parts(line);
            if (p.Length == 9 && p[0].Length > 0 && char.IsAsciiDigit(p[0][0]))
                yield return ["取引", Number(p[0]), Date(p[1]), p[2], p[3], Kind(p[4]), .. p.Skip(5).Select(Number)];
            else if (p.Length == 6 && p[0] == "分析コード")
                yield return ["分析", p[1], Number(p[3]), Number(p[5])];
            else if (p.Length == 8 && p[0].EndsWith("合計", StringComparison.Ordinal))
                yield return ["合計", Kind(p[0][..^2]), .. p.Skip(1).Select(Number)];
            else if (p.Length == 5 && p[0].StartsWith("税区分", StringComparison.Ordinal))
                yield return ["税集計", Number(p[0][3..]), .. Amounts(line)];
            else if (p[0] is not ("請求番号" or "商品額" or "税区分別集計")) throw new FormatException();
        }
    }

    private static IEnumerable<string[]> LegacyInvoice(string body)
    {
        var rows = Lines(body);
        int page = Array.FindIndex(rows, line => line.Contains("Page ", StringComparison.Ordinal));
        int head = Array.FindIndex(rows, line => line.TrimStart().StartsWith("Product Code ", StringComparison.Ordinal));
        if (page < 1 || head <= page + 2) throw new FormatException();
        var pageFields = Regex.Match(rows[page], @"Page\s+(\d+)\s+of\s+(\d+)\s+(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2})");
        if (!pageFields.Success) throw new FormatException();
        foreach (string line in rows.Take(page).Where(line => line.Trim() is not ("Invoice" or "=======")))
            yield return ["事業者", line.Trim()];
        yield return ["ページ", Number(pageFields.Groups[1].Value), Number(pageFields.Groups[2].Value)];
        yield return ["日付", Date(pageFields.Groups[3].Value), pageFields.Groups[4].Value];
        string number = rows[page + 1].Trim();
        if (!number.StartsWith("Inv: ", StringComparison.Ordinal)) throw new FormatException();
        yield return ["番号", Number(number[5..].Trim())];
        var address = rows[(page + 2)..head];
        if (address.Length == 0 || address.Any(line => Clip(line, 35, 30).Length > 0)) throw new FormatException();
        yield return ["得意先", Clip(address[0], 0, 31), .. address.Skip(1).Select(line => Clip(line, 0, 31)).Where(line => line.Length > 0)];
        yield return ["参照", Following(address, "A/C :"), Following(address, "Order:"), Following(address, "Ref :")];
        int i = head + 1;
        for (; i < rows.Length && !rows[i].StartsWith("Credit Terms:", StringComparison.Ordinal); i++)
        {
            string line = rows[i];
            yield return ["明細", Clip(line, 0, 14), Clip(line, 14, 30), Number(Clip(line, 44, 6)), Number(Clip(line, 50, 10)),
                Number(Clip(line, 60, 6)), Number(Clip(line, 67, 10)), Number(Clip(line, 77, 10))];
        }
        if (i + 2 != rows.Length - 1 || !rows[i + 2].Contains("Total Due:", StringComparison.Ordinal)) throw new FormatException();
        yield return ["期限", Number(Clip(rows[i], 14, 3)), Number(Clip(rows[i], 65, 11)), Number(Clip(rows[i], 76, 11))];
        yield return ["合計", Number(Clip(rows[i + 1], 65, 11)), Number(Clip(rows[i + 1], 76, 11)), .. Amounts(rows[i + 2])];
    }

    private static string Following(string[] lines, string label)
    {
        var matching = lines.Where(line => line.Contains(label, StringComparison.Ordinal)).ToArray();
        if (matching.Length != 1) throw new FormatException();
        var line = matching[0];
        return line[(line.IndexOf(label, StringComparison.Ordinal) + label.Length)..].Trim();
    }

    private static IEnumerable<string[]> LocalizedInvoice(string body)
    {
        var lines = Lines(body);
        if (lines.Length < 8 || lines[0] != "請求書") throw new FormatException();
        int number = Array.FindIndex(lines, line => line.StartsWith("請求番号" + Wide, StringComparison.Ordinal));
        int order = Array.FindIndex(lines, line => line.StartsWith("注文番号" + Wide, StringComparison.Ordinal));
        int page = Array.FindIndex(lines, line => line.StartsWith("ページ" + Wide, StringComparison.Ordinal));
        if (number < 4 || order <= number + 2 || page != order + 2) throw new FormatException();
        yield return ["事業者", Parts(lines[2])[1]];
        foreach (string line in lines[3..number]) yield return ["事業者", line.Trim()];
        yield return ["ページ", .. Parts(lines[page])[1].Split('／').Select(Number)];
        var date = Parts(lines[number + 1]);
        if (date.Length != 3) throw new FormatException();
        yield return ["日付", Date(date[1]), date[2]];
        yield return ["番号", Number(Parts(lines[number])[1])];
        var customer = Parts(lines[number + 2]);
        var reference = Parts(lines[order]);
        if (customer.Length != 3 || reference.Length != 4) throw new FormatException();
        yield return ["得意先", customer[2], .. lines[(number + 3)..order].Select(line => line.Trim())];
        yield return ["参照", customer[1], reference[1], reference[3]];
        foreach (string line in lines.Skip(page + 1))
        {
            var p = Parts(line);
            if (p.Length == 7 && p[0] != "税抜額")
                yield return ["明細", p[0], p[1], .. p.Skip(2).Select(Number)];
            else if (p.Length == 4 && p[0] == "支払期限（日数）") yield return ["期限", .. p.Skip(1).Select(Number)];
            else if (p.Length == 6 && p[0] == "税抜額") yield return ["合計", Number(p[1]), Number(p[3]), Number(p[5])];
            else throw new FormatException();
        }
    }
}
