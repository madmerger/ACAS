using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>common/sys002.cbl: システム設定 (System Set-Up)。画面定義は Sys002Scr (自動生成)。</summary>
public static partial class Sys002
{
    private const string Prog = "SYS002 (3.01.39)";

    private sealed class St
    {
        public required Ctx C; public required Rec S;
        public Dictionary<string, string> V = new(StringComparer.OrdinalIgnoreCase);
        public Crt T => C.Crt;
    }

    public static async Task<int> Run(Ctx c, string caller)
    {
        var t = c.Crt;
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D("System Parameters", 0130);
        if (!c.LoadSys())
        {
            c.Sys = Layouts.System.New();
            c.Sys.SetN("Date-Form", 1);
        }
        var st = new St { C = c, S = c.Sys };
        st.V["prog-name"] = Prog;
        st.V["line-1-date"] = Launcher.ConvDate(c, Launcher.BinToDate(c.Sys.N("Run-Date")));
        st.V["screen-nos"] = "1"; st.V["verify-message"] = "";
        if (await UserParams(st)) { c.LoadSys(); return 0; }   // Esc: 書き戻さずに終了
        await SystemParams(st);
        if (c.Sys.I("Level-1") == 1) await GlParams(st);
        if (c.Sys.I("Level-3") == 1) await SlParams(st);
        if (c.Sys.I("Level-2") == 1) await PlParams(st);
        if (c.Sys.I("Level-4") == 1) await StockParams(st);
        await PrintParams(st);
        t.D(" ", 0101, eos: true);
        c.SaveSys();
        return 0;
    }

    private static void Head(St st, int nos, string title)
    {
        st.V["screen-nos"] = nos.ToString();
        st.T.D(" ", 0101, eos: true);
        Sys002Scr.Banner.Display(st.T, st.S, st.V);
        st.T.D(title, 0436);
    }

    /// <summary>verify-screen を表示し「OK to file (Y/N)」を受け付ける。N なら true。</summary>
    private static async Task<bool> Redo(St st, string msg)
    {
        st.V["verify-message"] = msg;
        Sys002Scr.VerifyScreen.Display(st.T, st.S, st.V);
        st.T.D(msg.PadRight(24), 1355);
        st.T.V("Y", 1576, fg: 6);
        var r = await st.T.A(1576, 1, init: "Y");
        return r is "N" or "n";
    }

    private static string DateOf(Ctx c, decimal bin) => bin == 0 ? "" : Launcher.ConvDate(c, Launcher.BinToDate(bin));

    private static async Task<bool> UserParams(St st)
    {
        var (c, s, t) = (st.C, st.S, st.T);
    mainUser:
        Head(st, 1, "User Data");
        st.V["p-start"] = DateOf(c, s.N("Start-Date"));
        st.V["p-end"] = DateOf(c, s.N("End-Date"));
        st.V["s-pass-word"] = "";
        Sys002Scr.UserData.Display(t, s, st.V);
    accept:
        await Sys002Scr.UserData.Accept(t, s, st.V);
        if (t.Status == 2005) return true;
        int df = s.I("Date-Form");
        if (df == 1) t.D("    Using UK format dd/mm/ccyy", 1420, eol: true, fg: 3);
        else if (df == 2) t.D("    Using USA format mm/dd/ccyy", 1420, eol: true, fg: 3);
        else if (df == 3) t.D("    Using Intl format ccyy/mm/dd", 1420, eol: true, fg: 3);
        else { t.D("    Incorectly Set. You MUST set this", 1420, eol: true, fg: 4); s.SetN("Date-Form", 1); }
        int bin = 0;
        foreach (var (key, fld, pos) in new[] { ("p-start", "Start-Date", 1540), ("p-end", "End-Date", 1640) })
        {
            if (st.V[key].Trim().Length > 0)
            {
                string uk = Common.FromForm(c, st.V[key]);
                bin = Common.Maps04(uk);
                st.V[key] = uk;
            }
            if (bin == 0) { t.D("SY005 Invalid Date", pos, fg: 3); goto accept; }
            t.D(" ", pos, eol: true);
            s.SetN(fld, bin);
        }
        if (st.V["s-pass-word"].Trim().Length > 0) s.Set("Pass-Word", Maps01.Pass(st.V["s-pass-word"]));
        if (s.I("Period") == 13) t.D("Weekly    ", 2270, fg: 3);
        else if (s.I("Period") == 6) t.D("Fortnightly", 2270, fg: 3);
        else { s.SetN("Period", 3); t.D("Monthly   ", 2270, fg: 3); }
        if (s.I("Page-Lines") <= 28) { s.SetN("Page-Lines", 48); t.D("SY105 Lines > 28", 1750, fg: 3); goto accept; }
        t.D(" ", 1750, eol: true);
        int fs = s.I("File-System-Used");
        if (fs > 1) { s.SetN("File-System-Used", 0); t.D("Range 0 thru 1 only   ", 2410, fg: 3); }
        else if (fs == 0) t.D("Cobol data files used ", 2410, fg: 3);
        else t.D("Rdbms is used  ", 2410, fg: 3);
        int du = s.I("File-Duplicates-In-Use");
        if (du > 1) { s.SetN("File-Duplicates-In-Use", 0); t.D("Range 0 thru 1 only   ", 2450, fg: 3); }
        else if (du == 1) t.D("Duplicate file processing used", 2441, fg: 3);
        else t.D("Duplicate file processing NOT used", 2441, fg: 3);
        string vp = s.S("SL-VAT-Printed").ToUpperInvariant();
        if (vp != "Y" && vp != "N") { vp = "N"; t.V(vp, 2137); }
        s.Set("SL-VAT-Printed", vp);
        if (await Redo(st, "   User Data Complete")) goto mainUser;
        return false;
    }
}
