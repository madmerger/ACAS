using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>stock.cbl: 在庫管理 (Stock Control) システムメニュー。</summary>
public static partial class Stock
{
    public static async Task<int> Menu(Ctx c)
    {
        var t = c.Crt;
        string reply = "A";
    openSystem:
        if (!c.LoadSys() || c.Sys.I("Cyclea") == 0)
        {
            c.SaveSys();
            if (await Sys002.Run(c, "Stock") > 7) throw new StopRun();
            goto openSystem;
        }
        string toDay = Launcher.BinToDate(c.Sys.N("Run-Date"));
        int term = 0;
        if (reply == "A") goto load01;
    displayMenu:
        t.D(" ", 0101, eos: true);
        t.V(c.Sys.S("Maps-Ser-xx"), 2474);
        t.V(Cob.P9(c.Sys.N("Maps-Ser-nn"), 4), 2476);
        t.D("Copyright (c) 1976-", 2401, fg: 3);
        t.V(c.Now().ToString("yyyy"), 2420);
        t.D(" Applewood Computers", 2424, fg: 3);
        t.V(c.Sys.S("Usera"), 0101);
        t.V(Common.ToForm(c, toDay), 0171);
        t.V("Stock (3.01.19)", 0301, fg: 2);
        t.D("Stock Control System Menu", 0328);
        t.D("at ", 0355); t.V(c.Time(), 0358, fg: 2);
        t.D("Select one of the following by letter  :- [ ]", 0601);
        t.D("(A)  Date Entry", 1004);
        t.D("(B)  Stock Item Maintenance", 1104);
        t.D("(C)  Stock Movements", 1204);
        t.D("(D)  Reports", 1304);
        t.D("(E)  End of Cycle Processing", 1044);
        t.D("(X)", 1244); t.D("Using acasbkup.sh", 1249);
        t.D("(Y)  Stock File Compression", 1344);
        t.D("(Z)  System Set Up", 1444);
    acceptLoop:
        reply = (await t.A(0644, 1, auto: true)).ToUpperInvariant();
        switch (reply)
        {
            case "X": t.D(" ", 0101, eos: true); c.SaveSys(); c.BackupNoise = true; c.BackupNoiseShort = true; return 0;
            case "A": goto load01;
            case "B": term = await St010.Run(c, toDay); break;
            case "C": term = await St020.Run(c, toDay); break;
            case "D": term = await St030.Run(c, toDay); break;
            case "E":
                StHead(c, toDay, "ST040 (3.01.06)", "Stock Activity Reset", 31);
                t.D("Can I clear this   Month Totals? [N] (N/Y)", 0410);
                t.D("Can I clear End of Year Totals on Stock records [ ] (N/Y)", 0610);
                // TODO: 月次・年次累計クリアの更新処理は未移植 (既定値 N のまま戻る)
                await t.A(0444, 1, init: "N", upper: true);
                break;
            case "Y":
                StHead(c, toDay, "ST050 (3.01.06)", "Stock Compression Utility", 28);
                t.D("This process will clean up the Stock File of deleted records", 0410);
                t.D("Is this a recovery from a previous run of this process - [N] (N/Y)", 0610);
                // TODO: 在庫ファイル圧縮処理は未移植
                await t.A(0668, 1, init: "N", upper: true);
                break;
            case "Z":
                c.SaveSys();
                if (await Sys002.Run(c, "Stock") > 7) throw new StopRun();
                goto openSystem;
            default:
                if (reply.Length == 1 && reply[0] >= 'A' && reply[0] <= 'Z') goto displayMenu;
                goto acceptLoop;
        }
        if (term > 7) { c.SaveSys(); return 0; }
        goto displayMenu;
    load01:
        reply = " ";
        toDay = await Common.StartOfDay(c, "ST000 (3.01.03)", "Stock Control - Start Of Day", 0327, "ST005 Invalid Date", 0360);
        goto displayMenu;
    }

    public static void StHead(Ctx c, string toDay, string prog, string title, int col)
    {
        var t = c.Crt;
        t.V(prog, 0101, eos: true, fg: 2);
        t.D(title, 100 + col);
        t.V(Common.ToForm(c, toDay), 0171);
    }
}

/// <summary>st030: 在庫帳票メニューと条件入力画面。TODO: 各帳票の抽出・印刷は未移植。</summary>
public static class St030
{
    private const string Prog = "ST030 (3.01.22)";
    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        while (true)
        {
            Stock.StHead(c, toDay, Prog, "Stock Control - Reports Menu", 27);
            t.D("Select one of the following by number :- [ ]", 0401);
            t.D("(1)  Valuation Report", 0604);
            t.D("(2)  Activity Report", 0704);
            t.D("(3)  Re-Order Report", 0804);
            t.D("(4)  Stock History Report", 0904);
            t.D("(5)  Stock Report", 1004);
            t.D("(9)  Return to System Menu", 1204);
            int m = (int)await t.AN(0443, 1, 0, auto: true);
            switch (m)
            {
                case 9: return 0;
                case 1: await Range(c, toDay, "Stock Valuation Report", 26); break;
                case 4: await Range(c, toDay, "Stock History Report", 27); break;
                case 5: await Range(c, toDay, "Stock Report", 31); break;
                case 2:
                    Head(c, toDay, "Stock Activity Report", 26);
                    Opts(t, "All Stock Items", "Range of Items", "Items Active in current Month", "Items Active in Year To Date",
                        "Range of active Items in Current Month", "Range of active Items in Year To Date");
                    await t.AN(0535, 1, 0, auto: true);
                    break;
                case 3:
                    Head(c, toDay, "Stock Re-Order Report", 26);
                    Opts(t, "All Stock Items", "A Range of Items", "Items that are Understocked", "Range of Understocked Items",
                        "Items, Not in Stock", "Range of Items, Not in Stock", "Items on Order", "Range of Items on Order");
                    await t.AN(0535, 1, 0, auto: true);
                    break;
            }
        }
    }

    private static void Head(Ctx c, string toDay, string title, int col)
    {
        Stock.StHead(c, toDay, Prog, title, col);
        c.Crt.D("Report Attributes", 0332);
    }

    private static void Opts(Crt t, params string[] o)
    {
        t.D("Select an Report Option Number : [ ]", 0501);
        for (int i = 0; i < o.Length; i++) t.D($"({i + 1})   {o[i]}", (7 + i) * 100 + 10);
        t.D("(9)   Return to Main Menu", (8 + o.Length) * 100 + 10);
    }

    private static async Task Range(Ctx c, string toDay, string title, int col)
    {
        var t = c.Crt;
        Head(c, toDay, title, col);
        const string hint = "Enter characters in positions to match";
        t.D("Leave fields blank to select All", 0524);
        t.D("Select Stock no. or Abrev Stock no. but NOT both", 0617);
        t.D("From Stock Number - [_____________]", 0804); t.D(hint, 0841);
        t.D("To Stock Number - [_____________]", 0906); t.D(hint, 0941);
        t.D("OR", 1014);
        t.D("From Abrev Number - [_______]", 1104); t.D(hint, 1141);
        t.D("To Abrev Number - [_______]", 1206); t.D(hint, 1241);
        await t.A(0825, 13, init: new string('_', 13), upper: true);
    }
}
