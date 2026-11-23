using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl020: 既定勘定ファイルの保守 (登録・修正・照会)。</summary>
public static partial class Gl020
{
    private const string Prog = "GL020 (3.00.02)";

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        var d = Layouts.Default.From(c.Db.Read(Ctx.SysFile, "00000002") ?? Layouts.Default.New().B);
        int menu = 0, w = 1, lin = 7, cole = 1;
        bool autoVat = c.Sys.S("Vat") == "Y";
        int Curs(int add = 0) => lin * 100 + cole + add;

        Rec? Desc()
        {
            var b = c.Db.Read(Gl030.File, Gl030.Key(Cob.Trunc(d.N("acs" + w) * 100, 0), 0));
            return b == null ? null : Layouts.Ledger.From(b);
        }
        async Task Money()
        {
            var cur = Cob.P9(decimal.Truncate(d.N("acs" + w)), 4) + "." + Cob.P9(d.N("acs" + w) * 100 % 100, 2);
            t.V(cur, Curs(3));
            var s = await t.A(Curs(3), 7, cur);
            d.SetN("acs" + w, Cob.ToInt(s.Substring(0, 4)) + Cob.ToInt(s.Substring(5, 2)) / 100m);
        }
        void Headings() { Gl020.Headings(c, d); w = 1; cole = 1; lin = 7; }
        void Save() => c.Db.Put(Ctx.SysFile, "00000002", d.B);

        async Task Amend()
        {
            t.D(" ", 0101, eos: true);
            t.V(Prog, 0101, fg: 2);
            t.D("Default Accounts Amendment", 0127);
            t.V(toDay, 0171, fg: 2);
            t.V(c.Sys.S("Usera"), 0301, fg: 2);
            Headings();
            while (true)
            {
                t.D("Enter Number To Alter (Return to exit)  :- [  ]", 2401);
                int y = (int)await t.AN(2445, 2, 0);
                if (y == 0) return;
                if (y < 1 || y > 32) continue;
                w = y;
                if (y > 16) { y -= 16; cole = 41; } else cole = 1;
                lin = y + 6;
                t.V(Cob.P9(w, 2), Curs(), fg: 2);
                await Money();
                var l = Desc();
                if (l == null) continue;
                t.V(l.S("name"), Curs(12));
                t.D("[  ] ", Curs(32));
                d.Set("code" + w, await t.A(Curs(33), 2, d.S("code" + w)));
                t.V(d.S("code" + w), Curs(33));
                string v;
                do { v = await t.A(Curs(38), 1, d.S("vat" + w)); } while (v is not ("I" or "N" or "O"));
                d.Set("vat" + w, v);
            }
        }

        async Task SetUp()
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.V(Common.ToForm(c, toDay), 0171, fg: 2);
            t.D("Default Accounts Set-Up", 0129);
            t.V(c.Sys.S("Usera"), 0301, fg: 2);
            string reply;
            do
            {
                t.D("Add To Existing Defaults (Y/N) ? - [ ]", 0501);
                t.D("N.B. (1) If first time set-up for this client answer no (N)", 0701);
                t.D("(2) Answering no (N)", 0806);
                t.D("destroys", 0827, fg: 4);
                t.D("the existing defaults", 0836);
                reply = (await t.A(0537, 1)).ToUpperInvariant();
                if (reply == "N")
                {
                    t.D("Enter Password  - [    ]", 0551);
                    var pw = await t.A(0570, 4);
                    t.V("****", 0570, fg: 2);
                    if (Maps01.Pass(pw) != c.Sys.S("Pass-Word")) reply = "Z";
                    else d = Layouts.Default.New();
                }
            } while (reply != "Y" && reply != "N");
            for (int l = 5; l <= 8; l++) t.D(" ", l * 100 + 1, eol: true);
            Headings();
            bool Jump()   // Esc/ゼロ入力時の移動先。false = 入力終了
            {
                if (w < 30) { cole = 41; w = 30; lin = 20; return true; }
                if (w < 31 && autoVat) { cole = 41; w = 31; lin = 21; return true; }
                return false;
            }
            while (true)
            {
                t.V(Cob.P9(w, 2), Curs(), fg: 2);
                await Money();
                if (t.Status == 2005) { if (Jump()) continue; break; }
                if (d.N("acs" + w) == 0 && w < 30) { cole = 41; w = 30; lin = 20; continue; }
                if (d.N("acs" + w) == 0 && autoVat) { cole = 41; w = 31; lin = 21; continue; }
                var l = Desc();
                if (l == null) continue;
                t.V(l.S("name"), Curs(12));
                t.D("[  ] ", Curs(32));
                string codes = d.S("code" + w);
                t.V(codes, Curs(33));
                if (w < 30) codes = (await t.A(Curs(33), 2, codes)).ToUpperInvariant();
                else codes = w == 30 ? "OB" : w == 31 ? "VI" : "VO";
                t.V(codes, Curs(33), fg: 2);
                if (t.Status == 2005) { if (Jump()) continue; break; }
                d.Set("code" + w, codes);
                bool esc = false;
                while (true)
                {
                    string v = d.S("vat" + w);
                    t.V(v, Curs(38));
                    if (w < 30) v = (await t.A(Curs(38), 1, v)).ToUpperInvariant(); else { v = "N"; t.V(v, Curs(38)); }
                    if (t.Status == 2005) { esc = true; break; }
                    d.Set("vat" + w, v);
                    if (v is "I" or "N" or "O") break;
                }
                if (esc) { if (autoVat && w < 31) { cole = 41; w = 31; lin = 21; continue; } break; }
                w++;
                if (w > 32) break;
                if (w == 17) { cole = 41; lin = 6; }
                lin++;
            }
            await Amend();
        }

        while (true)
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Default File Utilities", 0129);
            t.V(Common.ToForm(c, toDay), 0171, fg: 2);
            t.V(c.Sys.S("Usera"), 0301, fg: 2);
            if (!c.Db.Exists(Gl030.File))
            {
                t.D("GL100 Chart of Accounts not set up", 2301, fg: 4);
                t.D("GL010 Hit Return", 2401);
                await t.A(2420, 1);
                Save(); return 0;
            }
            t.D("Select the required function by number    [ ]", 0501);
            t.D("(1)  Set-Up Default Accounts", 0806);
            t.D("(2)  Amend  Default Accounts", 1006);
            t.D("(3)  Display The Defaults", 1206);
            t.D("(9)  Return To System Menu", 2006);
            menu = (int)await t.AN(0544, 1, 0, auto: true);
            if (menu == 1) await SetUp();
            if (menu == 2) await Amend();
            if (menu == 3)
            {
                t.D(" ", 0101, eos: true);
                t.V(Prog, 0101, fg: 2);
                t.D("default accounts display", 0126);
                t.V(toDay, 0171, fg: 2);
                t.V(c.Sys.S("Usera"), 0301, fg: 2);
                Headings();
                t.D("End of listing. Hit return for Menu.", 2301);
                await t.A(2379, 1);
            }
            Save();
            if (menu == 9) return 0;
        }
    }
    public static void Headings(Ctx c, Rec d)
    {
        var t = c.Crt; int w = 1, lin = 7, cole = 1;
        int Curs(int add = 0) => lin * 100 + cole + add;
        Rec? Desc()
        {
            var b = c.Db.Read(Gl030.File, Gl030.Key(Cob.Trunc(d.N("acs" + w) * 100, 0), 0));
            return b == null ? null : Layouts.Ledger.From(b);
        }
            t.D("A/C Nos", 0504); t.D("Code Vat", 0533); t.D("A/C Nos", 0544); t.D("Code Vat", 0573);
            lin = 7; cole = 1;
            for (w = 1; w <= 32; w++)
            {
                if (w == 17) { lin = 7; cole = 41; }
                t.V(Cob.P9(w, 2), Curs(), fg: 2);
                t.D("[       ]", Curs(2));
                t.D("[  ] [ ]", Curs(32));
                lin++;
            }
            lin = 7; cole = 1;
            for (w = 1; w <= 32; w++)
            {
                if (w == 17) { lin = 7; cole = 41; }
                t.V(Cob.Edit(d.N("acs" + w), "9(4).99"), Curs(3));
                var l = d.N("acs" + w) == 0 ? null : Desc();
                if (l != null) { t.V(l.S("name"), Curs(12)); t.D("[  ] ", Curs(32)); }
                t.V(d.S("code" + w), Curs(33));
                t.V(d.S("vat" + w), Curs(38));
                lin++;
            }
            w = 1; cole = 1; lin = 7;
        }
}
