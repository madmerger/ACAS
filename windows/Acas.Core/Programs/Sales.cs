using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>sales.cbl: 売掛 (Sales Ledger) システムメニュー。</summary>
public static partial class Sales
{
    public static async Task<int> Menu(Ctx c)
    {
        var t = c.Crt;
        string reply = "A";
    openSystem:
        if (!c.LoadSys() || c.Sys.I("Cyclea") == 0)
        {
            c.SaveSys();
            if (await Sys002.Run(c, "Sales") > 7) throw new StopRun();
            goto openSystem;
        }
        string toDay = Launcher.BinToDate(c.Sys.N("Run-Date"));
        string op = c.Sys.I("Op-System") switch { 0 => "O/S", 1 => "Dos", 2 => "Windows", 3 => "Mac", 4 => "OS/2", 5 => "Unix", 6 => "Linux", _ => "" };
        int term = 0;
        if (reply == "A") goto load01;
    displayMenu:
        Common.MenuHead(c, toDay, "Sales (3.01.18)", "Sales Ledger System Menu", 0329);
        t.D("Select one of the following by letter  :- [ ]", 0601);
        t.Paint(
            (10, "   (A)  Date Entry                         (N)  Sales Day Book"),
            (11, "   (B)  Customer File Maintenance          (O)  Statement Production"),
            (12, "   (C)  Sales Ledger Enquiry               (P)  Dunning Letters Generation"),
            (13, "   (D)  Sales Transactions Input           (Q)  Aged Debtors Analysis"),
            (14, "   (E)  Sales Transactions Amend           (R)  Alphabetical Customer List"),
            (15, "   (F)  Sales Transactions Proof           (S)  Customer Turnover Report"),
            (16, "   (G)  Sales Transactions Post            (T)  Invoice Sub-System"),
            (17, "   (H)  Payment Input                      (U)  End of Cycle Processing"),
            (18, "   (I)  Payment Amend                      (V)  Customer File Dump"),
            (19, "   (J)  Payment Proof"),
            (20, "   (K)  Payment Post"),
            (21, "   (L)  Set-Up Sales Analysis Codes"),
            (22, "   (M)  Sales Analysis Report"));
        t.D("(X)  Exit To ", 2044); t.V(op, 2057, fg: 2);
        t.D("Using acasbkup.sh", 2149);
        t.D("(Z)  System Setup", 2344);
    acceptLoop:
        reply = (await t.A(0644, 1, auto: true)).ToUpperInvariant();
        switch (reply)
        {
            case "X": t.D(" ", 0101, eos: true); c.SaveSys(); c.BackupNoise = true; return 0;
            case "A": goto load01;
            case "B": term = await Sl010.Run(c, toDay); break;
            // レガシー実測: 以下は呼出先がファイルを開けず T-nnn エラーで停止する
            case "C": case "H": case "O": case "P": case "Q": await Ui.TError(c, "T-019", 56); break;
            case "I": await Ui.TError(c, "T-030", 56); break;
            case "K": await Ui.TError(c, "T-011", 56); break;
            case "D": term = await SlInv.Sl910(c, toDay); break;
            case "E": term = await SlInv.Sl920(c, toDay); break;
            case "F": term = await SlPost.Sl050(c, toDay); break;
            case "G": term = await SlPost.Sl055(c, toDay); break;
            case "J":
                t.V("SL090 (3.01.02)", 0101, eos: true, fg: 2);
                await Ui.TError(c, "T-030");
                break;
            case "L": term = await Sl070.Run(c, toDay); break;
            case "M": case "N": goto displayMenu;      // レガシー実測: 即時にメニューへ戻る
            case "R": term = await SlRep.Attributes(c, toDay, "SL160 (3.01.16)", 9, true); break;
            case "S": term = await SlRep.Attributes(c, toDay, "SL180 (3.01.08)", 9, true); break;
            case "V": term = await SlRep.Attributes(c, toDay, "SL170 (3.01.07)", 9, false); break;
            case "T": term = await SlInv.Sl900(c, toDay); break;
            case "U": term = await Xl150.Run(c, toDay); break;
            case "Z":
                c.SaveSys();
                if (await Sys002.Run(c, "Sales") > 7) throw new StopRun();
                goto openSystem;
            default: goto acceptLoop;
        }
        if (term > 7) { c.SaveSys(); return 0; }
        goto displayMenu;
    load01:
        reply = " ";
        toDay = await Common.StartOfDay(c, "SL000 (3.01.02)", "Sales Ledger  Start Of Day", 0328, "SL005 Invalid Date", 0360);
        goto displayMenu;
    }
}

/// <summary>得意先ファイルの帳票条件指定画面 (sl010 印刷 / sl160 / sl170 / sl180 共通)。</summary>
public static class SlRep
{
    public static async Task<int> Attributes(Ctx c, string toDay, string prog, int col, bool dateRow)
    {
        var t = c.Crt; string p = new string(' ', col - 1);
        t.V(prog, 0101, eos: true, fg: 2);
        t.D("Customer File", 0134); t.V(Common.ToForm(c, toDay), 0171);
        t.D("Report Attributes", 0332);
        t.Paint(
            (8, p + "Customer Number - [______]    Enter characters in positions to match"),
            (10, p + "Status          - [_]         <L> Live;<D> Dormant;< > All"),
            (12, p + "Credit Period   - [00]  [_]   Enter number of days & operator"),
            (13, p + "                                  <L>  for credit periods < than"),
            (14, p + "                                  <G>  for credit periods > than"),
            (15, p + "                                  <E>  for credit periods = to"),
            (17, p + "Invoice Activity  [00000] [_] Enter number of invoices & operator"),
            (19, p + "Average Value   - [00000] [_] Enter invoice value & operator"),
            (21, p + "Overdue A/Cs    - [00000] [_] Enter number of days & operator"));
        if (dateRow) t.Paint(23, p + "Date Entered-[__________] [_] Enter date & operator");
        await t.A(800 + col + 19, 6, init: "______");
        // TODO: 条件入力以降 (抽出・帳票出力) は未移植。入力後はメニューへ戻る。
        return 0;
    }
}
