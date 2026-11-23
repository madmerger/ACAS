using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Acas.App;
using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Purchase;

if (args.Length != 3)
{
    Console.Error.WriteLine("使用方法：台帳のパス、証跡のルート、結果の出力先を指定してください。");
    return 2;
}

using var ledger = JsonDocument.Parse(File.ReadAllBytes(args[0]));
var results = ledger.RootElement.GetProperty("cases").EnumerateArray()
    .Where(data => data.GetProperty("id").GetString()!.StartsWith("PL-", StringComparison.Ordinal))
    .Select(data => Check(data, args[1])).ToArray();
File.WriteAllText(args[2], JsonSerializer.Serialize(results, new JsonSerializerOptions
{
    WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
}));
foreach (var result in results.Where(result => result.Verdict == "不一致"))
    Console.WriteLine($"{result.Id}：{string.Join("／", result.Differences)}");
Console.WriteLine($"一致 {results.Count(result => result.Verdict == "一致")} / 不一致 {results.Count(result => result.Verdict == "不一致")} / 対象外 {results.Count(result => result.Verdict == "対象外")}");
return results.Any(result => result.Verdict == "不一致") ? 1 : 0;

static Result Check(JsonElement entry, string evidence)
{
    string id = entry.GetProperty("id").GetString()!;
    var legacy = entry.GetProperty("legacy_result");
    if (legacy.GetProperty("verdict").GetString() == "未実施") return new(id, "対象外", []);
    var targets = legacy.GetProperty("comparison_targets");
    List<string> differences = [];
    try
    {
        using var db = new Db();
        db.LoadBaseline(entry.GetProperty("baseline").GetString()!);
        string? referenceDirectory = targets.GetProperty("keyed_record_diff").GetString() is { } diffPath
            ? Path.GetDirectoryName(EvidenceFile(evidence, diffPath)) : null;
        if (referenceDirectory != null)
            foreach (var row in BTreeRows(Path.Combine(referenceDirectory, "before-files", PurchaseLedger.AnalysisFile)))
                db.Put(PurchaseLedger.AnalysisFile, Encoding.ASCII.GetString(row.Key), row.Data);
        var before = Rows(db);
        var reference = RecordChanges(evidence, targets);
        if (id == "PL-090")
        {
            VerifySupplierSetup(db, reference, differences);
        }
        else
        {
            Exercise(entry, id, db, differences);
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
            if (legacyReports != appReports) differences.Add($"帳票数が異なります（既存 {legacyReports}、移行 {appReports}）。");
            else if (id == "PL-232" && legacyReports == 1)
                VerifyScheduledPaymentReport(evidence, targets, db, differences);
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
    return new(id, differences.Count == 0 ? "一致" : "不一致", differences);
}

static void Exercise(JsonElement entry, string id, Db db, List<string> differences)
{
    var root = PurchaseNavigation(db);
    var path = entry.GetProperty("menu_path").EnumerateArray().Skip(1).Select(part => part.GetString()!).ToArray();
    var date = new DateTime(2026, 11, 23);
    var screen = PurchaseScreenAudit.Check(root.Open!());
    if (id == "PL-241")
    {
        Require(screen is FormScreen form && form.Fields.OfType<DateField>().Any(field => field.Id == "PurchaseProcessingDate"), differences,
            "開始時の処理日入力が表示されません。");
        return;
    }
    screen = Submit(screen, ("PurchaseProcessingDate", date));
    if (path.Length > 0) screen = Open(screen, path[0]);
    if (path.Length > 1) screen = Open(screen, path[0] + path[1]);

    switch (id)
    {
        case "PL-400":
            screen = Submit(screen, ("PurchaseSupplierCode", "SUPP018"));
            screen = Accept(Submit(screen, ("PurchaseSupplierName", "EQUIV UPDATED SUPPLIER")));
            Require(screen is InformationScreen { Message: "仕入先を保存しました。" }, differences, "仕入先の更新が完了していません。");
            return;
        case "PL-401":
            screen = Submit(screen, ("PurchaseSupplierCode", "SUPP026"));
            screen = Accept(Submit(screen, ("PurchaseSupplierRemovalAction", "remove")));
            Require(screen is InformationScreen { Message: "仕入先を削除しました。" }, differences, "仕入先の削除が完了していません。");
            return;
        case "PL-403":
            screen = Submit(screen, ("PurchaseSupplierCode", "TEST01"));
            screen = Accept(Submit(screen, ("PurchaseSupplierName", "EQUIV NEW SUPPLIER"), ("PurchaseSupplierAddressFirst", @"1 TEST ROAD\LONDON\UK")));
            Require(screen is InformationScreen { Message: "仕入先を保存しました。" }, differences, "仕入先の登録が完了していません。");
            return;
        case "PL-402":
            screen = Submit(screen, ("PurchaseSupplierCode", "MISS001"));
            Require(screen is InformationScreen { Message: "仕入先が見つかりません。" }, differences, "不存在仕入先が拒否されません。");
            return;
        case "PL-410":
            screen = Submit(screen, ("PurchaseAnalysisCode", "Z"));
            if (screen is FormScreen)
                screen = Accept(Submit(screen, ("PurchaseAnalysisAccount", "500001"), ("PurchaseAnalysisDescription", "PURCHASES"), ("PurchaseAnalysisReference", "P")));
            Require(screen is InformationScreen { Message: "分析ファイルのレコード長が定義と一致しません。" }, differences,
                "既存の分析ファイルが定義と異なる長さで開けない挙動を再現できません。");
            return;
        case "PL-411":
            screen = Submit(screen, ("PurchaseInvoiceSupplier", "SUPP018"), ("PurchaseInvoiceOrder", "PL-ORDER"), ("PurchaseInvoiceReference", "PL-REF"));
            screen = MenuAction(screen, "PurchaseInvoiceAddLine");
            screen = Submit(screen, ("PurchaseLineAnalysis", "a1"), ("PurchaseLineNet", "100.00"), ("PurchaseLineTaxCode", "1"), ("PurchaseLineTax", "20.00"));
            screen = MenuAction(screen, "PurchaseInvoiceTotals");
            screen = Accept(Submit(screen));
            Require(screen is InformationScreen { Message: "仕入取引を保存しました。" }, differences, "仕入伝票の登録が完了していません。");
            return;
        case "PL-412":
            screen = Submit(screen, ("PurchaseInvoiceSupplier", "MISS001"));
            Require(screen is InformationScreen { Message: "仕入先が見つかりません。" }, differences, "不存在仕入先が拒否されません。");
            return;
        case "PL-413":
            screen = Submit(screen);
            Require(screen is ReportScreen report && report.Body.Contains("ALPHA SUPPLIER", StringComparison.Ordinal)
                && report.Body.Contains("120.00", StringComparison.Ordinal), differences, "仕入検証帳票に仕入先と合計がありません。");
            return;
        case "PL-414":
            screen = Accept(Submit(screen));
            Require(screen is ReportScreen, differences, "仕入転記帳票が作成されません。");
            return;
    }

    string operation = string.Concat(path);
    bool same = operation switch
    {
        "" => screen is MenuScreen menu && menu.Items.Count == 24,
        "A" => HasField(screen, "PurchaseProcessingDate"),
        "B" => screen is MenuScreen suppliers && suppliers.Items.Select(item => item.Number).SequenceEqual((int?[])[1, 2, 3, 4, 5, 9]),
        "B1" or "B2" or "B3" or "B5" => HasField(screen, "PurchaseSupplierCode"),
        "B4" or "Q" or "V" => HasField(screen, "PurchaseSupplierReportStatus"),
        "R" => screen is FormScreen turnover && turnover.Fields.Any(field =>
            field.Id == "PurchaseSupplierReportActivity" && field.Label == "請求件数"),
        "C" or "I" or "J" or "K" or "P" => screen is InformationScreen { Message: "未決済明細ファイルがありません。" },
        "D" => HasField(screen, "PurchaseInvoiceDate") && HasField(screen, "PurchaseInvoiceSupplier"),
        "E" => HasField(screen, "PurchaseInvoiceFolio"),
        "F" or "O" => screen is InformationScreen { Message: "仕入伝票ファイルがありません。" },
        "G" => screen is InformationScreen { Message: "検証する仕入取引がありません。" },
        "H" => screen is InformationScreen { Message: "転記する仕入取引がありません。" },
        "L" => screen is InformationScreen { Message: "転記待ちの支払がありません。" },
        "M" => screen is MenuScreen analysis && analysis.Items.Select(item => item.Number).SequenceEqual((int?[])[1, 2, 3, 4, 5, 9]),
        "M1" or "M2" => HasField(screen, "PurchaseAnalysisCode"),
        "M3" or "M4" => Accept(screen) is ReportScreen,
        "M5" => screen is TableScreen { Id: "PurchaseAnalysisList" },
        "N" => screen is InformationScreen { Message: "集計データがありません。" },
        "S" or "S6" => screen is MenuScreen cheques && cheques.Items.Select(item => item.Number).SequenceEqual((int?[])[1, 2, 3, 4, 5, 6, 9]),
        "S1" => HasField(screen, "PurchaseChequeAge"),
        "S2" => HasField(screen, "PurchaseChequeSupplier"),
        "S3" => screen is ReportScreen { Title: "支払予定の検証" },
        "S4" => screen is InformationScreen { Message: "処理するデータがありません。" },
        "S5" => Submit(screen) is ConfirmationScreen,
        "T" => Submit(screen) is ConfirmationScreen,
        "U" => HasField(screen, "PurchaseNextFolio"),
        "X" => screen is InformationScreen { Message: "買掛元帳を閉じました。" },
        "Z" => HasField(screen, "PurchaseSetupUsera") && HasField(screen, "PurchaseSetupStartDate") &&
            HasField(screen, "PurchaseSetupPageLines") && HasField(screen, "PurchaseSetupTax5"),
        _ => false
    };
    Require(same, differences, "証跡に対応する画面状態または処理に到達していません。");
}

static void VerifyScheduledPaymentReport(string evidence, JsonElement targets, Db db, List<string> differences)
{
    var legacyPath = EvidenceFile(evidence, targets.GetProperty("report_files")[0].GetString()!);
    var nonblank = File.ReadLines(legacyPath).Select(line => line.Trim()).Where(line => line.Length != 0).ToArray();
    var body = db.Spool().Single().Body;
    var lines = body.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
    Require(nonblank.Length >= 3 && nonblank[0].Contains("Payments Due Proof Report", StringComparison.Ordinal) &&
        nonblank[0].EndsWith("Page   1", StringComparison.Ordinal) && lines.Contains("ページ 1") &&
        lines.Length >= 3 && nonblank[1].StartsWith(lines[1], StringComparison.Ordinal) &&
        nonblank[1].EndsWith("23/11/2026", StringComparison.Ordinal) && lines[2] == "処理日　2026年11月23日" &&
        nonblank[2] == "Folio M    Date     Invoice      Current       30 +        60 +        90 +       Total to Pay" &&
        lines.Contains("伝票番号　支払方法　支払日　請求書番号") && lines.Contains("当期　30日以上　60日以上　90日以上　支払額"),
        differences, "支払予定検証帳票の表題、事業者、処理日、ページ番号、列見出しが異なります。");
    if (nonblank.Length == 3 && !File.Exists(Path.Combine(Path.GetDirectoryName(legacyPath)!, "pay.dat")) &&
        new FileInfo(legacyPath).Length > 1_000_000)
        differences.Add("旧版の証跡は支払予定ファイルがなく、見出しの後に大量の空行が続き、合計欄・完了時の改ページを確認できません。移行版はゼロ件の合計を出力して終了します。");
    else
        differences.Add("支払予定検証帳票の明細・合計・改ページは未照合です。");
}

static void VerifySupplierSetup(Db db, Change[] reference, List<string> differences)
{
    var supplierRows = reference.Where(change => change.File == PurchaseLedger.SupplierFile)
        .ToDictionary(change => change.Key, StringComparer.Ordinal);
    Require(supplierRows.Count == 2 && supplierRows.Values.All(row => row.Before is null), differences,
        "仕入先二件の新規作成を示す証跡がありません。");
    db.Remove(PurchaseLedger.SupplierFile);
    var before = Rows(db);
    var root = PurchaseNavigation(db);
    var menu = Submit(PurchaseScreenAudit.Check(root.Open!()), ("PurchaseProcessingDate", new DateTime(2026, 11, 23)));
    menu = Accept(Submit(Open(menu, "Z")));
    var suppliers = Open(menu, "B");
    foreach (var (code, name, address) in new[]
    {
        ("SUPP01", "ALPHA SUPPLIER", @"1 SUPPLY ROAD\LONDON\UK"),
        ("SUPP02", "BETA SUPPLIER", @"2 SUPPLY ROAD\LONDON\UK")
    })
    {
        var form = Submit(Open(suppliers, "B1"), ("PurchaseSupplierCode", code));
        var result = Accept(Submit(form, ("PurchaseSupplierName", name), ("PurchaseSupplierAddressFirst", address)));
        Require(result is InformationScreen { Message: "仕入先を保存しました。" }, differences, $"仕入先 {code} の登録が完了していません。");
    }
    var after = Rows(db);
    var actual = after.Where(row => row.Key.File == PurchaseLedger.SupplierFile).ToArray();
    Require(actual.Length == supplierRows.Count && actual.All(row =>
        supplierRows.TryGetValue(row.Key.Key, out var expected) && expected.After == row.Value), differences,
        "新規作成した仕入先のレコードバイト列が証跡と異なります。");
    Require(before.All(row => after.GetValueOrDefault(row.Key) == row.Value) &&
        after.Keys.All(key => key.File == PurchaseLedger.SupplierFile || before.ContainsKey(key)) && db.Spool().Count == 0,
        differences, "仕入先以外のデータに予期しない変更があります。");
}

static bool HasField(Screen screen, string id) => screen is FormScreen form && form.Fields.Any(field => field.Id == id);
static MenuItem PurchaseNavigation(Db db) => PurchaseScreenAudit.Navigation(
    SubsystemScreens.Load(typeof(MainWindow).Assembly, db).Single(menu => menu.Id == "PurchaseNavigation"));
static void Require(bool condition, List<string> differences, string message)
{
    if (!condition) differences.Add(message);
}

static Screen Open(Screen screen, string code) => MenuAction(screen, "PurchaseMenu" + code);

static Screen MenuAction(Screen screen, string id) => screen is MenuScreen menu
    ? PurchaseScreenAudit.Check(menu.Items.Single(item => item.Id == id).Open!())
    : throw new InvalidOperationException("操作一覧が表示されていません。");

static Screen Submit(Screen screen, params (string Id, object? Value)[] overrides)
{
    if (screen is not FormScreen form) throw new InvalidOperationException("入力画面が表示されていません。");
    var values = form.Fields.ToDictionary(field => field.Id, field => field switch
    {
        TextField text => text.Value,
        ChoiceField choice => choice.Value,
        DateField date => (object?)date.Value,
        _ => throw new InvalidOperationException("未対応の入力項目です。")
    });
    foreach (var (id, value) in overrides)
    {
        if (!values.ContainsKey(id)) throw new InvalidOperationException("入力項目が見つかりません。");
        values[id] = value;
    }
    return PurchaseScreenAudit.Check(form.Submit(new FormValues(values)));
}

static Screen Accept(Screen screen) => screen is ConfirmationScreen confirmation
    ? PurchaseScreenAudit.Check(confirmation.Confirm()) : throw new InvalidOperationException("確認画面が表示されていません。");

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

internal sealed record Result(string Id, string Verdict, IReadOnlyList<string> Differences);
internal sealed record Change(string File, string Key, string? Before, string? After);
