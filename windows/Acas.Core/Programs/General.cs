using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>general.cbl: 総勘定元帳メニュー。</summary>
public static partial class General
{
    public static async Task<int> Menu(Ctx c)
    {
        var t = c.Crt;
        string reply = "A";   // 初回は処理日入力を強制
    openSystem:
        if (!c.LoadSys() || c.Sys.I("Cyclea") == 0)
        {
            c.SaveSys();
            if (await Sys002.Run(c, "General") > 7) throw new StopRun();
            goto openSystem;
        }
        string toDay = Launcher.BinToDate(c.Sys.N("Run-Date"));
        if (c.Sys.I("Level-1") != 1)
        {
            await Maps99.Show(c, 1); await Maps99.Show(c, 15);
            return 0;
        }
        string op = c.Sys.I("Op-System") switch { 0 => "O/S", 1 => "Dos", 2 => "Windows", 3 => "Mac", 4 => "OS/2", 5 => "Unix", 6 => "Linux", _ => "" };
        int term;
        if (reply == "A") goto load01;
    displayMenu:
        Common.MenuHead(c, toDay, "General (3.00.11)", "General Ledger System Menu", 0328);
        t.D("Select one of the following by letter  :- [ ]", 0601);
        t.D("(A)  Date Entry", 1004);
        t.D("(B)  Chart Of Accounts", 1104);
        t.D("(C)  Default Account Maintenance", 1204);
        t.D("(D)* Final Accounts Set-Up", 1304);
        t.D("(E)  Enter Transactions", 1404);
        t.D("(F)  Proof/Modify Transactions", 1504);
        t.D("(G)  Batch Status Report", 1604);
        t.D("(H)  Transaction Posting", 1704);
        t.D("(I)  End Of Cycle Processing", 1804);
        t.D("(J)  Print Trial Balance", 1144);
        t.D("(K)  Print P&L and Balance Sheet", 1244);
        t.D("(L)  Print Ledgers", 1344);
        t.D("(M)* Print Final Accounts", 1444);
        t.D("(X)  Exit to ", 1544);
        t.V(op, 1557, fg: 2);
        t.D("(Z)  System Set Up", 1744);
    acceptLoop:
        reply = (await t.A(0644, 1, auto: true)).ToUpperInvariant();
        switch (reply)
        {
            case "X": t.D(" ", 0101, eos: true); c.SaveSys(); return 0;
            case "A": goto load01;
            case "B": term = await Gl030.Run(c, toDay); break;
            case "C": term = await Gl020.Run(c, toDay); c.SaveSys(); c.LoadSys(); break;
            case "D": case "Y": t.D("Sorry not yet available", 2327); goto acceptLoop;
            case "E": term = await Gl050.Run(c, toDay); c.SaveSys(); c.LoadSys(); break;
            case "F": term = await Gl051.Run(c, toDay); c.SaveSys(); c.LoadSys(); break;
            case "G": term = await Gl060.Run(c, toDay); break;
            case "H":
                term = await Gl070.Run(c, toDay);
                if (term > 7) break;
                if (term == 5) goto displayMenu;
                term = await Gl071.Run(c, toDay);
                if (term > 7) break;
                term = await Gl072.Run(c, toDay);
                break;
            case "I": term = await Gl080.Run(c, toDay); break;
            case "J": term = await Gl090.Run(c, toDay); break;
            case "K": term = await Gl120.Run(c, toDay); break;
            case "L":
                term = await Gl100.Run(c, toDay);
                if (term > 7) break;
                if (term == 5) goto acceptLoop;
                if (term == 4) { await Maps99.Show(c, 31); await Maps99.Show(c, 15); goto displayMenu; }
                term = await Gl105.Run(c, toDay);
                break;
            case "Z":
                c.SaveSys();
                if (await Sys002.Run(c, "General") > 7) throw new StopRun();
                goto openSystem;
            default:
                if (reply.Length == 1 && reply[0] >= 'M' && reply[0] <= 'W') goto displayMenu;
                goto acceptLoop;
        }
        if (term > 7) { c.SaveSys(); return 0; }
        goto displayMenu;
    load01:
        reply = " ";
        toDay = await Common.StartOfDay(c, "GL000 (3.00.04)", "General Ledger  Start Of Day", 0328, "GL009 Invalid Date");
        goto displayMenu;
    }
}
