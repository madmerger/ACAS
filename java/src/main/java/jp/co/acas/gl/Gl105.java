package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** gl105.cbl: 元帳印刷（整列済み保管仕訳 workarc.tmp から勘定別に印刷）。 */
public class Gl105 extends GlProgram {
    static final String PROG_NAME = "gl105 (3.00.04)";
    private static final BigDecimal Z = BigDecimal.ZERO, MOD = new BigDecimal("100000000");
    private static final String LINE8 = sp(90) + "===========   ===========";

    private Rec led, arc; private CobFile ledger, archive; private Printer print;
    private int lineCnt, countx, sheet, saveAc, savePc, acToPrint, pcToPrint;
    private BigDecimal totDr = Z, totCr = Z;
    private String arcOutName = "workarc.tmp", wsDate, line4Head = "";

    private static BigDecimal s8(BigDecimal v) { return v.remainder(MOD); }
    private static String bwz(BigDecimal v) { return v.signum() == 0 ? sp(11) : Num.edit(v.abs(), "zzzzzzz9.99"); }

    @Override
    public void run(Object... args) {
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        arc = Layout.ofSource(Gl080.ARC_LAYOUT, "arc-trans-record").newRec();
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 35, "Ledger Print");
        wsDate = wsDate();
        show(1, 71, wsDate, 2);
        show(3, 1, sys.str("usera"), 3);
        diskChange();
        eraseEos(12, 1);
        ledger.open(CobFile.Mode.INPUT);
        display(6, 21, "Print All Accounts? (Y/N) [ ]");
        boolean askAc = true;
        while (true) {
            if (askAc) {
                String r = pad(acceptUpdate(6, 48, 1, "Y"), 1).toUpperCase();
                if (r.equals("Y")) break;
                if (!r.equals("N")) continue;
            }
            display(8, 21, "Enter Account to print   [     ]");
            acToPrint = (int) acceptNum(8, 47, 6, acToPrint);
            askAc = acToPrint == 0;
            if (askAc) continue;
            led.setNum("ledger-nos", acToPrint); led.setNum("ledger-pc", 0);
            if (!ledger.read(led).equals("00")) { display(8, 54, "GL118 A/C Not Found"); continue; }
            eraseEol(8, 54);
            break;
        }
        boolean askPc = true;
        while (true) {
            if (askPc) {
                display(12, 21, "Print all P/Cs ?    (Y/N) [ ]");
                String r = pad(acceptUpdate(12, 48, 1, "Y"), 1).toUpperCase();
                if (r.equals("Y")) break;
                if (!r.equals("N")) continue;
            }
            display(14, 21, "Enter P/C to Print       [     ]");
            pcToPrint = (int) acceptNum(14, 47, 2, pcToPrint);
            askPc = pcToPrint == 0;
            if (askPc) continue;
            if (acToPrint == 0) break;
            led.setNum("ledger-pc", pcToPrint);
            if (!ledger.read(led).equals("00")) { display(14, 54, "GL119 P/C Not Found"); continue; }
            eraseEol(14, 54);
            break;
        }
        archive = CobFile.lineSequential(ctx.store, ctx.path(arcOutName.trim()));
        if (!archive.open(CobFile.Mode.INPUT).equals("00")) runaway();
        print = new Printer("prt-1", 132);
        print.open();
        while (true) {
            String l = archive.readLine();
            if (l == null) { acEnd(); break; }
            arc.load(latin(pad(l, 86)));
            int ac = arc.intv("arc-ac"), pc = arc.intv("arc-pc");
            if (acToPrint != 0) {
                if (acToPrint < ac) continue;
                if (acToPrint > ac) { acEnd(); break; }
            }
            if (pcToPrint != 0 && pcToPrint != pc) continue;
            if (saveAc == 0) newAc();
            else if (ac != saveAc || pc != savePc) { acEnd(); newAc(); }
            BigDecimal amt = arc.num("arc-amount");
            if (amt.signum() > 0) totDr = s8(totDr.add(amt)); else totCr = s8(totCr.add(amt));
            int cac = arc.intv("arc-c-ac"), cpc = arc.intv("arc-c-pc");
            print.after(Num.edit(arc.intv("arc-batch"), "zzzz9") + "/" + Num.edit(arc.intv("arc-post"), "zzzz9") + sp(6)
                    + pad(arc.str("arc-code"), 7) + pad(arc.str("arc-date"), 14) + pad(arc.str("arc-legend"), 37)
                    + (cac == 0 ? sp(9) : Num.edit(cac / 100, "zzz9") + "." + Num.z9(cac % 100, 2) + "  ")
                    + (cpc == 0 ? sp(6) : Num.edit(cpc, "z9") + sp(4))
                    + (amt.signum() > 0 ? bwz(amt) : sp(11)) + sp(3) + (amt.signum() > 0 ? sp(11) : bwz(amt)), 1);
            lineCnt++;
            if (lineCnt > sys.intv("page-lines")) headings();
        }
        print.close(); ledger.close(); archive.close();
        ctx.spool("prt-1", printReport());
    }

    private void newAc() {
        int ac = arc.intv("arc-ac"), pc = arc.intv("arc-pc");
        led.setNum("ledger-nos", ac); led.setNum("ledger-pc", pc);
        if (!ledger.read(led).equals("00")) led.set("ledger-name", "***Unknown***");
        saveAc = ac; savePc = pc;
        line4Head = "Account - " + Num.edit(ac / 100, "zzz9") + "." + Num.z9(ac % 100, 2) + " / "
                + (pc == 0 ? sp(6) : Num.z9(pc, 2) + sp(4)) + pad(led.str("ledger-name"), 98) + "Sheet ";
        sheet = 0;
        headings();
    }

    private void headings() {
        countx = (countx + 1) % 1000;
        sheet = (sheet + 1) % 100;
        String l1 = pad(PROG_NAME, 54) + pad("Ledger - Print", 70) + "Page " + Num.edit(countx, "zz9");
        String l3 = pad(sys.str("usera"), 122) + wsDate;
        String l4 = line4Head + Num.edit(sheet, "z9");
        if (countx != 1) { print.afterPage(l1); print.after(l3, 1); print.after(l4, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l3, 1); print.before(l4, 1); }
        print.after("Transaction     Code    <--Date-->    <------------Legend------------>     "
                + "<--Contra-->   <--Debit-->   <-Credit-->    <--Balance-->", 1);
        print.after(sp(75) + "Account P.C.", 1);
        print.after("", 1);
        lineCnt = 7;
    }

    private void acEnd() {
        BigDecimal bal = s8(totDr.add(totCr));
        print.after(LINE8, 2);
        print.after(sp(75) + pad("B a l a n c e", 15) + Num.edit(totDr.abs(), "zzzzzzz9.99") + sp(3) + Num.edit(totCr.abs(), "zzzzzzz9.99") + sp(4)
                + (bal.signum() == 0 ? sp(13) : Num.edit(bal.abs(), "zzzzzzz9.99") + (bal.signum() < 0 ? "CR" : "  ")), 1);
        print.after(LINE8, 1);
        totDr = Z; totCr = Z;
    }

    private void diskChange() {
        arcOutName = "archives" + osDelimiter(3) + arcOutName.trim();
        display(12, 1, "GL115 Ensure Archive USB Memory Stick is in path"); eraseEol(12, 49);
        display(13, 1, "GL114 Enter <0> to signify change made or <9> to abort this run :- [ ]"); eraseEol(13, 71);
        while (true) {
            int a = (int) acceptNum(13, 69, 2);
            if (a == 9) return;
            if (a != 0) continue;
            display(14, 1, "Current path is :"); eraseEol(14, 18);
            show(15, 1, pad(arcOutName, 80), 2);
            arcOutName = acceptUpdate(15, 1, 80, pad(arcOutName, 80));
            if (arcOutName.isEmpty() || arcOutName.charAt(0) == ' ') continue;
            return;
        }
    }
}
