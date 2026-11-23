using System.Globalization;
using System.Security.Cryptography;
using Acas.Core.Engine;

namespace Acas.Core.Programs.Irs;

public sealed class IrsException(string message) : Exception(message);

public sealed record IrsConfiguration(DateTime Date, string Operator, decimal Tax, string Client,
    string Address1, string Address2, string Address3, string Address4, DateTime? Start, DateTime? End,
    int Platform, string Printer);

public sealed record IrsAccount(int Code, int SubAccount, string Name, string Category, decimal Debit, decimal Credit)
{
    public decimal Balance => Debit - Credit;
}

public sealed record IrsDefault(int Slot, int Account, string Name, string Code, string Tax);
public sealed record IrsJournalEntry(int Number, string Code, DateTime? Date, int Debit, int Credit,
    decimal Amount, string Legend, int TaxDefault, string TaxSide, decimal Tax);

public sealed partial class IrsBookkeeping(Db db, Func<DateTime>? clock = null)
{
    public const string Directory = "ledgers/irs/";
    public const string SharedDirectory = "ledgers/acas/";
    public static bool UsesSharedTransferDirectory(string? setting) =>
        string.Equals(setting?.Replace('\\', '/').TrimEnd('/'), SharedDirectory.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);
    private const string SystemFile = Directory + "system.dat";
    private const string AccountsFile = Directory + "acnts.dat";
    private const string DefaultsFile = Directory + "dflt.dat";
    private const string PostingFile = Directory + "post.dat";
    private const string AnalysisFile = Directory + "analysis.dat";
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;
    private static string Key(int code, int sub = 0) => Cob.P9(code, 5) + Cob.P9(sub, 5);
    public DateTime Today => (clock?.Invoke() ?? DateTime.Today).Date;
    public bool Configured => db.Read(SystemFile, "1") is not null;
    private Rec System => db.Read(SystemFile, "1") is { } bytes
        ? ReadRecord(IrsRecords.System, bytes, 304)
        : IrsRecords.System.New();
    public bool NeedsOpeningBalanceDecision => db.Count(AccountsFile) > 0 && !db.Exists(PostingFile);

    private static Rec ReadRecord(Layout layout, byte[] bytes, int minimum)
    {
        if (bytes.Length < minimum || bytes.Length > layout.Size)
            throw new IrsException("レコード長が一致しません（状態番号39）。");
        var row = layout.New();
        bytes.CopyTo(row.B, 0);
        return row;
    }

    private Rec Account(int code, int sub = 0) =>
        db.Read(AccountsFile, Key(code, sub)) is { } data
            ? ReadRecord(IrsRecords.Account, data, IrsRecords.Account.Size)
            : throw new IrsException("勘定が見つかりません。");

    private Rec Resolve(int code)
    {
        var row = Account(code);
        if (row.S("kind") != "S") return row;
        return Account(Cob.ToInt(row.S("name")[..5]), code);
    }

    private static IrsAccount AccountView(Rec row) => new(row.I("owner"), row.I("child"),
        IrsRecords.Text(row, "name"), row.St("category"), row.N("debit"), row.N("credit"));

    public IReadOnlyList<IrsAccount> Accounts() => db.Scan(AccountsFile)
        .Select(x => ReadRecord(IrsRecords.Account, x.Data, IrsRecords.Account.Size))
        .Where(x => x.S("kind") == "O")
        .Select(AccountView).ToList();

    public IrsConfiguration Configuration()
    {
        var row = System;
        return new(IrsRecords.Date(row.S("date")) ?? Today, IrsRecords.Text(row, "operator"), row.N("tax"),
            IrsRecords.Text(row, "client"), IrsRecords.Text(row, "address1"), IrsRecords.Text(row, "address2"),
            IrsRecords.Text(row, "address3"), IrsRecords.Text(row, "address4"), IrsRecords.Date(row.S("start")),
            IrsRecords.Date(row.S("end")), row.I("platform"), IrsRecords.Text(row, "spool"));
    }

    public bool CheckPassword(string password)
    {
        var row = System;
        var field = row.L.F["password"];
        byte[] bytes = IrsRecords.Encode(password, field.Len);
        byte[] entered = [(byte)' ', (byte)' ', (byte)' ', (byte)' '];
        bytes.CopyTo(entered, 0);
        return CryptographicOperations.FixedTimeEquals(entered, row.B.AsSpan(field.Off, field.Len));
    }

    public void Configure(IrsConfiguration configuration, string oldPassword, string newPassword)
    {
        if (!CheckPassword(oldPassword)) throw new IrsException("暗証番号が一致しません。");
        if (configuration.Start is not DateTime start || configuration.End is not DateTime end ||
            configuration.Platform is < 1 or > 6 || configuration.Tax is < 0 or > 99.99m)
            throw new IrsException("会計期間、税率、稼働環境を確認してください。");
        var row = System;
        foreach (var (field, value) in new (string, string)[]
        {
            ("operator", configuration.Operator), ("client", configuration.Client),
            ("address1", configuration.Address1), ("address2", configuration.Address2),
            ("address3", configuration.Address3), ("address4", configuration.Address4),
            ("spool", configuration.Printer)
        })
            IrsRecords.Text(row, field, value);

        row.Set("date", IrsRecords.DateText(configuration.Date));
        row.Set("start", IrsRecords.DateText(start));
        row.Set("end", IrsRecords.DateText(end));
        row.Set("files", "acnts.datsystem.datdflt.datpost.dat" + "prn".PadRight(13));
        row.SetN("platform", configuration.Platform);
        row.SetN("tax", configuration.Tax);
        IrsRecords.Text(row, "password", newPassword);
        row.Set("workgroup", "");
        foreach (var field in new[] { "passwordLevel", "save", "first" }) row.SetN(field, 0);
        SaveSystem(row);
    }

    private void SaveSystem(Rec row)
    {
        int size = row.B.Length;
        while (size > 304 && row.B[size - 1] == ' ') size--;
        db.Put(SystemFile, "1", row.B[..size]);
    }

    public void ClearBalances()
    {
        foreach (var (key, data) in db.Scan(AccountsFile))
        {
            var row = ReadRecord(IrsRecords.Account, data, IrsRecords.Account.Size);
            if (row.S("kind") != "O") continue;
            foreach (string side in new[] { "debit", "credit" })
            {
                row.SetN(side, 0);
                for (int i = 1; i <= 4; i++) row.SetN(side + i, 0);
            }
            db.Rewrite(AccountsFile, key, row.B);
        }
    }

    public void SaveAccount(int code, int sub, string name, string category, bool amend, bool reset = false)
    {
        if (code is < 1 or > 99999 || sub is < 0 or > 99999 || code == sub ||
            category.Length != 1 || category[0] is < 'A' or > 'Z')
            throw new IrsException("勘定コードまたは勘定区分が正しくありません。");

        var key = Key(code, sub);
        var row = amend ? Account(code, sub) : IrsRecords.Account.New();
        if (amend && row.S("kind") != "O") throw new IrsException("親勘定から補助勘定を指定してください。");
        if (!reset && !amend && db.Read(AccountsFile, key) is not null) throw new IrsException("勘定が既に存在します。");
        if (!amend && sub != 0 && (reset || Account(code).S("kind") != "O" || db.Read(AccountsFile, Key(sub)) is not null))
            throw new IrsException("補助勘定コードが既に使用されています。");

        row.SetN("owner", code);
        row.SetN("child", sub);
        row.Set("kind", "O");
        IrsRecords.Text(row, "name", name);
        row.Set("category", category);
        if (reset) db.Recreate(AccountsFile);
        db.Put(AccountsFile, key, row.B);
        if (amend || sub == 0) return;
        row.SetN("owner", sub);
        row.SetN("child", 0);
        row.Set("kind", "S");
        var pointer = global::System.Text.Encoding.ASCII.GetBytes(Cob.P9(code, 5));
        pointer.CopyTo(row.B, row.L.F["name"].Off);
        db.Put(AccountsFile, Key(sub), row.B);
    }

    private Rec DefaultRecord(bool reset = false)
    {
        if (!reset && db.Read(DefaultsFile, "1") is { } bytes)
            return ReadRecord(IrsRecords.Defaults, bytes, IrsRecords.Defaults.Size);
        var row = IrsRecords.Defaults.New();
        for (int i = 1; i <= 32; i++)
        {
            row.Set("code" + i, i switch { 30 => "OB", 31 => "VI", 32 => "VO", _ => "00" });
            row.Set("tax" + i, i >= 30 ? "N" : "0");
        }
        return row;
    }

    public IReadOnlyList<IrsDefault> Defaults(bool reset = false) => Defaults(DefaultRecord(reset));

    private IReadOnlyList<IrsDefault> Defaults(Rec row) => Enumerable.Range(1, 32).Select(i =>
    {
        int code = row.I("account" + i);
        string name = code == 0 ? "" : AccountName(code);
        return new IrsDefault(i, code, name, row.St("code" + i), row.St("tax" + i));
    }).ToList();

    private string AccountName(int code) => db.Read(AccountsFile, Key(code)) is null
        ? "" : IrsRecords.Text(Resolve(code), "name");

    public void SaveDefaults(IEnumerable<IrsDefault> updates, bool reset)
    {
        var row = DefaultRecord(reset);
        foreach (var entry in updates)
        {
            if (entry.Slot is < 1 or > 32 || entry.Account is < 0 or > 99999)
                throw new IrsException("既定勘定の番号が正しくありません。");
            if (entry.Account != 0) _ = Resolve(entry.Account);
            int i = entry.Slot;
            row.SetN("account" + i, entry.Account);
            if (i < 30 && entry.Account != 0)
            {
                string code = entry.Code.ToUpperInvariant();
                if (code.Length != 2 || code.Any(x => !char.IsAsciiLetterOrDigit(x)) || entry.Tax is not ("I" or "N" or "O"))
                    throw new IrsException("取引区分または付加価値税区分が正しくありません。");
                row.Set("code" + i, code);
                row.Set("tax" + i, entry.Tax);
            }
        }
        db.Put(DefaultsFile, "1", row.B);
    }
}
