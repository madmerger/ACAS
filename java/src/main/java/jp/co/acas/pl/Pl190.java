package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl190.cbl: 仕入先ファイルダンプ。 */
public class Pl190 extends PlSelect {
    static final String PROG_NAME = "PL190 (3.01.04)";
    private Printer prt;
    private int a;
    private String l3;

    private static String v2(BigDecimal v) { return Num.edit(v.abs(), "z(7)9.99") + "   "; }
    private static String v2(long v) { return v2(BigDecimal.valueOf(v)); }
    private static String v3(BigDecimal v) { return Num.edit(v, "z(7)9.99cr"); }

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        purchaseFile.open(Mode.INPUT);
        reportSelection(PROG_NAME, "Suppler File", false);
        String supplierIn = pad(custIn, 7);
        l3 = pad(sys.str("usera"), 40) + "Report On : "
                + reportHeading(allBlank() && supplierIn.isBlank(), supplierIn, false, " Days Overdue") + fromUk(toDay());
        prt = new Printer("prt-1");
        a = 0;
        int z = 0, recCnt = 0;
        headings();
        boolean sel = !supplierIn.isBlank();
        if (sel) {
            purch.set("purch-key", supplierIn);
            purchaseFile.read(purch);
            supplierIn = supplierIn.replace(' ', '\u00ff');
        }
        while (purchaseFile.readNext(purch).equals("00")) {
            boolean live = purch.intv("purch-status") == 1;
            if (statusIn.equals("L") && !live || statusIn.equals("D") && live) continue;
            String key = purch.str("purch-key");
            if (sel) {
                if (key.compareTo(supplierIn) > 0) break;
                if (!key.substring(0, 6).equals(supplierIn.substring(0, 6))) continue;
            }
            if (!numericTests(purch, false)) continue;
            line(2, "Purch-Key", key, "Purch-Credit", v2(purch.longv("purch-credit")), "Purch-Current",
                    v3(purch.num("purch-current").subtract(purch.num("purch-unapplied"))));
            line(1, "Purch-Name", purch.str("purch-name"), "Purch-Discount", v2(purch.num("purch-discount")), "Purch-Last",
                    v3(purch.num("purch-last")));
            line(1, "Purch-Addr1", purch.str("purch-addr1"), "Purch-Notes", Num.edit(purch.longv("purch-notes-tag"), "z(6)99"),
                    "Turnover-Q1", v3(purch.num("turnover-q1")));
            line(1, "Purch-Addr2", purch.str("purch-addr2"), "Purch-Average", v2(purch.longv("purch-average")), "Turnover-Q2",
                    v3(purch.num("turnover-q2")));
            line(1, "Purch-Phone", purch.str("purch-phone"), "Purch-Limit", v2(purch.longv("purch-limit")), "Turnover-Q3",
                    v3(purch.num("turnover-q3")));
            line(1, "Purch-Fax", purch.str("purch-fax"), "Purch-Activety", v2(purch.longv("purch-activety")), "Turnover-Q4",
                    v3(purch.num("turnover-q4")));
            line(1, "Purch-Status", live ? "Live" : "Dead", "Purch-Last-Inv", date(purch.longv("purch-last-inv")), "", "");
            line(1, "Purch-Email", purch.str("purch-email"), "Purch-Last-Pay", date(purch.longv("purch-last-pay")), "", "");
            z++; recCnt++;
            if (z > 3) { headings(); z = 0; }
            else prt.after(pad("", 40) + "<" + "-".repeat(50) + ">", 1);
        }
        prt.close();
        purchaseFile.close();
        if (recCnt != 0) spoolPrt1();
    }

    private String date(long bin) { return "   " + (bin == 0 ? "" : binToDate(bin)); }

    private void line(int n, String n1, String v1, String n2, String v2, String n3, String v3) {
        prt.after(pad(n1, 14) + pad(v1, 56) + pad(n2, 16) + pad(v2, 14) + pad(n3, 18) + pad(v3, 13), n);
    }

    private void headings() {
        a++;
        String l1 = pad(PROG_NAME, 57) + pad("Purchase Ledger Dump", 67) + "Page " + Num.edit(a % 1000, "zz9");
        if (a != 1) {
            prt.afterPage(l1);
            prt.after("", 1);
        } else prt.before(l1, 1);
        prt.after(l3, 1);
    }
}
