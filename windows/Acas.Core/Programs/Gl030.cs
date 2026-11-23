using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl030: 勘定科目表ユーティリティ (登録・変更/削除・照会・印刷)。</summary>
public static partial class Gl030
{
    public const string File = Ctx.L + "ledger.dat";
    private const string Prog = "GL030 (3.00.04)";
    private static readonly string[] Types = { "Header ", "Detail ", "Sales  ", "Purch. ", "Special" };
    private static readonly string[] Places = { "Direct Income", "Direct Costs ", "Sundry Income", "Indirect Cost", "Fixed Assets ", "Current Asset", "Current Liab.", "Capital A/Cs " };

    private static bool Pcs(Ctx c) => c.Sys.S("P-C") == "P";
    private static bool Branches(Ctx c) => c.Sys.S("P-C") == "B";
    private static bool Index2(Ctx c) => c.Sys.S("Ledger-2nd-Index") == "Y";
    public static string Key(decimal nos, decimal pc) => Cob.P9(nos, 6) + Cob.P9(pc, 2);

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var t = c.Crt;
        while (true)
        {
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Chart Of Account Utilities", 0128);
            t.V(Common.ToForm(c, toDay), 0171, fg: 2);
            t.V(c.Sys.S("Usera"), 0301);
            t.D("Select one of the following by number :- [ ]", 0801);
            int lin = 10, a = 1;
            void Item(string text) { t.V("(", lin * 100 + 1, fg: 2); t.V(a.ToString(), lin * 100 + 2, fg: 2); t.V(")", lin * 100 + 3, fg: 2); t.D(text, lin * 100 + 6); }
            if (Pcs(c)) { Item("Set-up or Amend Profit Centres"); lin++; a++; }
            if (Branches(c)) { Item("Set-up or Amend Branch Codes"); lin++; a++; }
            Item("Add New Accounts"); lin++; a++;
            Item("Amend/Delete Existing Accounts"); lin++; a++;
            if (Index2(c)) { Item("Print Alphabetic List"); lin++; a++; }
            Item("Display Chart of Accounts"); lin++; a++;
            Item("Print Chart of Accounts"); lin++; a++;
            if (Pcs(c)) Item("Print Report on Profit Centres");
            if (Branches(c)) Item("Print Report on Branch Codes");
            lin += 3; a = 9;
            Item("Exit to system menu");
            int menu = (int)await t.AN(0843, 1, 0);
            if (menu == 9) return 0;
            if (c.Sys.S("P-C") == " ") menu++;
            if (menu == 1) { await SetupPc(c, toDay); continue; }
            if (menu == 2) { await Add(c, toDay); continue; }
            if (menu == 3) { await Amend(c, toDay); continue; }
            if (!Index2(c)) menu++;
            if (menu == 4) { await Alpha(c, toDay); continue; }
            if (menu == 5 || menu == 6) { await Chart(c, toDay, menu); continue; }
            if (menu == 7) await PcReport(c, toDay);
        }
    }

    /// <summary>ledger-file が無ければ P/C 管理レコード(999999/99)付きで作成する。</summary>
    private static void EnsureFile(Ctx c)
    {
        if (c.Db.Exists(File)) return;
        var r = Layouts.Ledger.New();
        r.SetN("nos", 999999); r.SetN("pc", 99);
        for (int i = 16; i < 40; i++) r.B[i] = 0;   // ledger-name = low-values
        c.Db.Recreate(File);
        c.Db.Write(File, Key(999999, 99), r.B);
    }

    private static string Codes(Ctx c)
    {
        var b = c.Db.Read(File, Key(999999, 0));
        return b == null ? new string(' ', 99) : System.Text.Encoding.Latin1.GetString(b, 8, 99);
    }
}
