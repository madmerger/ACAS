using System.Text;
using Acas.Core.Engine;

namespace Acas.Core;

public enum AccountError { None, InvalidCode, ReservedCode, TradeCode, InvalidDivision, InvalidName,
    InvalidType, InvalidPlacement, InvalidLevel, MissingHeader, MissingAccount, Duplicate, NonzeroBalance }

public readonly record struct AccountCode(int Ledger, int Sub, int Division = 0)
{
    public string Number => FormattableString.Invariant($"{Ledger:0000}{Sub:00}");
    public string Key => Number + Division.ToString("00", System.Globalization.CultureInfo.InvariantCulture);
}

public sealed record Account(AccountCode Code, string Name, int Type, char Placement, int Level, decimal Balance = 0);

public sealed class GeneralLedger(Db database)
{
    public const string LedgerFile = "ledgers/acas/ledger.dat";

    public IReadOnlyList<Account> Accounts() => database.Scan(LedgerFile)
        .Where(row => !row.Key.StartsWith("9999", StringComparison.Ordinal))
        .Select(row => Decode(row.Data)).ToArray();

    public Account? Find(AccountCode code) => database.Read(LedgerFile, code.Key) is { } bytes ? Decode(bytes) : null;

    public AccountError Register(Rec system, Account account)
    {
        var code = account.Code;
        if (code.Ledger is < 1000 or > 9999 || code.Sub is < 0 or > 99) return AccountError.InvalidCode;
        if (code.Ledger == 9999) return AccountError.ReservedCode;
        if (code.Ledger / 1000 == system.I("Sales-Range") || code.Ledger / 1000 == system.I("Purchase-Range")) return AccountError.TradeCode;
        if (!ValidDivision(system, code.Division)) return AccountError.InvalidDivision;
        if (!Fits(account.Name, 24)) return AccountError.InvalidName;
        if (Find(code) != null) return AccountError.Duplicate;

        var record = Layouts.Ledger.New();
        if (code.Sub == 0)
        {
            var error = ValidateClassification(system, account);
            if (error != AccountError.None) return error;
            int interval = code.Ledger % 1000 == 0 ? 1000 : code.Ledger % 100 == 0 ? 100 : code.Ledger % 10 == 0 ? 10 : 1;
            int level = interval == 1000 ? 1 : interval == 100 ? 2 : interval == 10 ? 3 : 4;
            int parent = code.Ledger / (interval * 10) * (interval * 10);
            if (level != 1 && Find(new AccountCode(parent, 0, code.Division)) == null) return AccountError.MissingHeader;
            record.SetN("type", account.Type);
            if (account.Type == 0) record.Set("place", account.Placement.ToString());
            record.SetN("level", level);
        }
        else
        {
            var header = Find(code with { Sub = 0 });
            if (header == null) return AccountError.MissingHeader;
            record.SetN("type", header.Type == 9 ? 9 : 1);
            record.Set("place", header.Placement.ToString());
        }
        record.Set("nos", code.Number);
        record.Set("name", account.Name);
        database.Atomic(() =>
        {
            EnsureLedgerFile();
            foreach (int division in Divisions(code))
            {
                record.SetN("pc", division);
                database.Write(LedgerFile, (code with { Division = division }).Key, record.B);
            }
        });
        return AccountError.None;
    }

    public AccountError Amend(Rec system, Account account)
    {
        if (!ValidDivision(system, account.Code.Division)) return AccountError.InvalidDivision;
        if (!Fits(account.Name, 24)) return AccountError.InvalidName;
        var error = ValidateClassification(system, account);
        if (error != AccountError.None) return error;
        var code = account.Code;
        if (code.Ledger is < 1000 or >= 9999 || database.Read(LedgerFile, code.Key) is not { } bytes)
            return AccountError.MissingAccount;
        var record = Layouts.Ledger.From(bytes);
        record.Set("name", account.Name);
        record.SetN("type", account.Type);
        if (account.Type == 0)
        {
            record.Set("place", account.Placement.ToString());
            record.SetN("level", account.Level);
        }
        database.Atomic(() =>
        {
            foreach (int division in Divisions(code))
            {
                record.SetN("pc", division);
                database.Put(LedgerFile, (code with { Division = division }).Key, record.B);
            }
        });
        return AccountError.None;
    }

    public AccountError Delete(AccountCode code)
    {
        var record = Find(code);
        if (code.Ledger is < 1000 or >= 9999 || record == null) return AccountError.MissingAccount;
        if (record.Balance != 0) return AccountError.NonzeroBalance;
        database.Atomic(() =>
        {
            foreach (int division in Divisions(code)) database.Delete(LedgerFile, (code with { Division = division }).Key);
        });
        return AccountError.None;
    }

    private bool ValidDivision(Rec system, int division)
    {
        if (division == 0) return true;
        if (division is < 1 or > 99 || system.S("P-C") is not ("P" or "B")) return false;
        var codes = database.Read(LedgerFile, "99999900");
        return codes != null && codes.Length > 7 + division && codes[7 + division] is (byte)'E' or (byte)'Y';
    }

    private static IEnumerable<int> Divisions(AccountCode code) => code.Division == 0 ? [0] : [code.Division, 0];

    private void EnsureLedgerFile()
    {
        if (database.Exists(LedgerFile)) return;
        var management = Layouts.Ledger.New();
        management.SetN("nos", 999999);
        management.SetN("pc", 99);
        Array.Clear(management.B, 16, 24);
        database.Write(LedgerFile, "99999999", management.B);
    }

    private static Account Decode(byte[] bytes)
    {
        var r = Layouts.Ledger.From(bytes);
        int number = r.I("nos");
        return new Account(new AccountCode(number / 100, number % 100, r.I("pc")), r.St("name"),
            r.I("type"), r.S("place")[0], r.I("level"), r.N("balance"));
    }

    private static AccountError ValidateClassification(Rec system, Account account)
    {
        if (account.Type is not (0 or 1 or 9)) return AccountError.InvalidType;
        if (account.Type != 0) return AccountError.None;
        if (account.Placement is < 'A' or > 'Z' ||
            (account.Code.Division != 0 && system.S("P-C-Level") == "R" && account.Placement > 'N')) return AccountError.InvalidPlacement;
        return account.Level is < 1 or > 4 ? AccountError.InvalidLevel : AccountError.None;
    }

    internal static bool Fits(string value, int width) => value.Length <= width && value.All(c => c is >= ' ' and <= '\u00ff');
}
