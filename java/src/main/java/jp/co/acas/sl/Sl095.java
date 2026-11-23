package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl095.cbl: 入金・振替の検証帳票。 */
public class Sl095 extends SlProgram {
    static final String PROG_NAME = "SL095 (3.01.07)";
    private static final BigDecimal Z = BigDecimal.ZERO;

    private Rec sys;
    private Prt print;
    private int lineCnt, pageNos, pageLines;
    // line-6
    private String bNos, slash = "/", bItem, trans, date, ac, name, value, approp, dedn, invoice, iDate, iApprop, iBalance;

    private static String bwz(BigDecimal v, String pic, int width) {
        return v.signum() == 0 ? " ".repeat(width) : pad(Num.edit(v, pic), width);
    }
    private String line6() {
        return bNos + slash + bItem + trans + date + ac + name + value + approp + dedn + invoice + iDate + iApprop + iBalance;
    }
    private void clearHead() {
        bNos = " ".repeat(5); bItem = " ".repeat(4); dedn = " ".repeat(9); value = " ".repeat(11); approp = " ".repeat(11);
        date = " ".repeat(11); ac = " ".repeat(8); name = " ".repeat(29); trans = "  ";
    }

    @Override
    public void run(Object... args) {
        sys = sys();
        if (sys.intv("s-flag-p") == 0) return;
        sys.set("oi-3-flag", "Y");
        sys.setNum("s-flag-p", 2);
        eraseEos(1, 1);
        show(1, 1, PROG_NAME);
        display(1, 32, "Payment Proof Report");
        show(2, 71, fromUk(toDay()), 2);
        display(12, 1, "Printing..... Please Wait");
        report1();
    }

    private void report1() {
        CobFile sFile = CobFile.sequential(ctx.store, ctx.path(F_OISORT));
        sFile.open(CobFile.Mode.INPUT);
        if (!sFile.status.equals("00")) { sFile.close(); return; }
        Rec sales = salesRec(), oi = oiHeader(), in = oi3Rec();
        CobFile salesFile = salesFile(sales);
        salesFile.open(CobFile.Mode.INPUT);
        pageLines = sys.intv("page-lines");
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        clearHead();
        invoice = " ".repeat(9); iDate = " ".repeat(10); iApprop = " ".repeat(9); iBalance = " ".repeat(13);
        BigDecimal tPay = Z, tApprop = Z, tDeducts = Z, jPay = Z, jApprop = Z, jDeducts = Z, savApprop = Z;
        String saveCustomer = " ".repeat(7);
        headings();
        while (sFile.readNext(in).equals("00")) {
            move(in, oi);
            int type = oi.intv("oi-type");
            if (type == 2) {
                // process-invoice
                if (oi.num("oi-paid").signum() == 0) continue;
                if (!oi.str("oi-customer").equals(saveCustomer)) continue;
                invoice = pad(Num.edit(oi.longv("oi-invoice"), "z(7)9"), 9);
                if (oi.longv("oi-invoice") == 0) invoice = " ".repeat(9);
                iDate = pad(binToDate(oi.longv("oi-date")), 10);
                slash = " ";
                iApprop = bwz((oi.num("oi-paid").compareTo(savApprop) > 0 ? savApprop : oi.num("oi-paid")).abs(), "z(5)9.99", 9);
                BigDecimal work1 = Z;
                for (String f : new String[] {"oi-net", "oi-extra", "oi-vat", "oi-discount", "oi-carriage", "oi-e-vat", "oi-c-vat", "oi-deduct-amt", "oi-deduct-vat"})
                    work1 = work1.add(oi.num(f));
                work1 = work1.abs().remainder(new BigDecimal(1000000));
                iBalance = bwz(work1.subtract(oi.num("oi-paid")), "z(7)9.99cr", 13);
                print.after(line6(), 1);
                lineCnt++;
                if (lineCnt > pageLines) headings();
                continue;
            }
            if (type < 5 || type > 6 || oi.intv("oi-status") != 0) continue;
            saveCustomer = oi.str("oi-customer");
            bNos = oi.longv("oi-b-nos") == 0 ? " ".repeat(5) : Num.edit(oi.longv("oi-b-nos"), "z(4)9");
            slash = "/";
            bItem = oi.longv("oi-b-item") == 0 ? " ".repeat(4) : z(oi.longv("oi-b-item"), 3) + " ";
            trans = type == 6 ? "J " : "P ";
            date = pad(binToDate(oi.longv("oi-date")), 11);
            ac = pad(oi.str("oi-customer"), 8);
            sales.set("sales-key", oi.str("oi-customer"));
            salesFile.read(sales);
            name = pad(invalidKey(salesFile) ? "!! Customer Unknown" : sales.str("sales-name"), 29);
            BigDecimal paid = oi.num("oi-paid"), ap = oi.num("oi-net"), ded = oi.num("oi-deduct-amt");
            if (type == 6) { jPay = jPay.add(paid); jApprop = jApprop.add(ap); jDeducts = jDeducts.add(ded); }
            else { tPay = tPay.add(paid); tApprop = tApprop.add(ap); tDeducts = tDeducts.add(ded); }
            value = bwz(paid.abs(), "z(5)9.99", 11);
            approp = bwz(ap.abs(), "z(5)9.99", 11);
            savApprop = ap;
            dedn = bwz(ded.abs(), "z(3)9.99", 9);
            invoice = " ".repeat(9); iApprop = " ".repeat(9); iBalance = " ".repeat(13); iDate = " ".repeat(10);
            if (lineCnt > pageLines) headings();
            print.after(line6(), 2);
            lineCnt += 2;
            clearHead();
        }
        if (lineCnt > pageLines - 8) headings();
        totals("Payment", tPay, tApprop, tDeducts, 4);
        totals("Journal", jPay, jApprop, jDeducts, 2);
        sFile.close(); salesFile.close(); print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private void totals(String tit, BigDecimal pay, BigDecimal approp, BigDecimal deducts, int skip) {
        print.after(" ".repeat(30) + pad(tit, 7) + " Totals", skip);
        print.after(" ".repeat(30) + "**************", 1);
        print.after(line9("Payments", pay), 3);
        print.after(line9("Appropriations", approp), 1);
        print.after(line9("Unapplied Cash", pay.subtract(approp)), 1);
        print.after(line9("Deductions Taken", deducts), 2);
    }

    private String line9(String desc, BigDecimal v) {
        return " ".repeat(23) + pad(desc, 17) + Num.edit(v.abs(), "z(6)9.99");
    }

    private void headings() {
        pageNos++;
        String l1 = pad(PROG_NAME, 48) + pad("Payment And Journal Proof Report", 76) + "Page " + Num.edit(pageNos, "zz9");
        String l2 = pad(sys.str("usera"), 48) + " ".repeat(74) + pad(fromUk(toDay()), 10);
        if (pageNos != 1) {
            print.afterPage(l1);
            print.after(l2, 1);
            print.after("", 1);
        } else {
            print.before(l1, 1);
            print.before(l2, 1);
        }
        print.after("  Batch  Tp  Pay Date  <-------------Customer------------->" + "  Value    Approp.    Ded'n    <--------Payment Appropriation--------->", 2);
        print.after(" ".repeat(22) + pad(" A/C               Name", 70) + "Invoice   Date      Approp.     Balance ", 1);
        lineCnt = 6;
    }
}
