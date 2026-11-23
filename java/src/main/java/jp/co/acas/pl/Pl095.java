package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl095.cbl: 支払・振替検証帳票。 */
public class Pl095 extends PlBase {
    static final String PROG_NAME = "PL095 (3.01.04)";
    private Printer prt;
    private int page, lineCnt;

    static String bwz(BigDecimal v, String pic, int width) {
        return v.signum() == 0 ? " ".repeat(width) : pad(Num.edit(v, pic), width);
    }
    static String bwz(long v, String pic, int width) { return bwz(BigDecimal.valueOf(v), pic, width); }

    @Override
    public void run(Object... args) {
        init();
        if (sys.intv("p-flag-p") == 0) return;
        sys.set("oi-5-flag", "Y");
        sys.setNum("p-flag-p", 2);
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 32, "Payment Proof Report");
        show(1, 71, fromUk(toDay()), 2);
        display(12, 1, "Printing..... Please Wait");
        report1();
    }

    private void report1() {
        CobFile ois = CobFile.sequential(ctx.store, ctx.path("poisort.wrk"));
        if (!ois.open(Mode.INPUT).equals("00")) { ois.close(); return; }
        Rec purch = purchRec(), oi = oiRec();
        CobFile purchaseFile = purchaseFile(purch);
        purchaseFile.open(Mode.INPUT);
        prt = new Printer("prt-1");
        int pageLines = sys.intv("page-lines");
        headings();
        BigDecimal[] t = {BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO}, j = {BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO};
        String saveCustomer = "";
        BigDecimal savApprop = BigDecimal.ZERO;
        while (ois.readNext(oi).equals("00")) {
            int type = oi.intv("oi-type");
            if (type == 2) {
                if (oi.num("oi-paid").signum() == 0) continue;
                if (!oi.str("oi-supplier").equals(saveCustomer)) continue;
                BigDecimal ia = oi.num("oi-paid").compareTo(savApprop) > 0 ? savApprop : oi.num("oi-paid");
                BigDecimal work1 = oi.num("oi-net").add(oi.num("oi-vat")).add(oi.num("oi-carriage")).add(oi.num("oi-c-vat"));
                work1 = new BigDecimal(work1.abs().toPlainString()).remainder(new BigDecimal("1000000"));
                prt.after(pad("", 77) + bwz(oi.longv("oi-invoice"), "z(7)9", 10) + pad(binToDate(oi.longv("oi-date")), 10)
                        + bwz(ia, "z(5)9.99", 9) + bwz(work1.subtract(oi.num("oi-paid")), "z(7)9.99cr", 13), 1);
                lineCnt++;
                if (lineCnt > pageLines) headings();
                continue;
            }
            if (type < 5 || type > 6 || oi.intv("oi-status") != 0) continue;
            saveCustomer = oi.str("oi-supplier");
            purch.set("purch-key", saveCustomer);
            String name = purchaseFile.read(purch).equals("00") ? purch.str("purch-name") : "Supplier Unknown";
            BigDecimal[] a = type == 6 ? j : t;
            a[0] = a[0].add(oi.num("oi-paid"));
            a[1] = a[1].add(oi.num("oi-approp"));
            a[2] = a[2].add(oi.num("oi-deduct-amt"));
            savApprop = oi.num("oi-approp");
            if (lineCnt > pageLines - 2) headings();
            prt.after(bwz(oi.longv("oi-b-nos"), "z(4)9", 5) + "/" + bwz(oi.longv("oi-b-item"), "999", 4)
                    + (type == 6 ? "J " : "P ") + pad(binToDate(oi.longv("oi-date")), 11) + pad(saveCustomer, 8)
                    + pad(name, 29)
                    + bwz(oi.num("oi-paid"), "z(5)9.99", 11) + bwz(oi.num("oi-approp"), "z(5)9.99", 11)
                    + bwz(oi.num("oi-deduct-amt"), "z(3)9.99", 8), 2);
            lineCnt += 2;
        }
        if (lineCnt > pageLines - 22) headings();
        totals("Payment", t);
        totals("Journal", j);
        ois.close(); purchaseFile.close(); prt.close();
        spoolPrt1();
    }


    private void totals(String tit, BigDecimal[] v) {
        prt.after(pad("", 30) + pad(tit, 7) + " Totals", 3);
        prt.after(pad("", 30) + "**************", 1);
        prt.after(l9("Payments", v[0]), 3);
        prt.after(l9("Appropriations", v[1]), 1);
        prt.after(l9("Unapplied Cash", v[0].subtract(v[1])), 1);
        prt.after(l9("Deductions Taken", v[2]), 2);
    }

    private static String l9(String desc, BigDecimal v) {
        return pad("", 23) + pad(desc, 17) + Num.edit(v.abs(), "z(6)9.99");
    }

    private void headings() {
        page++;
        String line1 = pad(PROG_NAME, 48) + pad("Payment and Journal Proof Report", 76) + "Page  " + Num.edit(page, "z9");
        String line2 = pad(sys.str("usera"), 20) + pad("", 102) + fromUk(toDay());
        if (page != 1) {
            prt.afterPage(line1);
            prt.after(line2, 1);
            prt.after("", 1);
        } else {
            prt.before(line1, 1);
            prt.before(line2, 1);
        }
        prt.after("  Batch  TP Pay Date <-------------Supplier------------->"
                + "     " + "  Value    Approp.  Ded'N    <--------Payment Appropriation--------->", 1);
        prt.after(pad("", 22) + pad("A/C               Name", 70) + "Folio     Date      Approp.     Balance ", 1);
        lineCnt = 5;
    }
}
