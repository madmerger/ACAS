using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl050
{
    /// <summary>gl050a batch-in: バッチヘッダ (サイクル・件数・金額・摘要)。Esc で日付へ戻ると s.Back。</summary>
    private static async Task BatchIn(Ctx c, St s)
    {
        var t = c.Crt; var b = s.B;
        b.SetN("ledger", 1);
        foreach (var f in new[] { "batch-status", "cleared-status", "proofed", "posted", "stored", "actual-gross", "actual-vat" }) b.SetN(f, 0);
        b.SetN("bcycle", c.Sys.N("Cyclea"));
        b.SetN("batch-start", c.Sys.N("Postings") + 1);
        t.V(Sp44, 1703); t.V(Sp44, 1803); t.V(Sp44, 1903);
        t.D("Assigned Batch :- {     }", 1701);
        t.D("Enter Cycle    :- [  ]", 1801);
        t.D("Number of Items:- [  ]", 1901);
        t.D("Gross Amount   :- [            ]", 2001);
        t.D("Vat   Amount   :- [            ]", 2101);
        t.D("Batch Desc.    :- [", 2201);
        t.D("]", 2245);
        t.V(Cob.Edit(b.N("batch-nos"), "Z(4)9"), 1720);
    cycleIn:
        t.V(b.S("bcycle"), 1820);
        b.SetN("bcycle", await t.AN(1820, 2, b.N("bcycle")));
        if (t.Status == 2005) { s.Back = true; return; }
        if (b.N("bcycle") < c.Sys.N("Cyclea")) { t.D("GL108 Invalid. Too early", 1824, fg: 4); goto cycleIn; }
        if (b.N("bcycle") - c.Sys.N("Cyclea") > 1) { t.D("GL109 Invalid. Too forward", 1824, fg: 4); goto cycleIn; }
        t.V("                    ", 1824);
    itemsIn:
        b.SetN("items", await t.AN(1920, 2, b.N("items")));
        if (t.Status == 2005) goto cycleIn;
        if (b.N("items") == 0) t.D("GL110 No check on items.", 1924);
    grossIn:
        decimal g = await Money(t, 2020, 9, 0);
        if (t.Status == 2005) goto itemsIn;
        b.SetN("input-gross", g);
    vatIn:
        if (AutoVat(c))
        {
            g = await Money(t, 2120, 9, 0);
            if (t.Status == 2005) goto grossIn;
            b.SetN("input-vat", g);
        }
        b.Set("description", await t.A(2220, 24, b.S("description")));
        if (t.Status != 2005) return;
        if (AutoVat(c)) goto vatIn;
        goto grossIn;
    }

    private static void HelpB(Crt t)
    {
        t.V(new string('+', 27), 1454); t.V(new string('+', 27), 2354);
        for (int l = 15; l <= 22; l++) { t.V("+", l * 100 + 54, fg: 2); t.V("+", l * 100 + 80, fg: 2); }
        t.D("Option :- [ ]", 1656);
        t.D("B - Back-up one field", 1856);
        t.D("E - End", 1956);
        t.D("F - Force Write", 2056);
        t.D("Q - Quit Batch", 2156);
        t.D("n - Back-up n records", 2256);
    }

    private sealed class Line
    {
        public string Date = "", Legend = "", VatSide = "", Code = "";
        public decimal Dr, DrPc, Cr, CrPc, Amount, VatAc, VatPc, VatAmount;
    }

    private static void WriteOut(Ctx c, St s, Line[] arr, ref int a)
    {
        if (a < 1) return;
        a--;
        for (int y = 1; y <= a; y++)
        {
            var p = Layouts.Posting.New(); var l = arr[y];
            p.SetN("batch", s.B.N("batch-nos"));
            p.SetN("post-number", s.SaveA + y);
            decimal rrn = s.B.N("batch-start") + s.SaveA + y;
            p.Set("post-code", s.B.S("batch-def-code")); p.Set("post-date", l.Date);
            p.SetN("post-dr", l.Dr); p.SetN("dr-pc", l.DrPc); p.SetN("post-cr", l.Cr); p.SetN("cr-pc", l.CrPc);
            p.SetN("post-amount", l.Amount); p.Set("post-legend", l.Legend);
            p.SetN("vat-ac", Cob.Trunc(l.VatAc * 100, 0)); p.SetN("vat-pc", l.VatPc);
            p.Set("post-vat-side", l.VatSide); p.SetN("vat-amount", l.VatAmount);
            c.Db.Write(PostFile, Cob.P9(rrn, 8), p.B);
        }
        s.SaveA += a; a = 1;
    }

    private static void QuitBatch(Ctx c, St s)
    {
        foreach (var (k, data) in c.Db.Scan(PostFile, Cob.P9(s.B.N("batch-start"), 8)))
            if (Layouts.Posting.From(data).N("batch") == s.B.N("batch-nos")) c.Db.Delete(PostFile, k);
        s.Z = 9;
    }
}
