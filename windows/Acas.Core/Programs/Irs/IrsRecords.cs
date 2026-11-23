using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Irs;

internal static class IrsRecords
{
    internal static readonly Layout System = new Layout()
        .X("date", 8).X("operator", 24).X("client", 24)
        .Group(4, (l, i) => l.X("address" + i, 24))
        .X("start", 8).X("end", 8).X("files", 48).N9("platform", 1)
        .X("password", 4).N9("next", 5)
        .N9("tax", 2, 2).N9("tax2", 2, 2).N9("tax3", 2, 2)
        .N9("passwordLevel", 1).N9("save", 1).X("workgroup", 18)
        .X("appropriationCreated", 1).N9("appropriation", 5)
        .X("spool", 32).N9("first", 1).N9("filler", 7).X("endFiller", 8);

    internal static readonly Layout Account = new Layout()
        .N9("owner", 5).N9("child", 5).X("kind", 1).X("name", 24)
        .Comp("debit", 8, 2).Comp("credit", 8, 2)
        .Group(4, (l, i) => l.Comp("debit" + i, 8, 2))
        .Group(4, (l, i) => l.Comp("credit" + i, 8, 2))
        .X("category", 1);

    internal static readonly Layout Defaults = new Layout()
        .Group(32, (l, i) => l.N9("account" + i, 5))
        .Group(32, (l, i) => l.X("code" + i, 2))
        .Group(32, (l, i) => l.X("tax" + i, 1));

    internal static readonly Layout Journal = new Layout()
        .N9("number", 5).X("code", 2).X("date", 8).N9("debit", 5).N9("credit", 5)
        .X("amount", 9).X("legend", 32).N9("taxDefault", 2).X("taxSide", 2).X("tax", 9);

    private static readonly Encoding TextEncoding = GetTextEncoding();

    private static Encoding GetTextEncoding()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        return Encoding.GetEncoding(932, EncoderFallback.ExceptionFallback, DecoderFallback.ReplacementFallback);
    }

    internal static string DateText(DateTime date) => date.ToString("dd/MM/yy", CultureInfo.InvariantCulture);

    internal static DateTime? Date(string value)
    {
        if (value.Length != 8 || value[2] != '/' || value[5] != '/' ||
            !int.TryParse(value.AsSpan(6), NumberStyles.None, CultureInfo.InvariantCulture, out int year))
            return null;
        string date = value[..6] + (year < 60 ? "20" : "19") + value[6..];
        return DateTime.TryParseExact(date, "dd/MM/yyyy", CultureInfo.InvariantCulture, DateTimeStyles.None, out var result)
            ? result : null;
    }

    internal static decimal Signed(Rec row, string field)
    {
        string raw = row.S(field);
        bool negative = raw[0] is >= 'p' and <= 'y';
        if (negative) raw = (char)(raw[0] - 64) + raw[1..];
        return (negative ? -1 : 1) * Cob.ToNum(raw) / 100;
    }

    internal static void Signed(Rec row, string field, decimal amount)
    {
        string raw = Cob.P9(amount * 100, 9);
        row.Set(field, amount < 0 ? (char)(raw[0] + 64) + raw[1..] : raw);
    }

    internal static string Text(Rec record, string name)
    {
        var field = record.L.F[name];
        return TextEncoding.GetString(record.B, field.Off, field.Len).TrimEnd(' ', '\0');
    }

    internal static byte[] Encode(string text, int max)
    {
        if (text.Any(char.IsControl))
            throw new IrsException("制御文字は入力できません。");
        try
        {
            byte[] bytes = TextEncoding.GetBytes(text);
            if (bytes.Length <= max) return bytes;
        }
        catch (EncoderFallbackException)
        {
            throw new IrsException("帳簿に保存できない文字が含まれています。");
        }
        throw new IrsException($"入力は{max}バイト以内にしてください。");
    }

    internal static string Fit(string text, int max)
    {
        while (TextEncoding.GetByteCount(text) > max) text = text[..^1];
        return text;
    }

    internal static void Text(Rec record, string name, string value)
    {
        var field = record.L.F[name];
        var bytes = Encode(value, field.Len);
        Array.Fill(record.B, (byte)' ', field.Off, field.Len);
        bytes.CopyTo(record.B, field.Off);
    }
}
