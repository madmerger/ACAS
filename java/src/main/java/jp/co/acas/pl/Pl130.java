package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** pl130.cbl: 仕入分析帳票。 */
public class Pl130 extends PlBase {
    static final String PROG_NAME = "PL130 (3.01.04)";
    private Printer prt;
    private int a, lineCnt = 66, pageLines;
    private String wsDate;

    @Override
    public void run(Object... args) {
        init();
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 34, "Purchase Analysis");
        wsDate = fromUk(toDay());
        show(1, 71, wsDate, 2);
        pageLines = sys.intv("page-lines");
        report1();
        sys.setNum("p-flag-a", 0);
    }

    private static BigDecimal pct(BigDecimal x, BigDecimal y, BigDecimal[] work) {
        if (y.signum() != 0) work[0] = x.divide(y, 4, RoundingMode.DOWN).abs().remainder(bd("10000"));
        return work[0].movePointRight(2);
    }

    private void report1() {
        Rec val = Layout.of("copybooks/fdval.cob", "value-record").newRec();
        CobFile valueFile = CobFile.indexed(ctx.store, ctx.path("value.dat"), val, "va-code");
        if (!valueFile.open(Mode.INPUT).equals("00")) { valueFile.close(); return; }
        prt = new Printer("prt-1");
        a = 0;
        headings();
        BigDecimal[] work = {BigDecimal.ZERO};
        while (true) {
            String st = valueFile.readNext(val);
            if (st.equals("10")) break;
            if (!st.equals("00")) {
                display(23, 1, "PL150 PE 130-01 - ");
                display(24, 40, "PL003 Hit Return To Continue");
                accept(23, 60, 1);
                break;
            }
            if (!val.str("va-system").equals("P")) continue;
            boolean second = !val.str("va-second").equals(" ");
            if (second && val.num("va-v-this").signum() == 0 && val.num("va-v-year").signum() == 0) continue;
            String type;
            if (!second && val.longv("va-gl") == 0) {
                type = "Group";
                headings();
                prt.after("", 1);
                lineCnt++;
            } else type = " Detail";
            BigDecimal pt = pct(val.num("va-t-this"), val.num("va-t-last"), work);
            BigDecimal pa = pct(val.num("va-v-this"), val.num("va-v-last"), work);
            prt.after("   " + pad(val.str("va-group"), 6) + pad(type, 9) + pad(val.str("va-desc"), 28)
                    + Pl095.bwz(val.longv("va-t-this"), "zzzz9", 5) + "     " + Pl095.bwz(val.longv("va-t-last"), "zzzz9", 5)
                    + "      " + Pl095.bwz(val.longv("va-t-year"), "zzzz9", 5) + "    "
                    + Pl095.bwz(val.num("va-v-this"), "z(7)9.99cr", 13) + Pl095.bwz(val.num("va-v-last"), "z(8)9.99cr", 14)
                    + Pl095.bwz(val.num("va-v-year"), "z(8)9.99cr", 14)
                    + Pl095.bwz(pt.setScale(2, RoundingMode.DOWN).remainder(bd("100000")), "z(4)9.99", 8)
                    + Pl095.bwz(pa.setScale(2, RoundingMode.DOWN).remainder(bd("10000")), "zzz9.99", 7), 1);
            lineCnt++;
            if (lineCnt > pageLines) headings();
        }
        valueFile.close();
        prt.close();
        spoolPrt1();
    }

    private void headings() {
        if (lineCnt < pageLines - 8) return;
        a++;
        lineCnt = 0;
        String l1 = pad(PROG_NAME, 49) + pad("              Purchase  Analysis", 75) + " Page " + Num.edit(a % 100, "z9");
        String l2 = pad(sys.str("usera"), 49) + pad("", 73) + wsDate;
        if (a != 1) {
            prt.afterPage(l1);
            prt.after(l2, 1);
            prt.after("", 1);
        } else {
            prt.before(l1, 1);
            prt.before(l2, 1);
        }
        prt.after("Analysis  Type    <-----Description------>   <-------Transactions------->   <----------------A"
                + "mount----------------->  % Period Mvmt", 1);
        prt.after(pad("  Code", 45)
                + "Current   Previous   Y. to D      Current      Previous     Year to Date  Trans. Amount", 1);
        prt.after("", 1);
    }
}
