package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;

/** gl060.cbl: バッチ状況報告（画面表示・印刷）。 */
public class Gl060 extends GlProgram {
    static final String PROG_NAME = "gl060 (3.00.04)";
    private static final String LINE4 = pad("Ledger  Batch  Status       Last", 48) + "---------Batch Controls---------";
    private static final String LINE5 = pad("------  -----  ------     Activity", 48) + "Items  ---Gross---- -----VAT----";

    private Rec bat; private CobFile batchFile; private Printer print;
    private int a, y, lineCnt, lin;
    private String wsDate = sp(10), l3Date = sp(10), l6Ledger = sp(8), l6Status = sp(11);

    @Override
    public void run(Object... args) {
        init();
        bat = GlCommon.batchRec(); batchFile = GlCommon.batchFile(ctx, bat);
        bat.load(new byte[bat.bytes().length]);
        print = new Printer("prt-1", 132);
        while (true) {
            menuInput();
            show(3, 1, sys.str("usera"), 2);
            display(8, 1, "Select one of the following by number :- [ ]");
            display(10, 1, "(1)  Display Batch Report");
            display(12, 1, "(2)  Print Batch Report");
            display(15, 1, "(9)  Exit to system menu");
            a = (int) acceptNum(8, 43, 1, 0);
            if (a == 9) return;
            if (a == 1 || a == 2) gl060a();
        }
    }

    private void menuInput() {
        wsDate = wsDate();
        l3Date = wsDate;
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 32, "Batch Status Report");
        show(1, 71, wsDate, 2);
    }

    private static String money(BigDecimal v, boolean blankZero) {
        if (blankZero && v.signum() == 0) return sp(12);
        return Num.edit(v, "zzzzzzzz9.99");
    }

    private void gl060a() {
        menuInput();
        String cycle = Num.edit(sys.intv("scycle"), "z9");
        display(3, 1, "cycle - ");
        show(3, 9, cycle, 2);
        if (a == 2) { print.open(); headings(); }
        else { show(5, 1, LINE4, 2); show(6, 1, LINE5, 2); }
        lin = 7;
        batchFile.open(CobFile.Mode.INPUT);
        loop:
        while (true) {
            String st = batchFile.readNext(bat);
            if (st.equals("10")) break;
            if (!st.equals("00")) runaway();
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            int ledger = bat.intv("ledger");
            if (ledger == 1) l6Ledger = pad(" G/L", 8);
            if (ledger == 2) l6Ledger = pad(" P/L", 8);
            if (ledger == 3) l6Ledger = pad(" S/L", 8);
            for (String f : new String[]{"stored", "posted", "proofed", "entered"}) {
                long bin = bat.num(f).longValue();
                if (bin != 0) {
                    if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
                    wsDate = GlCommon.ukToForm(sys, Maps04.toDate(bin));
                    break;
                }
            }
            int bs = bat.intv("batch-status"), cs = bat.intv("cleared-status");
            if (bs == 0) l6Status = pad("Open", 11);
            if (bs == 1 && cs == 0) l6Status = pad("Waiting", 11);
            if (bs == 1 && cs == 1) l6Status = pad("Processed", 11);
            if (bs == 1 && cs == 2) l6Status = pad("Archived", 11);
            String items = Num.edit(bat.intv("items"), "z9") + sp(4);
            String line6 = l6Ledger + Num.edit(bat.intv("batch-nos"), "zzzz9") + "  " + l6Status + pad(wsDate, 14) + "Header   " + items
                    + money(bat.num("input-gross"), false) + " " + money(bat.num("input-vat"), true);
            String line7 = sp(40) + "Actual   " + items + money(bat.num("actual-gross"), false) + " " + money(bat.num("actual-vat"), true);
            if (a == 2) {
                print.after(line6, 2);
                lineCnt += 2;
                if (lineCnt > sys.intv("page-lines")) headings();
                print.after(line7, 1);
                lineCnt++;
            } else {
                show(lin + 1, 1, line6, 2);
                show(lin + 2, 1, line7, 2);
                lin += 3;
            }
            if (lin < 21) continue;
            display(22, 1, "Enter <N> for next screen or <X> to exit :- [ ]");
            while (true) {
                String r = upper(pad(accept(22, 46, 1), 1));
                if (r.equals("X")) break loop;
                if (r.equals("N")) { lin = 7; eraseEos(7, 1); continue loop; }
            }
        }
        if (a == 2) {
            print.close();
            ctx.spool("prt-1", printReportP());
        } else {
            display(22, 1, "Type return to exit.");
            accept(22, 22, 1);
        }
        batchFile.close();
    }

    private void headings() {
        y++;
        String l1 = pad(PROG_NAME, 31) + pad("Batch Status Report", 41) + "Page -" + Num.edit(y, "z9");
        String l3 = "Cycle - " + Num.edit(sys.intv("scycle"), "z9") + sp(60) + l3Date;
        if (y != 1) {
            print.afterPage(l1);
            print.after(l3, 1);
            print.after("", 1);
        } else {
            print.before(l1, 1);
            print.before(l3, 1);
        }
        print.after(LINE4, 1);
        print.after(LINE5, 1);
        print.after("", 1);
        lineCnt = 6;
    }
}
