package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** gl090a.cbl: 階層別（P/C・拠点）試算表の印刷。 */
public class Gl090a extends GlProgram {
    static final String PROG_NAME = "gl090a (3.00.04)";
    private static final BigDecimal MOD = new BigDecimal("100000000"), Z = BigDecimal.ZERO;
    private static final String LINE7 = sp(108) + " ==========  ==========";

    private Rec led; private CobFile ledger; private Printer print;
    private final BigDecimal[] lDr = new BigDecimal[6], lCr = new BigDecimal[6];
    private final int[] store = new int[6];
    private int pageCnt, lineCnt; private BigDecimal totDr = Z, totCr = Z; private String wsDate;

    private static BigDecimal u8(BigDecimal v) { return v.abs().remainder(MOD); }

    @Override
    public void run(Object... args) {
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        display(1, 1, PROG_NAME); eraseEos(1, 17);
        display(1, 29, "Structured Trial Balance");
        wsDate = wsDate();
        show(1, 71, wsDate, 2);
        print = new Printer("prt-1", 132);
        print.open();
        ledger.open(CobFile.Mode.INPUT);
        for (int i = 1; i <= 5; i++) { lDr[i] = Z; lCr[i] = Z; store[i] = 0; }
        headings();
        while (true) {
            String st = ledger.readNext(led);
            if (!st.equals("00") && !st.equals("10")) runaway();
            if (st.equals("10") || led.intv("ledger-n") == 9999) {
                detailPrint(); totalPrint(4); totalPrint(3); totalPrint(2); totalPrint(1);
                break;
            }
            int nos = led.intv("ledger-nos"), level = led.intv("ledger-level");
            if (nos != store[5] && store[5] != 0) {
                detailPrint();
                lCr[5] = Z; lDr[5] = Z;
                if (level == 0) store[5] = nos;
            }
            if (nos == store[4] || nos == store[3] || nos == store[2] || nos == store[1]) continue;
            if (level >= 1 && level <= 4) {
                if (store[level] != 0) for (int l = 4; l >= level; l--) totalPrint(l);
                store[level] = nos;
                continue;
            }
            BigDecimal bal = led.num("ledger-balance");
            if (nos == store[5]) {
                if (bal.signum() < 0) lCr[5] = u8(lCr[5].subtract(bal)); else lDr[5] = u8(lDr[5].add(bal));
                continue;
            }
            if (bal.signum() < 0) lCr[5] = bal.abs(); else lDr[5] = bal;
            store[5] = nos;
        }
        print.after(LINE7, 3);
        print.after(sp(20) + pad("t o t a l", 88) + Num.edit(totDr, "zzzzzzz9.99") + " " + Num.edit(totCr, "zzzzzzz9.99"), 1);
        print.after(LINE7, 1);
        print.close(); ledger.close();
        ctx.spool("prt-1", printReport());
    }

    private void headings() {
        pageCnt = (byte) (pageCnt + 1);
        String l1 = pad(PROG_NAME, 50) + "Profit Centre Trial Balance" + sp(47) + "Page " + Num.edit(Math.abs(pageCnt) % 1000, "zz9");
        String l3 = pad(sys.str("usera"), 32) + sp(25) + "Condensed Report" + sp(49) + wsDate;
        if (pageCnt != 1) { print.afterPage(l1); print.after(l3, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l3, 1); }
        print.after("Account      <----Detail   Level----><-------Level"
                + "  4-------><-------Level  3-------><-------Level  2---"
                + "----><-------Level  1------>", 1);
        print.after("               Debit        Credit      Debit       C"
                + "Redit      Debit       Credit      Debit       Credit   "
                + "   Debit       Credit  ", 1);
        print.after("", 1);
        lineCnt = 6;
    }

    private void writeLine6(int level, int col, BigDecimal dr, BigDecimal cr) {
        int indent = level - 1;
        StringBuilder sb = new StringBuilder(pad(sp(indent) + Num.z9(store[level] / 100, 4) + "." + Num.z9(store[level] % 100, 2), 12));
        for (int i = 1; i <= 10; i++) {
            BigDecimal v = i == col ? dr : i == col + 1 ? cr : Z;
            sb.append(v.signum() == 0 ? sp(12) : Num.edit(v, "zzzzzzz9.99") + " ");
        }
        print.after(sb.toString(), 1);
        lineCnt++;
        if (lineCnt > sys.intv("page-lines")) headings();
    }

    /** 上位レベル（無ければ総合計）へ繰り上げる。 */
    private void rollUp(int level) {
        for (int up = level - 1; up >= 1; up--) {
            if (store[up] != 0) {
                lDr[up] = u8(lDr[up].add(lDr[level])); lCr[up] = u8(lCr[up].add(lCr[level]));
                return;
            }
        }
        if (lDr[level].compareTo(lCr[level]) > 0) totDr = u8(u8(totDr.add(lDr[level])).subtract(lCr[level]));
        else totCr = u8(u8(totCr.add(lCr[level])).subtract(lDr[level]));
    }

    private void detailPrint() {
        writeLine6(5, 1, lDr[5], lCr[5]);
        rollUp(5);
        lDr[5] = Z; lCr[5] = Z;
    }

    private void totalPrint(int level) {
        boolean drSide = lDr[level].compareTo(lCr[level]) > 0;
        BigDecimal dr = drSide ? lDr[level].subtract(lCr[level]) : Z, cr = drSide ? Z : lCr[level].subtract(lDr[level]);
        int col = 11 - 2 * level;
        if (level == 1) {
            writeLine6(1, col, dr, cr);
            print.after("", 1);
        } else if (store[level] != 0) writeLine6(level, col, dr, cr);
        rollUp(level);
        store[level] = 0; lDr[level] = Z; lCr[level] = Z;
    }
}
