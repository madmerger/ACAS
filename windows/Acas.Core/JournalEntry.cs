using System.Globalization;
using Acas.Core.Engine;

namespace Acas.Core;

public enum JournalError { None, Setup, Number, Default, Cycle, Header, Line, ExistingRecord }

public sealed record JournalHeader(int Number, DefaultAccount Default, int Division, bool Debit,
    DateTime Date, int Cycle, int Items, decimal Gross, decimal Tax, string Description);

public sealed record JournalLine(DateTime Date, AccountCode Account, decimal Amount, string Description,
    int Rate = 1, string Calculation = "", decimal? Tax = null);

public sealed class JournalEntry(Db database)
{
    public const string BatchFile = "ledgers/acas/batch.dat";
    public const string PostingFile = "ledgers/acas/postings.dat";
    private readonly SystemSettings _settings = new(database);
    private readonly GeneralLedger _ledger = new(database);
    private static readonly DateTime Epoch = new(1600, 12, 31);

    public void Open()
    {
        database.Atomic(() =>
        {
            if (!database.Exists(BatchFile))
            {
                var sentinel = Layouts.Batch.New();
                sentinel.SetN("ledger", 9);
                sentinel.SetN("batch-nos", 99999);
                sentinel.SetN("bcycle", 99);
                database.Write(BatchFile, "999999", sentinel.B);
            }
            if (!database.Exists(PostingFile)) database.Create(PostingFile);
        });
    }

    public JournalError Check(JournalHeader header) => Check(header, _settings.Read());

    public JournalError Check(JournalHeader header, JournalLine line)
    {
        var system = _settings.Read();
        var status = Check(header, system);
        if (status != JournalError.None) return status;
        return MakePosting(header, line, system!, 1) == null ? JournalError.Line : JournalError.None;
    }

    public JournalError CancelSetup(int number)
    {
        var result = JournalError.Number;
        database.Atomic(() =>
        {
            if (_settings.Read() is not { } system || !IsNext(system, number)) return;
            system.SetN("Next-Batch", number + 1);
            database.Put(SystemSettings.SystemFile, "00000001", system.B);
            result = JournalError.None;
        });
        return result;
    }

    public void Discard(JournalHeader header)
    {
        database.Atomic(() =>
        {
            if (_settings.Read() is { } system && Check(header, system) == JournalError.None)
                SaveTemporaryDefault(header.Default);
        });
    }

    public JournalError Save(JournalHeader header, IReadOnlyList<JournalLine> lines)
    {
        var result = JournalError.Line;
        database.Atomic(() =>
        {
            var system = _settings.Read();
            result = Check(header, system);
            if (result != JournalError.None) return;

            int previous = system!.I("Postings");
            if (previous < 0 || lines.Count > short.MaxValue - previous)
            {
                result = JournalError.Number;
                return;
            }
            var entries = lines.Select((line, i) => MakePosting(header, line, system, i + 1)).ToArray();
            if (entries.Any(entry => entry == null))
            {
                result = JournalError.Line;
                return;
            }
            var batchKey = "1" + Cob.P9(header.Number, 5);
            if (database.Read(BatchFile, batchKey) != null ||
                entries.Where((_, i) => database.Read(PostingFile, Cob.P9(previous + i + 2, 8)) != null).Any())
            {
                result = JournalError.ExistingRecord;
                return;
            }

            var batch = Layouts.Batch.New();
            batch.SetN("ledger", 1);
            batch.SetN("batch-nos", header.Number);
            batch.SetN("bcycle", header.Cycle);
            batch.SetN("entered", (header.Date.Date - Epoch).Days);
            batch.SetN("items", header.Items);
            batch.SetN("input-gross", header.Gross);
            if (system.S("Vat") == "Y") batch.SetN("input-vat", header.Tax);
            batch.Set("description", header.Description);
            batch.SetN("bdefault", header.Default.Number);
            batch.Set("convention", header.Debit ? "DR" : "CR");
            batch.SetN("batch-def-ac", header.Default.Code * 100);
            batch.SetN("batch-def-pc", header.Division);
            batch.Set("batch-def-code", header.Default.Reference);
            batch.Set("batch-def-vat", header.Default.Tax);
            batch.SetN("batch-start", previous + 1);
            database.Write(BatchFile, batchKey, batch.B);
            for (int i = 0; i < entries.Length; i++)
                database.Write(PostingFile, Cob.P9(previous + i + 2, 8), entries[i]!.B);
            system.SetN("Next-Batch", header.Number + 1);
            system.SetN("Postings", previous + lines.Count);
            database.Put(SystemSettings.SystemFile, "00000001", system.B);
            SaveTemporaryDefault(header.Default);
        });
        return result;
    }

    private JournalError Check(JournalHeader header, Rec? system)
    {
        if (system == null || system.I("Level-1") != 1 || system.I("Cyclea") == 0) return JournalError.Setup;
        if (!IsNext(system, header.Number)) return JournalError.Number;
        if (header.Default.Number is < 1 or > 33 ||
            (header.Default.Number < 33 && _settings.DefaultAccounts()[header.Default.Number - 1] != header.Default) ||
            (header.Default.Number == 33 && header.Default.Tax is not ("I" or "O" or "N")) ||
            !Money(header.Default.Code, 9999.99m) || !GeneralLedger.Fits(header.Default.Reference, 2) ||
            header.Division is < 0 or > 99 || (!HasDivisions(system) && header.Division != 0) ||
            _ledger.Find(AsAccount(header.Default.Code, 0)) == null ||
            _ledger.Find(AsAccount(header.Default.Code, header.Division)) == null)
            return JournalError.Default;
        if (header.Cycle < system.I("Cyclea") || header.Cycle > system.I("Cyclea") + 1 || header.Cycle > 99)
            return JournalError.Cycle;
        if (header.Date.Date <= Epoch || header.Items is < 0 or > 99 || !Money(header.Gross, 999999999.99m) ||
            !Money(header.Tax, 999999999.99m) || !GeneralLedger.Fits(header.Description, 24))
            return JournalError.Header;
        return JournalError.None;
    }

    private Rec? MakePosting(JournalHeader header, JournalLine line, Rec system, int number)
    {
        var code = line.Account;
        if (line.Date.Date <= Epoch || code.Ledger is < 1000 or >= 9999 || code.Sub is < 0 or > 99 ||
            code.Division is < 0 or > 99 || (!HasDivisions(system) && code.Division != 0) ||
            _ledger.Find(code) == null || !Money(line.Amount, 99999999.99m) ||
            !GeneralLedger.Fits(line.Description, 32) || line.Rate is < 1 or > 3 ||
            line.Calculation is not ("" or "P" or "M"))
            return null;

        var defaults = _settings.DefaultAccounts();
        decimal taxAccount = header.Default.Tax switch { "I" => defaults[30].Code, "O" => defaults[31].Code, _ => 0 };
        bool taxBatch = header.Default.Tax is "I" or "O";
        decimal codeAmount = code.Ledger + code.Sub / 100m;
        bool taxOnly = new[] { defaults[30].Code, defaults[31].Code }.Any(v => v == codeAmount || v == header.Default.Code);
        decimal amount = taxOnly ? 0 : line.Amount;
        decimal rate = system.N("Vat-Rate-" + line.Rate);
        decimal tax = taxBatch ? line.Tax ?? (system.S("Vat") == "Y" ? line.Calculation switch
        {
            "P" => Cob.Round(amount * rate / 100, 2),
            "M" when rate > -100 => Cob.Round(amount - amount / (1 + rate / 100), 2),
            _ => 0
        } : 0) : 0;
        if (!Money(tax, 99999999.99m)) return null;
        if (taxBatch && line.Calculation == "M" && system.S("Vat") == "Y" && amount != 0) amount -= tax;
        if (amount < 0 || (amount == 0 && tax == 0)) return null;

        var p = Layouts.Posting.New();
        p.SetN("batch", header.Number);
        p.SetN("post-number", number);
        p.Set("post-code", header.Default.Reference);
        p.Set("post-date", FormatDate(line.Date, system));
        var contra = AsAccount(header.Default.Code, header.Division);
        SetAccount(p, "post-dr", "dr-pc", header.Debit ? code : contra);
        SetAccount(p, "post-cr", "cr-pc", header.Debit ? contra : code);
        p.SetN("post-amount", amount);
        p.Set("post-legend", line.Description);
        p.SetN("vat-ac", taxAccount * 100);
        p.SetN("vat-pc", header.Division);
        p.Set("post-vat-side", header.Debit ? "DR" : "CR");
        p.SetN("vat-amount", tax);
        return p;
    }

    private void SaveTemporaryDefault(DefaultAccount account)
    {
        if (account.Number != 33) return;
        var defaults = Layouts.Default.From(database.Read(SystemSettings.SystemFile, "00000002") ?? Layouts.Default.New().B);
        defaults.SetN("acs33", account.Code);
        defaults.Set("code33", account.Reference);
        defaults.Set("vat33", account.Tax);
        database.Put(SystemSettings.SystemFile, "00000002", defaults.B);
    }

    private static bool IsNext(Rec system, int number) =>
        number == system.I("Next-Batch") && number is >= 0 and < short.MaxValue;
    private static bool HasDivisions(Rec system) => system.S("P-C") is "P" or "B";
    private static bool Money(decimal value, decimal limit) =>
        value >= 0 && value <= limit && Cob.Trunc(value, 2) == value;

    internal static string FormatDate(DateTime date, Rec system) => date.ToString(system.I("Date-Form") switch
    {
        2 => "MM'/'dd'/'yyyy", 3 => "yyyy'/'MM'/'dd", _ => "dd'/'MM'/'yyyy"
    }, CultureInfo.InvariantCulture);

    private static AccountCode AsAccount(decimal value, int division)
    {
        int n = (int)(value * 100);
        return new AccountCode(n / 100, n % 100, division);
    }

    private static void SetAccount(Rec posting, string account, string division, AccountCode code)
    {
        posting.SetN(account, code.Ledger * 100 + code.Sub);
        posting.SetN(division, code.Division);
    }
}
