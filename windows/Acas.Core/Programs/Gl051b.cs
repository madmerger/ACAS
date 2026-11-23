using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl051
{
    /// <summary>gl050d + batch-print: 検証 (プルーフ) 帳票。z=99 は全仕訳。</summary>
    private static void Proof(Ctx c, Rec b, string wsDate, int z, ref bool firstTime, int menu)
    {
        var t = c.Crt;
        if (!firstTime)
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("General Ledger - Proof Report", 0127);
            t.V(wsDate, 0171, fg: 2);
            t.D("Printing......please wait", 1212);
            if (menu == 2) firstTime = true;
        }
        var rp = c.OpenReport(Ctx.L + "prt-1");
        b.SetN("actual-gross", 0); b.SetN("actual-vat", 0);
        b.SetN("ledger", 1);
        int page = 0, cnt = 0; bool truth = true; decimal saveBatch = 0;
        int pageLines = c.Sys.I("Page-Lines");
        string EnteredDate() => b.N("entered") == 0 ? "" : Common.ToForm(c, Launcher.BinToDate(b.N("entered")));
        void Line4(int after) => rp.After(after, new Lit("Batch - "), Cob.Edit(b.N("batch-nos"), "Z(4)9"), new string(' ', 8), b.S("description"),
            new Lit("    Date Entered - "), " ", EnteredDate().PadRight(10));
        void Headings()
        {
            page++;
            rp.After(1, Prog.Substring(0, 14), new string(' ', 41), new Lit("Transaction Proof Report"), new string(' ', 45), new Lit("Page  "), Cob.Edit(page, "Z9"));
            rp.After(1, c.Sys.S("Usera"), new string(' ', 90), wsDate);
            cnt = 6;
            if (z != 99) { Line4(2); cnt += 2; }
            rp.After(2, new Lit("Number  Code  ---Date--- --Debit--   --Credit-    Net Amount    VAT Amount  VAT Account  VAT Side   ------------Narative------------"));
            rp.After(1, new Lit("------  ----              A/C  P/C    A/C  P/C    ----------    ----------    A/C  P/C   --------"));
            rp.After(1, "");
        }
        Headings();
        foreach (var (_, data) in c.Db.Scan(Gl050.PostFile))
        {
            var p = Layouts.Posting.From(data);
            if (p.N("batch") == 0) continue;
            if (z == 99 && saveBatch != p.N("batch"))
            {
                saveBatch = p.N("batch");
                var bd = c.Db.Read(Gl050.BatchFile, "1" + Cob.P9(saveBatch, 5));
                if (bd != null) b.B.AsSpan().Clear();
                if (bd != null) bd.CopyTo(b.B, 0); else { b.SetN("batch-nos", 99999); }
                Line4(2); cnt += 2;
            }
            else if (z != 99 && p.N("batch") != b.N("batch-nos")) continue;
            string vatAc = p.N("vat-ac") == 0 ? "       " : Cob.Edit(p.N("vat-ac") / 100m, "ZZZ9.99");
            string vatPc = p.N("vat-pc") == 0 ? "         " : " " + Cob.Edit(p.N("vat-pc"), "Z9") + "      ";
            rp.After(1, Cob.Edit(p.N("post-number"), "Z(4)9"), "    ", p.S("post-code").PadRight(5), p.S("post-date").PadRight(12),
                Cob.Edit(p.N("post-dr") / 100m, "ZZZ9.99"), " ", p.S("dr-pc"), "  ",
                Cob.Edit(p.N("post-cr") / 100m, "ZZZ9.99"), " ", p.S("cr-pc"), "  ",
                Cob.Edit(p.N("post-amount"), "Z(8)9.99"), "  ", Cob.Edit(p.N("vat-amount"), "Z(8)9.99"), "  ",
                vatAc, vatPc, (p.N("vat-ac") != 0 ? p.S("post-vat-side") : "").PadRight(8), p.S("post-legend"));
            cnt++;
            bool drOk = c.Db.Read(Gl030.File, Gl030.Key(p.N("post-dr"), p.N("dr-pc"))) != null;
            bool crOk = c.Db.Read(Gl030.File, Gl030.Key(p.N("post-cr"), p.N("cr-pc"))) != null;
            if (!drOk || !crOk)
            {
                truth = false;
                rp.After(1, new string(' ', 24), (drOk ? "" : "^^^^^^^^^^").PadRight(12), (crOk ? "" : "^^^^^^^^^^").PadRight(12));
                cnt++;
            }
            if (cnt > pageLines - 6) Headings();
            b.SetN("actual-gross", b.N("actual-gross") + p.N("post-amount"));
            b.SetN("actual-vat", b.N("actual-vat") + p.N("vat-amount"));
        }
        if (z != 99)
        {
            if (!truth) b.SetN("batch-status", 0);
            else
            {
                decimal actGross = b.N("actual-gross"), actVat = b.N("actual-vat");
                string E(decimal v) => Cob.Edit(v, "Z(9)9.99") + "  ";
                b.SetN("actual-gross", actGross + actVat);
                if (cnt > pageLines - 12) Headings();
                string sp = new string(' ', 20);
                rp.After(3, sp, new Lit("Batch              ----Net----    ----VAT----"));
                rp.After(2, sp, new Lit("Header".PadRight(17)), E(b.N("input-gross") - b.N("input-vat")), E(b.N("input-vat")));
                rp.After(2, sp, new Lit("Actual".PadRight(17)), E(actGross), E(actVat));
                bool ok = b.N("input-gross") == b.N("actual-gross") && b.N("input-vat") == b.N("actual-vat");
                b.SetN("batch-status", ok ? 1 : 0);
                rp.After(3, sp, "*********************");
                rp.After(1, sp, new Lit(ok ? "* Batch Verified Ok *" : "*  Batch In ERROR   *"));
                rp.After(1, sp, "*********************");
            }
        }
        rp.Close();
    }
}
