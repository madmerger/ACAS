package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl170.cbl: 顧客ファイルダンプ帳票。 */
public class Sl170 extends CustReport {
    static final String PROG_NAME = "SL170 (3.01.07)";

    private Rec sales;
    private Prt print;
    private int a, z;
    private byte recCnt;
    private String l3 = "", name3 = "", value3 = "";

    @Override
    public void run(Object... args) {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        upperCase = false;
        sales = salesRec();
        CobFile salesFile = salesFile(sales);
        salesFile.open(CobFile.Mode.INPUT);
        reportSelection(PROG_NAME, false);
        customerIn = pad(custIn, 7);
        l3 = pad(sys.str("usera"), 40) + "Report On : " + pad(reportHeadingSetup(false, " Days Overdue"), 70) + pad(fromUk(toDay()), 10);
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        a = 0; z = 0;
        headings1();
        boolean sel = !customerIn.isBlank();
        if (sel) {
            sales.set("sales-key", customerIn);
            salesFile.read(sales);
            if (invalidKey(salesFile)) a = 1;
            customerIn = customerIn.replace(' ', 'Z');
        }
        String statusIn = this.statusIn;
        read:
        while (salesFile.readNext(sales).equals("00")) {
            int status = sales.intv("sales-status");
            if (statusIn.equals("L") && status == 0) continue;
            if (statusIn.equals("D") && status == 1) continue;
            String key = pad(sales.str("sales-key"), 7);
            if (sel) {
                if (key.compareTo(customerIn) > 0) break;
                for (int y = 0; y < 6; y++)
                    if (customerIn.charAt(y) != ' ' && customerIn.charAt(y) != key.charAt(y)) continue read;
            }
            if (!matchNumeric(sales, false)) continue;
            listing();
        }
        print.close(); salesFile.close();
        if (recCnt != 0) spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private void headings1() {
        a++;
        String l1 = pad(PROG_NAME, 57) + pad("Sales Ledger Dump", 67) + "Page " + Num.edit(a, "zz9");
        if (a != 1) { print.afterPage(l1); print.after("", 1); }
        else print.before(l1, 1);
        print.after(l3, 2);
    }

    private static String v2(BigDecimal v) { return Num.edit(v.abs(), "z(7)9.99") + "   "; }
    private static String v2(long v) { return v2(BigDecimal.valueOf(v)); }
    private static String v3(BigDecimal v) { return Num.edit(v, "z(7)9.99cr"); }

    private void line4(String name1, String value1, String name2, String value2, String n3, String val3, int skip) {
        name3 = pad(n3, 18); value3 = pad(val3, 13);
        print.after(pad(name1, 14) + pad(value1, 56) + pad(name2, 16) + pad(value2, 14) + name3 + value3, skip);
    }

    private String date(long bin) { return bin == 0 ? " ".repeat(14) : "   " + pad(binToDate(bin), 11); }

    private void listing() {
        sales.setNum("sales-current", sales.num("sales-current").subtract(sales.num("sales-unapplied")));
        line4("Sales-Key", sales.str("sales-key"), "Sales-Credit", v2(sales.longv("sales-credit")), "Sales-Current", v3(sales.num("sales-current")), 2);
        line4("Sales-Name", sales.str("sales-name"), "Sales-Discount", v2(sales.num("sales-discount")), "Sales-Last", v3(sales.num("sales-last")), 1);
        line4("Sales-Addr1", sales.str("sales-addr1"), "Sales-Late-Min", v2(sales.longv("sales-late-min")), "Turnover-Q1", v3(sales.num("turnover-q1")), 1);
        line4("Sales-Addr2", sales.str("sales-addr2"), "Sales-Late-Max", v2(sales.longv("sales-late-max")), "Turnover-Q2", v3(sales.num("turnover-q2")), 1);
        line4("Sales-Phone", sales.str("sales-phone"), "Sales-Limit", v2(sales.longv("sales-limit")), "Turnover-Q3", v3(sales.num("turnover-q3")), 1);
        line4("Delivery-Tag", sales.str("delivery-tag"), "Sales-Activety", v2(sales.longv("sales-activety")), "Turnover-Q4", v3(sales.num("turnover-q4")), 1);
        line4("Notes Tag", sales.str("notes-tag"), "", "", name3, value3, 1);
        line4("Sales-Status", sales.intv("sales-status") == 1 ? "Live" : "Dead", "Sales-Last-Inv", date(sales.longv("sales-last-inv")), "", "", 1);
        line4("Sales-Late", sales.intv("sales-late") == 1 ? "Yes" : "No", "Sales-Last-Pay", date(sales.longv("sales-last-pay")), "", "", 1);
        line4("Sales-Dunning", sales.intv("sales-dunning") == 1 ? "Yes" : "No", "Sales-Average", v2(sales.longv("sales-average")), "", "", 1);
        if (!sales.str("sales-email").isBlank()) {
            StringBuilder l = new StringBuilder(" ".repeat(131));
            int p = stringInto(l, 1, "Sales-Email   ");
            p = stringInto(l, p, delimited(pad(sales.str("sales-email"), 30), " "));
            boolean inv = sales.intv("email-invoice") == 1, stm = sales.intv("email-statement") == 1, dun = sales.intv("email-letters") == 1;
            if (inv || stm || dun) {
                p = stringInto(l, p, "  Used by ");
                if (inv) p = stringInto(l, p, "Invoicing. ");
                if (stm) { if (inv) { p -= 2; p = stringInto(l, p, ", Statements. "); } else p = stringInto(l, p, "Statements. "); }
                if (dun) { if (inv || stm) { p -= 2; stringInto(l, p, ", Dunning. "); } else stringInto(l, p, "Dunning. "); }
            }
            print.after(l.toString(), 1);
        }
        z++; recCnt++;
        if (z > 3) { headings1(); z = 0; }
        else print.after(" ".repeat(40) + "<" + "-".repeat(50) + ">", 1);
    }
}
