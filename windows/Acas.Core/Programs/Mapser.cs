using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>common/maps01.cbl: パスワード・利用者名の符号化。</summary>
public static class Maps01
{
    private const string Alpha = "CKQUAELSMWYIZJRPBXFVGNODTH";

    private static int Index(char ch)
    {
        int a = Alpha.IndexOf(ch);
        if (a < 0) a = Alpha.ToLowerInvariant().IndexOf(ch);
        return a + 1;
    }

    public static string Pass(string pw)
    {
        pw = pw.PadRight(4).Substring(0, 4);
        var o = new[] { ' ', ' ', ' ', ' ' };
        for (int y = 1; y <= 4; y++)
        {
            int a = Index(pw[y - 1]);
            if (a == 0) continue;
            int z = a + y * y + 3 - 26;
            if (z < 1) z = -z;
            o[4 - y] = z != 0 ? Alpha[z - 1] : ' ';
        }
        return new string(o);
    }

    public static string Name(string name)
    {
        name = name.PadRight(32).Substring(0, 32);
        var o = new string(' ', 32).ToCharArray();
        for (int y = 1; y <= 31; y++)
        {
            int a = Index(name[y - 1]);
            if (a == 0) continue;
            int b = (int)Cob.Round((y + 51m) / y, 0);
            if (b > 25) b -= 26;
            int z = a + b - 27;
            if (z < 1) z = -z;
            if (z > 26) z -= 26;
            o[y - 1] = z != 0 ? Alpha[z - 1] : ' ';
        }
        return new string(o);
    }
}

/// <summary>ACAS.cbl mapser / level-setup: システムファイルが無い場合の初期設定 (Level 1)。</summary>
public static class Mapser
{
    public static async Task Run(Ctx c)
    {
        var t = c.Crt;
        t.V("ACAS (3.00.05)", 0101, eos: true, fg: 2);
        t.D("ACAS System Setup Routine - Level 1", 0122);
        var s = Layouts.System.New();
        s.SetN("Version-Prime", 1); s.SetN("Version-Secondary", 1);
        s.SetN("Date-Form", 1);
        string usera = "";
        while (true)
        {
            t.D("Enter the Company Name :- [", 1101); t.V("]", 1160, fg: 2);
            usera = await t.A(1128, 32, init: usera);
            t.D("Please verify that name is correct (Y/N) :- [ ]", 1301);
            var r = await t.A(1346, 1, init: "Y");
            if (r.ToUpperInvariant() == "Y") break;
        }
        s.Set("Usera", usera);
        s.Set("User-Code", Maps01.Name(usera));
        s.Set("Pass-Word", Maps01.Pass("pass"));
        s.Set("Sl-Own-Nos", "N");
        s.SetN("Run-Date", Launcher.DateToBin(c.Now()));
        while (true)
        {
            s.Set("Maps-Ser-xx", "mp"); s.SetN("Maps-Ser-nn", 9999);
            t.D("Using General  Ledger (Y/N) ? :- [ ]", 1901);
            t.D("Using Purchase Ledger (Y/N) ? :- [ ]", 2001);
            t.D("Using Sales    Ledger (Y/N) ? :- [ ]", 2101);
            t.D("Using Invoicing       (Y/N) ? :- [ ]", 1941);
            t.D("Using Stock Control   (Y/N) ? :- [ ]", 2041);
            t.D("Using Order Entry     (Y/N) ? :- [ ]", 2141);
            // レガシーは ws-reply を update 付きで使い回すため、前回の応答が次欄の初期値になる
            string r = "Y";
            async Task<int> Ask(int pos) { r = await t.A(pos, 1, init: r); return r.ToUpperInvariant() == "Y" ? 1 : 0; }
            s.SetN("Level-1", await Ask(1935));
            s.SetN("Level-2", await Ask(2035));
            s.SetN("Level-3", await Ask(2135));
            s.SetN("Full-Invoicing", await Ask(1975));
            s.SetN("Level-4", await Ask(2075));
            s.SetN("Level-5", await Ask(2175));
            t.D("Please confirm (Y/N) :- [ ] ", 2301);
            bool g = s.I("Level-1") == 1, b = s.I("Level-2") == 1, sl = s.I("Level-3") == 1;
            string o = "";
            if (g) o += "General ";
            if (b && g) o += "/ ";
            if (b) o += "Purchase ";
            if (sl && (g || b)) o += "/ ";
            if (sl) o += "Sales ";
            if (sl && s.I("Full-Invoicing") == 1) o += "/ Invoicing";
            if (s.I("Level-4") == 1) o += "/ Stock ";
            if (s.I("Level-5") == 1) o += "/ Order Entry";
            t.V(o.PadRight(60).Substring(0, 60), 2401, fg: 2);
            if ((await t.A(2326, 1)).ToUpperInvariant() == "Y") break;
        }
        s.SetN("Op-System", 1); s.SetN("Sales-Range", 1); s.SetN("Purchase-Range", 2); s.SetN("Next-Batch", 1);
        s.SetN("SL-Dunning", 1); s.SetN("SL-Charges", 1); s.SetN("SL-Credit", 30); s.SetN("Invoicer", 2);
        s.Set("SL-Delim", "\\");
        c.Db.Recreate(Ctx.SysFile);
        // 各レコードは 1024 バイトのレコード領域へ書き出され、定義長より後ろは空白で埋まる
        Array.Fill(s.B, (byte)0x20, 768, 256);
        c.Sys = s; c.SaveSys();
        var d = Layouts.Default.New().B;
        Array.Fill(d, (byte)0x20, 132, d.Length - 132);
        c.Db.Put(Ctx.SysFile, "00000002", d);
        c.Db.Put(Ctx.SysFile, "00000003", System.Text.Encoding.ASCII.GetBytes(new string(' ', 1024)));
        // system-record-4 (wssys4.cob): comp-3 s9(8)v99 × 20 をゼロ初期化
        var r4 = System.Text.Encoding.ASCII.GetBytes(new string(' ', 1024));
        for (int i = 0; i < 20; i++) { Array.Fill(r4, (byte)0, i * 6, 5); r4[i * 6 + 5] = 0x0c; }
        c.Db.Put(Ctx.SysFile, "00000004", r4);
    }
}
