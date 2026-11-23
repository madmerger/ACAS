namespace Acas.Core.Engine;

/// <summary>レガシー論理レコード差分・帳票との比較補助。</summary>
public static class Records
{
    // レガシー証跡 (records.py) が論理レコードを抽出している10ファイル
    private static readonly string[] TrackedFiles =
    {
        "ledgers/acas/ledger.dat", "ledgers/acas/salesled.dat", "ledgers/acas/purchled.dat", "ledgers/acas/stockctl.dat",
        "ledgers/acas/system.dat", "ledgers/acas/batch.dat", "ledgers/acas/postings.dat", "ledgers/acas/invoice.dat",
        "ledgers/acas/pinvoice.dat", "ledgers/irs/acnts.dat", "ledgers/irs/system.dat", "ledgers/irs/dflt.dat"
    };
    public static bool Tracked(string file) => Array.IndexOf(TrackedFiles, file) >= 0;

    public static bool Same(string fileKey, string? expHex, string? actHex) => expHex == actHex;

    public static string Describe(string? exp, string? act)
    {
        if (exp == null) return "削除";
        if (act == null) return "追加/変更";
        int n = Math.Min(exp.Length, act.Length), i = 0;
        while (i < n && exp[i] == act[i]) i++;
        return $"バイト{i / 2}から相違 旧={exp.Substring(i, Math.Min(24, exp.Length - i))} 新={act.Substring(i, Math.Min(24, act.Length - i))}";
    }

    /// <summary>レガシーの帳票ファイル (files/**/prt-*) と本実行の帳票(原文)を行単位で比較する。</summary>
    public static bool CompareReports(Ctx ctx, string? runDir, List<string> diffs)
    {
        if (runDir == null) return true;
        var dir = Path.Combine(runDir, "files", "ledgers");
        var legacy = new List<string>();
        if (Directory.Exists(dir))
            foreach (var f in Directory.GetFiles(dir, "prt-*", SearchOption.AllDirectories)) legacy.Add(f);
        legacy.Sort(StringComparer.Ordinal);
        bool ok = true;
        if (legacy.Count != ctx.EnglishReports.Count)
        {
            diffs.Add($"帳票数: 旧[{legacy.Count}] 新[{ctx.EnglishReports.Count}]");
            return false;
        }
        for (int i = 0; i < legacy.Count; i++)
        {
            var name = Path.GetFileName(legacy[i]);
            var mine = ctx.EnglishReports.FirstOrDefault(r => Path.GetFileName(r.Name) == name);
            if (mine.Lines == null) { diffs.Add($"帳票 {name}: 新側に無し"); ok = false; continue; }
            var exp = File.ReadAllText(legacy[i]).Replace("\r", "").Split('\n').Select(CaseRunner.Norm).ToList();
            var act = string.Join("\n", mine.Lines).Split('\n').Select(CaseRunner.Norm).ToList();
            while (exp.Count > 0 && exp[^1].Length == 0) exp.RemoveAt(exp.Count - 1);
            while (act.Count > 0 && act[^1].Length == 0) act.RemoveAt(act.Count - 1);
            for (int r = 0; r < Math.Max(exp.Count, act.Count); r++)
            {
                var e = r < exp.Count ? exp[r] : "<なし>"; var a = r < act.Count ? act[r] : "<なし>";
                if (e != a) { ok = false; if (diffs.Count < 20) diffs.Add($"帳票 {name} 行{r + 1}: 旧[{e}] 新[{a}]"); }
            }
        }
        return ok;
    }
}
