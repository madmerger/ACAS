using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl070: 仕訳転記 (フェーズ1: バッチ検査)。</summary>
public static partial class Gl070
{
    private const string Prog = "gl070 (3.00.02)";

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D("Transaction Posting", 0132);
        t.V(Common.ToForm(c, toDay), 0171, fg: 2);
        t.D("Phase - 1.  Batch Check", 0801);
        // レガシー実測: batch.dat が無いと OPEN INPUT で異常終了する
        if (!c.Db.Exists(Gl050.BatchFile)) throw new Halt("batch.dat が存在しません");
        bool open = false;
        foreach (var (_, data) in c.Db.Scan(Gl050.BatchFile))
        {
            var b = Layouts.Batch.From(data);
            if (b.N("bcycle") == c.Sys.N("Cyclea") && b.N("batch-status") == 0) open = true;
        }
        if (open) return 5;
        t.D("Phase - 2.  Transaction Pre-process", 0801);
        // 未実装: gl071b 以降 (転記前処理・gl071 ソート・gl072 元帳更新) は未移植
        t.V("未実装: 仕訳転記 (フェーズ2 以降) は移植されていません", 1001, fg: 4);
        await t.A(1070, 1);
        return 0;
    }
}

/// <summary>gl080: サイクル締め処理 (開始確認まで)。</summary>
public static partial class Gl080
{
    private const string Prog = "gl080 (3.00.02)";

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D("End Of Cycle Processing", 0130);
        t.V(Common.ToForm(c, toDay), 0171, fg: 2);
        t.V(c.Sys.S("Usera"), 0301, fg: 3);
        t.D("GL115 Ensure Archive USB Memory Stick is in path", 0801, fg: 3);
        t.D("GL116 Ensure you have done a file backup prior to running!!!", 0901, fg: 3);
        t.D("GL117 Hit Escape or press A to abort", 1001, fg: 3);
        var r = await t.A(1065, 1, " ", auto: true);
        if (t.Status == 2005 || r is "A" or "a") return 0;
        t.D("Phase - 1.  Batch Check", 0801, eos: true);
        if (!c.Db.Exists(Gl050.BatchFile)) throw new Halt("batch.dat が存在しません");
        // 未実装: gl080a 以降 (アーカイブ・削除・期末処理) は未移植
        t.V("未実装: サイクル締め (フェーズ1 以降) は移植されていません", 1001, fg: 4);
        await t.A(1070, 1);
        return 0;
    }
}
