using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl050
{
    /// <summary>gl050a: バッチ既定値・ヘッダの設定。</summary>
    private static async Task SetUp(Ctx c, St s)
    {
        var t = c.Crt; var b = s.B; var d = s.D;
        bool usePc = Pcs(c) || Branches(c), preserve = c.Sys.S("Batch-Id") == "Y";
        if (usePc)
        {
            var pcr = c.Db.Read(Gl030.File, "99999900");
            if (pcr == null)
            {
                t.D("GL107 Set Up P/C Branches First", 0101, eos: true, fg: 4);
                t.D("GL010 Hit Return", 0211);
                await t.A(0234, 1);
                s.Exit = true; return;
            }
            s.Codes = System.Text.Encoding.Latin1.GetString(pcr, 8, 99);
        }
        bool truth; int a; string tranDate;
        bool PcOk(decimal pc) => pc == 0 || s.Codes[(int)pc - 1] is 'Y' or 'E';
    initDone:
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D("General Ledger - Posting Set-Up", 0126);
        t.V(s.WsDate, 0171, fg: 2);
        if (preserve) BatchOutline(t);
        HelpA(t);
        t.D("select default number          :- [  ]", 0401);
        t.D("select posting convention      :- [CR]", 0701);
        if (Pcs(c)) t.D("Select Default Profit Centre   :- [  ]", 1001);
        if (Branches(c)) t.D("Select Default Branch          :- [  ]", 1001);
        t.D("Enter Transaction Posting Date :- [        ]", 1301);
    defIn:
        t.D(" 0 - Return to System Menu   ", 1851);
        t.D("33 - Set-up Temporary Default", 1951);
        t.D("99 - Display current Defaults", 2051);
        t.D(" ", 2151, eol: true);
        t.D(" ", 2251, eol: true);
        a = (int)await t.AN(0436, 2, 0);
        if (a == 99)
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Default Accounts Display", 0126);
            t.V(s.WsDate, 0171, fg: 2);
            t.V(c.Sys.S("Usera"), 0301, fg: 2);
            Gl020.Headings(c, d);
            t.D("End of listing. Hit return for Menu.", 2301);
            await t.A(2379, 1);
            goto initDone;
        }
        if (a == 0) { b.SetN("bdefault", 0); return; }
        if (a > 33) goto defIn;
        b.SetN("batch-def-pc", 0);
        if (a == 33)
        {
            for (int l = 16; l < 23; l++) t.V(Sp44, l * 100 + 2);
            t.D("Default Set-Up", 1716);
            t.D("A/C  - [       ]", 1903);
            t.D("VAT  - [ ]", 2003);
            t.D("Code - [  ]", 2103);
        getAc:
            truth = false;
            d.SetN("acs33", await Money(t, 1911, 4, 0));
            if (d.N("acs33") == 0) goto defIn;
            var l33 = Desc(c, s, 33, 0);
            if (l33 == null) goto getAc;
            t.V(l33.S("name"), 1920);
        getVat:
            t.D("<I> - Input  VAT             ", 1851);
            t.D("<O> - Output VAT             ", 1951);
            t.D("<N> - No     VAT             ", 2051);
            t.V(d.S("vat33"), 2011);
            string v = (await t.A(2011, 1, d.S("vat33"))).ToUpperInvariant();
            if (t.Status == 2005) goto getAc;
            if (v is not ("I" or "O" or "N")) goto getVat;
            d.Set("vat33", v);
            t.D(" ", 1851, eol: true); t.D(" ", 1951, eol: true); t.D(" ", 2051, eol: true);
            t.V(d.S("code33"), 2111);
            string cd = await t.A(2111, 2, d.S("code33"));
            if (t.Status == 2005) goto getVat;
            d.Set("code33", cd.ToUpperInvariant());
            if (preserve) BatchOutline(t);
            truth = true;
        }
        else truth = Desc(c, s, a, d.N("acs" + a) == 0 ? 0 : b.N("batch-def-pc")) != null;
        if (!truth) goto defIn;
        b.SetN("bdefault", a);
        s.VatFlag = d.N("acs" + a) == d.N("acs31") || d.N("acs" + a) == d.N("acs32") ? 1 : 0;
    postIn:
        t.D("Enter <DR> or <CR>           ", 1851);
        t.D("DR - Debits the A/c posted to", 1951);
        t.D("   & Credits the default A/c ", 2051);
        t.D("<Esc> - to back-up one field ", 2151);
        string conv = (await t.A(0736, 2, "CR")).ToUpperInvariant();
        b.Set("convention", conv);
        if (t.Status == 2005) goto defIn;
        if (conv != "DR" && conv != "CR") goto postIn;
    defaultPc:
        for (int l = 18; l <= 21; l++) t.D(" ", l * 100 + 51, eol: true);
        if (usePc)
        {
            t.V(b.S("batch-def-pc"), 1036);
            b.SetN("batch-def-pc", await t.AN(1036, 2, b.N("batch-def-pc")));
            if (t.Status == 2005) goto postIn;
            var lr = PcOk(b.N("batch-def-pc")) ? Desc(c, s, a, b.N("batch-def-pc")) : null;
            if (lr != null) t.V(lr.S("name"), 0441); else { t.D("Unrecognised Account/P.C.", 0441); goto defaultPc; }
        }
    defDate:
        b.SetN("batch-def-ac", Cob.Trunc(d.N("acs" + a) * 100, 0));
        b.Set("batch-def-vat", d.S("vat" + a));
        b.Set("batch-def-code", d.S("code" + a));
        if (AutoVat(c))
        {
            if (b.S("batch-def-vat") == "I") t.D("Input VAT", 0470);
            if (b.S("batch-def-vat") == "O") t.D("Output VAT", 0470);
            if (b.S("batch-def-vat") == "N") t.D("No VAT", 0470);
        }
        tranDate = s.WsDate.PadRight(8).Substring(0, 8);
        t.V(tranDate, 1336);
        tranDate = await t.A(1336, 8, tranDate);
        if (t.Status == 2005) { if (usePc) goto defaultPc; goto postIn; }
        s.WsDate = tranDate.Replace('.', '/').Replace(',', '/').Replace('-', '/').PadRight(10);
        int bin = Common.Maps04(Common.FromForm(c, s.WsDate));
        if (bin == 0) goto defDate;
        b.SetN("entered", bin);
        await BatchIn(c, s);
        if (s.Back) { s.Back = false; goto defDate; }
    }
}
