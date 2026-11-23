using System.Globalization;
using System.Text;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Sales;

public sealed class SalesRuleException(string message) : Exception(message);

public sealed partial class SalesLedger(Db db)
{
    public const string Prefix = "ledgers/acas/";
    public const string SystemFile = Prefix + "system.dat";
    public const string CustomerFile = Prefix + "salesled.dat";
    public const string DeliveryFile = Prefix + "delivery.dat";
    public const string AnalysisFile = Prefix + "analysis.dat";
    internal const string SystemKey = "00000001";
    private static readonly DateTime Epoch = new(1600, 12, 31);
    private static readonly Encoding DataEncoding = CodePagesEncodingProvider.Instance.GetEncoding(932,
        EncoderFallback.ExceptionFallback, DecoderFallback.ReplacementFallback)!;

    public Rec SystemRecord() => db.Read(SystemFile, SystemKey) is { Length: 1024 } data
        ? Layouts.System.From(data) : throw new SalesRuleException("共通設定が登録されていません。");
    public static int EncodeDate(DateTime value) => (value.Date - Epoch).Days;
    public static DateTime? DecodeDate(int value) =>
        value > 0 && value <= (DateTime.MaxValue.Date - Epoch).Days ? Epoch.AddDays(value) : null;
    public static string ShowDate(int value) => DecodeDate(value)?.ToString("yyyy年MM月dd日", CultureInfo.InvariantCulture) ?? "";
    public static string Amount(decimal value) => value.ToString("0.00", CultureInfo.InvariantCulture);

    public void SetProcessingDate(DateTime date)
    {
        int value = EncodeDate(date);
        if (value <= 0) throw new SalesRuleException("処理日が有効な範囲にありません。");
        var system = SystemRecord();
        system.SetN("Run-Date", value);
        if (system.I("Date-Form") == 0) system.SetN("Date-Form", 1);
        SaveSystem(system);
    }

    private void SaveSystem(Rec system) => db.Put(SystemFile, SystemKey, system.B);
    public bool HasFile(string file) => db.Exists(Prefix + file);
    public void KeepReport(string name, string body) => db.AddSpool(name, body);

    private static void SetText(Rec record, string field, string value, string label)
    {
        var target = record.L.F[field];
        byte[] bytes;
        try { bytes = DataEncoding.GetBytes(value); }
        catch (EncoderFallbackException) { throw BadText(label); }
        if (bytes.Length > target.Len || value.Any(char.IsControl))
            throw BadText(label);
        record.B.AsSpan(target.Off, target.Len).Fill(0x20);
        bytes.CopyTo(record.B, target.Off);

        static SalesRuleException BadText(string label) =>
            new($"{label}は固定長レコードに保存できる文字と長さで入力してください。");
    }

    internal static string GetText(Rec record, string field)
    {
        var source = record.L.F[field];
        return DataEncoding.GetString(record.B, source.Off, source.Len).TrimEnd(' ', '\0');
    }

    private static decimal TruncateMoney(decimal value) => decimal.Truncate(value * 100) / 100;
    private static decimal RoundMoney(decimal value) => decimal.Round(value, 2, MidpointRounding.AwayFromZero);
}
