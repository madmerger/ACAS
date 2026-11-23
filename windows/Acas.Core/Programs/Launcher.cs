using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>ACAS.cbl (システムメニュー) の移植と各サブシステムの起動。</summary>
public static partial class Launcher
{
    public static readonly DateTime Epoch = new(1600, 12, 31);
    /// <summary>maps04: 通算日 → dd/mm/yyyy。</summary>
    public static string BinToDate(decimal bin) => Epoch.AddDays((double)bin).ToString("dd/MM/yyyy");
    public static int DateToBin(DateTime d) => (int)(d.Date - Epoch).TotalDays;

    /// <summary>システムのDate-Formに応じて UK 形式 dd/mm/yyyy を表示形式へ変換する。</summary>
    public static string ConvDate(Ctx c, string uk)
    {
        int form = c.Sys.I("Date-Form");
        if (form == 2) return uk.Substring(3, 2) + "/" + uk.Substring(0, 2) + uk.Substring(5);
        if (form == 3) return uk.Substring(6, 4) + "/" + uk.Substring(3, 2) + "/" + uk.Substring(0, 2);
        return uk;
    }

    public static async Task RunAcas(Ctx c)
    {
        var t = c.Crt;
        try
        {
        openSystem:
            if (!c.LoadSys() || c.Sys.I("Cyclea") == 0)
            {
                int term = await Sys002.Run(c, "ACAS");
                if (term > 7) throw new StopRun();
                goto openSystem;
            }
            string toDay = BinToDate(c.Sys.N("Run-Date"));
            while (true)
            {
                t.D(" ", 0101, eos: true);
                t.V(c.Sys.S("Maps-Ser-xx"), 2474);
                t.V(Cob.P9(c.Sys.N("Maps-Ser-nn"), 4), 2476);
                t.D("Copyright (c) 1976-", 2401, fg: 3);
                t.V(c.Now().ToString("yyyy"), 2420);
                t.D(" Applewood Computers", 2424, fg: 3);
                t.V(c.Sys.S("Usera"), 0101);
                t.V(ConvDate(c, toDay), 0171);
                t.V("ACAS (3.00.05)", 0301, fg: 2);
                t.D("ACAS System Menu", 0333);
                t.D("at ", 0355); t.V(c.Time(), 0358, fg: 2);
                t.D("on ", 0367); t.V(ConvDate(c, c.Now().ToString("dd/MM/yyyy")).Substring(0, 6) + c.Now().ToString("yy"), 0370, fg: 2);
                t.D("Select one of the following by letter  :- [ ]", 0601);
                t.D("(A)  General Ledger", 1004);
                t.D("(B)  Sales Ledger", 1104);
                t.D("(C)  Purchase Ledger", 1204);
                t.D("(D)  Stock Control", 1304);
                t.D("(E)  Order Entry", 1404);
                t.D("(F)  Payroll", 1504);
                t.D("(G)  Epos", 1604);
                t.D("(X)  Exit To system", 1444);
                t.D("(Z)  System Setup", 1644);
            acceptLoop:
                var reply = (await t.A(0644, 1, auto: true)).ToUpperInvariant();
                switch (reply)
                {
                    case "X": t.D(" ", 0101, eos: true); throw new StopRun();
                    case "A": if (await General.Menu(c) > 7) throw new StopRun(); break;
                    case "B": if (await Sales.Menu(c) > 7) throw new StopRun(); break;
                    case "C": if (await Purchase.Menu(c) > 7) throw new StopRun(); break;
                    case "D": if (await Stock.Menu(c) > 7) throw new StopRun(); break;
                    case "E": case "F": case "G": t.D("Sorry, not available", 2331); goto acceptLoop;
                    case "H": case "Y": t.D("Sorry, not yet available", 2331); goto acceptLoop;
                    case "Z":
                        if (await Sys002.Run(c, "ACAS") > 7) throw new StopRun();
                        goto openSystem;
                    case "W": goto acceptLoop;
                    default:
                        if (reply.Length == 1 && reply[0] >= 'I' && reply[0] <= 'V') break;
                        goto acceptLoop;
                }
            }
        }
        catch (StopRun) { }
        await EndOfProgram(c);
    }

    /// <summary>GnuCOBOL ランタイムの終了待ち画面。</summary>
    public static async Task EndOfProgram(Ctx c)
    {
        c.Crt.Clear();
        c.Crt.D("end of program, please press a key to exit", 0201, fg: 7);
        await c.Crt.Keys.Read();
    }

    public static async Task RunIrs(Ctx c)
    {
        try { await Irs.Menu(c); } catch (StopRun) { }
    }
}
