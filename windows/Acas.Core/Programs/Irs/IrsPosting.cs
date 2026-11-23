using Acas.Core.Engine;

namespace Acas.Core.Programs.Irs;

public sealed partial class IrsBookkeeping
{
    private void EnsureJournal()
    {
        if (!db.Exists(PostingFile))
            throw new IrsException("転記ファイルを開けません（状態番号35）。");
    }

    public IReadOnlyList<IrsJournalEntry> Journal()
    {
        EnsureJournal();
        return db.Scan(PostingFile)
            .Select(x => Entry(ReadRecord(IrsRecords.Journal, x.Data, IrsRecords.Journal.Size))).ToList();
    }

    private static IrsJournalEntry Entry(Rec row) => new(row.I("number"), row.St("code"),
        IrsRecords.Date(row.S("date")), row.I("debit"), row.I("credit"), IrsRecords.Signed(row, "amount"),
        IrsRecords.Text(row, "legend"), row.I("taxDefault"), row.St("taxSide"), IrsRecords.Signed(row, "tax"));

    public void ResetPostings(string password)
    {
        if (!CheckPassword(password)) throw new IrsException("暗証番号が一致しません。");
        var system = System;
        foreach (var (key, data) in db.Scan(AccountsFile))
        {
            var row = ReadRecord(IrsRecords.Account, data, IrsRecords.Account.Size);
            if (row.S("kind") != "O") continue;
            row.SetN("debit", 0);
            row.SetN("credit", 0);
            db.Put(AccountsFile, key, row.B);
        }
        db.Recreate(PostingFile);
        system.SetN("next", 0);
        system.SetN("save", 0);
        SaveSystem(system);
    }

    public IrsJournalEntry Post(int slot, bool creditDefault, DateTime date, int account, decimal amount, string legend, decimal? tax = null)
    {
        if (slot is < 1 or > 32 || account is < 1 or > 99999 ||
            amount == 0 || Math.Abs(amount) > 9999999.99m)
            throw new IrsException("仕訳の既定勘定、金額、転記先勘定を確認してください。");

        var defaults = Defaults();
        var selected = defaults[slot - 1];
        if (selected.Account == 0) throw new IrsException("既定勘定が設定されていません。");
        var system = System;
        if (IrsRecords.Date(system.S("start")) is DateTime start && date.Date < start ||
            IrsRecords.Date(system.S("end")) is DateTime end && date.Date > end)
            throw new IrsException("会計期間内の日付を指定してください。");

        int taxSlot = selected.Tax switch { "I" => 31, "O" => 32, _ => 0 };
        if (slot >= 31 || selected.Account == defaults[30].Account || selected.Account == defaults[31].Account)
            taxSlot = 0;
        decimal vat = taxSlot == 0 ? 0 : tax ?? Cob.Round(amount * system.N("tax") / 100, 2);
        if (Math.Abs(vat) > 9999999.99m)
            throw new IrsException("付加価値税額が有効範囲外です。");

        bool bankCredit = creditDefault != (amount < 0);
        int sequence = system.I("next");
        var row = NewEntry(new(sequence, selected.Code, date,
            bankCredit ? account : selected.Account, bankCredit ? selected.Account : account,
            Math.Abs(amount), legend, taxSlot, bankCredit ? "DR" : "CR", Math.Abs(vat)));
        var updates = new Dictionary<string, Rec>(StringComparer.Ordinal);
        Apply(Entry(row), defaults, updates, 1);
        int next = WritePosting(system, row);
        foreach (var (key, update) in updates) db.Put(AccountsFile, key, update.B);
        return Entry(row) with { Number = next };
    }

    private static Rec NewEntry(IrsJournalEntry entry)
    {
        var row = IrsRecords.Journal.New();
        row.SetN("number", entry.Number);
        row.Set("code", entry.Code);
        row.Set("date", entry.Date is DateTime date ? IrsRecords.DateText(date) : "");
        row.SetN("debit", entry.Debit);
        row.SetN("credit", entry.Credit);
        IrsRecords.Signed(row, "amount", entry.Amount);
        IrsRecords.Text(row, "legend", entry.Legend);
        row.SetN("taxDefault", entry.TaxDefault);
        row.Set("taxSide", entry.TaxSide);
        IrsRecords.Signed(row, "tax", entry.Tax);
        return row;
    }

    private int WritePosting(Rec system, Rec row)
    {
        int sequence = system.I("next");
        for (int i = 0; i < 100000; i++)
        {
            sequence = (sequence + 1) % 100000;
            string key = Cob.P9(sequence, 5);
            row.SetN("number", sequence);
            if (!db.Write(PostingFile, key, row.B)) continue;
            system.SetN("next", sequence);
            system.SetN("save", 0);
            SaveSystem(system);
            return sequence;
        }
        throw new IrsException("転記番号に空きがありません。");
    }

    private void Apply(IrsJournalEntry item, IReadOnlyList<IrsDefault> defaults, Dictionary<string, Rec> updates, int direction)
    {
        void Update(int code, string side, decimal value)
        {
            var account = Resolve(code);
            var key = Key(account.I("owner"), account.I("child"));
            if (!updates.TryGetValue(key, out var update)) updates.Add(key, update = account);
            update.SetN(side, update.N(side) + value * direction);
        }

        bool debitTax = item.TaxSide == "DR";
        Update(item.Debit, "debit", item.Amount + (!debitTax ? item.Tax : 0));
        Update(item.Credit, "credit", item.Amount + (debitTax ? item.Tax : 0));
        if (item.Tax == 0) return;
        if (item.TaxDefault is < 1 or > 32 || defaults[item.TaxDefault - 1].Account == 0)
            throw new IrsException("税の既定勘定が設定されていません。");
        Update(defaults[item.TaxDefault - 1].Account, debitTax ? "debit" : "credit", item.Tax);
    }

    public void AmendPosting(int number, DateTime date, string legend)
    {
        EnsureJournal();
        string key = Cob.P9(number, 5);
        byte[] bytes = db.Read(PostingFile, key) ?? throw new IrsException("転記が見つかりません。");
        var row = ReadRecord(IrsRecords.Journal, bytes, IrsRecords.Journal.Size);
        row.Set("date", IrsRecords.DateText(date));
        IrsRecords.Text(row, "legend", legend);
        db.Rewrite(PostingFile, key, row.B);
    }

    public void Rebuild(string password)
    {
        if (!CheckPassword(password)) throw new IrsException("暗証番号が一致しません。");
        var journal = Journal();
        var defaults = Defaults();
        Dictionary<string, Rec> staged = db.Scan(AccountsFile)
            .Select(x => (x.Key, Record: ReadRecord(IrsRecords.Account, x.Data, IrsRecords.Account.Size)))
            .Where(x => x.Record.St("kind") == "O").ToDictionary(x => x.Key, x => x.Record, StringComparer.Ordinal);
        foreach (var account in staged.Values)
        {
            account.SetN("debit", 0);
            account.SetN("credit", 0);
        }
        foreach (var row in journal) Apply(row, defaults, staged, 1);
        foreach (var (key, row) in staged) db.Rewrite(AccountsFile, key, row.B);
    }

    public int ImportPostings(bool clear, bool shared = false)
    {
        string file = (shared ? SharedDirectory : Directory) + "postings2irs.dat";
        if (!db.Exists(file)) throw new IrsException("連携転記ファイルを開けません（状態番号35）。");
        var entries = db.Scan(file).Select(x =>
        {
            if (x.Data.Length != 5 + IrsRecords.Journal.Size)
                throw new IrsException("連携レコード長が一致しません（状態番号39）。");
            return IrsRecords.Journal.From(x.Data[5..]);
        }).ToArray();
        var defaults = Defaults();
        var accounts = new Dictionary<string, Rec>(StringComparer.Ordinal);
        foreach (var row in entries) Apply(Entry(row), defaults, accounts, 1);
        if (entries.Length > 100000 - db.Count(PostingFile))
            throw new IrsException("転記番号に空きがありません。");
        var system = System;
        foreach (var row in entries) WritePosting(system, row);
        foreach (var (key, account) in accounts) db.Put(AccountsFile, key, account.B);
        if (clear) db.Recreate(file);
        return entries.Length;
    }

    public IReadOnlyList<IrsJournalEntry> Analysis()
    {
        if (db.Scan(AnalysisFile).Any(x => x.Data.Length != 36))
            throw new IrsException("分析ファイルのレコード長が一致しません（状態番号39）。");
        return Journal();
    }
}
