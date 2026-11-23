using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>irs020: 既定勘定ユーティリティ。TODO: 既定勘定の登録・修正、決算書見出し設定の更新処理は未移植。</summary>
public static class Irs020
{
    private const string Prog = "irs020 (3.01.10)";
    public static async Task Run(Ctx c)
    {
        var t = c.Crt;
        while (true)
        {
            Irs.Head(c, Prog, "Default File Utilities", 29);
            t.D("Select the required function by number    [ ]", 0501);
            t.D("(1)  Set-Up Default Accounts", 0806);
            t.D("(2)  Amend  Default Accounts", 1006);
            t.D("(3)  Display the Defaults", 1206);
            t.D("(4)  Print   the Defaults", 1406);
            t.D("(5)  Set-Up Final Accounts", 1706);
            t.D("(9)  Return to System Menu", 2006);
            t.D("F1 to F5 = options 1 to 5;  Return to Accept data;   Escape to quit", 2301);
            int m = (int)await t.AN(0544, 1, 0, auto: true);
            switch (m)
            {
                case 9: return;
                case 1:
                    Irs.Head(c, Prog, "Default Accounts Setup", 29);
                    t.D("Add to Existing Defaults (Y/N) ? - [_]", 0501);
                    t.D("N.B. (1) If first time setup for this client answer no (N)", 0701);
                    t.D("(2) Answering no (N) destroys the existing defaults", 0806);
                    t.D("Escape to quit;    Return to Accept data", 2301);
                    await t.A(0537, 1, init: "_", upper: true);
                    break;
                case 2:
                    Table(c, "Default Accounts Amendments", 28);
                    t.D("Give Default to amend - [00]  (Use 00 to quit)", 2420);
                    await t.A(2445, 2, init: "00");
                    break;
                case 3:
                    Table(c, "Default Accounts Display", 27);
                    t.D("End of listing. Hit return for Menu.", 2401);
                    await t.A(2438, 1);
                    break;
                case 4: Print(c); break;
                case 5: await Final(c); break;
            }
        }
    }

    private static (string Ac, string Desc, string Code, string Vat) Entry(Ctx c, byte[]? d, int i)
    {
        string ac = Irs.S(d, i * 5, 5), desc = "";
        if (ac != "00000" && ac.Trim().Length > 0) desc = Irs.S(c.Db.Read(Ctx.I + "acnts.dat", ac + "00000"), 11, 24).TrimEnd();
        return (ac, desc, Irs.S(d, 160 + i * 2, 2), Irs.S(d, 224 + i, 1));
    }

    private static void Table(Ctx c, string title, int col)
    {
        var t = c.Crt; var d = c.Db.Read(Ctx.I + "dflt.dat", "1");
        Irs.Head(c, Prog, title, col);
        const string h = "A/C Nos   Description        Code VAT";
        t.D(h, 0504); t.D(h, 0544);
        for (int r = 0; r < 16; r++)
            for (int side = 0; side < 2; side++)
            {
                int i = r + side * 16; var e = Entry(c, d, i);
                // レガシー実測: 角括弧は先頭行のみ表示され、2 行目以降は行末の ] だけが残る
                string s = $"{i + 1:00} [{e.Ac}]{e.Desc.PadRight(22).Substring(0, 22)}[{e.Code}] [{e.Vat}]";
                if (r > 0) s = s.Substring(0, 39).Replace('[', ' ').Replace(']', ' ') + "]";
                t.V(s, (7 + r) * 100 + 1 + side * 40, fg: 2);
            }
    }

    private static void Print(Ctx c)
    {
        var s = Irs.SysRec(c); var d = c.Db.Read(Ctx.I + "dflt.dat", "1");
        var rp = c.OpenReport(Ctx.I + "prt-1");
        rp.Write("");
        rp.Write(Irs.S(s, 8, 24).PadRight(29), new Lit("Incomplete Records System".PadRight(42)), Irs.Today(c));
        rp.Write("");
        rp.Write(Irs.S(s, 32, 24).PadRight(33), new Lit("Posting Defaults"));
        rp.Write("");
        rp.Write(new Lit("             A/C Nos     ------Description------    Code VAT"));
        rp.Write(""); rp.Write("");
        for (int i = 0; i < 32; i++)
        {
            var e = Entry(c, d, i);
            if (e.Ac == "00000" || e.Ac.Trim().Length == 0) rp.Write((i + 1).ToString().PadLeft(12));
            else rp.Write((i + 1).ToString().PadLeft(12), "  ", e.Ac, new string(' ', 6), e.Desc.PadRight(28), e.Code, new string(' ', 5), e.Vat);
        }
        rp.Close();
    }

    private static async Task Final(Ctx c)
    {
        var t = c.Crt; var s = Irs.SysRec(c);
        t.V(" ", 0101, eos: true);
        t.D("Client ", 0101); t.V(Irs.S(s, 32, 24).TrimEnd(), 0108);
        t.D("Finished Accounts Setup", 0134); t.V(Irs.Today(c), 0173);
        t.D("Trading and Profit & Loss Account", 0304); t.D("Balance Sheet", 0354);
        const string hd = "--------Heading---------  Sign";
        t.D(hd, 0410); t.D(hd, 0450);
        string f(char ch) => $"<{ch}>   [________________________] [_]";
        void L(int row, char? l, char? r) { if (l != null) t.V(f(l.Value), row * 100 + 3, fg: 2); if (r != null) t.V(f(r.Value), row * 100 + 43, fg: 2); }
        t.D("Income Accounts", 0501); t.D("Fixed     Assets", 0541);
        L(6, 'A', 'O'); L(7, 'B', 'P'); L(8, 'C', 'Q'); L(9, 'D', null);
        t.D("Direct Cost Accounts", 1001); t.D("Current Assets", 1041);
        L(11, 'E', 'R'); L(12, 'F', 'S'); L(13, 'G', 'T'); L(14, 'H', null);
        t.D("Sundry Income Accounts", 1501); t.D("Current Liabilities", 1541);
        L(16, 'I', 'U'); L(17, 'J', 'V');
        t.D("Indirect Cost Accounts", 1801); t.D("Capital Accounts", 1841);
        L(19, 'K', 'W'); L(20, 'L', 'X'); L(21, 'M', 'Y'); L(22, 'N', 'Z');
        t.D("P & L Appropriation Account [00000]", 2301);
        await t.A(0610, 24, init: new string('_', 24));
    }
}
