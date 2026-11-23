using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>請求サブシステム (sl900 メニュー・固定項目 / sl910 入力 / sl920 修正 / sl940 削除 / sl930・sl950 印刷) の入口画面。
/// TODO: 各画面の最初の入力項目より先 (明細入力・更新・印刷) は未移植。</summary>
public static class SlInv
{
    private static void Head(Ctx c, string toDay, string prog, string title, int col)
    {
        var t = c.Crt;
        t.V(prog, 0101, eos: true, fg: 2);
        t.D(title, 100 + col);
        t.V(Common.ToForm(c, toDay), 0171);
    }

    public static async Task<int> Sl900(Ctx c, string toDay)
    {
        var t = c.Crt;
        if (c.Sys.N("Next-Invoice") == 0) await FixedData(c, toDay);
        while (true)
        {
            Head(c, toDay, "SL900 (3.01.09)", "Invoicing Menu", 34);
            t.D("Select one of the following by number :- [ ]", 0501);
            t.D("(1)  Amend Invoicing Fixed Data", 0811);
            t.D("(2)  Enter Invoices For Batch Printing", 0911);
            t.D("(3)  Enter Invoice For Immediate Printing", 1011);
            t.D("(7)  Print Invoices", 1411);
            t.D("(8)  Print Delivery Notes/Picking Lists", 1511);
            t.D("(4)  Amend Invoices", 1111);
            t.D("(5)  Delete Invoices", 1211);
            t.D("(6)  Invoice Deletion Report", 1311);
            t.D("(9)  Return To System menu", 1711);
            int m = (int)await t.AN(0543, 1, 0, auto: true);
            switch (m)
            {
                case 9: return 0;
                case 1: await FixedData(c, toDay); break;
                case 2: case 3: await Sl910(c, toDay); break;
                case 4: await Sl920(c, toDay); break;
                case 5: await Sl940(c, toDay); break;
                case 6: break;                       // sl200: レガシー実測では即時にメニューへ戻る
                case 7: await Print(c, toDay, "SL930 (3.01.12)", "Invoice Printing", 34); break;
                case 8: await Print(c, toDay, "SL950 (3.01.05)", "Delivery / Picking Note Print", 26); break;
            }
        }
    }

    private static async Task FixedData(Ctx c, string toDay)
    {
        var t = c.Crt;
        Head(c, toDay, "SL900 (3.01.09)", "Invoicing Fixed Data", 31);
        t.D("Next Invoice", 0511); t.D("- [        ]", 0545);
        t.D("Extra Charge/Discount Description - [", 0711); t.D("]", 0762);
        t.D("Extra Charge/Discount Type (C/D)  - [ ]", 0911);
        t.D("Print Extra on Invoices (N/Y)     - [ ]", 1011);
        t.D("Extra Charge/Discount Percentage  - [     ]", 1111);
        t.D("Invoice Entry Level (1, 2) ", 1311); t.D("- [ ]", 1345);
        t.D("Invoice to Stock Link  - [ ]", 1411);
        t.D("Invoice to Stock Audit - [ ]", 1511);
        t.D("Extra Charge Discount Account", 1611); t.D("- [      ]", 1645);
        t.D("Vat Account", 1711); t.D("- [      ]", 1745);
        t.D("Proforma Retention In Days ", 1911); t.D("- [   ]", 1945);
        t.D("Details Ok To File (Y/N) ...........[Y]", 2111);
        t.V(Cob.P9(c.Sys.N("Next-Invoice"), 8), 0548);
        t.V("00.00", 1148); t.V("2", 1348); t.V("N", 1437); t.V("000000", 1648); t.V("000000", 1748); t.V("000", 1948);
        var s = await t.A(0548, 8, init: Cob.P9(c.Sys.N("Next-Invoice"), 8));
        // TODO: 残りの固定項目の入力と保存
        _ = s;
    }

    private static void Box(Crt t, string l5, string l6, string l7)
    {
        string stars = new string('*', 40);
        t.V(stars, 0441, fg: 2); t.V(stars, 0841, fg: 2);
        t.D(l5, 0541); t.D(l6, 0641); t.D(l7, 0741);
    }

    public static async Task<int> Sl910(Ctx c, string toDay)
    {
        var t = c.Crt;
        Head(c, toDay, "SL910 (3.01.13)", "Invoicing Data Entry", 32);
        Box(t, "*Date  [          ]*                   *", "*A/C Nos  [       ]*Ref    [          ]*", "*Invoice [        ]*Order  [          ]*");
        t.V(Common.ToForm(c, toDay), 0549);
        t.D("F1 = Setup new Customer; F8 = Only Show delivery details", 0911);
        t.D("Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note; <4> = Pro-Forma", 1001);
        await t.A(0549, 10, init: Common.ToForm(c, toDay));
        return 0;
    }

    public static async Task<int> Sl920(Ctx c, string toDay)
    {
        var t = c.Crt;
        Head(c, toDay, "SL920 (3.01.08)", "Invoicing Data Amend", 32);
        Box(t, "*Date   [  /  /    ]*                  *", "*A/C Nos   [       ]*Ref   [          ]*", "*Invoice [00000000] *Order [          ]*");
        t.D("F8 = Only Show delivery details on 'A/C nos' entry", 0911);
        t.D("Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note; <4> = Pro-Forma", 1001);
        await t.A(0751, 8, init: "00000000");
        return 0;
    }

    public static async Task<int> Sl940(Ctx c, string toDay)
    {
        var t = c.Crt;
        Head(c, toDay, "SL940 (3.01.04)", "Invoicing Data Deletion", 31);
        Box(t, "*Date   [  /  /    ]*                  *", "*A/C Nos   [       ]*                 **", "*Invoice [00000000 ]*Order [          ]*");
        t.D("Type [ ]  <1> = Receipt; <2> = Account; <3> = CrediT Note; <4> = Pro-Forma", 1001);
        await t.A(0751, 8, init: "00000000");
        return 0;
    }

    private static async Task Print(Ctx c, string toDay, string prog, string title, int col)
    {
        var t = c.Crt;
        Head(c, toDay, prog, title, col);
        t.D("Print Or Re-Print.............  (P/R) ? - [P]", 0701);
        await t.A(0744, 1, init: "P");
    }
}
