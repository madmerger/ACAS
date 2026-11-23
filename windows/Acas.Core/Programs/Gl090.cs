using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl090: 試算表メニュー / gl090b: 詳細試算表。</summary>
public static partial class Gl090
{
    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        string wsDate = Common.ToForm(c, toDay);
        while (true)
        {
            t.V("gl090 (3.00.03)", 0101, eos: true, fg: 2);
            t.D("Trial Balance", 0135);
            t.V(wsDate, 0171, fg: 2);
            t.V(c.Sys.S("Usera"), 0301, fg: 3);
            t.D("Select Option By Number :- [ ]", 0801);
            t.D("(1)  Detailed Trial Balance", 1001);
            if (Gl030.Pcs(c)) t.D("(2)  Profit Centre Trial Balance", 1201);
            else if (Gl030.Branches(c)) t.D("(2)  Branch Trial Balance", 1201);
            t.D("(9)  Exit to system menu", 1701);
            int m = (int)await t.AN(0829, 1, 9);
            if (m == 1) await Detail(c, wsDate);
            if (m == 2) Structured(c, wsDate);
            if (m == 9) return 0;
        }
    }

    private static string Bwz(decimal v, string pic, int len) => v == 0 ? new string(' ', len) : Cob.Edit(v, pic).PadRight(len);
    private static string Qtr(decimal v) => v == 0 ? new string(' ', 13) : Cob.Edit(Math.Abs(v), "Z(7)9.99") + (v < 0 ? "CR" : "  ");

    /// <summary>gl090b</summary>
    private static async Task Detail(Ctx c, string wsDate)
    {
        var t = c.Crt;
        const string prog = "gl090b (3.00.04)";
        if (!c.Db.Exists(Gl030.File))
        {
            t.D(" ", 0101, eos: true);
            t.D("GL106 Ledger File Does Not Exist", 0901, fg: 4);
            t.D("GL012 Hit return to continue", 1001);
            await t.A(1026, 1);
            return;
        }
        t.V(prog, 0101, eos: true, fg: 2);
        t.V(wsDate, 0171, fg: 2);
        t.D("Detailed Trial Balance", 0129);
        t.D("Working.......Please wait", 1212);
        var rp = c.OpenReport(Ctx.L + "prt-1");
        string f1 = Gl030.Pcs(c) ? "  P/C " : Gl030.Branches(c) ? "Branch" : "";
        int page = 0, cnt = 0, j = 0, k = 0;
        void Heading()
        {
            page++;
            (j, k) = c.Sys.I("Current-Quarter") switch { 1 => (4, 3), 2 => (1, 4), 3 => (2, 1), 4 => (3, 2), _ => (j, k) };
            object[] l1 = { prog.PadRight(56), new Lit("Detail Trial Balance"), new string(' ', 48), new Lit("Page "), Cob.Edit(page, "ZZ9") };
            object[] l3 = { c.Sys.S("Usera").PadRight(32), new string(' ', 90), wsDate };
            if (page != 1) { rp.Page(); rp.Write(l1); rp.After(1, l3); rp.After(1, ""); }
            else { rp.Write(l1); rp.Write(l3); }
            rp.After(1, new Lit("Account   "), f1.Length == 0 ? new string(' ', 10) : new Lit(f1.PadRight(10)),
                new Lit("<---------Name--------->      <---Current Balance--->    <--Last Year Balance->     "),
                new Lit("<-Quarter "), j.ToString(), "->  ", new Lit("<-Quarter "), k.ToString(), "->");
            rp.After(1, new string(' ', 53), new Lit("Debit      Credit          Debit     Credit"));
            rp.After(1, "");
            cnt = 6;
        }
        string Line6(decimal ac, decimal pc, object name, decimal cdr, decimal ccr, decimal pdr, decimal pcr, decimal q1, decimal q2) =>
            Bwz(ac, "9999.99", 7) + "     " + Bwz(pc, "Z9", 8) + "\u0001" +
            Bwz(cdr, "Z(7)9.99", 12) + Bwz(ccr, "Z(7)9.99", 11) + "    " + Bwz(pdr, "Z(7)9.99", 12) + Bwz(pcr, "Z(7)9.99", 11) + "    " + Qtr(q1) + "  " + Qtr(q2);
        void Write6(int after, string l6, object name)
        {
            var p = l6.Split('\u0001');
            rp.After(after, p[0], name, p[1]);
        }
        Heading();
        decimal saveN = 0, totDr = 0, totCr = 0, prevDr = 0, prevCr = 0;
        foreach (var (_, data) in c.Db.Scan(Gl030.File))
        {
            var r = Layouts.Ledger.From(data);
            decimal n = Math.Floor(r.N("nos") / 100);
            if (n == 9999) break;
            if (n != saveN) { saveN = n; rp.After(1, ""); cnt++; }
            decimal bal = r.N("balance"), last = r.N("last");
            if (bal < 0) totCr -= bal; else totDr += bal;
            if (last < 0) prevCr -= last; else prevDr += last;
            Write6(1, Line6(r.N("nos") / 100m, r.N("pc"), "", bal < 0 ? 0 : bal, bal < 0 ? -bal : 0, last < 0 ? 0 : last, last < 0 ? -last : 0,
                r.N("q" + j), r.N("q" + k)), r.S("name").PadRight(30).Substring(0, 30));
            cnt++;
            if (cnt > c.Sys.I("Page-Lines")) Heading();
        }
        var l7 = new object[] { new string(' ', 50), "=========== ===========    =========== ===========" };
        rp.After(3, l7);
        Write6(1, Line6(0, 0, "", totDr, totCr, prevDr, prevCr, 0, 0), new Lit("T o t a l".PadRight(30)));
        rp.After(1, l7);
        rp.Close();
    }
}
