using Acas.Core.Engine;
namespace Acas.Core.Programs;

/// <summary>irs.cbl: IRS (Incomplete Records System) システムメニュー。</summary>
public static partial class Irs
{
    public static string S(byte[]? d, int off, int len) =>
        d == null || d.Length < off + len ? new string(' ', len) : System.Text.Encoding.Latin1.GetString(d, off, len);
    public static byte[]? SysRec(Ctx c) => c.Db.Read(Ctx.I + "system.dat", "1");
    public static string Today(Ctx c) => c.Now().ToString("dd/MM/yy");

    /// <summary>共通ヘッダ: 1 行目 (プログラム名・表題・日付) と 3 行目 (Client / 会計期間)。</summary>
    public static void Head(Ctx c, string prog, string title, int col, bool client = true, bool date = true)
    {
        var t = c.Crt; var s = SysRec(c);
        t.V(prog, 0101, eos: true, fg: 2);
        t.D(title, 100 + col);
        if (date) t.V(Today(c), 0173);
        if (!client) return;
        t.D("Client - ", 0301); t.V(S(s, 32, 24).TrimEnd(), 0310);
        t.D("Start date - ", 0339); t.V(S(s, 152, 8), 0352);
        t.D("End date - ", 0362); t.V(S(s, 160, 8), 0373);
    }

    public static async Task<int> Menu(Ctx c)
    {
        var t = c.Crt;
        while (true)
        {
            Head(c, "IRS (3.01.18)", "S Y S T E M   M E N U", 31);
            t.D("Select the required function    [_]", 0501);
            t.D("(1)  System Set-Up & Maintenance", 0706);
            t.D("(2)  Accounts Set-Up & Maintenance", 0806);
            t.D("(3)  Default A/Cs Set-Up & Maintenance", 0906);
            t.D("(4)  Posting", 1006);
            t.D("(5)  Trial Balance", 1106);
            t.D("(6)  Audit Trail", 1206);
            t.D("(7)  Accounts Production", 1306);
            t.D("(8)  Posting Amendments", 1406);
            t.D("(9)  Analysis Report", 1506);
            t.D("(A)  Nominal File Fix up", 1606);
            t.D("(X)  Exit to Linux", 2006); t.D("Back Up Script Not Found", 2041);
            t.D("F1 to F10 = options 1 to A;  Return to Accept data;   Escape to quit", 2301);
            var r = (await t.A(0534, 1, init: "_", auto: true)).ToUpperInvariant();
            switch (r)
            {
                case "1":
                    // TODO: システム設定の更新 (パスワード照合後の Menu-Screen-3) は未移植
                    Head(c, "IRS (3.01.18)", "SYSTEM FILE SET-UP", 32, client: false);
                    t.D("Date - {", 0406); t.V(S(SysRec(c), 0, 8), 0414); t.V("}", 0422);
                    t.D("Pass Word - {****}", 0446);
                    await t.A(0414, 8, init: S(SysRec(c), 0, 8));
                    break;
                case "2": await Irs010.Run(c); break;
                case "3": await Irs020.Run(c); break;
                case "4":
                    // TODO: 転記入力 (irs030) の実行オプション以降は未移植
                    Head(c, "irs030 (3.01.15)", "Transaction Posting", 31, client: false, date: false);
                    t.D("Enter Run Option     -    [00] (<99>    Display Existing Defaults)", 0501);
                    t.D("(<88>    Add to Existing Postings)", 0632);
                    t.D("(<77>    Clear Existing Postings)", 0732);
                    t.D("(<66>    Add PL or SL Postings from file)", 0832);
                    t.D("(<Return> to exit to System Menu)", 1032);
                    await t.A(0528, 2, init: "00");
                    break;
                case "5":
                    // TODO: 試算表 (irs040) の出力は未移植
                    Head(c, "irs040 (3.01.12)", "Trial Balance", 31, client: false);
                    t.D("Summary or Detail <S> or <D>......[ ]", 0501);
                    t.D("Zero balances to Print (Y/N)......[ ]", 0701); t.D("Press <Return> to exit", 0741);
                    t.D("Display or Print  <D> or <P>......[ ]", 0901);
                    await t.A(0536, 1, upper: true);
                    break;
                case "6":
                    // TODO: 転記帳票 (irs050) の出力は未移植
                    Head(c, "irs050 (3.01.13)", "Posting  Reports", 28, client: false);
                    t.D("Input Report required by letter...[ ]", 0501); t.D("Press <RETURN> to exit", 0541);
                    t.D("(A) - Audit Report", 0701);
                    t.D("(L) - Ledgers", 0801);
                    t.D("(D) - VAT Day Book", 0901);
                    t.D("Display or Print  <D> or <P>......[ ]", 1101);
                    t.D("Select required sort by number....[ ]", 1301);
                    t.D("(1) - Code order sequence", 1501);
                    t.D("(2) - Date order sequence", 1601);
                    t.D("(3) - Transaction number sequence", 1701);
                    await t.A(0536, 1, upper: true);
                    break;
                case "7":
                    // TODO: 決算書作成 (irs060/irs065) は未移植
                    Head(c, "irs060 (3.01.12)", "Final Accounts Production", 29, client: false);
                    t.D("Enter comparative to use (0 to 4) -  [0]", 0801);
                    await t.A(0839, 1, init: "0");
                    break;
                case "8":
                    // レガシー実測 (IRS-008): 転記ファイルが無くエラー 35 を表示する
                    t.D("Failure to open posting-file", 2301);
                    t.D("error code = ", 2430); t.V("35", 2443); t.D("Hit return to continue", 2448);
                    await t.A(2471, 1);
                    break;
                case "9":
                    // レガシー実測 (IRS-009): 転記ファイルが無くエラー 35 を表示する
                    t.D("Error opening postings = ", 2401); t.V("35", 2426);
                    await t.A(2429, 1);
                    break;
                case "A":
                    // TODO: 勘定ファイル修復 (irs080) は未移植
                    Head(c, "irs080 (3.01.13)", "Fixup Accounts File", 29, client: false);
                    t.D("You have, made a backup of all the data files? If not do it NOW!!", 0301);
                    t.D("To quit, just enter an invalid password", 0410);
                    t.D("Enter pass word - [    ]", 0501);
                    await t.A(0520, 4, secure: true);
                    break;
                case "X":
                    throw new StopRun { KeepScreen = true };
            }
        }
    }
}
