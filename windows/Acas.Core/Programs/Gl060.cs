using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl060: バッチ状態一覧 (照会・印刷)。</summary>
public static class Gl060
{
    private const string Prog = "gl060 (3.00.04)";
    private const string L4a = "Ledger  Batch  Status       Last", L4b = "---------Batch Controls---------";
    private const string L5a = "------  -----  ------     Activity", L5b = "Items  ---Gross---- -----VAT----";

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        string wsDate = Common.ToForm(c, toDay);
        void Head()
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Batch Status Report", 0132);
            t.V(wsDate, 0171, fg: 2);
        }
        while (true)
        {
            Head();
            t.V(c.Sys.S("Usera"), 0301, fg: 2);
            t.D("Select one of the following by number :- [ ]", 0801);
            t.D("(1)  Display Batch Report", 1001);
            t.D("(2)  Print Batch Report", 1201);
            t.D("(9)  Exit to system menu", 1501);
            int a = (int)await t.AN(0843, 1, 0);
            if (a == 9) return 0;
            if (a is 1 or 2) await Report(c, a, wsDate, Head);
        }
    }

    private static async Task Report(Ctx c, int a, string wsDate, Action head)
    {
        var t = c.Crt;
        head();
        string cycle = Cob.Edit(c.Sys.N("Cyclea"), "Z9");
        t.D("cycle - ", 0301);
        t.V(cycle, 0309, fg: 2);
        Report? rp = null; int page = 0, cnt = 0;
        void Headings()
        {
            page++;
            object[] l1 = { Prog.PadRight(31), new Lit("Batch Status Report".PadRight(41)), new Lit("Page -"), Cob.Edit(page, "Z9") };
            object[] l3 = { new Lit("Cycle - "), cycle, new string(' ', 60), wsDate };
            if (page != 1) { rp!.Page(); rp.Write(l1); rp.After(1, l3); rp.After(1, ""); }
            else { rp!.Write(l1); rp.Write(l3); }
            rp.After(1, new Lit(L4a.PadRight(48)), new Lit(L4b));
            rp.After(1, new Lit(L5a.PadRight(48)), new Lit(L5b));
            rp.After(1, "");
            cnt = 6;
        }
        if (a == 2) { rp = c.OpenReport(Ctx.L + "prt-1"); Headings(); }
        else
        {
            t.D(L4a, 0501); t.D(L4b, 0549);
            t.D(L5a, 0601); t.D(L5b, 0649);
        }
        if (!c.Db.Exists(Gl050.BatchFile))
        {
            // レガシー実測: batch.dat が無いと OPEN INPUT で異常終了する
            rp?.Close();
            throw new Halt("batch.dat が存在しません");
        }
        int lin = 7; string ledger = "", status = "";
        var recs = c.Db.Scan(Gl050.BatchFile);
        bool exit = false;
        foreach (var (_, data) in recs)
        {
            var b = Layouts.Batch.From(data);
            if (b.N("bcycle") != c.Sys.N("Cyclea")) continue;
            ledger = b.N("ledger") switch { 1 => " G/L", 2 => " P/L", 3 => " S/L", _ => ledger };
            decimal bin = 0;
            foreach (var f in new[] { "stored", "posted", "proofed", "entered" }) if (b.N(f) != 0) { bin = b.N(f); break; }
            string date = bin == 0 ? wsDate : Common.ToForm(c, Launcher.BinToDate(bin));
            if (bin != 0) wsDate = date;
            decimal bs = b.N("batch-status"), cs = b.N("cleared-status");
            if (bs == 0) status = "Open";
            else if (bs == 1) status = cs switch { 0 => "Waiting", 1 => "Processed", 2 => "Archived", _ => status };
            string Vat(decimal v) => v == 0 ? new string(' ', 12) : Cob.Edit(v, "Z(8)9.99");
            string items = Cob.Edit(b.N("items"), "Z9") + "    ";
            object[] l6 = { ledger.PadRight(8), Cob.Edit(b.N("batch-nos"), "Z(4)9") + "  ", new Lit(status.PadRight(11)), date.PadRight(14),
                new Lit("Header   "), items, Cob.Edit(b.N("input-gross"), "Z(8)9.99") + " ", Vat(b.N("input-vat")) };
            object[] l7 = { new string(' ', 40), new Lit("Actual   "), items, Cob.Edit(b.N("actual-gross"), "Z(8)9.99") + " ", Vat(b.N("actual-vat")) };
            if (a == 2)
            {
                rp!.After(2, l6); cnt += 2;
                if (cnt > c.Sys.I("Page-Lines")) Headings();
                rp.After(1, l7); cnt++;
            }
            else
            {
                Row(t, lin + 1, l6); Row(t, lin + 2, l7);
                lin += 3;
            }
            if (lin < 21) continue;
            t.D("Enter <N> for next screen or <X> to exit :- [ ]", 2201);
            while (true)
            {
                var r = (await t.A(2246, 1)).ToUpperInvariant();
                if (r == "X") { exit = true; break; }
                if (r == "N") { lin = 7; t.D(" ", 0701, eos: true); break; }
            }
            if (exit) break;
        }
        if (a == 2) rp!.Close();
        else
        {
            t.D("Type return to exit.", 2201);
            await t.A(2222, 1);
        }
    }

    private static void Row(Crt t, int row, object[] parts)
    {
        int col = 1;
        foreach (var p in parts)
        {
            if (p is Lit l) { if (l.Text.Trim().Length > 0) t.D(l.Text, row * 100 + col); col += l.Text.Length; }
            else { var s = p.ToString()!; t.V(s, row * 100 + col, fg: 2); col += s.Length; }
        }
    }
}
