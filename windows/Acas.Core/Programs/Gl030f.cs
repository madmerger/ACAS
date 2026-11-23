using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl030
{
    private static int PlaceIdx(string p)
    {
        char ch = p.Length > 0 ? p[0] : ' ';
        return ch < 'E' ? 1 : ch < 'I' ? 2 : ch < 'K' ? 3 : ch < 'O' ? 4 : ch < 'R' ? 5 : ch < 'U' ? 6 : ch < 'W' ? 7 : 8;
    }

    /// <summary>gl030f: 勘定科目表の照会 (menu=5) / 印刷 (menu=6)。</summary>
    private static async Task Chart(Ctx c, string toDay, int menu)
    {
        var t = c.Crt;
        if (!c.Db.Exists(File)) { t.D(" ", 0101, eos: true); t.D("GL106 Ledger File Does Not Exist", 0901); return; }
        bool usePc = Pcs(c) || Branches(c);
        int lin = 3, gate = 1;
        int P(int col) => lin * 100 + col;
        void Head1()
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.V(Common.ToForm(c, toDay), 0171, fg: 2);
            t.D("Chart Of Accounts Display", 0127);
        }
        void SecondHead()
        {
            t.D("Ledger    ", P(1)); t.D("Sub    ", P(11));
            if (Pcs(c)) t.D("  P/C   ", P(18)); else if (Branches(c)) t.D("Branch  ", P(18)); else t.V("        ", P(18));
            t.D("<---------Name--------->    Type    Level --Placement--", P(26));
        }
        void Detail(Rec r)
        {
            t.V(r.S("nos").Substring(0, 4), P(2), fg: 2);
            t.V(r.S("nos").Substring(4), P(11), fg: 2);
            if (usePc) t.V(r.S("pc"), P(20), fg: 2);
            t.V(r.S("name"), P(25), fg: 2);
            int ty = r.I("type") == 9 ? 5 : r.I("type") + 1;
            t.D(ty < 1 || ty > 5 ? "ERROR?" : Types[ty - 1], P(53));
            if (r.I("level") != 0)
            {
                t.V(r.S("level"), P(64), fg: 2);
                t.D(Places[PlaceIdx(r.S("place")) - 1], P(68));
            }
        }
        async Task AskClear()
        {
            t.D("Press Return for next screen ", 2301, eol: true);
            await t.A(2341, 1);
        }
        async Task ScreenClear()
        {
            if (gate != 1) await AskClear();
            gate = 2;
            for (int l = lin; l < 23; l++) t.D(" ", l * 100 + 1, eol: true);
        }

        Head1();
        if (menu == 6) { t.D("Print Out", 0145); Print(c, toDay); return; }
    mainTarget:
        lin = 3;
        await ScreenClear();
        t.D("Enter the start Account - [      ]", 0401);
        if (usePc) t.D("/  ]", 0434);
        t.D(" ", 2301, eol: true);
        t.D("Press <Esc> key to exit", 2301);
        decimal nos = await t.AN(0428, 6, 0);
        if (t.Status == 2005) return;
        decimal pc = 0;
        if (usePc) pc = await t.AN(0435, 2, 0);
        lin = 4; gate = 1;
        SecondHead();
        var rows = c.Db.Scan(File, Key(nos, pc));
        int ix = 0;
        if (rows.Count == 0) { t.D("No match found !", 0841); goto mainTarget; }
        var r = Layouts.Ledger.From(rows[ix++].Data);
        string saveLedger = Cob.P9(nos, 6);
        lin += 2;
        string seek;
    mainLoop:
        t.D("<N> Next; <I> Next ignore same code; <C> Cont; <Q> Quit :- [I]", 2301);
        Detail(r);
        seek = (await t.A(2361, 1, "I")).ToUpperInvariant();
        if (seek == "Q") return;
    subsid:
        gate = 2;
        if (ix >= rows.Count) goto mainTarget;
        r = Layouts.Ledger.From(rows[ix++].Data);
        if (r.S("nos").Substring(0, 4) == "9999") goto mainTarget;
        if (seek == "I" && r.S("nos") == saveLedger) goto subsid;
        saveLedger = r.S("nos");
        lin++;
        if (lin == 22)
        {
            await AskClear();
            if (t.Status == 2005) { gate = 1; goto mainTarget; }
            Head1(); lin = 4; SecondHead(); lin = 6;
        }
        if (seek != "C" && seek != "I") goto mainLoop;
        Detail(r);
        goto subsid;
    }

    private static void Print(Ctx c, string toDay)
    {
        var rp = c.OpenReport(Ctx.L + "prt-1");
        string f2 = Pcs(c) ? "Profit Centre    " : Branches(c) ? "   Branch       " : "";
        int page = 0, cnt = 0;
        void Heading()
        {
            page++;
            if (page != 1) rp.Page();
            rp.After(1, Prog.Substring(0, 14), new string(' ', 28), new Lit("Chart of Accounts"), new string(' ', 31), toDay);
            rp.After(1, c.Sys.S("Usera"), new string(' ', 60), new Lit("Page -"), Cob.Edit(page, "Z9"));
            rp.After(2, new Lit("---Level---   Header       Detail   "), "    ", new Lit(f2.PadRight(17)), new Lit("--Placement--      ----------Name----------"));
            rp.After(1, "");
            cnt = 5;
        }
        Heading();
        foreach (var (_, data) in c.Db.Scan(File))
        {
            var r = Layouts.Ledger.From(data);
            if (r.S("nos").Substring(0, 4) == "9999") break;
            var lv = new char[10]; Array.Fill(lv, ' ');
            string header = "       ", detail = "       ", place = new string(' ', 13);
            decimal n = r.N("nos") / 100m;
            if (r.I("level") != 0)
            {
                int i = r.I("level") * 2 + 1;
                lv[i - 1] = r.S("level")[0];
                header = n == 0 ? header : Cob.Edit(n, "ZZZ9.99");
                place = Places[PlaceIdx(r.S("place")) - 1];
            }
            else detail = n == 0 ? detail : Cob.Edit(n, "ZZZ9.99");
            string pc = r.N("pc") == 0 ? "       " : "     " + Cob.Edit(r.N("pc"), "Z9");
            rp.After(1, new string(lv), "   ", header, new string(' ', 7), detail, new string(' ', 6), pc, new string(' ', 10), new Lit(place), new string(' ', 6), r.S("name"));
            cnt++;
            if (cnt > c.Sys.I("Page-Lines")) Heading();
        }
        rp.Close();
    }
}
