using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>irs010: 勘定科目表ユーティリティ。TODO: 科目の登録・修正・エクスポート・インポートの更新処理は未移植。</summary>
public static class Irs010
{
    private const string Prog = "irs010 (3.01.11)";
    public static async Task Run(Ctx c)
    {
        var t = c.Crt;
        while (true)
        {
            // zz000-clear-NL: 科目表があり転記ファイルが無い場合は初回実行とみなして確認する
            if (c.Db.Count(Ctx.I + "acnts.dat") > 0 && !c.Db.Exists(Ctx.I + "post.dat"))
            {
                t.V(" ", 0101, eos: true);
                t.D("This appears to be the first time you are running IRS and there is a", 0101);
                t.D("set of accounts (Nominal Ledger) present", 0221);
                t.D("Can I clear down all amounts from these, so that you can start with a clean", 0401);
                t.D("set of accounts", 0533);
                Warn(t);
                var r = await t.A(1215, 1);
                // TODO: Y (残高クリア) は未移植。N 以外でも残高は変更しない
                _ = r;
            }
        menu:
            Irs.Head(c, Prog, "Accounts File Utilities", 29);
            t.D("Select the required function by number    [ ]", 0501);
            t.D("(1)  Set-Up Chart of Accounts", 0806);
            t.D("(2)  Amend  Chart of Accounts", 1006);
            t.D("(3)  Display the Chart", 1206);
            t.D("(4)  Print   the Chart", 1406);
            t.D("(5)  Export  the Chart", 1506);
            t.D("(6)  Import  the Chart", 1606);
            t.D("(9)  Return to System Menu", 1806);
            t.D("F1 to F4 = options 1 to 4;  Return to Accept data;   Escape to quit", 2301);
            int m = (int)await t.AN(0544, 1, 0, auto: true);
            switch (m)
            {
                case 9: return;
                case 1:
                    Irs.Head(c, Prog, "Chart of Accounts Setup", 30);
                    t.D("Add to Existing Chart (Y/N) ? - [_]", 0501);
                    t.D("N.B. (1) If first time setup for this client answer no (N)", 0701);
                    t.D("(2) Answering no (N) destroys the existing chart", 0806);
                    t.D("Escape to quit;    Return to Accept data", 2301);
                    await t.A(0534, 1, init: "_", upper: true);
                    goto menu;
                case 2:
                    Irs.Head(c, Prog, "Chart of Accounts Amendments", 28);
                    t.D("Main A/C      Sub-Nominal       Sub-Account       Description          A/C Type", 0402);
                    foreach (int r in new[] { 6, 22, 23 })
                        t.V(" [     ]           [ ]             [     ]   [                        ]   [ ]", r * 100 + 1, fg: 2);
                    await t.A(0603, 5, init: "00000");
                    goto menu;
                case 3:
                    {
                        var s = Irs.SysRec(c);
                        t.V(Irs.S(s, 8, 24).TrimEnd(), 0101, eos: true, fg: 2);
                        t.D("Incomplete Records System", 0128); t.V(Irs.Today(c), 0173);
                        t.D("Client - ", 0301); t.V(Irs.S(s, 32, 24).TrimEnd(), 0310);
                        t.D("Accounts Directory", 0332); t.D("Page ", 0373); t.V("  1", 0378);
                        t.D("Main       Sub             Description              Type", 0513);
                        int row = 7;
                        foreach (var (k, d) in c.Db.Scan(Ctx.I + "acnts.dat"))
                        {
                            if (row > 22) break;    // TODO: 2 ページ目以降の表示は未移植
                            t.V(k.Substring(0, 5), row * 100 + 12);
                            if (k.Substring(5) != "00000") t.V(k.Substring(5), row * 100 + 23);
                            t.V(Irs.S(d, 11, 24), row * 100 + 36);
                            t.V(Irs.S(d, d.Length - 1, 1), row * 100 + 66);
                            row++;
                        }
                        t.D("End of display. Hit return for Menu.", 2418);
                        await t.A(2455, 1);
                        goto menu;
                    }
                case 4:
                    {
                        var s = Irs.SysRec(c);
                        var rp = c.OpenReport(Ctx.I + "prt-1");
                        rp.Write("");
                        rp.Write(Irs.S(s, 8, 24).PadRight(28), new Lit("Incomplete Records System".PadRight(44)), Irs.Today(c));
                        rp.Write("");
                        rp.Write(Irs.S(s, 32, 24).PadRight(31), new Lit("Accounts Directory".PadRight(40)), new Lit("Page -"), "  1");
                        rp.Write("");
                        rp.Write(new Lit("             Main A/C       Sub-Account     ------Description------    A/C Type"));
                        rp.Write("");
                        foreach (var (k, d) in c.Db.Scan(Ctx.I + "acnts.dat"))
                            rp.Write(new string(' ', 14), k.Substring(0, 5), new string(' ', 11),
                                (k.Substring(5) == "00000" ? "" : k.Substring(5)).PadRight(14), Irs.S(d, 11, 24), new string(' ', 7), Irs.S(d, d.Length - 1, 1));
                        rp.Close();
                        break;      // レガシー実測 (IRS-206): 印刷後は初回確認から再開する
                    }
                case 5:
                    t.V(" ", 0101, eos: true);
                    t.D("This process will export a copy of the current CoA (Chart of Accounts)", 0101);
                    t.D("overwriting any copy of the file if it exists.", 0221);
                    t.D("Continue Y/N [ ]", 0401);
                    await t.A(0415, 1);
                    goto menu;
                case 6:
                    t.V(" ", 0101, eos: true);
                    t.D("This process will import a CoA (Chart of Accounts) in TEXT format", 0101);
                    t.D("overwriting any existing IRS Chart of Accounts.", 0201);
                    t.D("This must only be done for a new set of accounts for a new client.", 0301);
                    t.D("OTherwise, If you have not made a back up of it you should quit this process.", 0401);
                    Warn(t);
                    await t.A(1215, 1);
                    goto menu;
                default: goto menu;
            }
        }
    }

    private static void Warn(Crt t)
    {
        t.D("Warning: This is NON RECOVERABLE, so think about it", 0714, fg: 4);
        t.D("Before responding (Y)es ensure you have a back copy of the original file", 0901);
        t.D("Otherwise respond (N)o and then exit the main menu to do so.", 1001);
        t.D("Continue Y/N [ ]", 1201);
    }
}
