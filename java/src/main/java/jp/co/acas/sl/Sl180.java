package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl180.cbl: 顧客別売上（回転）帳票。 */
public class Sl180 extends CustReport {
    static final String PROG_NAME = "SL180 (3.01.08)";

    private Prt print;
    private int a, lineCnt, pageLines;

    @Override
    public void run(Object... args) {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        upperCust = false;
        Rec sales = salesRec();
        CobFile salesFile = salesFile(sales);
        salesFile.open(CobFile.Mode.INPUT);
        pageLines = sys.intv("page-lines");
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        reportSelection(PROG_NAME, true);
        customerIn = pad(custIn, 7);
        a = 0;
        pHeadings();
        boolean sel = !customerIn.isBlank();
        if (sel) {
            sales.set("sales-key", customerIn);
            salesFile.start(sales, ">=");
            if (invalidKey(salesFile)) a = 1;
            customerIn = customerIn.replace(' ', 'Z');
        }
        while (salesFile.readNext(sales).equals("00")) {
            int status = sales.intv("sales-status");
            if (statusIn.equals("L") && status == 0) continue;
            if (statusIn.equals("D") && status == 1) continue;
            if (sel && pad(sales.str("sales-key"), 7).compareTo(customerIn) > 0) break;
            if (!matchNumeric(sales, true)) continue;
            listing(sales);
        }
        salesFile.close(); print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private void pHeadings() {
        a++;
        String l1 = pad(PROG_NAME, 51) + pad("Sales Ledger Turnover Report", 73) + "Page " + Num.edit(a, "zz9");
        String l2 = pad(sys.str("usera"), 51) + " ".repeat(71) + pad(fromUk(toDay()), 10);
        if (a != 1) { print.afterPage(l1); print.after(l2, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l2, 1); }
        print.after(" ".repeat(38) + "Credit Terms  <------------- T u r n o v e r ------------> <--S A L E S-->  <--Date Of Last-->", 2);
        print.after(pad("Acct No          Name", 38) + "Days   Limit  Mvmt Average   Qtr 1   Qtr 2   Qtr 3   Qtr 4 Current    Last  Invoice    Payment", 1);
        print.after("", 1);
        lineCnt = 6;
    }

    /** 整数編集項目への転記（小数部切捨て）。 */
    private static String m8(BigDecimal v) { return Num.edit(v.setScale(0, java.math.RoundingMode.DOWN), "-(7)9"); }

    /** shorten-ws-date: 年を 2 桁にする。 */
    private String shortDate(long bin) {
        if (bin == 0) return " ".repeat(10);
        String d = pad(binToDate(bin), 10);
        if (dateForm() == 3) return d.substring(2, 10) + "  ";
        return d.substring(0, 6) + d.substring(8, 10) + "  ";
    }

    private void listing(Rec s) {
        s.setNum("sales-current", s.num("sales-current").subtract(s.num("sales-unapplied")));
        String line = pad(s.str("sales-key"), 8) + pad(s.str("sales-name"), 30) + Num.edit(s.longv("sales-credit"), "zzz9")
            + Num.edit(Math.abs(s.longv("sales-limit")) % 100000000L, "z(7)9") + Num.edit(s.longv("sales-activety"), "-(5)9")
            + Num.edit(s.longv("sales-average"), "-(7)9")
            + m8(s.num("turnover-q1")) + m8(s.num("turnover-q2")) + m8(s.num("turnover-q3")) + m8(s.num("turnover-q4"))
            + m8(s.num("sales-current")) + m8(s.num("sales-last")) + "  " + shortDate(s.longv("sales-last-inv")) + shortDate(s.longv("sales-last-pay")).substring(0, 8);
        print.after(line, 1);
        lineCnt++;
        if (lineCnt > pageLines) pHeadings();
    }
}
