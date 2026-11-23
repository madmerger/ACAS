using Acas.Core.Engine;

namespace Acas.Core.Programs.Purchase;

public sealed partial class PurchaseLedger(Db database)
{
    public const string SystemFile = "ledgers/acas/system.dat";
    public const string SupplierFile = "ledgers/acas/purchled.dat";
    private const string DeliveryFile = "ledgers/acas/delivery.dat";
    private const string SystemKey = "00000001";
    private static readonly DateTime Epoch = new(1600, 12, 31);

    private static readonly Layout SupplierLayout = new Layout().X("key", 7).N9("status", 1).N9("notes", 1)
        .X("name", 30).X("address1", 48).X("address2", 48).X("phone", 13).X("extension", 4).X("fax", 13)
        .X("email", 30).Comp("discount", 2, 2).BChar("credit").BLong("sort").BLong("account")
        .BLong("limit").BLong("activity").BLong("lastInvoice").BLong("lastPayment").BLong("average")
        .BLong("created").BLong("payActivity").BLong("payAverage").BLong("payWorst")
        .C3("current", 8, 2).C3("last", 8, 2).Group(4, (layout, index) => layout.C3("q" + index, 8, 2))
        .C3("unapplied", 8, 2).Fill(16);
    private static readonly Layout NoteLayout = new Layout().X("key", 8).X("name", 30).X("note1", 48).X("note2", 48);

    public bool IsConfigured => database.Read(SystemFile, SystemKey) != null;
    public Rec System() => Layouts.System.From(database.Read(SystemFile, SystemKey) ?? throw new InvalidOperationException("初期設定が必要です。"));
    public void SaveSystem(Rec record) => database.Rewrite(SystemFile, SystemKey, record.B);
    public DateTime? ProcessingDate => IsConfigured ? DecodeDate(System().I("Run-Date")) : null;
    public static int EncodeDate(DateTime date) => (date.Date - Epoch).Days;
    public static DateTime? DecodeDate(int date) => date > 0 && date <= EncodeDate(DateTime.MaxValue) ? Epoch.AddDays(date) : null;

    public static string? SupplierKey(string value)
    {
        string code = value.Trim().ToUpperInvariant();
        if (code.Length != 6) return null;
        const string alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-";
        int sum = 0;
        for (int i = 0; i < code.Length; i++)
        {
            int position = alphabet.IndexOf(code[i]);
            if (position < 0) return null;
            sum += (position + 1) * (7 - i);
        }
        return code + ((11 - sum % 11) % 10);
    }

    public static bool FitsRecord(string value, int width) => value.Length <= width && value.All(c => c is >= ' ' and <= 'ÿ' && c is not (>= '\u007f' and <= '\u009f'));

    public Rec? GetSupplier(string key) => database.Read(SupplierFile, key) is { Length: 300 } value ? SupplierLayout.From(value) : null;
    public IEnumerable<Rec> Suppliers() => database.Scan(SupplierFile).Where(row => row.Data.Length == 300)
        .Select(row => SupplierLayout.From(row.Data));

    public Rec NewSupplier(string key)
    {
        var record = SupplierLayout.New();
        var system = System();
        record.Set("key", key);
        record.SetN("status", 1);
        record.SetN("created", system.N("Run-Date"));
        record.SetN("credit", system.N("Age-To-Pay"));
        return record;
    }

    public bool ValidAddress(string first, string second)
    {
        char separator = System().S("PL-Delim")[0];
        var address = first.PadRight(48) + second.PadRight(48);
        return address.Count(c => c == separator) is >= 1 and <= 4 && address.IndexOf(separator) is >= 0 and <= 30;
    }

    public (string First, string Second) Notes(string key)
    {
        var bytes = database.Read(DeliveryFile, "N" + key);
        if (bytes is null) return ("", "");
        var note = NoteLayout.From(bytes);
        return (note.St("note1"), note.St("note2"));
    }

    public bool SaveSupplier(Rec record, bool create, string firstNote, string secondNote) =>
        database.ExecuteAtomically(() => WriteSupplier(record, create, firstNote, secondNote));

    private bool WriteSupplier(Rec record, bool create, string firstNote, string secondNote)
    {
        string key = record.St("key");
        string noteKey = "N" + key;
        bool hasNotes = !string.IsNullOrWhiteSpace(firstNote) || !string.IsNullOrWhiteSpace(secondNote);
        record.SetN("notes", hasNotes ? 1 : 0);
        if (!(create ? database.Write(SupplierFile, key, record.B) : database.Rewrite(SupplierFile, key, record.B)))
            return false;
        if (create && database.Read(SystemFile, SystemKey) is { } raw)
        {
            var system = Layouts.System.From(raw);
            if (system.S("Purchase-Ledger") != "Y")
            {
                database.Create(DeliveryFile);
                system.Set("Purchase-Ledger", "Y");
                system.SetN("File-Status-14", 1);
                system.SetN("File-Status-22", 1);
                database.Put(SystemFile, SystemKey, system.B);
            }
        }
        if (hasNotes)
        {
            var note = NoteLayout.New();
            note.Set("key", noteKey);
            note.Set("note1", firstNote);
            note.Set("note2", secondNote);
            database.Put(DeliveryFile, noteKey, note.B);
        }
        else
        {
            database.Delete(DeliveryFile, noteKey);
        }
        return true;
    }

    public static bool CanRemove(Rec record) => record.N("current") == 0 && record.N("unapplied") == 0;

    public bool RemoveSupplier(string key, bool deactivate) => database.ExecuteAtomically(() => RemoveSupplierRecord(key, deactivate));

    private bool RemoveSupplierRecord(string key, bool deactivate)
    {
        var record = GetSupplier(key);
        if (record is null || !CanRemove(record)) return false;
        if (deactivate)
        {
            record.SetN("status", 0);
            return database.Rewrite(SupplierFile, key, record.B);
        }
        if (record.N("notes") != 0) database.Delete(DeliveryFile, "N" + key);
        return database.Delete(SupplierFile, key);
    }

    public ReportScreen Report(string title, string body, Func<Screen>? back = null)
    {
        database.AddSpool(title, body);
        return new ReportScreen(title, body, back);
    }
}
