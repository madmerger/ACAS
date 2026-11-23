using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl120: 損益計算書・貸借対照表。gl100: 元帳印刷ソート。</summary>
public static partial class Gl120
{
    public const string FinalFile = Ctx.L + "final.dat";
    private static readonly Layout Final = new Layout().X("place", 1).N9("nos", 6).N9("pc", 2).X("name", 24).C3("balance", 8, 2).C3("last", 8, 2);
    private static readonly string[] PlaceName = { "Sales Income", "Direct Costs", "Sundry Income", "Indirect Costs", "Fixed Assets", "Current Assets", "Current Liabilities", "Shareholders Funds" };
    private const string PlaceNos = "11112222334444555666778888";

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        string wsDate = Common.ToForm(c, toDay);
        t.V("gl120 (3.00.04)", 0101, eos: true, fg: 2);
        t.D("P&L and Balance Sheet", 0131);
        t.V(wsDate, 0171, fg: 2);
        string datePl = wsDate;
        while (true)
        {
            t.D("Enter P&L Date  (space to abort) - [", 0521);
            t.D("]", 0567);
            datePl = await t.A(0557, 10, datePl);
            if (datePl.Trim().Length == 0) return 0;
            datePl = wsDate;   // レガシー実測: 入力値は当日日付で上書きされる
            t.D("Ok to continue ? (Y/N)", 0721);
            t.V("[Y]", 0746, fg: 2);
            var r = await t.A(0747, 1, "Y");
            if (r is not ("N" or "n")) break;
        }
        if (!c.Db.Exists(Gl030.File))
        {
            t.D("GL106 Ledger File Does Not Exist", 0901, fg: 4);
            t.D("GL012 Hit Return to Quit", 1001);
            await t.A(1026, 1);
            return 0;
        }
        c.Db.Recreate(FinalFile);
        var dr = new decimal[6]; var cr = new decimal[6]; var store = new decimal[6];
        string storePlace = " ", storeName = "";
        void RollUp(int lvl)
        {
            for (int n = Math.Min(lvl - 1, 4); n >= 1; n--)
                if (store[n] != 0) { dr[n] += dr[lvl]; cr[n] += cr[lvl]; return; }
        }
        void Total(int n)
        {
            if (n == 1)
            {
                var f = Final.New();
                f.Set("place", storePlace); f.SetN("nos", store[1]); f.SetN("pc", 0); f.Set("name", storeName);
                f.SetN("balance", dr[1] - cr[1]); f.SetN("last", 0);
                c.Db.Write(FinalFile, storePlace + Cob.P9(store[1], 6) + "00", f.B);
            }
            else RollUp(n);
            store[n] = dr[n] = cr[n] = 0;
        }
        void DetailPrint() { RollUp(5); dr[5] = cr[5] = 0; }
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
                if (level == 1) { storePlace = r.S("place"); storeName = r.S("name"); }
                continue;
            }
            if (nos == store[5]) { if (bal < 0) cr[5] -= bal; else dr[5] += bal; continue; }
            if (bal < 0) cr[5] = -bal; else dr[5] = bal;
            store[5] = nos;
        }
        DetailPrint();
        for (int n = 4; n >= 1; n--) Total(n);
        Print(c, datePl);
        return 0;
    }

    private static string Cr(decimal v, bool bwz = false) =>
        bwz && v == 0 ? new string(' ', 13) : Cob.Edit(Math.Abs(v), "Z(7)9.99") + (v < 0 ? "CR" : "  ");

    private static void Print(Ctx c, string datePl)
    {
        var rp = c.OpenReport(Ctx.L + "prt-1");
        string sp(int n) => new string(' ', n);
        object[] l5 = { sp(50), new Lit("<--------This  Year-------->".PadRight(40)), new Lit("<--------Last  Year-------->") };
        string l8 = sp(50) + new string('=', 11) + sp(29) + new string('=', 11);
        string l10 = sp(66) + new string('=', 11) + sp(29) + new string('=', 11);
        rp.After(1, c.Sys.S("Usera").PadRight(32));
        rp.After(2, sp(32), new Lit("Profit & Loss Account    For the period to "), datePl);
        rp.After(1, sp(33) + new string('*', 52));
        rp.After(3, l5);
        string storePlace = " "; int a = 0, xx = 0;
        decimal totThis = 0, totLast = 0, runThis = 0, runLast = 0, gpThis = 0, gpLast = 0, npThis = 0, npLast = 0;
        object l11Name = sp(66);
        void Line7(object name, decimal th, decimal la) => rp.After(1, sp(20), name, Cr(th), sp(27), Cr(la, true));
        foreach (var (_, data) in c.Db.Scan(FinalFile))
        {
            var f = Final.From(data);
            if (f.S("place") != storePlace)
            {
                storePlace = f.S("place");
                int j = storePlace.Length == 1 ? "ABCDEFGHIJKLMNOPQRSTUVWXYZ".IndexOf(storePlace[0]) : -1;
                a = j < 0 ? 0 : PlaceNos[j] - '0';
                if (a != xx && xx != 0)
                {
                    rp.After(2, l8);
                    rp.After(1, sp(50), Cr(totThis), sp(3), Cr(totThis), sp(11), Cr(totLast, true), sp(3), Cr(totLast, true));
                    rp.After(1, l8);
                    if (xx is 1 or 3 or 5) { runThis += totThis; runLast += totLast; } else { runThis -= totThis; runLast -= totLast; }
                    decimal lt = 0, ll = 0;
                    if (a == 3) { l11Name = new Lit("Gross Profit".PadRight(66)); lt = gpThis = runThis; ll = gpLast = runLast; }
                    if (a == 5) { l11Name = new Lit("Net Profit  ".PadRight(66)); lt = npThis = runThis + gpThis; ll = npLast = runLast + gpLast; }
                    if (a == 8) { l11Name = new Lit("Net Current Value".PadRight(66)); lt = runThis; ll = runLast; }
                    if (a is 3 or 5 or 8)
                    {
                        rp.After(2, l10);
                        rp.After(1, l11Name, Cr(lt), sp(27), Cr(ll, true));
                        if (a == 5)
                        {
                            rp.After(1, l10);
                            rp.After(1, c.Sys.S("Usera").PadRight(32));
                            rp.After(2, sp(42), new Lit("Balance Sheet  as at  "), datePl);
                            rp.After(1, sp(44) + new string('*', 30));
                            rp.After(3, l5);
                        }
                        else rp.After(2, "");
                        runThis = runLast = 0;
                    }
                }
                if (a != xx)
                {
                    rp.After(1, a >= 1 ? new Lit(PlaceName[a - 1].PadRight(24)) : sp(24));
                    xx = a; totThis = totLast = 0;
                }
            }
            decimal bal = f.N("balance"), last = f.N("last");
            if (a is 1 or 3 or 5) { bal = -bal; last = -last; }
            totThis += bal; totLast += last;
            Line7(f.S("name").PadRight(30), bal, last);
        }
        Line7(new Lit("Net Profit  ".PadRight(30)), npThis, npLast);
        runThis += npThis; runLast += npLast;
        rp.After(2, l10);
        rp.After(1, l11Name, Cr(runThis), sp(27), Cr(runLast, true));
        rp.After(1, l10);
        rp.Close();
    }
}

public static partial class Gl100
{
    public static Task<int> Run(Ctx c, string toDay)
    {
        c.Crt.V("gl100 (3.00.01)", 0101, eos: true, fg: 2);
        c.Crt.D("Ledger Print - Sort", 0131);
        // レガシー実測: 見出し表示直後にランタイムが終了する (GL-011 / GL-228)。以降の保管仕訳ソート・gl105 元帳印刷は未移植。
        throw new StopRun { KeepScreen = true };
    }
}
