using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl050
{
    /// <summary>gl050b: 仕訳明細の入力。</summary>
    private static async Task Input(Ctx c, St s)
    {
        var t = c.Crt; var b = s.B; var d = s.D;
        bool usePc = Pcs(c) || Branches(c), autoVat = AutoVat(c);
        t.V(Prog, 0101, eos: true, fg: 2);
        t.D("General Ledger - Posting Input", 0126);
        t.V(s.WsDate, 0171, fg: 2);
        HelpB(t);
        int w = b.S("batch-def-vat") == "O" ? 32 : b.S("batch-def-vat") == "I" ? 31 : 0;
        decimal vatRate = 0;
        async Task RegetVat()
        {
            int v;
            do
            {
                do
                {
                    t.D("VAT Rate :- [ ]", 0401);
                    t.V("1", 0414);
                    v = (int)await t.AN(0414, 1, 1);
                } while (v < 1 || v > 3);
                vatRate = c.Sys.N("Vat-Rate-" + v);
                t.V(Cob.Edit(vatRate, "Z9.99"), 0417);
                t.D("% OK (Y/N) :- [Y]", 0422);
            } while ((await t.A(0437, 1, "Y")) is "N" or "n");
        }
        if (w != 0) await RegetVat();
        t.D("Batch      - ", 0456);
        t.V(Cob.Edit(b.N("batch-nos"), "Z(4)9"), 0469, fg: 2);
        t.V("/", 0474, fg: 2);
        t.D("Default    - ", 0656);
        t.V(b.S("bdefault"), 0669, fg: 2);
        t.D("Contra A/C - ", 0856);
        t.V(b.S("batch-def-ac"), 0869, fg: 2);
        if (b.N("batch-def-pc") != 0) { t.V("/", 0875, fg: 2); t.V(b.S("batch-def-pc"), 0876); }
        if (w != 0) { t.D("VAT A/C    - ", 1056); t.V(Cob.Edit(d.N("acs" + w), "9(4).99"), 1069); }
        else t.D("No VAT on this Batch.", 1056);
        t.D("Convention - ", 1256);
        t.V(b.S("convention"), 1269);
        t.D("Date           [          ]", 0601);
        t.D("Account        [       ]", 0801);
        if (Pcs(c)) t.D("Profit Centre  [  ]", 1001);
        if (Branches(c)) t.D("Branch         [  ]", 1001);
        t.D("Amount         [           ]", 1201);
        if (autoVat && w != 0) t.D("VAT Code       [ ]  {p or m or space}", 1401);
        t.D("VAT Amount     [           ]", 1601);
        t.D("Narrative      [", 1801);
        t.D("]", 1849);
        s.SaveA = 0;
        int a = 1, vatFlag2;
        var arr = new Line[14];
        for (int i = 0; i < arr.Length; i++) arr[i] = new Line();
        decimal accountIn, arrayPc = 0;
        string arrayVat = " ";
        bool Up() => t.Status is 2001 or 2003;
        bool Down() => t.Status is 2002 or 2004;
        bool Esc() => t.Status == 2005;
    mainLoop:
        t.V(Cob.P9(a, 2), 0475);
        t.V(s.WsDate, 0617);
        s.WsDate = await t.A(0617, 10, s.WsDate);
        arr[a].Date = s.WsDate;
        if (Up() && w != 0) { await RegetVat(); goto mainLoop; }
        if (Up() || Down() || Esc()) goto mainLoop;
        if (s.Z > 0) goto mainLoop;
        s.WsDate = s.WsDate.Replace('.', '/').Replace(',', '/').Replace('-', '/');
        arr[a].Date = s.WsDate;
        if (Common.Maps04(Common.FromForm(c, s.WsDate)) == 0) { t.D("Invalid Date", 0636, fg: 4); goto mainLoop; }
        t.V(Sp44.Substring(0, 29), 0626);
    getAccount:
        accountIn = await Money(t, 0817, 4, 0);
        if (Up() || Down() || s.Z != 0) goto mainLoop;
        if (Esc()) goto mainExit;
        var lr = c.Db.Read(Gl030.File, Gl030.Key(Cob.Trunc(accountIn * 100, 0), arrayPc));
        if (lr != null) t.V(Layouts.Ledger.From(lr).S("name"), 0826);
        else { t.D("Invalid A/C number", 0826, fg: 4); goto getAccount; }
        vatFlag2 = s.VatFlag == 1 || accountIn == d.N("acs31") || accountIn == d.N("acs32") ? 1 : 0;
    acceptPc:
        arrayPc = 0;
        if (usePc)
        {
            t.V("00", 1017);
            arrayPc = await t.AN(1017, 2, 0);
            if (Down() || s.Z != 0) goto mainLoop;
            if (Up()) goto getAccount;
            if (Esc()) goto mainExit;
        }
    acceptAmount:
        arr[a].Amount = vatFlag2 == 0 ? await Money(t, 1217, 8, 0) : 0;
        t.V(Cob.Edit(arr[a].Amount, "9(8).99"), 1217);
        if (Down() || s.Z != 0) goto mainLoop;
        if (Up()) { if (usePc) goto acceptPc; goto getAccount; }
        if (Esc()) goto mainExit;
    acceptVat:
        if (!autoVat || w == 0) { arr[a].VatAmount = 0; goto vatAmountInput; }
        arrayVat = " ";
        if (vatFlag2 == 1) { arr[a].VatAmount = 0; goto vatAmountInput; }
        t.V(arrayVat, 1417);
        arrayVat = (await t.A(1417, 1, arrayVat)).ToUpperInvariant();
        if (Down() || s.Z != 0) goto mainLoop;
        if (Up()) goto acceptAmount;
        if (Esc()) goto mainExit;
        if (arrayVat == "P")
        {
            arr[a].VatAmount = Cob.Round(arr[a].Amount * vatRate / 100, 2);
            t.V(Cob.Edit(arr[a].VatAmount, "9(8).99"), 1617);
            goto vatAmountInput;
        }
        if (arrayVat == "M")
        {
            arr[a].VatAmount = Cob.Round(arr[a].Amount - arr[a].Amount / ((vatRate + 100) / 100), 2);
            arr[a].Amount -= arr[a].VatAmount;
            t.V(Cob.Edit(arr[a].VatAmount, "9(8).99"), 1617);
            goto vatAmountInput;
        }
        if (arrayVat == " ") { arr[a].VatAmount = 0; goto acceptNarrative; }
        t.D("Invalid code", 1439, fg: 4);
        goto acceptVat;
    vatAmountInput:
        if (w == 0) goto acceptNarrative;
        decimal va = await Money(t, 1617, 8, arr[a].VatAmount, show: false);
        if (va != arr[a].VatAmount && arr[a].Amount != 0 && arrayVat == "M") arr[a].Amount += arr[a].VatAmount - va;
        arr[a].VatAmount = va;
        if (Down() || s.Z != 0) goto mainLoop;
        if (Up()) goto acceptVat;
        if (Esc()) goto mainExit;
    acceptNarrative:
        if (arr[a].Amount == 0 && arr[a].VatAmount == 0) goto mainLoop;
        t.V("            ", 1439);
        arr[a].Legend = await t.A(1817, 32, new string(' ', 32));
        if (Down() || s.Z != 0) goto mainLoop;
        if (Up()) { if (autoVat) goto acceptVat; goto acceptAmount; }
        if (Esc()) goto mainExit;
        bool dr = b.S("convention") == "DR";
        if (dr) { arr[a].Dr = Cob.Trunc(accountIn * 100, 0); arr[a].DrPc = arrayPc; arr[a].Cr = b.N("batch-def-ac"); arr[a].CrPc = b.N("batch-def-pc"); }
        else { arr[a].Cr = Cob.Trunc(accountIn * 100, 0); arr[a].CrPc = arrayPc; arr[a].Dr = b.N("batch-def-ac"); arr[a].DrPc = b.N("batch-def-pc"); }
        arr[a].VatSide = dr ? "DR" : "CR";
        arr[a].Code = b.S("batch-def-code");
        arr[a].VatAc = w != 0 ? d.N("acs" + w) : 0;
        arr[a].VatPc = b.N("batch-def-pc");
        a++;
        if (a > 12) WriteOut(c, s, arr, ref a);
        goto mainLoop;
    mainExit:
        if (Esc()) QuitBatch(c, s);
        else c.Sys.SetN("Postings", c.Sys.N("Postings") + s.SaveA);
    }
}
