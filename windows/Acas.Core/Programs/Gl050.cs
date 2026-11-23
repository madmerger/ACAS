using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>gl050: 仕訳 (取引) 入力。バッチ設定 (gl050a) と明細入力 (gl050b)。</summary>
public static partial class Gl050
{
    private const string Prog = "gl050 (3.00.03)";
    public const string BatchFile = Ctx.L + "batch.dat";
    public const string PostFile = Ctx.L + "postings.dat";
    private const string Sp44 = "                                            ";

    private sealed class St
    {
        public Rec B = Layouts.Batch.New();
        public Rec D = Layouts.Default.New();
        public string WsDate = "", Codes = new string(' ', 99);
        public int A, Z, VatFlag, SaveA;
        public bool Exit, Back;
    }
    private static bool Pcs(Ctx c) => c.Sys.S("P-C") == "P";
    private static bool Branches(Ctx c) => c.Sys.S("P-C") == "B";
    private static bool AutoVat(Ctx c) => c.Sys.S("Vat") == "Y";
    public static string BKey(Rec b) => b.S("ledger") + b.S("batch-nos");

    public static async Task<int> Run(Ctx c, string toDay)
    {
        var s = new St { D = Layouts.Default.From(c.Db.Read(Ctx.SysFile, "00000002") ?? Layouts.Default.New().B) };
        int r = await Run(c, toDay, s);
        c.Db.Put(Ctx.SysFile, "00000002", s.D.B);   // 呼出元 (general) が既定勘定レコードを書き戻す
        return r;
    }

    private static async Task<int> Run(Ctx c, string toDay, St s)
    {
        var t = c.Crt;
        if (!c.Db.Exists(BatchFile))
        {
            c.Db.Create(BatchFile);
            var b = Layouts.Batch.New();
            b.SetN("ledger", 9); b.SetN("batch-nos", 99999); b.SetN("bcycle", 99);
            c.Db.Write(BatchFile, BKey(b), b.B);
        }
        if (!c.Db.Exists(PostFile)) c.Db.Create(PostFile);
        while (true)
        {
            s.WsDate = Common.ToForm(c, toDay);
            t.V(Prog, 0101, eos: true, fg: 2);
            t.D("Transaction Entry Functions", 0127);
            t.V(s.WsDate, 0171, fg: 2);
            t.V(c.Sys.S("Usera"), 0301, fg: 2);
            t.D("Select one of the following by number :- [1]", 0801);
            s.A = 1;
            t.D("(1)  Set up New Batch", 1001);
            t.D("(9)  Exit to system menu", 1301);
            int menu = (int)await t.AN(0843, 1, 1);
            if (menu == 9) return 0;
            if (menu != 1) continue;
            s.B.SetN("ledger", 1);
            s.B.SetN("batch-nos", c.Sys.N("Next-Batch"));
            c.Sys.SetN("Next-Batch", c.Sys.N("Next-Batch") + 1);
            await SetUp(c, s);
            if (s.Exit || s.B.N("bdefault") == 0) return 0;
            await Input(c, s);
            if (s.Z == 9) c.Sys.SetN("Next-Batch", c.Sys.N("Next-Batch") - 1);
            else c.Db.Write(BatchFile, BKey(s.B), (byte[])s.B.B.Clone());
        }
    }

    private static void HelpA(Crt t)
    {
        t.V(new string('+', 31), 1550, fg: 2); t.V(new string('+', 31), 2350, fg: 2);
        for (int l = 16; l <= 22; l++) { t.V("+", l * 100 + 50, fg: 2); t.V("+", l * 100 + 80, fg: 2); }
        t.D("Help Data", 1661);
    }
    private static void BatchOutline(Crt t)
    {
        for (int l = 16; l <= 23; l++) t.V(Sp44, l * 100 + 1);
        t.V(new string('*', 46), 1501, fg: 2); t.V(new string('*', 46), 2301, fg: 2);
        for (int l = 16; l <= 22; l++) { t.V("*", l * 100 + 1, fg: 2); t.V("*", l * 100 + 46, fg: 2); }
        t.D("Batch Data", 1618);
    }
    private static Rec? Desc(Ctx c, St s, int a, decimal pc)
    {
        var b = c.Db.Read(Gl030.File, Gl030.Key(Cob.Trunc(s.D.N("acs" + a) * 100, 0), pc));
        return b == null ? null : Layouts.Ledger.From(b);
    }
    /// <summary>nnnn.nn 形式 (整数部 n 桁) の金額・勘定入力。</summary>
    private static async Task<decimal> Money(Crt t, int pos, int n, decimal cur, bool show = true)
    {
        string init = Cob.P9(decimal.Truncate(cur), n) + "." + Cob.P9(decimal.Truncate(cur * 100) % 100, 2);
        if (show) t.V(init, pos);
        var r = (await t.A(pos, n + 3, init)).PadRight(n + 3);
        return Cob.ToInt(r.Substring(0, n)) + Cob.ToInt(r.Substring(n + 1, 2)) / 100m;
    }
}
