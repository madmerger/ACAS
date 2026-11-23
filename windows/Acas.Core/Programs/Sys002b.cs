using Acas.Core.Engine;
namespace Acas.Core.Programs;

public static partial class Sys002
{
    private static async Task SystemParams(St st)
    {
        var (s, t) = (st.S, st.T);
    opsMain:
        Head(st, 2, "OPS  Data 1");
        await Sys002Scr.OpsData.Accept(t, s, st.V);
        int host = s.I("Host"), os = s.I("Op-System");
        if (host > 1) { s.SetN("Host", 1); host = 1; t.D("Multi-user system assumed", 1823, fg: 3); }
        else if (host == 0) t.D("Single-user system    ", 1823, fg: 3);
        else t.D("Multi-user system     ", 1823, fg: 3);
        t.V(new string(' ', 51), 2000);
        if (host == 0 && (os < 1 || os > 6)) { s.SetN("Op-System", 1); os = 1; t.D("MSDOS assumed", 2023, fg: 3); }
        else if (host == 1 && (os < 2 || os > 6)) { s.SetN("Op-System", 6); os = 6; t.D("Linux assumed", 2023, fg: 3); }
        else t.V(new[] { "", "DOS", "Windows", "Mac OSX", "OS/2", "Unix", "Linux" }[os], 2023, fg: 3);
        if (os is 3 or 5 or 6)
        {
            if (s.St("Print-Spool-Name2").Length == 0) s.Set("Print-Spool-Name2", s.S("Print-Spool-Name"));
            if (s.St("Print-Spool-Name3").Length == 0) s.Set("Print-Spool-Name3", s.S("Print-Spool-Name"));
            await Sys002Scr.OpsData2.Accept(t, s, st.V);
            if (s.S("Print-Spool-Name")[0] == ' ') t.D(" Print Spool Name must be defined", 2402, fg: 3);
        }
        int dc = s.I("Data-Capture-Used");
        if (dc == 0) t.D("Cobol Standard Display  ", 2054, fg: 3);
        else if (dc == 1) t.D("Gui Display             ", 2054, fg: 3);
        else if (dc == 2) t.D("Widget Display          ", 2054, fg: 3);
        else { t.D(" Invalid - Std selected ", 2054, fg: 3); s.SetN("Data-Capture-Used", 0); }
        if (s.S("Maps-Ser-xx") == "mp" && s.I("Maps-Ser-nn") == 9999) t.D("Using (Free) Open Source Version of ACAS", 1501, fg: 3);
        else t.D("Using Commercial Version of ACAS", 1501, fg: 3);
        if (await Redo(st, "    OPS Data 1 Complete ")) goto opsMain;
        if (s.I("File-System-Used") == 0) return;
    opsMain2:
        Head(st, 3, "OPS  Data 2");
        await Sys002Scr.OpsData3.Accept(t, s, st.V);
        if (s.St("RDBMS-DB-Name").Length > 0) t.D(" DB name, set as requested", 0746, fg: 3);
        if (s.St("RDBMS-User").Length > 0) t.D(" DB User, set as requested", 0846, fg: 3);
        if (s.St("RDBMS-Passwd").Length > 0) { t.D(" DB User pwd, set as requested", 0946, fg: 3); t.V("************", 0922); }
        if (await Redo(st, "    OPS Data 2 Complete ")) goto opsMain2;
    }

    private static string Up(Rec s, string f) { var v = s.S(f).ToUpperInvariant(); s.Set(f, v); return v; }

    private static void YesNo(St st, string f, int pos)
    {
        if (Up(st.S, f) == "Y") st.T.D("Selected        ", pos);
        else { st.S.Set(f, " "); st.T.D("Not selected    ", pos); }
    }

    private static async Task GlParams(St st)
    {
        var (s, t) = (st.S, st.T);
    top:
        Head(st, 4, "G-L  Data");
        st.V["num-6"] = Cob.P9(s.N("Next-Batch"), 5);
        await Sys002Scr.GlData.Accept(t, s, st.V);
        s.SetN("Next-Batch", Cob.ToNum(st.V["num-6"]));
        st.V.Remove("num-6");
        string pc = Up(s, "P-C");
        if (pc == "P") t.D("Profit centres selected", 0732);
        else if (pc == "B") t.D("Branches selected", 0732);
        else { s.Set("P-C", " "); pc = " "; t.D("Not selected  ", 0732); Up(s, "P-C-Level"); }
        if (pc == " " && s.S("P-C-Level") != " ") s.Set("P-C-Level", " ");
        if (pc != " " && s.S("P-C-Level") == "R") t.D("Revenue A/cs only ", 0832);
        if (pc != " " && s.S("P-C-Level") != "R") { s.Set("P-C-Level", " "); t.D("All A/cs          ", 0832); }
        t.D("1st digit of P.C./Branch ", 0932);
        if (Up(s, "P-C-Grouped") == "Y") t.D("is the group identifier", 0957);
        else { t.D("is not significant", 0957); s.Set("P-C-Grouped", " "); }
        YesNo(st, "Comps", 1032);
        YesNo(st, "Ledger-2nd-Index", 1132);
        YesNo(st, "M-V", 1232);
        YesNo(st, "Arch", 1332);
        YesNo(st, "Vat", 1632);
        t.D(Up(s, "Irs-Instead") == "Y" ? "Selected        " : "Not selected    ", 1832);
        if (await Redo(st, "    G-L Data Complete  ")) goto top;
    }

    private static void SetUnset(St st, string f, int pos)
    {
        if (st.S.N(f) != 0) st.T.D("Selected & Set", pos, eol: true);
        else st.T.D("Unset", pos, eol: true, fg: 3);
    }

    private static void StockLink(St st, string f, int pos)
    {
        if (Up(st.S, f) == "Y" && st.S.I("Level-4") == 1) st.T.D("Selected & Set       ", pos);
        else { st.S.Set(f, "N"); st.T.D("Unset and/or No Stock", pos, fg: 3); }
    }
}
