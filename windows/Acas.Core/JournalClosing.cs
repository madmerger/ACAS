using Acas.Core.Engine;

namespace Acas.Core;

public enum ClosingStatus { MissingFiles, OpenBatches, PostingLayoutMismatch }

public sealed partial class JournalBatches
{
    public const string ArchiveFile = "ledgers/acas/archives/archive.dat";

    private static readonly Layout ArchivePosting = new Layout()
        .N9("batch", 5).N9("number", 5).X("code", 2).X("date", 8)
        .X("account", 8).N9("amount", 8, 2, true).X("description", 32).X("contra", 8);

    public ClosingStatus CloseCycle()
    {
        var status = ClosingStatus.MissingFiles;
        database.Atomic(() =>
        {
            if (_settings.Read() is not { } system || !database.Exists(JournalEntry.BatchFile)) return;
            var batches = database.Scan(JournalEntry.BatchFile).Select(b => (b.Key, Batch: Layouts.Batch.From(b.Data)))
                .Where(b => b.Batch.I("bcycle") == system.I("Cyclea")).ToArray();
            if (batches.Any(b => b.Batch.I("batch-status") != 1 && b.Batch.I("cleared-status") != 1))
            {
                status = ClosingStatus.OpenBatches;
                return;
            }
            if (batches.Length != 0 && !database.Exists(JournalEntry.PostingFile)) return;

            bool archive = system.S("Arch") == "Y";
            int archiveRow = 0;
            if (archive)
            {
                database.Create(ArchiveFile);
                archiveRow = database.Scan(ArchiveFile).Select(row => (int)Cob.ToNum(row.Key)).DefaultIfEmpty(0).Max();
            }
            var postings = database.Scan(JournalEntry.PostingFile).Select(p => (p.Key, Posting: Layouts.Posting.From(p.Data)))
                .Where(p => p.Posting.I("batch") != 0 || p.Posting.I("post-number") != 0).ToLookup(p => p.Posting.I("batch"));
            var removed = new HashSet<int>();
            foreach (var (key, batch) in batches)
            {
                int number = batch.I("batch-nos");
                if (removed.Add(number))
                    foreach (var (postingKey, posting) in postings[number])
                    {
                        if (archive) Archive(number, posting, ref archiveRow);
                        database.Delete(JournalEntry.PostingFile, postingKey);
                    }
                batch.SetN("cleared-status", 2);
                batch.SetN("stored", system.I("Run-Date"));
                batch.SetN("batch-start", 0);
                database.Rewrite(JournalEntry.BatchFile, key, batch.B);
            }
            status = ClosingStatus.PostingLayoutMismatch;
        });
        return status;
    }

    private void Archive(int batch, Rec posting, ref int archiveRow)
    {
        int leg = 0;
        foreach (var movement in ExpandPosting(posting))
        {
            var record = ArchivePosting.New();
            record.SetN("batch", batch);
            record.SetN("number", movement.Number);
            record.Set("code", posting.S("post-code"));
            record.Set("date", movement.Date);
            record.Set("account", movement.Account);
            record.SetN("amount", movement.Amount);
            record.Set("description", posting.S("post-legend"));
            record.Set("contra", leg++ == 0
                ? posting.S("post-cr") + posting.S("cr-pc")
                : posting.S("post-dr") + posting.S("dr-pc"));
            database.Write(ArchiveFile, Cob.P9(++archiveRow, 8), record.B);
        }
    }
}
