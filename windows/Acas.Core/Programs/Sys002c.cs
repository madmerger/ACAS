using Acas.Core.Engine;
namespace Acas.Core.Programs;

public static partial class Sys002
{
    private static async Task SlParams(St st)
    {
        var (s, t) = (st.S, st.T);
    top:
        Head(st, 5, "S-L  Data 1");
        Sys002Scr.SlData.Display(t, s, st.V);
        await Sys002Scr.SlData.Accept(t, s, st.V);
        if (s.I("SL-Dunning") == 1) t.D("Late letters selected    ", 0722);
        else { s.SetN("SL-Dunning", 0); t.D("Late letters not selected", 0722); }
        if (s.I("SL-Charges") == 1) t.D("Late charges selected    ", 0822);
        else { s.SetN("SL-Charges", 0); t.D("Late charges not selected", 0822); }
        if (s.S("SL-Delim") == " ") { t.D(@"Delimiter <\> assumed", 1422); s.Set("SL-Delim", "\\"); }
        t.D(Up(s, "Sl-Own-Nos") == "Y" ? "Selected & Set" : "Unset         ", 1528);
        StockLink(st, "SL-Stock-Link", 1828);
        SetUnset(st, "SL-Pay-Ac", 1928);
        SetUnset(st, "SL-Sales-Ac", 2028);
        SetUnset(st, "S-Debtors", 2128);
        if (await Redo(st, "    S-L Data Complete  ")) goto top;
    top2:
        Head(st, 6, "S-L  Data 2");
        await Sys002Scr.SlData2.Accept(t, s, st.V);
        foreach (var (f, pos) in new[] { ("SL-Comp-Head-Inv", 0822), ("SL-Comp-Head-Stat", 0922), ("SL-Comp-Head-Lets", 1022), ("SL-Comp-Head-Pick", 1122) })
        {
            var v = Up(s, f);
            if (v != "Y" && v != "N") { t.D("Error, set to N", pos, fg: 4); t.Beep?.Invoke(); s.Set(f, "N"); }
        }
        if (await Redo(st, "  S-L Data 2 Complete  ")) goto top2;
    }

    private static async Task PlParams(St st)
    {
        var (s, t) = (st.S, st.T);
    top:
        Head(st, 7, "P-L  Data");
        await Sys002Scr.PlData.Accept(t, s, st.V);
        if (s.S("PL-Delim") == " ") { t.D(@"Delimiter <\> assumed", 1422); s.Set("PL-Delim", "\\"); }
        if (Up(s, "PL-Stock-Link") == "Y" && s.I("Level-4") == 1) t.D("Selected & Set", 1528, eol: true);
        else { s.Set("PL-Stock-Link", "N"); t.D("Unset and/or No Stock", 1528, eol: true, fg: 3); }
        SetUnset(st, "BL-Pay-Ac", 1828);
        SetUnset(st, "BL-Purch-Ac", 1928);
        SetUnset(st, "P-Creditors", 2028);
        if (await Redo(st, "    P-L Data Complete")) goto top;
    }

    private static void Flag(St st, string f, int pos)
    {
        if (st.S.I(f) == 1) st.T.D("    Set", pos, eol: true, fg: 3);
        else { st.S.SetN(f, 0); st.T.D("    UnSet", pos, eol: true, fg: 3); }
    }

    private static async Task StockParams(St st)
    {
        var (s, t) = (st.S, st.T);
    top:
        Head(st, 8, "Stock Data");
        await Sys002Scr.StockData.Accept(t, s, st.V);
        Flag(st, "Stk-Debug", 0720);
        Flag(st, "Stk-Manu-Used", 0920);
        Flag(st, "Stk-OE-Used", 1020);
        Flag(st, "Stk-Audit-Used", 1120);
        Flag(st, "Stk-Mov-Audit", 1220);
        switch (Up(s, "Stk-Period-Cur"))
        {
            case "M": t.D("    Set to Monthly", 1320, eol: true, fg: 3); break;
            case "Q": t.D("    Set to Quarterly", 1320, eol: true, fg: 3); break;
            case "W": t.D("    Set to Weekly", 1320, eol: true, fg: 3); break;
            default: s.Set("Stk-Period-Cur", "M"); t.D("    Unset: Has been set to Monthly", 1320, eol: true, fg: 3); break;
        }
        switch (Up(s, "Stk-Period-dat"))
        {
            case "M": t.D("    Set to Monthly", 1420, eol: true, fg: 3); break;
            case "Q": t.D("    Set to Quarterly", 1420, eol: true, fg: 3); break;
            case "Y": t.D("    Set to Yearly", 1420, eol: true, fg: 3); break;
            default: s.Set("Stk-Period-dat", "Y"); t.D("    Unset: Has been set to Yearly", 1420, eol: true, fg: 3); break;
        }
        Flag(st, "Stk-Averaging", 1520);
        Flag(st, "Stk-Activity-Rep-Run", 1820);
        if (s.I("Stk-Audit-No") > 0) t.D("  Set", 1922, eol: true, fg: 3);
        else { s.SetN("Stk-Audit-No", 0); t.D("  Set to zero", 1922, eol: true, fg: 4); }
        if (await Redo(st, "  Stock Data Complete")) goto top;
    }

    private static async Task PrintParams(St st)
    {
        var t = st.T;
        t.D(" ", 0101, eos: true);
        t.D("Do you want printed copy (Y/N) [ ]", 1201);
        var r = await t.A(1233, 1, init: "Y");
        if (r is "N" or "n") return;
        Print(st);
    }
}
