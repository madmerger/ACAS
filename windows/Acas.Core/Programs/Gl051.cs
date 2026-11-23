using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl051: バッチ修正・検証 (プルーフ) 帳票。</summary>
public static partial class Gl051
{
    private const string Prog = "gl051 (3.00.04)";

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        Rec? b = null;          // FD レコード領域。未読込の間は LOW-VALUES (レガシー実測: ^@ 表示)
        bool firstTime = false; int menu = 0;
        string wsDate = Common.ToForm(c, toDay);
        while (true)
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Batch Amendment / Reporting Functions", 0123);
            t.V(wsDate, 0171, fg: 2);
            t.V(c.Sys.S("Usera"), 0301, fg: 2);
            t.D("Select one of the following by number :- [ ]", 0801);
            t.D("(1)  Amend existing Batch", 1001);
            t.D("(2)  Print Proof Reports - All Batches", 1101);
            t.D("(3)  Print Proof Reports - One Batch", 1201);
            t.D("(4)  Print all Transactions", 1301);
            t.D("(9)  Exit to system menu", 1601);
            menu = (int)await t.AN(0843, 1, menu);
            if (menu == 9) return 0;
            if (menu is 1 or 3)
            {
                decimal nos;
                while (true)
                {
                    t.D("Enter Batch Number :- [     ]", 1801);
                    if (b == null)
                    {
                        var raw = await t.A(1824, 10, "^@^@^@^@^@");
                        nos = Cob.ToNum(new string(raw.Substring(0, 5).Select(ch => char.IsDigit(ch) ? ch : '0').ToArray()));
                    }
                    else nos = await t.AN(1824, 5, b.N("batch-nos"));
                    if (nos == 0) break;
                    var data = c.Db.Read(Gl050.BatchFile, "1" + Cob.P9(nos, 5));
                    if (data != null) { b = Layouts.Batch.From(data); break; }
                }
                if (nos == 0) continue;
            }
            int bin = Common.Maps04(toDay);
            if (menu == 1) await Amend(c, b!, wsDate);
            if (menu == 3) { Proof(c, b!, wsDate, 0, ref firstTime, menu); b!.SetN("proofed", bin); }
            if (menu == 2)
            {
                foreach (var (k, data) in c.Db.Scan(Gl050.BatchFile))
                {
                    b = Layouts.Batch.From(data);
                    if (b.N("bcycle") != c.Sys.N("Cyclea") || b.N("cleared-status") != 0) continue;
                    Proof(c, b, wsDate, 0, ref firstTime, menu);
                    c.Db.Rewrite(Gl050.BatchFile, k, (byte[])b.B.Clone());
                }
                if (b != null) b.SetN("proofed", bin);
            }
            if (menu == 4)
            {
                b ??= Layouts.Batch.New();
                b.SetN("batch-start", 1);
                Proof(c, b, wsDate, 99, ref firstTime, menu);
                b.SetN("proofed", bin);
            }
            if (b != null && menu is >= 1 and <= 4) c.Db.Rewrite(Gl050.BatchFile, Gl050.BKey(b), (byte[])b.B.Clone());
        }
    }

    /// <summary>gl050c: バッチ修正。</summary>
    private static Task Amend(Ctx c, Rec b, string wsDate)
    {
        // TODO: gl051.cbl gl050c / batch-amendment (428-885) は未移植
        return Task.CompletedTask;
    }
}
