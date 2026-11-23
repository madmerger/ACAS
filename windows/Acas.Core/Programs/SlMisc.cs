using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>売掛の転記系 (sl050 proof / sl055 post) の入口。TODO: 取引がある場合の帳票・転記は未移植。</summary>
public static class SlPost
{
    public static async Task<int> Sl050(Ctx c, string toDay)
    {
        var t = c.Crt;
        t.V("SL050 (3.01.10)", 0101, eos: true, fg: 2);
        t.D("Invoice Proof Report", 0132); t.V(Common.ToForm(c, toDay), 0171);
        if (c.Db.Count(Ctx.L + "invoice.dat") == 0)
        {
            t.D("SL120 No Transactions to proof! ...Press return for menu.", 0501);
            await t.A(0560, 1);
        }
        return 0;
    }

    public static async Task<int> Sl055(Ctx c, string toDay)
    {
        var t = c.Crt;
        t.V("SL055 (3.01.06)", 0101, eos: true, fg: 2);
        t.V(Common.ToForm(c, toDay), 0171);
        t.D("Working...........Please Wait", 1201);
        // レガシー実測 (SL-007): Open Item 2 ファイルが無く書込エラーで停止する
        t.D("SL121 Error writing to Open Item 2 File", 2301); t.V("35 File Not Found", 2341);
        t.D("SL002 Note error and hit return", 2401);
        await t.A(2433, 1);
        throw new StopRun { KeepScreen = true };
    }
}

/// <summary>xl150: 期末 (サイクル末) 処理の入口。TODO: 確認後の締め処理は未移植。</summary>
public static class Xl150
{
    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        t.V("xl150 (3.00.03)", 0101, eos: true, fg: 2);
        t.D("End of Cycle Processing", 0130); t.V(Common.ToForm(c, toDay), 0171);
        t.D("WARNING: MAKE SURE THAT DATE IS AT END OF CYCLE.IE END OF MONTH", 0501);
        t.D("Have you made a Backup of ALL DATA FILES? If so;", 0612);
        t.D("Confirm end of Cycle Processing to be Run (Y/N) - [N]", 0712);
        var r = await t.A(0763, 1, init: "N");
        _ = r;
        return 0;
    }
}

/// <summary>sl010: 得意先ファイル保守 (機能メニューと各入力画面の入口)。TODO: 得意先レコードの登録・変更・削除・表示は未移植。</summary>
public static class Sl010
{
    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        while (true)
        {
            t.V("SL010 (3.01.20)", 0101, eos: true, fg: 2);
            t.D("Customer File Set-Up & Maintenance", 0124); t.V(Common.ToForm(c, toDay), 0171);
            t.D("Function  Menu", 0434);
            t.D("Select one of the following by number :- [ ]", 0701);
            t.D("(1)  Set-up customer records", 1004);
            t.D("(2)  Amend Customer records", 1204);
            t.D("(3)  Delete Customer records", 1404);
            t.D("(4)  Print Customer records", 1604);
            t.D("(5)  Display Customer records", 1804);
            t.D("(9)  Return to system menu", 2104);
            int m = (int)await t.AN(0743, 1, 0, auto: true);
            switch (m)
            {
                case 9: return 0;
                case 1: await Form(c, toDay, "Customer Record Creation", true, false); break;
                case 2: await Form(c, toDay, "Customer Record Amendment", false, false); break;
                case 3: await Form(c, toDay, "Customer Record Deletion", false, true); break;
                case 4: await SlRep.Attributes(c, toDay, "SL010 (3.01.20)", 3, true); break;
                case 5: await Form(c, toDay, "Customer Record Display ", false, false); break;
            }
        }
    }

    private static async Task Form(Ctx c, string toDay, string title, bool create, bool delete)
    {
        var t = c.Crt;
        t.V("SL010 (3.01.20)", 0101, eos: true, fg: 2);
        t.D(title, 0129); t.V(Common.ToForm(c, toDay), 0171);
        string f30 = "[" + new string(' ', 30) + "]", f48 = "[" + new string(' ', 48) + "]";
        t.Paint(4, create ? "Customer Nos : [      ]  Check Digit { }" : "Customer Nos : [       ]");
        t.Paint(
            (6, "Customer Name: " + f30), (7, "         Addr: " + f48), (8, "               " + f48),
            (9, "Delivery name: " + f30), (10, "         Addr: " + f48), (11, "               " + f48),
            (12, "Customer Note: " + f48), (13, "               " + f48),
            (14, "Telephone    : [             ] Ext: [    ]  Fax : [             ]"),
            (15, "Email Sales  : " + f30),
            (16, "Late charges : [ ]       Minimum balance before late charge : [0000]"),
            (17, "Late letters : [ ]       Maximum late charge                : [0000]"),
            (18, "Credit period: [00]      EMail-Inv:[ ] Stat: [ ] Dun : [ ]"),
            (19, "Credit limit : [0000000] Discount : [00.00]"),
            (20, "Unapplied Bal: {            }"), (21, "Current Bal  : {            }"),
            (22, "Last invoice : {          }"), (23, "Last payment : {          }"));
        string stars = new string('*', 19);
        t.V(stars, 1956, fg: 2); t.V(stars, 2456, fg: 2);
        t.D("* Escape Code [ ] *", 2056);
        t.D(delete ? "* <D> = Dormant   *" : "* <B> = Back      *", 2156);
        t.D(delete ? "* <K> = Kill      *" : "* <S> = Save      *", 2256);
        t.D("* <Q> = Quit      *", 2356);
        await t.A(0417, create ? 6 : 7);
    }
}
