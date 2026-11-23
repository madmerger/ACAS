using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl030
{
    /// <summary>gl030b: 勘定科目の新規登録。</summary>
    private static async Task Add(Ctx c, string toDay)
    {
        var t = c.Crt; var sys = c.Sys;
        EnsureFile(c);
        string codes = Codes(c);
        bool usePc = Pcs(c) || Branches(c);
        var r = Layouts.Ledger.New();
        string pcCode = "  ";
        t.V(Prog, 0101, eos: true, fg: 2);
        t.V(toDay, 0171, fg: 2);
        t.D("Chart of Accounts Set-Up", 0129);
        t.D("Ledger    Sub", 0401);
        if (Pcs(c)) t.D("P/C", 0417);
        if (Branches(c)) t.D("Branch", 0415);
        t.D("-----------Name-----------  Type  Placement  Level", 0423);
        int lin = 6, lin2 = 7;
        string check = "000000";
        bool truth = false;
        int P(int col) => lin * 100 + col;
        int P2(int col) => lin2 * 100 + col;

        // ledger-read: check(+pc) のレコード有無。test=D のとき type/place を読んだレコードから引き継ぐ。
        void Read(bool d)
        {
            r.Set("nos", check);
            decimal pc = pcCode[1] == '*' ? 0 : Cob.ToNum(pcCode);
            r.SetN("pc", pc);
            var b = c.Db.Read(File, Key(Cob.ToNum(check), pc));
            truth = b != null;
            if (d && b != null)
            {
                var h = Layouts.Ledger.From(b);
                r.SetN("type", Common.IsNum(h.S("type")) ? h.N("type") : 0);
                r.Set("place", h.S("place"));
            }
        }
        void Write(decimal y) { r.SetN("pc", y); c.Db.Write(File, Key(r.N("nos"), y), (byte[])r.B.Clone()); }
        bool Parent(int from, int len)
        {
            // 上位ヘッダの存在確認後、自レコードの重複を確認する
            var save = check;
            check = check.Substring(0, from) + new string('0', len) + check.Substring(from + len);
            Read(false);
            check = save;
            if (truth) { Read(false); return true; }
            t.D("INVALID! Header Missing", P2(1));
            truth = true;
            return false;
        }

    loop:
        t.D("[    ]   [  ]", P(1));
        if (usePc) t.D("[  ]", P(16));
        t.D("[", P(23));
        t.D("]  [ ]      [ ]      [ ]", P(48));
        r.SetN("nos", 0);
    acceptLedger:
        r.Set("nos", Cob.P9(await t.AN(P(2), 4, Cob.ToNum(r.S("nos").Substring(0, 4))), 4) + r.S("nos").Substring(4));
        if (Cob.ToNum(r.S("nos").Substring(0, 4)) == 0) return;
        lin2 = lin + 1;
        if (Cob.ToNum(r.S("nos").Substring(0, 4)) < 1000) { t.D("GL102 Error! Ledger Code must be not less 1000", P2(1)); goto acceptLedger; }
        t.D(" ", P2(1), eol: true);
        r.Set("nos", r.S("nos").Substring(0, 4) + Cob.P9(await t.AN(P(11), 2, Cob.ToNum(r.S("nos").Substring(4))), 2));
        check = r.S("nos");
        int first = check[0] - '0';
        if (first == sys.I("Sales-Range") || first == sys.I("Purchase-Range")) { t.D("Invalid start number!", P2(1)); goto acceptLedger; }
        if (check.Substring(0, 4) == "9999") { t.D("<9999>  Is reserved!", P2(1)); goto acceptLedger; }
    acceptPc:
        if (!usePc) r.SetN("pc", 0);
        else
        {
            pcCode = await t.A(P(17), 2, "  ");
            if (pcCode == "  ") pcCode = "00";
            bool ok = pcCode == "**" || Common.IsNum(pcCode) || (pcCode[1] == '*' && char.IsDigit(pcCode[0]));
            if (ok && pcCode != "**" && Common.IsNum(pcCode) && pcCode != "00") { char pb = codes[int.Parse(pcCode) - 1]; ok = pb == 'E' || pb == 'Y'; }
            if (!ok) { t.D("Invalid! Code must be numeric or <n*>.", P2(17)); goto acceptPc; }
        }
        r.Set("name", await t.A(P(24), 24, ""));
        bool isDetail = check.Substring(4) != "00";
        if (isDetail) goto acceptEnd;
    acceptType:
        r.SetN("type", 0);
        t.D("0", P(52));
        r.SetN("type", await t.AN(P(52), 1, 0));
        if (r.I("type") is not (0 or 1 or 9)) { t.D("Invalid type!", P2(52)); goto acceptType; }
    acceptPlacement:
        t.V(" ", P(61));
        if (r.I("type") != 0) goto acceptEnd;
        r.Set("place", (await t.A(P(61), 1, " ")).ToUpperInvariant());
        if (r.S("place")[0] < 'A' || r.S("place")[0] > 'Z') { t.D("Invalid Placement!.", P2(61)); goto acceptPlacement; }
        if (sys.S("P-C-Level") == "R" && r.S("place")[0] > 'N' && pcCode != "00" && usePc)
        { t.D("Profit centres/branches only valid for Revenue Accounts!", P2(61)); goto acceptLedger; }
    acceptHeader:
        r.SetN("level", 0);
        t.V(" ", P(70));
        r.SetN("level", await t.AN(P(70), 1, 0));
        if (r.I("level") < 1 || r.I("level") > 4) { t.D("Invalid!", P2(70)); goto acceptHeader; }
    acceptEnd:
        foreach (var f in new[] { "balance", "last", "q1", "q2", "q3", "q4" }) r.SetN(f, 0);
        if (isDetail)
        {
            var saveS = check.Substring(4);
            check = check.Substring(0, 4) + "00";
            Read(true);
            check = check.Substring(0, 4) + saveS; r.Set("nos", check);
            if (!truth) { t.D("INVALID! Header Missing", P2(1)); truth = true; }
            else Read(false);
            if (r.I("type") != 9) r.SetN("type", 1);
            r.SetN("level", 0);
        }
        else
        {
            int h1 = int.Parse(check.Substring(1, 3)), h2 = int.Parse(check.Substring(2, 2)), h3 = check[3] - '0';
            if (h1 == 0) { Read(false); r.SetN("level", 1); }
            if (h1 != 0 && h2 == 0) { r.SetN("level", 2); Parent(1, 3); }
            if (h2 != 0 && h3 == 0) { r.SetN("level", 3); Parent(2, 2); }
            if (h3 != 0) { r.SetN("level", 4); Parent(3, 1); }
        }
        t.V(r.S("type"), P(52), fg: 2);
        t.V(r.S("level"), P(70), fg: 2);
        if (truth) goto acceptLedger;
        if (pcCode[1] == '*')
        {
            int y;
            if (pcCode[0] == '*') { for (y = 1; y <= 99; y++) if (codes[y - 1] is 'E' or 'Y') Write(y); }
            else
            {
                y = (pcCode[0] - '0') * 10; int n = 10;
                if (y == 0) { y = 1; n = 9; }
                for (int i = 0; i < n; i++, y++) if (codes[y - 1] is 'E' or 'Y') Write(y);
            }
        }
        else Write(Cob.ToNum(pcCode));
        Write(0);
        lin++;
        t.D(" ", P(1), eol: true);
        t.D(" ", 2301, eol: true);
        if (lin < 22) goto loop;
        for (lin = 6; lin < 22; lin++) t.D(" ", P(1), eol: true);
        lin = 6;
        goto loop;
    }
}
