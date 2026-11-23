using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>pl900: 小切手 (支払) サブシステムのメニューと各入口画面。TODO: 支払生成・修正・小切手作成・登録簿は未移植。</summary>
public static class PlChq
{
    public static async Task<int> Menu(Ctx c, string toDay)
    {
        var t = c.Crt;
        bool redraw = true; int last = 0;
        while (true)
        {
            if (redraw)
            {
                Head(c, toDay, "PL900 (3.01.02)", "Cheque Menu", 36);
                t.D("Select one of the following by number :- [ ]", 0501);
                t.D("(1)  Generate payments to be made", 0811);
                t.D("(2)  Amend payments", 1011);
                t.D("(3)  Proof payments", 1211);
                t.D("(4)  Generate cheques", 1411);
                t.D("(5)  Print cheque register", 1611);
                t.D("(6)  Print remittance advices", 1811);
                t.D("(9)  Return to system menu", 2111);
            }
            int m = (int)await t.AN(0543, 1, redraw ? 0 : last, auto: true);
            redraw = true; last = m;
            switch (m)
            {
                case 9: return 0;
                case 1:
                    Head(c, toDay, "PL910 (3.01.07)", "Cheque Due Reporting", 32);
                    t.D("Current Age to Pay on is - [  ]", 0501); t.V("00", 0529);
                    t.D("is this correct (Y/N) ?  - [ ]", 0701);
                    await t.A(0729, 1);
                    break;
                case 2:
                    Head(c, toDay, "PL920 (3.01.03)", "Cheque Due Amendment", 32);
                    t.D("Supplier - [       /  ]", 0501);
                    for (int i = 1; i <= 9; i++) { t.V(i.ToString("00"), (8 + i) * 100 + 1, fg: 2); t.V("{        } [          ]", (8 + i) * 100 + 6, fg: 2); }
                    await t.A(0513, 7, upper: true);
                    break;
                case 4:
                    Head(c, toDay, "PL940 (3.01.04)", "Cheque Print File Generation", 28);
                    t.D("PL903 No data to process. Hit return", 0401);
                    await t.A(0438, 1);
                    break;
                case 5:
                    Head(c, toDay, "PL950 (3.01.09)", "Cheque Register", 32);
                    t.D("Warning: Updating Open Item File. Do You Wish to Continue (YES/NO) [   ]", 1201);
                    await t.A(1269, 3);
                    break;
                case 6: break;                       // レガシー実測 (PL-235): メニューを再表示する
                default: redraw = false; break;      // レガシー実測 (PL-232): 3 はメニューに留まる
            }
        }
    }

    public static void Head(Ctx c, string toDay, string prog, string title, int col)
    {
        var t = c.Crt;
        t.V(prog, 0101, eos: true, fg: 2);
        t.D(title, 100 + col);
        t.V(Common.ToForm(c, toDay), 0171);
    }
}
