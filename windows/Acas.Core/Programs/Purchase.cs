using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>purchase.cbl: 買掛 (Purchase Ledger) システムメニュー。</summary>
public static partial class Purchase
{
    public static async Task<int> Menu(Ctx c)
    {
        var t = c.Crt;
        string reply = "A";
    openSystem:
        if (!c.LoadSys() || c.Sys.I("Cyclea") == 0)
        {
            c.SaveSys();
            if (await Sys002.Run(c, "Purchase") > 7) throw new StopRun();
            goto openSystem;
        }
        string toDay = Launcher.BinToDate(c.Sys.N("Run-Date"));
        string op = c.Sys.I("Op-System") switch { 0 => "O/S", 1 => "Dos", 2 => "Windows", 3 => "Mac", 4 => "OS/2", 5 => "Unix", 6 => "Linux", _ => "" };
        int term = 0;
        if (reply == "A") goto load01;
    displayMenu:
        Common.MenuHead(c, toDay, "Purchase (3.01.19)", "Purchase Ledger System Menu", 0326);
        t.D("Select one of the following by letter  :- [ ]", 0601);
        t.Paint(
            (10, "   (A)  Date Entry                         (N)  Purchase Analysis Report"),
            (11, "   (B)  Supplier File Maintenance          (O)  Purchase Day Book"),
            (12, "   (C)  Purchase Ledger Enquiry            (P)  Aged Creditors Report"),
            (13, "   (D)  Purchase Transactions Input        (Q)  Alphabetical Supplier List"),
            (14, "   (E)  Purchase Transactions Amend        (R)  Supplier Turnover Report"),
            (15, "   (F)  Purchase Transactions Delete       (S)  Cheque  Sub-System"),
            (16, "   (G)  Purchase Transactions Proof        (T)  End Of Cycle Processing"),
            (17, "   (H)  Purchase Transactions Post         (U)  Invoice Parameter Amend"),
            (18, "   (I)  Payment Input                      (V)  Supplier File Dump"),
            (19, "   (J)  Payment Amend"),
            (20, "   (K)  Payment Proof"),
            (21, "   (L)  Payment Post"),
            (22, "   (M)  Set-Up Purchase Analysis Codes"));
        t.D("(X)  Exit to ", 1944); t.V(op, 1957, fg: 2);
        t.D("Using acasbkup.sh", 2049);
        t.D("(Z)  System Set Up", 2244);
    acceptLoop:
        reply = (await t.A(0644, 1, auto: true)).ToUpperInvariant();
        switch (reply)
        {
            case "X": t.D(" ", 0101, eos: true); c.SaveSys(); c.BackupNoise = true; return 0;
            case "A": goto load01;
            case "B": term = await Pl010.Run(c, toDay); break;
            // レガシー実測: 以下は呼出先がファイルを開けず T-nnn エラーで停止する
            case "C": case "P": await Ui.TError(c, "T-025", 56); break;
            case "F": await Ui.TError(c, "T-017", 56); break;
            case "J": await Ui.TError(c, "T-030", 56); break;
            case "L": await Ui.TError(c, "T-023", 56); break;
            case "G": await Cleared(c, c.Db.Count(Ctx.L + "pinvoice.dat") > 0 ? "T-015" : "T-014", true); break;
            case "H": await Cleared(c, c.Db.Count(Ctx.L + "pinvoice.dat") > 0 ? "T-015" : "T-014", true); break;
            case "I": await Cleared(c, "T-025", true); break;
            case "K": await Cleared(c, "T-030", false); break;
            case "D": term = await PlInv.Pl020(c, toDay); break;
            case "E": term = await PlInv.Pl030(c, toDay); break;
            case "M": term = await Sl070.Run(c, toDay, "PL070 (3.01.11)"); break;
            case "N": case "O": goto displayMenu;      // レガシー実測: 即時にメニューへ戻る
            case "Q": term = await SlRep.Attributes(c, toDay, "PL160 (3.01.05)", 9, true, "Supplier File", 34, "Supplier"); break;
            case "R": term = await SlRep.Attributes(c, toDay, "PL170 (3.01.06)", 9, true, "Supplier File", 34, "Supplier"); break;
            case "V": term = await SlRep.Attributes(c, toDay, "PL190 (3.01.04)", 9, false, "Suppler File", 34, "Supplier"); break;
            case "S": term = await PlChq.Menu(c, toDay); break;
            case "T": term = await Xl150.Run(c, toDay); break;
            case "U": term = await PlInv.Pl180(c, toDay); break;
            case "Z":
                c.SaveSys();
                if (await Sys002.Run(c, "Purchase") > 7) throw new StopRun();
                goto openSystem;
            default: goto acceptLoop;
        }
        if (term > 7) { c.SaveSys(); return 0; }
        goto displayMenu;
    load01:
        reply = " ";
        toDay = await Common.StartOfDay(c, "PL000 (3.01.01)", "Purchase Ledger  Start Of Day", 0328, "PL005 Invalid Date", 0360);
        goto displayMenu;
    }

    /// <summary>レガシー実測: 呼出先が画面を消去した後にファイルエラーで停止する (PL-007/009/011/413)。</summary>
    private static async Task Cleared(Ctx c, string code, bool frame)
    {
        var t = c.Crt;
        t.V(" ", 0101, eos: true);
        if (frame)
        {
            t.V(c.Sys.S("Usera"), 0101);
            t.D("Copyright (c) 1976-", 2401); t.V(c.Now().Year.ToString(), 2420); t.D(" Applewood Computers", 2424);
            t.V("mp999", 2474, fg: 2);
        }
        await Ui.TError(c, code);
    }
}

/// <summary>pl010: 仕入先ファイル保守 (機能メニューと各入力画面の入口)。TODO: 仕入先レコードの登録・変更・削除・表示は未移植。</summary>
public static class Pl010
{
    private const string Prog = "PL010 (3.01.13)";
    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        while (true)
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Supplier File Set-Up & Maintenance", 0124); t.V(Common.ToForm(c, toDay), 0171);
            t.D("Function  Menu", 0434);
            t.D("Select one of the following by number :- [ ]", 0701);
            t.D("(1)  Set-up Supplier records", 1004);
            t.D("(2)  Amend Supplier records", 1204);
            t.D("(3)  Delete Supplier records", 1404);
            t.D("(4)  Print Supplier records", 1604);
            t.D("(5)  Display Supplier records", 1804);
            t.D("(9)  Return to system menu", 2104);
            int m = (int)await t.AN(0743, 1, 0, auto: true);
            switch (m)
            {
                case 9: return 0;
                case 1: await Form(c, toDay, "Supplier Record Creation", true, false); break;
                case 2: await Form(c, toDay, "Supplier Record Amendment", false, false); break;
                case 3: await Form(c, toDay, "Supplier Record Deletion", false, true); break;
                case 4: await SlRep.Attributes(c, toDay, Prog, 3, true, "Supplier File", 34, "Supplier"); break;
                case 5: await Form(c, toDay, "Supplier Record Display ", false, false); break;
            }
        }
    }

    private static async Task Form(Ctx c, string toDay, string title, bool create, bool delete)
    {
        var t = c.Crt;
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D(title, 0129); t.V(Common.ToForm(c, toDay), 0171);
        string f30 = "[" + new string(' ', 30) + "]", f48 = "[" + new string(' ', 48) + "]";
        t.Paint(4, create ? "Supplier Nos : [      ]  Check Digit { }" : "Supplier Nos : [       ]");
        t.Paint(
            (6, "Supplier Name: " + f30), (7, "         Addr: " + f48), (8, "               " + f48),
            (9, "Suppliers Bank Details"), (10, "  Sort Code  : [000000]"), (11, "  Account No : [00000000]"),
            (12, "Supplier Note: " + f48), (13, "               " + f48),
            (14, "Telephone    : [             ] Ext: [    ]  Fax : [             ]"),
            (15, "Email Sales  : " + f30),
            (18, "Credit Period: [00]"),
            (19, "Credit limit : [0000000] Discount : [00.00]"),
            (20, "Unapplied Bal: {            }"), (21, "Current Bal  : {            }"),
            (22, "Last invoice : {          }"), (23, "Last payment : {          }"));
        string stars = new string('*', 19);
        t.V(stars, 1956, fg: 2); t.V(stars, 2456, fg: 2);
        t.D("* Escape Code [ ] *", 2056);
        t.D(delete ? "* <D> = Dormant   *" : "* <B> = Back      *", 2156);
        t.D(delete ? "* <K> = Kill      *" : "* <S> = Save      *", 2256);
        t.D("* <Q> = Quit      *", 2356);
        var no = await t.A(0417, create ? 6 : 7, upper: true);
        // TODO: 仕入先レコードの読込以降は未移植
        // レガシー実測 (PL-402): 表示で存在しないキーを指定するとファイルエラー T-003 で停止する
        if (title.StartsWith("Supplier Record Display") && no.Trim().Length > 0) await Ui.TError(c, "T-003", 56);
    }
}

/// <summary>仕入請求 (pl020 入力 / pl030 修正 / pl180 固定項目) の入口画面。TODO: 明細入力・更新は未移植。</summary>
public static class PlInv
{
    private static void Box(Crt t, string l5, string l6, string l7)
    {
        string stars = new string('*', 40);
        t.V(stars, 0441, fg: 2); t.V(stars, 0841, fg: 2);
        t.D(l5, 0541); t.D(l6, 0641); t.D(l7, 0741);
    }

    public static async Task<int> Pl020(Ctx c, string toDay)
    {
        var t = c.Crt;
        PlChq.Head(c, toDay, "PL020 (3.01.08)", "Invoice Data Entry", 32);
        Box(t, "*Date [          ]*A/C Nos    [       ]*", "**                *Order   [          ]*", "*Folio  [        ]*Invoice [          ]*");
        t.V(Common.ToForm(c, toDay), 0548);
        t.D("F1 = Setup new Supplier", 0911);
        t.D("Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note", 1001);
        await t.A(0548, 10, init: Common.ToForm(c, toDay));
        var ac = await t.A(0572, 7, upper: true);
        // レガシー実測 (PL-412): 仕入先ファイル参照でファイルエラーとなり停止する
        if (ac.Trim().Length > 0) await Ui.TError(c, "T-021");
        return 0;
    }

    public static async Task<int> Pl030(Ctx c, string toDay)
    {
        var t = c.Crt;
        PlChq.Head(c, toDay, "PL030 (3.01.01)", "Invoice Data Amend", 33);
        Box(t, "*Date [  /  /    ]*A/C Nos    [       ]*", "**                *Order   [          ]*", "*Folio  [00000000]*Invoice [          ]*");
        t.D("Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note", 1001);
        await t.A(0750, 8, init: "00000000");
        return 0;
    }

    public static async Task<int> Pl180(Ctx c, string toDay)
    {
        var t = c.Crt;
        PlChq.Head(c, toDay, "PL180 (3.00.02)", "Invoicing Fixed Data", 31);
        t.D("Next Folio", 0511); t.D("- [        ]", 0545);
        t.D("Vat Account", 0711); t.D("- [      ]", 0745);
        t.D("Details ok to file (Y/N) ...........[Y]", 1011);
        await t.A(0548, 8, init: "00000000");
        return 0;
    }
}
