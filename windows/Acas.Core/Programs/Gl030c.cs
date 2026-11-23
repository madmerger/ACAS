using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl030
{
    /// <summary>gl030c: 勘定科目の変更・削除。</summary>
    private static async Task Amend(Ctx c, string toDay, St st)
    {
        var t = c.Crt; var sys = c.Sys;
        if (!c.Db.Exists(File)) { t.D("GL103 No Ledger File to update", 0901); return; }
        bool usePc = Pcs(c) || Branches(c);
        string codes = usePc ? Codes(c) : new string(' ', 99);
        var r = Layouts.Ledger.New();
        string pcCode = st.PcCode;
        t.V(Prog, 0101, eos: true, fg: 2);
        t.V(Common.ToForm(c, toDay), 0171, fg: 2);
        t.D("Chart Of Accounts Update", 0129);
        t.D("Ledger    Sub", 0401);
        if (Pcs(c)) t.D("P/C", 0417);
        if (Branches(c)) t.D("Branch", 0415);
        t.D("-----------Name-----------  Type  Placement  Level", 0423);
        int lin = 6, lin2 = 6;
        int P(int col) => lin * 100 + col;
        int P2(int col) => lin2 * 100 + col;

        async Task Rewrite(decimal y)
        {
            r.SetN("pc", y);
            if (!c.Db.Rewrite(File, Key(r.N("nos"), y), (byte[])r.B.Clone()))
            {
                t.D("GL104 Rewrite ERR 030-01. hit return to finish", 2301, fg: 4);
                await t.A(2348, 1);
                c.Db.Write(File, Key(r.N("nos"), y), (byte[])r.B.Clone());
            }
        }
        void Delete(decimal y)
        {
            r.SetN("pc", y);
            if (r.N("balance") != 0) { t.D("Deletion Request Denied! Current Balance Not Zero", P2(24)); return; }
            c.Db.Delete(File, Key(r.N("nos"), y));
        }
        IEnumerable<int> Multi()
        {
            if (pcCode[0] == '*') { for (int y = 1; y <= 99; y++) if (codes[y - 1] is 'E' or 'Y') yield return y; yield break; }
            int s = (pcCode[0] - '0') * 10, n = 10;
            if (s == 0) { s = 1; n = 9; }
            for (int i = 0; i < n; i++, s++) if (codes[s - 1] is 'E' or 'Y') yield return s;
        }

    loop:
        t.D("[    ]", P(1));
        t.D("[  ]", P(11));
        if (usePc) t.D("[  ]", P(16));
        t.D("[", P(23));
        t.D("]  [ ]      [ ]      [ ]", P(48));
    acceptLedger:
        r.SetN("nos", 0);
        decimal n4 = await t.AN(P(2), 4, 0);
        r.Set("nos", Cob.P9(n4, 4) + "00");
        if (n4 == 0) return;
        r.Set("nos", Cob.P9(n4, 4) + Cob.P9(await t.AN(P(12), 2, 0), 2));
    acceptPc:
        lin2 = lin;
        bool star = false;
        if (!usePc) st.PcCode = pcCode = "0 ";
        else
        {
            pcCode = await t.A(P(17), 2, pcCode); st.PcCode = pcCode;
            if (pcCode == "  ") pcCode = "00";
            bool ok = pcCode == "**" || Common.IsNum(pcCode) || (pcCode[1] == '*' && char.IsDigit(pcCode[0]));
            if (ok && Common.IsNum(pcCode) && pcCode != "00") { char pb = codes[int.Parse(pcCode) - 1]; ok = pb == 'E' || pb == 'Y'; }
            lin2++;
            if (!ok) { t.D("Invalid! Code must be numeric or <n*>", P2(17)); goto acceptPc; }
            lin2--;
        }
        lin2 = usePc ? lin + 1 : lin;
        t.D(" ", P2(1), eol: true);
        star = pcCode[1] == '*';
        r.SetN("pc", star ? 0 : Cob.ToNum(pcCode));
        var b = c.Db.Read(File, Key(r.N("nos"), r.N("pc")));
        if (b == null)
        {
            t.V(r.S("nos"), P2(1), fg: 2); t.V("/", P2(7), fg: 2); t.V(r.S("pc"), P2(8), fg: 2);
            t.D("Does not exist!", P2(11));
            goto acceptLedger;
        }
        r = Layouts.Ledger.From(b);
        t.D("Enter <+> only to Delete", P2(24));
        t.V(r.S("name"), P(24), fg: 2);
        r.Set("name", await t.A(P(24), 24, r.S("name")));
        if (r.S("name")[0] == '+')
        {
            if (star) foreach (var y in Multi()) Delete(y); else Delete(Cob.ToNum(pcCode));
            Delete(0);
            goto end2;
        }
    acceptType:
        t.D(" ", P2(1), eol: true);
        t.V(r.S("type"), P(52), fg: 2);
        r.SetN("type", await t.AN(P(52), 1, r.N("type")));
        if (r.I("type") is not (0 or 1 or 9)) { t.D("Invalid type!", P2(52)); goto acceptType; }
    acceptPlacement:
        if (r.I("type") != 0) goto loopEnd;
        r.Set("place", (await t.A(P(61), 1, r.S("place"))).ToUpperInvariant());
        if (r.S("place")[0] < 'A' || r.S("place")[0] > 'Z') { t.D("Invalid Placement!", P2(61)); goto acceptPlacement; }
        if (sys.S("P-C-Level") == "R" && r.S("place")[0] > 'N' && r.N("pc") != 0)
        { t.D("Profit centres/branches only valid for Revenue Accounts!", P2(61)); goto acceptLedger; }
    acceptHeader:
        t.V(r.S("level"), P(70), fg: 2);
        r.SetN("level", await t.AN(P(70), 1, r.N("level")));
        if (r.I("level") < 1 || r.I("level") > 4) { t.D("Invalid!", P2(70)); goto acceptHeader; }
    loopEnd:
        if (star) foreach (var y in Multi()) await Rewrite(y); else await Rewrite(Cob.ToNum(pcCode));
        await Rewrite(0);
    end2:
        lin++;
        t.D(" ", P(1), eol: true);
        if (lin < 22) goto loop;
        for (lin = 6; lin < 22; lin++) t.D(" ", P(1), eol: true);
        lin = 6;
        goto loop;
    }
}
