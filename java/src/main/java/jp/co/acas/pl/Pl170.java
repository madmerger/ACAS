package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** pl170.cbl: 仕入先別取引高帳票（Turnover Report）。 */
public class Pl170 extends PlSelect {
    static final String PROG_NAME = "PL170 (3.01.06)";
    private Printer prt;
    private int a, lineCnt;
    private String wsDate;

    private static String e(BigDecimal v, String pic) { return Num.edit(v.setScale(0, RoundingMode.DOWN), pic); }
    private static String e(long v, String pic) { return Num.edit(v, pic); }

    @Override
    public void run(Object... args) {
        init();
        wsDate = fromUk(toDay());
        term().exceptionsEnabled = true; term().escEnabled = true;
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        purchaseFile.open(Mode.INPUT);
        prt = new Printer("prt-1");
        prt.create();
        reportSelection(PROG_NAME, "Supplier File", true);
        String customerIn = pad(custIn, 7);
        a = 0;
        headings();
        if (!customerIn.isBlank()) {
            purch.set("purch-key", customerIn);
            purchaseFile.start(purch, ">=");
            customerIn = customerIn.replace(' ', 'Z');
        }
        int pageLines = sys.intv("page-lines");
        while (purchaseFile.readNext(purch).equals("00")) {
            boolean live = purch.intv("purch-status") == 1;
            if (statusIn.equals("L") && !live || statusIn.equals("D") && live) continue;
            if (!customerIn.isBlank() && purch.str("purch-key").compareTo(customerIn) > 0) break;
            if (!numericTests(purch, true)) continue;
            BigDecimal cur = purch.num("purch-current").subtract(purch.num("purch-unapplied"));
            StringBuilder sb = new StringBuilder(pad(purch.str("purch-key"), 8)).append(pad(purch.str("purch-name"), 30))
                    .append(e(Math.abs(purch.longv("purch-credit")), "zzz9")).append(e(Math.abs(purch.longv("purch-limit")), "z(7)9"))
                    .append(e(purch.longv("purch-activety"), "-(5)9")).append(e(purch.longv("purch-average"), "-(7)9"));
            for (int q = 1; q <= 4; q++) sb.append(e(purch.num("turnover-q" + q), "-(7)9"));
            sb.append(e(cur, "-(7)9")).append(e(purch.num("purch-last"), "-(7)9")).append("  ")
                    .append(shortDate(purch.longv("purch-last-inv"), 10)).append("  ")
                    .append(shortDate(purch.longv("purch-last-pay"), 8));
            prt.after(sb.toString(), 1);
            lineCnt++;
            if (lineCnt > pageLines) headings();
        }
        purchaseFile.close();
        prt.close();
        spoolPrt1();
    }

    /** shorten-ws-date: 年を 2 桁にする。 */
    private String shortDate(long bin, int width) {
        if (bin == 0) return pad("", width);
        String d = binToDate(bin);
        d = sys.intv("date-form") == 3 ? d.substring(2) : d.substring(0, 6) + d.substring(8);
        return pad(d, 10).substring(0, width);
    }

    private void headings() {
        a++;
        String l1 = pad(PROG_NAME, 51) + pad("Purchase Ledger Turnover Report", 73) + "Page " + Num.edit(a % 1000, "zz9");
        String l2 = pad(sys.str("usera"), 51) + pad("", 71) + wsDate;
        if (a != 1) {
            prt.afterPage(l1);
            prt.after(l2, 1);
            prt.after("", 1);
        } else {
            prt.before(l1, 1);
            prt.before(l2, 1);
        }
        prt.after(pad("", 38)
                + "Credit Terms  <------------- T u r n o v e r ------------> <--Purchases-->  <--Date of Last-->", 1);
        prt.after(pad("Acct No          Name", 38)
                + "Days   Limit  Mvmt Average   Qtr 1   Qtr 2   Qtr 3   Qtr 4 Current    Last  Invoice    Payment", 1);
        prt.after("", 1);
        lineCnt = 6;
    }
}
