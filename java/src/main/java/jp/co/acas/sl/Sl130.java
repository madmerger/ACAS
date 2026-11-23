package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** sl130.cbl: 売上分析帳票。 */
public class Sl130 extends SlProgram {
    static final String PROG_NAME = "SL130 (3.01.07)";

    private Rec sys;
    private Prt print;
    private int a, lineCnt = 66, pageLines;
    /** work-1 pic 9(4)v9(4)。ゼロ除算（SIZE ERROR）時は直前の値が残る。 */
    private BigDecimal work1 = BigDecimal.ZERO;

    @Override
    public void run(Object... args) {
        sys = sys();
        eraseEos(1, 1);
        show(1, 1, PROG_NAME);
        display(1, 34, "Sales Analysis");
        show(1, 71, fromUk(toDay()), 2);
        report1();
        sys.setNum("s-flag-a", 0);
    }

    private static String bwz(BigDecimal v, String pic, int width) { return v.signum() == 0 ? " ".repeat(width) : pad(Num.edit(v, pic), width); }
    private static String cnt(long v) { return bwz(BigDecimal.valueOf(v), "zzzz9", 5); }

    private void divide(BigDecimal x, BigDecimal y) {
        if (y.signum() == 0) return;
        BigDecimal q = x.divide(y, 4, RoundingMode.DOWN).abs();
        if (q.compareTo(new BigDecimal(10000)) >= 0) return;
        work1 = q;
    }
    private BigDecimal pct(int intDigits) {
        return work1.multiply(new BigDecimal(100)).setScale(2, RoundingMode.DOWN).remainder(BigDecimal.TEN.pow(intDigits));
    }

    private void report1() {
        Rec val = valueRec();
        CobFile valFile = valueFile(val);
        valFile.open(CobFile.Mode.INPUT);
        if (!valFile.status.equals("00")) { valFile.close(); return; }
        pageLines = sys.intv("page-lines");
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        a = 0;
        headings();
        String type = " ".repeat(9);
        while (valFile.readNext(val).equals("00")) {
            if (!val.str("va-system").equals("S")) continue;
            boolean group = val.str("va-second").isBlank();
            if (!group && val.num("va-v-this").signum() == 0 && val.num("va-v-year").signum() == 0) continue;
            if (group && val.longv("va-gl") == 0) {
                type = "Group";
                headings();
                print.after("", 1);
                lineCnt++;
            } else type = " Detail";
            divide(BigDecimal.valueOf(val.longv("va-t-this")), BigDecimal.valueOf(val.longv("va-t-last")));
            String pt = bwz(pct(5), "z(4)9.99", 8);
            divide(val.num("va-v-this"), val.num("va-v-last"));
            String pa = bwz(pct(4), "zzz9.99", 7);
            print.after("   " + pad(val.str("va-group"), 6) + pad(type, 9) + pad(val.str("va-desc"), 28)
                + cnt(val.longv("va-t-this")) + " ".repeat(5) + cnt(val.longv("va-t-last")) + " ".repeat(6) + cnt(val.longv("va-t-year")) + " ".repeat(4)
                + bwz(val.num("va-v-this"), "z(7)9.99cr", 13) + bwz(val.num("va-v-last"), "z(8)9.99cr", 14) + bwz(val.num("va-v-year"), "z(8)9.99cr", 14)
                + pt + pa, 1);
            lineCnt++;
            if (lineCnt > pageLines) headings();
        }
        valFile.close(); print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private void headings() {
        if (lineCnt < pageLines) return;
        a++;
        lineCnt = 6;
        String l1 = pad(PROG_NAME, 58) + pad("Sales  Analysis", 64) + "Page " + Num.edit(a, "zz9");
        String l2 = pad(sys.str("usera"), 52) + " ".repeat(70) + pad(fromUk(toDay()), 10);
        if (a != 1) { print.afterPage(l1); print.after(l2, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l2, 1); }
        print.after("Analysis  Type    <-----Description------>   <-------Transactions------->   <----------------Amount----------------->  % Period Mvmt", 2);
        print.after(pad("  Code", 45) + L5, 1);
        print.after("", 1);
    }
    static final String L5 = "Current   Previous   Y. to D      Current      Previous    Year To Date  Trans. Amount";
}
