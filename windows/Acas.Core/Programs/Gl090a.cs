using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl090
{
    /// <summary>gl090a: 構造化 (部門・拠点) 試算表。レガシーのコントロールブレーク処理を忠実に移植。</summary>
    private static void Structured(Ctx c, string wsDate)
    {
        var t = c.Crt;
        const string prog = "gl090a (3.00.04)";
        t.V(prog, 0101, eos: true, fg: 2);
        t.D("Structured Trial Balance", 0129);
        t.V(wsDate, 0171, fg: 2);
        var rp = c.OpenReport(Ctx.L + "prt-1");
        var dr = new decimal[6]; var cr = new decimal[6]; var store = new decimal[6];
        decimal totDr = 0, totCr = 0;
        int page = 0, cnt = 0, pageLines = c.Sys.I("Page-Lines");
        void Headings()
        {
            page++;
            object[] l1 = { prog.PadRight(50), new Lit("Profit Centre Trial Balance"), new string(' ', 47), new Lit("Page "), Cob.Edit(page, "ZZ9") };
            object[] l3 = { c.Sys.S("Usera").PadRight(32), new string(' ', 25), new Lit("Condensed Report"), new string(' ', 49), wsDate };
            if (page != 1) { rp.Page(); rp.Write(l1); rp.After(1, l3); rp.After(1, ""); }
            else { rp.Write(l1); rp.Write(l3); }
            rp.After(1, new Lit("Account      <----Detail   Level----><-------Level  4-------><-------Level  3-------><-------Level  2-------><-------Level  1------>"));
            rp.After(1, new Lit("               Debit        Credit      Debit       CRedit      Debit       Credit      Debit       Credit      Debit       Credit  "));
            rp.After(1, "");
            cnt = 6;
        }
        void Line6(int lvl, int indent, decimal a, decimal b)
        {
            var am = new decimal[10];
            int ix = (5 - lvl) * 2; am[ix] = a; am[ix + 1] = b;
            string ac = (new string(' ', indent) + Cob.Edit(store[lvl] / 100m, "9999.99")).PadRight(12).Substring(0, 12);
            rp.After(1, ac + string.Concat(am.Select(v => Bwz(v, "Z(7)9.99", 12))));
            cnt++;
            if (cnt > pageLines) Headings();
        }
        void Net(int lvl)
        {
            if (dr[lvl] > cr[lvl]) totDr += dr[lvl] - cr[lvl]; else totCr += cr[lvl] - dr[lvl];
        }
        void RollUp(int lvl)
        {
            for (int n = Math.Min(lvl - 1, 4); n >= 1; n--)
                if (store[n] != 0) { dr[n] += dr[lvl]; cr[n] += cr[lvl]; return; }
            Net(lvl);
        }
        void DetailPrint()
        {
            Line6(5, 4, dr[5], cr[5]);
            RollUp(5);
            dr[5] = cr[5] = 0;
        }
        void Total(int n)
        {
            if (n == 1)
            {
                if (dr[1] > cr[1]) Line6(1, 0, dr[1] - cr[1], 0); else Line6(1, 0, 0, cr[1] - dr[1]);
                rp.After(1, "");
                Net(1);
            }
            else
            {
                if (store[n] != 0) { if (dr[n] > cr[n]) Line6(n, n - 1, dr[n] - cr[n], 0); else Line6(n, n - 1, 0, cr[n] - dr[n]); }
                RollUp(n);
            }
            store[n] = dr[n] = cr[n] = 0;
        }
        Headings();
        foreach (var (_, data) in c.Db.Scan(Gl030.File))
        {
            var r = Layouts.Ledger.From(data);
            decimal nos = r.N("nos"), bal = r.N("balance"); int level = (int)r.N("level");
            if (Math.Floor(nos / 100) == 9999) break;
            if (nos != store[5] && store[5] != 0)
            {
                DetailPrint();
                if (level == 0) store[5] = nos;
            }
            if (nos == store[4] || nos == store[3] || nos == store[2] || nos == store[1]) continue;
            if (level is >= 1 and <= 4)
            {
                if (store[level] != 0) for (int n = 4; n >= level; n--) Total(n);
                store[level] = nos;
                continue;
            }
            if (nos == store[5])
            {
                if (bal < 0) cr[5] -= bal; else dr[5] += bal;
                continue;
            }
            if (bal < 0) cr[5] = -bal; else dr[5] = bal;
            store[5] = nos;
        }
        DetailPrint();
        for (int n = 4; n >= 1; n--) Total(n);
        var l7 = new string(' ', 108) + " ==========  ==========";
        rp.After(3, l7);
        rp.After(1, new string(' ', 20), new Lit("t o t a l".PadRight(88)), Cob.Edit(totDr, "Z(7)9.99") + " ", Cob.Edit(totCr, "Z(7)9.99"));
        rp.After(1, l7);
        rp.Close();
    }
}
