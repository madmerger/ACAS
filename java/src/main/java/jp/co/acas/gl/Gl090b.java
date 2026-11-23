package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** gl090b.cbl: 明細試算表の印刷。 */
public class Gl090b extends GlProgram {
    static final String PROG_NAME = "gl090b (3.00.04)";
    private static final BigDecimal MOD = new BigDecimal("100000000");
    private static final String LINE7 = sp(50) + "=========== ===========    =========== ===========";

    private Rec led; private CobFile ledger; private Printer print;
    private int j, k, pageNos, lineCnt, saveN;
    private BigDecimal totlDr = BigDecimal.ZERO, totlCr = BigDecimal.ZERO, prevDr = BigDecimal.ZERO, prevCr = BigDecimal.ZERO;
    private String l4Filler = sp(10), wsDate;

    private static BigDecimal u8(BigDecimal v) { return v.abs().remainder(MOD); }
    private static String bwz(BigDecimal v, String pic, int n) { return v.signum() == 0 ? sp(n) : pad(Num.edit(v, pic), n); }
    private static String qtr(BigDecimal v) {
        return v.signum() == 0 ? sp(13) : Num.edit(v.abs(), "zzzzzzz9.99") + (v.signum() < 0 ? "CR" : "  ");
    }

    @Override
    public void run(Object... args) {
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
            eraseEos(1, 1);
            display(9, 1, "GL106 Ledger File Does Not Exist", 4);
            display(10, 1, "GL012 Hit Return to Quit");
            accept(10, 26, 1);
            return;
        }
        display(1, 1, PROG_NAME); eraseEos(1, 17);
        wsDate = wsDate();
        show(1, 71, wsDate, 2);
        display(1, 29, "Detailed Trial Balance");
        display(12, 12, "Working.......Please wait");
        print = new Printer("prt-1", 132);
        print.open();
        l4Filler = pad(profitCentres() ? "  P/C " : branches() ? "Branch" : "", 10);
        pageNos = 0;
        pageHeading();
        while (ledger.readNext(led).equals("00") && led.intv("ledger-n") != 9999) {
            if (led.intv("ledger-n") != saveN) {
                saveN = led.intv("ledger-n");
                print.after("", 1);
                lineCnt++;
            }
            BigDecimal bal = led.num("ledger-balance"), last = led.num("ledger-last");
            BigDecimal cDr = BigDecimal.ZERO, cCr = BigDecimal.ZERO, pDr = BigDecimal.ZERO, pCr = BigDecimal.ZERO;
            if (bal.signum() < 0) { cCr = bal.abs(); totlCr = u8(totlCr.subtract(bal)); } else { cDr = bal; totlDr = u8(totlDr.add(bal)); }
            if (last.signum() < 0) { pCr = last.abs(); prevCr = u8(prevCr.subtract(last)); } else { pDr = last; prevDr = u8(prevDr.add(last)); }
            print.after(line6(led.intv("ledger-nos"), led.intv("ledger-pc"), led.str("ledger-name"), cDr, cCr, pDr, pCr, q(j), q(k)), 1);
            lineCnt++;
            if (lineCnt > sys.intv("page-lines")) pageHeading();
        }
        print.after(LINE7, 3);
        print.after(line6(0, 0, "T o t a l", totlDr, totlCr, prevDr, prevCr, BigDecimal.ZERO, BigDecimal.ZERO), 1);
        print.after(LINE7, 1);
        print.close();
        ctx.spool("prt-1", printReport());
        ledger.close();
    }

    private BigDecimal q(int n) { return n >= 1 && n <= 4 ? led.num("ledger-q", n) : led.num("ledger-last"); }

    private String line6(int nos, int pc, String name, BigDecimal cDr, BigDecimal cCr, BigDecimal pDr, BigDecimal pCr, BigDecimal q1, BigDecimal q2) {
        return (nos == 0 ? sp(7) : Num.z9(nos / 100, 4) + "." + Num.z9(nos % 100, 2)) + sp(5)
                + (pc == 0 ? sp(8) : Num.edit(pc, "z9") + sp(6)) + pad(name, 30)
                + bwz(cDr, "zzzzzzz9.99", 12) + bwz(cCr, "zzzzzzz9.99", 11) + sp(4)
                + bwz(pDr, "zzzzzzz9.99", 12) + bwz(pCr, "zzzzzzz9.99", 11) + sp(4)
                + qtr(q1) + "  " + qtr(q2);
    }

    private void pageHeading() {
        pageNos = (pageNos + 1) % 1000;
        switch (sys.intv("current-quarter")) {
            case 1 -> { j = 4; k = 3; }
            case 2 -> { j = 1; k = 4; }
            case 3 -> { j = 2; k = 1; }
            case 4 -> { j = 3; k = 2; }
            default -> { }
        }
        String l1 = pad(PROG_NAME, 56) + "Detail Trial Balance" + sp(48) + "Page " + Num.edit(pageNos, "zz9");
        String l3 = pad(sys.str("usera"), 32) + sp(90) + wsDate;
        if (pageNos != 1) { print.afterPage(l1); print.after(l3, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l3, 1); }
        print.after("Account   " + l4Filler
                + "<---------Name--------->      <---Current Balance--->    <--Last Year Balance->     <-Quarter "
                + j + "->  <-Quarter " + k + "->", 1);
        print.after(sp(53) + "Debit      Credit          Debit     Credit", 1);
        print.after("", 1);
        lineCnt = 6;
    }
}
