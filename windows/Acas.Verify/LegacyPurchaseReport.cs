using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Acas.Verify;

internal static class LegacyPurchaseReport
{
    public static bool Matches(string path, string body, string title, bool posting, bool analysis)
    {
        string source = File.ReadAllText(path, Encoding.Latin1);
        var expected = source.Split('\f').Select((page, index) => TranslatePage(page, index + 1)).ToArray();
        var actual = body.Split('\f').Select(Lines).ToArray();
        return expected.Length == actual.Length && expected.Zip(actual).All(p => p.First.SequenceEqual(p.Second));

        string[] TranslatePage(string page, int number)
        {
            var rows = Lines(page);
            string legacyTitle = analysis ? "Product Analysis Codes" : posting ? "Invoice Posting Report" : "Unapplied Purchase Transaction Report";
            if (rows.Length < 3 || !rows[0].Contains(legacyTitle, StringComparison.Ordinal) ||
                !Regex.IsMatch(rows[0], $@"\bPage\s+{number}$"))
                throw new InvalidOperationException("旧帳票の表題とページ番号を読み取れません。");
            var header = Regex.Match(rows[1], @"^(.*?)\s+(\d{2}/\d{2}/\d{4})$");
            if (!header.Success) throw new InvalidOperationException("旧帳票の事業者と日付を読み取れません。");
            List<string> output = [title, header.Groups[1].Value, "処理日　" + Date(header.Groups[2].Value), $"ページ {number}"];
            foreach (string row in rows.Skip(2))
                Translate(row, output);
            return output.ToArray();
        }

        void Translate(string row, List<string> output)
        {
            if (analysis && Regex.IsMatch(row, @"^Code\s+GL\.No\.\s+<-----Description------>\s+Print\s+-Type-$"))
                output.Add("分析コード　勘定コード　摘要　帳票参照コード　区分");
            else if (Regex.IsMatch(row, @"^Number\s+(---Date---|Date)\s+<------------Supplier------------>\s+(--Type--|Type)\s+"))
            {
                string columns = posting ? "Old Balance  New Balance            Net         Vat       Gross" :
                    "Goods                 <---Net-->  <---Vat-->  <--Gross->";
                if (!row.EndsWith(columns, StringComparison.Ordinal)) throw new InvalidOperationException("旧帳票の列見出しが異なります。");
                output.Add("伝票番号　仕入日　仕入先コード　仕入先名　区分");
                output.Add((posting ? "前残高　新残高" : "商品額") + "　税抜額　税額　合計");
            }
            else if (Regex.Match(row, @"^(\d+)\s+(\d{2}/\d{2}/\d{4})\s+(\S+)\s+(.*?)\s+(Receipt|Invoice|Cr\. Note)\s+(.+)$") is { Success: true } invoice)
            {
                string[] amounts = Amounts(invoice.Groups[6].Value, posting ? 5 : 4);
                int offset = posting ? 2 : 1;
                output.Add($"{invoice.Groups[1].Value}　{Date(invoice.Groups[2].Value)}　{invoice.Groups[3].Value}　{invoice.Groups[4].Value}　{Type(invoice.Groups[5].Value)}");
                output.Add(posting ? $"前残高 {amounts[0]}　新残高 {amounts[1]}" : $"商品額 {amounts[0]}");
                output.Add($"税抜額 {amounts[offset]}　税額 {amounts[offset + 1]}　合計 {amounts[offset + 2]}");
            }
            else if (Regex.Match(row, @"^Analysis\s+(\S+)\s+Value\s+(.+?)\s+Vat Code\s+(\d)$") is { Success: true } detail)
                output.Add($"分析 {detail.Groups[1].Value}　金額 {Amounts(detail.Groups[2].Value, 1)[0]}　税区分 {detail.Groups[3].Value}");
            else if (Regex.Match(row, @"^Prompt Pay\s+(.+)$") is { Success: true } discount)
                output.Add($"早期支払割引 {Amounts(discount.Groups[1].Value, 1)[0]}");
            else if (Regex.Match(row, @"^Carriage\s+(.+?)\s+(\d)$") is { Success: true } carriage)
                output.Add($"送料 {Amounts(carriage.Groups[1].Value, 1)[0]}　税区分 {carriage.Groups[2].Value}");
            else if (Regex.IsMatch(row, @"^Goods\s+Carriage\s+Net\s+Vat\s+Gross\s+Prompt Pay$"))
                output.Add("商品額　送料　税抜額　税額　合計　早期支払割引");
            else if (Regex.Match(row, @"^Total\s+(?:Posted\s+)?(Receipts|Invoices|Credit Notes)\s+(.+)$") is { Success: true } total)
            {
                string[] amounts = Amounts(total.Groups[2].Value, posting ? 3 : 6);
                string prefix = Type(total.Groups[1].Value) + "合計　";
                output.Add(posting ? $"{prefix}税抜額 {amounts[0]}　税額 {amounts[1]}　合計 {amounts[2]}" :
                    $"{prefix}商品額 {amounts[0]}　送料 {amounts[1]}　税抜額 {amounts[2]}　税額 {amounts[3]}　合計 {amounts[4]}　早期支払割引 {amounts[5]}");
            }
            else if (Regex.IsMatch(row, @"^V\.A\.T\. Reconciliation\s+Receipts\s+Invoices\s+Credit Notes$"))
                output.Add("税額照合　領収　掛仕入　貸方票");
            else if (Regex.Match(row, @"^Vat Code\s+(\d)\s+([\d.]+)%\s+(.+)$") is { Success: true } tax)
                output.Add($"税区分 {tax.Groups[1].Value}　税率 {tax.Groups[2].Value}％　{string.Join("　", Amounts(tax.Groups[3].Value, 3))}");
            else
                throw new InvalidOperationException("旧帳票に未照合の行があります。");
        }
    }

    private static string[] Lines(string text) =>
        text.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    private static string Date(string value) =>
        DateTime.ParseExact(value, "dd/MM/yyyy", CultureInfo.InvariantCulture).ToString("yyyy年M月d日", CultureInfo.InvariantCulture);

    private static string Type(string value) => value switch
    {
        "Receipt" or "Receipts" => "領収",
        "Invoice" or "Invoices" => "掛仕入",
        "Cr. Note" or "Credit Notes" => "貸方票",
        _ => throw new InvalidOperationException("旧帳票の取引区分を読み取れません。")
    };

    private static string[] Amounts(string value, int count)
    {
        var matches = Regex.Matches(value, @"([0-9]+\.[0-9]{2})(CR)?");
        if (matches.Count != count || !Regex.IsMatch(value, @"^(?:\s*[0-9]+\.[0-9]{2}(?:CR)?)+\s*$"))
            throw new InvalidOperationException("旧帳票の金額を読み取れません。");
        return matches.Select(m => (m.Groups[2].Success ? "-" : "") + m.Groups[1].Value).ToArray();
    }
}
