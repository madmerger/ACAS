using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>st020: 在庫移動 (入庫・出庫・バーコード入庫・発注) の入口画面。TODO: 明細入力後の在庫更新・監査ファイル更新・監査帳票は未移植。</summary>
public static class St020
{
    private const string Prog = "ST020 (3.01.29)";
    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        while (true)
        {
            Stock.StHead(c, toDay, Prog, "Stock Movements Menu", 31);
            t.D("Select one of the following by number :- [ ]", 0401);
            t.D("(1)  Stock Additions Entry", 0604);
            t.D("(2)  Stock Deductons Entry", 0704);
            t.D("(3)  Stock Additions from Barcode Readers", 0804);
            t.D("(4)  Stock Order Entry", 0904);
            t.D("(5)  End of Month Audit Reports", 1104);
            t.D("(9)  Return to System Menu", 1404);
            int m = (int)await t.AN(0443, 1, 0, auto: true);
            switch (m)
            {
                case 9: return 0;
                case 1: await Grid(c, toDay, "Stock Additions Entry", 30, 0); break;
                case 2: await Grid(c, toDay, "Stock Deductions Entry", 30, 1); break;
                case 3: await Grid(c, toDay, "Stock Barcode Additions Entry", 23, 0); break;
                case 4: await Grid(c, toDay, "Stock End of Month Processing", 26, 2); break;
                case 5:
                    t.D("Can I Delete the Audit File Now? [N]", 0401);
                    t.D(" Making sure that Sales Invoicing and Purchase Ledger are NOT running", 0601);
                    t.D(" Check that Reports are complete first, before responding", 0801);
                    t.D("Printing", 1337);
                    t.V(new string(' ', 79), 1401);
                    Audit(c, toDay, "Additions Stock Audit Report ", "Source/PO.no.");
                    // レガシーは同じ prt-1 を上書きする (スプールには両方残る)
                    c.Reports.RemoveAt(c.Reports.Count - 1); c.EnglishReports.RemoveAt(c.EnglishReports.Count - 1);
                    Audit(c, toDay, "Deductions Stock Audit Report", "Source/Inv.no.");
                    await t.A(0435, 1, init: "N", upper: true);
                    break;
            }
        }
    }

    private static async Task Grid(Ctx c, string toDay, string title, int col, int kind)
    {
        var t = c.Crt;
        Stock.StHead(c, toDay, Prog, title, col);
        t.Paint(3, kind switch
        {
            0 => " Stock Number    Description         Quantity    Price   Stk Qty   Stk Value",
            1 => " Stock Number    Description         Quantity    Stk Qty",
            _ => " Stock Number   Description          Qty Ord Date Ordered  Date Due  Back Qty"
        });
        string row = kind switch
        {
            0 => "[             ]{                    }[       ][         ]{      } [           ]",
            1 => "[             ]{                    }[       ]{      }",
            _ => "[             ]{                    }[      ][          ][          ][      ]"
        };
        for (int r = 5; r <= 22; r++) t.V(row, r * 100 + 1, fg: 2);
        c.OpenReport(Ctx.L + "prt-1").Close();      // レガシー実測: 監査帳票ファイルを開く (明細なしは空)
        var no = (await t.A(0502, 13, upper: true)).Trim();
        if (no.Length > 0)
        {
            // TODO: 明細入力は未移植。存在しない品目はレガシーと同じ ST203 を表示する
            if (kind < 2 && !StockExists(c, no))
            {
                t.D("ST203 Abbreviated Stock number not present", 2301);
                await t.A(0502, 13, upper: true);
            }
        }
    }

    /// <summary>月末監査帳票 (監査ファイルが空の場合の合計のみ)。TODO: 監査明細の印字は未移植。</summary>
    private static void Audit(Ctx c, string toDay, string title, string src)
    {
        var rp = c.OpenReport(Ctx.L + "prt-1");
        rp.Write(Prog.PadRight(55), new Lit(title.PadRight(69)), new Lit("Page "), "  1");
        rp.Write(c.Sys.S("Usera").PadRight(61), new Lit("Batch "), "  0".PadRight(49), Common.ToForm(c, toDay), " ", c.Time().Substring(0, 5));
        rp.Write("");
        rp.Write(new Lit("Proc. Date Stock Number  Description                         Qty    Price    Stock Value    " + src));
        rp.Write(""); rp.Write(""); rp.Write("");
        rp.Write(new string(' ', 56), new Lit("Total Additions "), "            0.00");
        rp.Write(new string(' ', 56), new Lit("Total Deductions"), "            0.00");
        rp.Write(new string(' ', 74), "--------------");
        rp.Write(new string(' ', 56), new Lit("Total Changes   "), "            0.00");
        rp.Write(new string(' ', 74), "==============");
        rp.Close();
    }

    private static bool StockExists(Ctx c, string no) =>
        c.Db.Scan(Ctx.L + "stockctl.dat").Any(r => System.Text.Encoding.Latin1.GetString(r.Data).Contains(no.PadRight(7)));
}
