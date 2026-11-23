using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>sl070: 売上分析コード保守 (機能メニューと各画面の入口)。TODO: 分析コードの登録・変更・印刷・表示は未移植。</summary>
public static class Sl070
{
    private static readonly AsyncLocal<string?> _prog = new();
    private static string Prog => _prog.Value ?? "SL070 (3.01.11)";
    public static async Task<int> Run(Ctx c, string toDay, string prog = "SL070 (3.01.11)")
    {
        _prog.Value = prog;
        var t = c.Crt;
        while (true)
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Product Analysis File Set-Up & Maintenance", 0120); t.V(Common.ToForm(c, toDay), 0171);
            t.D("Function  Menu", 0434);
            t.D("Select one of the following by number :- [ ]", 0701);
            t.D("(1)  Set-up P/A records", 1004);
            t.D("(2)  Amend/Delete P/A records", 1204);
            t.D("(3)  Print P/A records", 1404);
            t.D("(4)  Print All P/A records", 1604);
            t.D("(5)  Display P/A records", 1804);
            t.D("(9)  Return to system menu", 2004);
            int m = (int)await t.AN(0743, 1, 0, auto: true);
            switch (m)
            {
                case 9: return 0;
                case 1: await Grid(c, toDay, "Set-Up P/A Records", 32, true); break;
                case 2: await Grid(c, toDay, "Amend/Delete P/A Records", 29, true); break;
                case 3: await Head(c, toDay, "Print P/A Records", 32, true); break;
                case 4: await Head(c, toDay, "Print All P/A Records", 32, false); break;   // レガシー実測 (SL-221) は不定データ約 11MB を出力する。再現しない (未解消)
                case 5: await Grid(c, toDay, "Display P/A Records", 31, false); break;
            }
        }
    }

    private static async Task Head(Ctx c, string toDay, string title, int col, bool print)
    {
        var t = c.Crt;
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D(title, 100 + col); t.V(Common.ToForm(c, toDay), 0171);
        if (print)
        {
            // TODO: 分析コード明細行は未移植 (見出しのみ)
            var rp = c.OpenReport(Ctx.L + "prt-1");
            rp.Write(Prog.PadRight(33), new Lit("Product Analysis Codes".PadRight(39)), new Lit("Page "), "  1");
            rp.Write(""); rp.Write(c.Sys.S("Usera").PadRight(70), Common.ToForm(c, toDay));
            rp.Write(""); rp.Write(new Lit(Prog.StartsWith("PL") ? "    Code    GL.No.      <-----Description------>   Print       -Type-" : "    Code    Gl.Nos.      <-----Description------>   Print      -Type-"));
            rp.Close();
            if (Prog.StartsWith("PL")) return;      // レガシー実測 (PL-221): 印刷後ただちに機能メニューへ戻る
        }
        await t.A(2480, 1);
    }

    private static async Task Grid(Ctx c, string toDay, string title, int col, bool edit)
    {
        var t = c.Crt;
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D(title, 100 + col); t.V(Common.ToForm(c, toDay), 0171);
        t.Paint(4, "Code   G/L Nos          Description            Ref     Type");
        for (int r = 6; r <= 22; r++) t.V("[  ]  [      ]    [                        ]  [   ]", r * 100 + 1, fg: 2);
        if (edit)
        {
            string stars = new string('*', 19);
            t.V(stars, 1762, fg: 2); t.V(stars, 2362, fg: 2);
            t.D("* Escape Code [ ] *", 1862);
            t.D("* <B> = Back      *", 1962);
            t.D("* <S> = Save      *", 2062);
            t.D("* <Q> = Quit      *", 2162);
            t.D("* <K> = Deleted   *", 2262);
            await t.A(0602, 2);
        }
        else
        {
            t.D("Enter <X> to exit or <Return> to continue...[ ]", 2331);
            await t.A(2376, 1);
        }
    }
}
