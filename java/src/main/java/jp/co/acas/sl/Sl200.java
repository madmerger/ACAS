package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

/** sl200.cbl: 請求書削除一覧。 */
public class Sl200 extends SlProgram {
    static final String PROG_NAME = "SL200 (3.01.04)";
    private Prt print;
    private int lineCnt, pageCnt;

    @Override
    public void run(Object... args) {
        Rec sys = sys();
        Rec dnos = fdRec("sales/fddnos.cob", "del-inv-nos-record");
        CobFile dnosFile = CobFile.sequential(ctx.store, ctx.path(F_DELINV));
        print = new Prt(ctx, "prt-1").variable(132);
        print.openOutput();
        headings1();
        dnosFile.open(CobFile.Mode.INPUT);
        if (!dnosFile.status.equals("00")) print.after("       None to report", 2);
        else {
            while (true) {
                dnosFile.readNext(dnos);
                if (!dnosFile.status.equals("00")) break;
                print.after("   " + Num.edit(dnos.longv("del-inv-nos"), "z(9)9") + " ".repeat(5) + pad(binToDate(dnos.longv("del-inv-dat")), 10)
                    + "   " + dnos.str("del-inv-cus"), 1);
                lineCnt++;
                if (lineCnt > 70) headings1();
            }
        }
        dnosFile.close();
        print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), false);
    }

    private void headings1() {
        pageCnt = (pageCnt + 1) % 100;
        String head = PROG_NAME + " ".repeat(14) + "Invoice Deletion Report" + " ".repeat(9) + pad(fromUk(toDay()), 12) + "Page "
            + Num.edit(pageCnt, "z9");
        lineCnt = 4;
        if (pageCnt != 1) print.afterPage(head); else print.after(head, 1);
        print.after("   Invoice No       Date         Cust No", 2);
        print.after("", 1);
    }
}
