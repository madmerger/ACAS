using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using System.Text.Json;
using Acas.Core.Engine;
using Acas.Core.Programs.Purchase;

namespace Acas.Verify;

public static class PurchaseVerification
{
    public static IReadOnlyList<string> Compare(string id, JsonElement targets, string evidence, Db db,
        Action<List<string>> exercise)
    {
        List<string> differences = [];
        try
        {
            string? referenceDirectory = targets.GetProperty("keyed_record_diff").GetString() is { } diffPath
                ? Path.GetDirectoryName(EvidenceFile(evidence, diffPath)) : null;
            if (referenceDirectory != null)
                foreach (var row in BTreeRows(Path.Combine(referenceDirectory, "before-files", PurchaseLedger.AnalysisFile)))
                    db.Put(PurchaseLedger.AnalysisFile, Encoding.ASCII.GetString(row.Key), row.Data);
            var reference = RecordChanges(evidence, targets);
            if (id == "PL-090")
            {
                db.Remove(PurchaseLedger.SupplierFile);
                var beforeSetup = Rows(db);
                exercise(differences);
                VerifySupplierSetup(db, reference, differences, beforeSetup);
            }
            else
            {
                var before = Rows(db);
                exercise(differences);
                var after = Rows(db);
                var expected = reference.ToDictionary(change => (change.File, change.Key), change => (change.Before, change.After));
                const string openItems = "ledgers/acas/openitm5.dat";
                if (referenceDirectory != null)
                    foreach (var (key, record) in BTreeRows(Path.Combine(referenceDirectory, "files", openItems)))
                    {
                        string supplier = Encoding.ASCII.GetString(key, 0, 7);
                        string folio = BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(7)).ToString("00000000", CultureInfo.InvariantCulture);
                        expected.Add((openItems, $"{supplier}/{folio}"), (null, Convert.ToHexString(record).ToLowerInvariant()));
                    }
                foreach (var key in before.Keys.Concat(after.Keys).Concat(expected.Keys).Distinct().OrderBy(key => key))
                {
                    before.TryGetValue(key, out string? oldHex);
                    after.TryGetValue(key, out string? newHex);
                    if (!expected.TryGetValue(key, out var record))
                    {
                        if (oldHex != newHex) differences.Add(id == "PL-414" && key.File == PurchaseLedger.SystemFile
                            ? "旧版では転記フラグがメモリ上で変わりますが、買掛終了までシステムレコードを書き戻しません。証跡は買掛メニューで停止し、移行版は転記と同じトランザクションで保存します。"
                            : $"{key.File}／{key.Key}：追加のレコード差分があります。");
                    }
                    else if (record.Before != oldHex || record.After != newHex)
                        differences.Add($"{key.File}／{key.Key}：更新前後のレコードバイト列が異なります。");
                }

                var legacyReports = targets.GetProperty("report_files").EnumerateArray().Select(item => item.GetString()!)
                    .Select(path => File.ReadAllBytes(EvidenceFile(evidence, path))).Where(body => body.Length != 0)
                    .Select(System.Security.Cryptography.SHA256.HashData)
                    .Select(Convert.ToHexString).Distinct().Count();
                int appReports = db.Spool().Count;
                if (id == "PL-232" && legacyReports == 1 && appReports == 0 && referenceDirectory != null)
                    VerifyScheduledPaymentReport(evidence, targets, referenceDirectory, differences);
                else if (legacyReports != appReports) differences.Add($"帳票数が異なります（既存 {legacyReports}、移行 {appReports}）。");
                else if (id is "PL-221" or "PL-413" or "PL-414" && legacyReports == 1)
                {
                    var report = db.Spool().Single();
                    string path = EvidenceFile(evidence, targets.GetProperty("report_files")[0].GetString()!);
                    if (!LegacyPurchaseReport.Matches(path, report.Body, report.Name, id == "PL-414", id == "PL-221"))
                        differences.Add("帳票の項目、順序またはページ構成が異なります。");
                }
                else if (id == "PL-222" && legacyReports == 1)
                {
                    string path = EvidenceFile(evidence, targets.GetProperty("report_files")[0].GetString()!);
                    string contents = File.ReadAllText(path, Encoding.Latin1);
                    if (!new PurchaseLedger(db).HasInvalidAnalysisLength || contents.Count(c => c == '\f') < 2 ||
                        !contents.Contains("\0\0     010000", StringComparison.Ordinal))
                        differences.Add("全件印刷の旧証跡に既知の異常を確認できません。");
                    else
                        differences.Add("旧版はレコード長不一致で開けない分析ファイルを全件読み取りし、同一の不正明細を多数ページに出力しました。移行版では無効レコードを印刷しません。");
                }
                else if (legacyReports != 0)
                    differences.Add("帳票の全項目・改ページの同一性は未確認です。");
            }
        }
        catch (Exception error) when (error is IOException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        {
            differences.Add(error is InvalidOperationException ? error.Message : $"検証手順を完了できませんでした（{error.GetType().Name}）。");
        }
        return differences;
    }

    static void VerifyScheduledPaymentReport(string evidence, JsonElement targets, string referenceDirectory, List<string> differences)
    {
        var legacyPath = EvidenceFile(evidence, targets.GetProperty("report_files")[0].GetString()!);
        var nonblank = File.ReadLines(legacyPath).Select(line => line.Trim()).Where(line => line.Length != 0).ToArray();
        using var before = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(referenceDirectory, "before.json")));
        if (nonblank.Length == 3 && nonblank[0].Contains("Payments Due Proof Report", StringComparison.Ordinal) &&
            !before.RootElement.TryGetProperty("ledgers/acas/pay.dat", out _) &&
            new FileInfo(legacyPath).Length > 1_000_000)
            differences.Add("旧版は支払予定ファイルの開始に失敗（状態35）し、読み取りエラー（状態47）を終端と扱わず、空行を出力し続けます。移行版はファイル欠如を表示し、帳票を作成しません。");
        else
            differences.Add("旧版に支払予定の検証帳票がありますが、移行版にはありません。");
    }

    static void VerifySupplierSetup(Db db, Change[] reference, List<string> differences,
        Dictionary<(string File, string Key), string> before)
    {
        var supplierRows = reference.Where(change => change.File == PurchaseLedger.SupplierFile)
            .ToDictionary(change => change.Key, StringComparer.Ordinal);
        Require(supplierRows.Count == 2 && supplierRows.Values.All(row => row.Before is null), differences,
            "仕入先二件の新規作成を示す証跡がありません。");
        var after = Rows(db);
        var actual = after.Where(row => row.Key.File == PurchaseLedger.SupplierFile).ToArray();
        Require(actual.Length == supplierRows.Count && actual.All(row =>
            supplierRows.TryGetValue(row.Key.Key, out var expected) && expected.After == row.Value), differences,
            "新規作成した仕入先のレコードバイト列が証跡と異なります。");
        Require(before.All(row => after.GetValueOrDefault(row.Key) == row.Value) &&
            after.Keys.All(key => key.File == PurchaseLedger.SupplierFile || before.ContainsKey(key)) && db.Spool().Count == 0,
            differences, "仕入先以外のデータに予期しない変更があります。");
    }

    static void Require(bool condition, List<string> differences, string message)
    {
        if (!condition) differences.Add(message);
    }

    static Dictionary<(string File, string Key), string> Rows(Db db) =>
        db.Snapshot().SelectMany(file => file.Value.Select(row => (Key: (file.Key, row.Key), row.Value))).ToDictionary(row => row.Key, row => row.Value);

    static Change[] RecordChanges(string evidence, JsonElement targets)
    {
        if (targets.GetProperty("keyed_record_diff").GetString() is not { } path) return [];
        using var document = JsonDocument.Parse(File.ReadAllBytes(EvidenceFile(evidence, path)));
        return document.RootElement.GetProperty("changes").EnumerateArray().Select(change =>
            new Change(change.GetProperty("file").GetString()!, change.GetProperty("key").GetString()!,
                Hex(change.GetProperty("before")), Hex(change.GetProperty("after")))).ToArray();

        static string? Hex(JsonElement record) => record.ValueKind == JsonValueKind.Null ? null : record.GetProperty("hex").GetString();
    }

    static string EvidenceFile(string evidence, string relative)
    {
        string root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(evidence)) + Path.DirectorySeparatorChar;
        string file = Path.GetFullPath(Path.Combine(root, relative));
        if (!file.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("証跡範囲外の参照です。");
        return file;
    }

    static (byte[] Key, byte[] Data)[] BTreeRows(string path)
    {
        if (!File.Exists(path)) return [];
        var bytes = File.ReadAllBytes(path);
        if (bytes.Length < 512 || BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(12)) != 0x00053162)
            throw new InvalidOperationException("証跡の索引ファイル形式が異なります。");
        int pageSize = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(20));
        if (pageSize is < 512 or > 32768 || (pageSize & (pageSize - 1)) != 0 || bytes.Length != 2 * pageSize)
            throw new InvalidOperationException("証跡の一ページ索引ファイルではありません。");
        var page = bytes.AsSpan(pageSize);
        int slots = BinaryPrimitives.ReadUInt16LittleEndian(page[20..]);
        if (page[25] != 5 || slots % 2 != 0 || 26 + slots * 2 > pageSize)
            throw new InvalidOperationException("証跡の索引ページが無効です。");
        var records = new (byte[], byte[])[slots / 2];
        for (int i = 0; i < records.Length; i++)
            records[i] = (ReadSlot(page, 2 * i), ReadSlot(page, 2 * i + 1));
        return records;

        static byte[] ReadSlot(ReadOnlySpan<byte> page, int index)
        {
            int offset = BinaryPrimitives.ReadUInt16LittleEndian(page[(26 + index * 2)..]);
            if (offset < 26 || offset > page.Length - 3 || page[offset + 2] != 1)
                throw new InvalidOperationException("証跡の索引項目が無効です。");
            int length = BinaryPrimitives.ReadUInt16LittleEndian(page[offset..]);
            return page.Slice(offset + 3, length).ToArray();
        }
    }

    private sealed record Change(string File, string Key, string? Before, string? After);
}
