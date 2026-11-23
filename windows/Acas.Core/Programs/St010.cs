using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>st010: 在庫品目ファイル保守 (機能メニューと各入力画面の入口)。TODO: 在庫レコードの登録・変更・削除・付番・表示・印刷の更新処理は未移植。</summary>
public static class St010
{
    private const string Prog = "ST010 (3.01.37)";
    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        while (true)
        {
            Stock.StHead(c, toDay, Prog, "Stock File Set-Up & Maintenance", 24);
            t.V(c.Sys.S("Usera"), 0301);
            t.D("Function  Menu", 0434);
            t.D("Select one of the following by number :- [ ]", 0701);
            t.D("(1)  Set-up Stock records", 0904);
            t.D("(2)  Amend Stock records", 1104);
            t.D("(3)  Delete Stock records", 1304);
            t.D("(4)  Renumber Stock records", 1504);
            t.D("(5)  Display Stock records", 1704);
            t.D("(6)  Print Stock records", 1904);
            t.D("(9)  Return to system menu", 2104);
            int m = (int)await t.AN(0743, 1, 0, auto: true);
            switch (m)
            {
                case 9: return 0;
                case 1: await Form(c, toDay, "Stock Record Creation", false, true); break;
                // レガシー実測 (ST-204): 変更はファイルエラー T-045 で停止する
                case 2: await Ui.TError(c, "T-045"); break;
                case 3: await Form(c, toDay, "Stock Record Deletion", false, true); break;
                // レガシー実測 (ST-206): 付番は画面を消去せずに入力画面を重ね描きする
                case 4: await Form(c, toDay, null, true, false); break;
                case 5: await Form(c, toDay, "Stock Record Display ", true, true); break;
                case 6: Print(c, toDay); break;
            }
        }
    }

    private static async Task Form(Ctx c, string toDay, string? title, bool prices, bool clear)
    {
        var t = c.Crt;
        if (clear)
        {
            Stock.StHead(c, toDay, Prog, title!, 29);
            t.V(c.Sys.S("Usera"), 0301);
        }
        if (!clear) for (int r = 4; r <= 14; r++) t.V(new string(' ', 19), r * 100 + 1);
        t.Paint(
            (4, "Stock Number     - [             ]      PL Fast key  - [       ]"),
            (5, "Desc [                                ] Stock Location [          ]"),
            (6, "Supplier: 1 - [       ] : 2 - [       ]          : 3 - [       ]"),
            (7, "Stock Qty        - [000000]             Qty Ordered      - [000000]"),
            (8, "Re-Order Point   - [000000]             Back Ordered     - [000000]"),
            (9, "Re-Order Qty     - [000000]             Sales Orders O/S - [000000]"),
            (10, "Sales Anal. Code - [  ]                 Purch Anal.Code[  ]"),
            (11, "Services only Flag [ ] (Y/N)"),
            (12, "Date Ordered - [          ]             Date Due     - [          ]"));
        if (prices)
            t.Paint(
                (13, "Retail Price - [0000000.00]             Cost   Price - [0000000.0000]"),
                (14, "Stock Value  - [000000000.00]"));
        string stars = new string('*', 19);
        t.V(stars, 1861, fg: 2); t.V(stars, 2361, fg: 2);
        t.D("* Escape Code [ ] *", 1961);
        t.D("* <B> = Back      *", 2061);
        t.D("* <S> = Save      *", 2161);
        t.D("* <Q> = Quit      *", 2261);
        var no = await t.A(0421, 13, upper: true);
        _ = no;     // TODO: 在庫レコードの読込以降は未移植
    }

    private static decimal P3(byte[] d, int off, int len, int dec)
    {
        decimal v = 0;
        for (int i = 0; i < len; i++)
        {
            v = v * 10 + (d[off + i] >> 4);
            if (i < len - 1) v = v * 10 + (d[off + i] & 15);
        }
        for (int i = 0; i < dec; i++) v /= 10;
        return (d[off + len - 1] & 15) == 0x0D ? -v : v;
    }
    private static int Bin(byte[] d, int off) => (d[off] << 24) | (d[off + 1] << 16) | (d[off + 2] << 8) | d[off + 3];
    private static string Txt(byte[] d, int off, int len) => System.Text.Encoding.Latin1.GetString(d, off, len);

    /// <summary>在庫ファイル一覧表 (全件)。TODO: 範囲指定・サービス品・発注日/納期の印字・改ページは未移植。</summary>
    private static void Print(Ctx c, string toDay)
    {
        var rp = c.OpenReport(Ctx.L + "prt-1");
        rp.Write(Prog.PadRight(57), new Lit("Stock File Report".PadRight(67)), new Lit("Page "), "  1");
        rp.Write(c.Sys.S("Usera").PadRight(116), Common.ToForm(c, toDay), " ", c.Time().Substring(0, 5));
        rp.Write("");
        rp.Write(new Lit("<------ Stock ------> Supplier  Location     Unit      Unit        Value    Number <- ReOrder -> <------- Date ------>  Quantity On"));
        rp.Write(new Lit("Abrev   Number         Number               Price      Cost        in Stk   in Stk  Point    Qty   Ordered     Due      Order  B/Ord"));
        int n = 0;
        foreach (var (_, d) in c.Db.Scan(Ctx.L + "stockctl.dat"))
        {
            if (d.Length < 177) continue;
            rp.Write(n == 0 ? "" : new string('-', 132));
            n++;
            rp.Write(Txt(d, 13, 7), " ", Txt(d, 0, 13), " ", Txt(d, 20, 7), " ", Txt(d, 86, 10), " ",
                Cob.Edit(P3(d, 152, 5, 2), "ZZZZZZ9.99"), Cob.Edit(P3(d, 157, 6, 4), "ZZZZZZ9.99"), Cob.Edit(P3(d, 163, 6, 2), "ZZZZZZZZZZ9.99"),
                Bin(d, 144).ToString().PadLeft(7), Bin(d, 128).ToString().PadLeft(7), Bin(d, 132).ToString().PadLeft(7),
                new string(' ', 22), Bin(d, 140).ToString().PadLeft(7), Bin(d, 136).ToString().PadLeft(7));
            rp.Write(new Lit("     Description: "), Txt(d, 41, 32));
        }
        rp.Write(""); rp.Write("");
        rp.Write(new Lit(" Total Stock Records "), n.ToString());
        rp.Close();
    }
}
