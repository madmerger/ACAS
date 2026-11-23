package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl050.cbl: 売上取引（請求書）検証帳票。 */
public class Sl050 extends SlProgram {
    static final String PROG_NAME = "SL050 (3.01.10)";
    static final String SL120 = "SL120 No Transactions to proof! ...Press return for menu.";
    private static final String M = "z(6)9.99cr";
    private static final String[] LIT = {"Receipts", "Invoices", "Credit Notes"};

    private Rec sys, sales, inv, sih, bodies;
    private CobFile invFile;
    private Prt print;
    private int j, lineCnt, a, pageLines;
    private boolean firstTime, atEnd, salesMissing;
    // total-group (1..3): ded gds car net vat grs dis cvat(1..5)
    private final BigDecimal[][] tot = new BigDecimal[3][12];
    private static final int DED = 0, GDS = 1, CAR = 2, NET = 3, VAT = 4, GRS = 5, DIS = 6, CVAT = 7;
    private String lbA = "", lcA = "", ldA = "", leA = "";
    private BigDecimal lbAmt, lcAmt, ldAmt, leAmt;
    private int ldVat, leVat;

    private static String m(BigDecimal v) { return Num.edit(v, M); }
    private void add(int f, BigDecimal... vs) { for (BigDecimal v : vs) tot[a - 1][f] = tot[a - 1][f].add(v); }

    @Override
    public void run(Object... args) {
        sys = sys();
        for (BigDecimal[] t : tot) java.util.Arrays.fill(t, BigDecimal.ZERO);
        clearScreen();
        show(1, 1, PROG_NAME);
        display(1, 32, "Invoice Proof Report");
        show(1, 71, fromUk(toDay()), 2);
        if (sys.intv("file-status", 16) == 0) {
            display(5, 1, SL120, 4);
            term().accept(5, 63, 1, " ", 0, 6);
            return;
        }
        pageLines = sys.intv("page-lines");
        sales = salesRec();
        CobFile salesFile = salesFile(sales);
        inv = fdRec("sales/fdinv.cob", "invoice-record");
        sih = Layout.of("sales/wsinv.cob", "sinvoice-header").newRec();
        bodies = Layout.of("sales/wsinv.cob", "sInvoice-Bodies").newRec();
        int lineSize = bodies.bytes().length / 40;
        invFile = CobFile.indexed(ctx.store, ctx.path(F_INVOICE), inv, "invoice-key");
        print = new Prt(ctx, "prt-1");
        salesFile.open(CobFile.Mode.INPUT);
        print.openOutput();
        j = 0;
        headings1();
        invFile.open(CobFile.Mode.INPUT);
        while (true) {
            invFile.readNext(inv);
            if (!invFile.status.equals("00")) break;
            move(inv, sih);
            if (sih.intv("sih-test") != 0) continue;
            if (sih.str("sih-status").equalsIgnoreCase("z")) continue;
            int type = sih.intv("sih-type");
            if (type == 4) continue;
            sales.set("sales-key", sih.str("sih-customer"));
            salesFile.read(sales);
            String name;
            if (invalidKey(salesFile)) { name = "!! Customer Unknown"; salesMissing = true; }
            else name = sales.str("sales-name");
            BigDecimal sg = BigDecimal.valueOf(type == 3 ? -1 : 1);
            BigDecimal net = sih.num("sih-net").multiply(sg), extra = sih.num("sih-extra").multiply(sg),
                carr = sih.num("sih-carriage").multiply(sg), vat = sih.num("sih-vat").multiply(sg),
                cVat = sih.num("sih-c-vat").multiply(sg), eVat = sih.num("sih-e-vat").multiply(sg),
                disc = sih.num("sih-discount").multiply(sg), dAmt = sih.num("sih-deduct-amt").multiply(sg),
                dVat = sih.num("sih-deduct-vat").multiply(sg);
            lbA = dAmt.signum() == 0 ? "" : "Late Charge "; lbAmt = dAmt;
            lcA = disc.signum() == 0 ? "" : "Discount    "; lcAmt = disc;
            ldA = carr.signum() == 0 ? "" : "Carriage    "; ldAmt = carr; ldVat = carr.signum() != 0 && cVat.signum() != 0 ? 1 : 0;
            leA = extra.signum() == 0 ? "" : sys.str("extra-desc"); leAmt = extra; leVat = extra.signum() != 0 && eVat.signum() != 0 ? 1 : 0;
            String typeName;
            if (type == 1) { typeName = "Receipt"; a = 1; }
            else if (type == 2) { typeName = "Invoice"; a = 2; }
            else { typeName = "Cr. Note"; a = 3; }
            add(CVAT, cVat, eVat);
            BigDecimal tv = vat.add(cVat).add(eVat).add(dVat), tn = net.add(extra).add(carr).add(disc).add(dAmt);
            add(GDS, net); add(DIS, disc, extra); add(DED, dAmt); add(CAR, carr); add(VAT, tv); add(NET, tn); add(GRS, tv, tn);
            if (lineCnt > pageLines - 2) headings1();
            print.after(Num.edit(sih.longv("sih-invoice"), "z(7)9") + " " + pad(binToDate(sih.longv("sih-date")), 11)
                + pad(sih.str("sih-customer"), 8) + pad(name, 25) + " ".repeat(5) + pad(typeName, 14) + m(net) + " ".repeat(13)
                + m(tn) + m(tv) + m(tv.add(tn)), 2);
            lineCnt += 2;
            firstTime = true; atEnd = false;
            for (int n = sih.intv("sih-lines"); n > 0; n--) {
                // analysis-print
                if (atEnd) break;
                invFile.readNext(inv);
                if (!invFile.status.equals("00")) { atEnd = true; break; }
                System.arraycopy(inv.bytes(), 0, bodies.bytes(), 0, lineSize);
                if (bodies.str("sil-product", 1).startsWith("/")) continue;
                BigDecimal lNet = bodies.num("sil-net", 1).multiply(sg), lVat = bodies.num("sil-vat", 1).multiply(sg);
                int k = bodies.intv("sil-vat-code", 1);
                if (k > 0 && k <= 5) add(CVAT + k - 1, lVat);
                print.after(" ".repeat(46) + pad(firstTime ? "Analysis" : "", 12) + pad(bodies.str("sil-pa", 1), 6)
                    + pad(firstTime ? "Value" : "", 8) + m(lNet) + "  " + pad(firstTime ? "Vat Code" : "", 9) + k, 1);
                firstTime = false;
                lineCnt++;
                if (lineCnt > pageLines) headings1();
            }
            // extra-analysis
            if (lineCnt > pageLines - 4) headings1();
            if (!lbA.isBlank()) { print.after(" ".repeat(46) + pad(lbA, 26) + m(lbAmt), 1); lineCnt++; lbA = ""; }
            if (!lcA.isBlank()) { print.after(" ".repeat(46) + pad(lcA, 26) + m(lcAmt) + " ".repeat(11) + "0", 1); lineCnt++; lcA = ""; }
            if (!ldA.isBlank()) { print.after(" ".repeat(46) + pad(ldA, 26) + m(ldAmt) + " ".repeat(11) + ldVat, 1); lineCnt++; ldA = ""; }
            if (!leA.isBlank()) { print.after(" ".repeat(46) + pad(leA, 12) + " ".repeat(14) + m(leAmt) + " ".repeat(11) + leVat, 1); lineCnt++; leA = ""; }
        }
        salesFile.close(); invFile.close();
        if (lineCnt < pageLines - 16) print.after("", 3); else main12();
        print.after(" ".repeat(36) + "Goods    Discount  Prompt Pay    Carriage         Net         Vat       Gross", 2);
        print.after("", 1);
        for (a = 1; a <= 3; a++) {
            BigDecimal[] t = tot[a - 1];
            print.after(" ".repeat(7) + "Total " + pad(LIT[a - 1], 18) + m(t[GDS]) + m(t[DIS]) + m(t[DED]) + m(t[CAR]) + m(t[NET]) + m(t[VAT]) + m(t[GRS]), 1);
        }
        if (salesMissing) print.after("Warning Record/s Missing In Sales File", 2);
        print.after("V.A.T. Reconciliation       Receipts       Invoices   Credit Notes", 2);
        print.after("", 1);
        int n = sys.num("vat-rate", 4).signum() != 0 || sys.num("vat-rate", 5).signum() != 0 ? 5 : 3;
        for (int i = 1; i <= n; i++)
            print.after("Vat Code " + i + "   " + Num.edit(sys.num("vat-rate", i), "z9.99") + pad("%", 5)
                + Num.edit(tot[0][CVAT + i - 1], "z(7)9.99cr") + Num.edit(tot[1][CVAT + i - 1], "z(9)9.99cr")
                + Num.edit(tot[2][CVAT + i - 1], "z(9)9.99cr"), 1);
        print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private void main12() {
        j++;
        String l1 = pad(PROG_NAME, 49) + pad("Unapplied Sales Transaction Report", 75) + "Page " + Num.edit(j, "zz9");
        if (j != 1) print.afterPage(l1); else print.after(l1, 1);
        print.after(pad(sys.str("usera"), 49) + " ".repeat(73) + fromUk(toDay()), 1);
    }

    private void headings1() {
        main12();
        print.after(pad("  Number ---Date--- <------------Customer------------>  --Type--", 75)
            + "Goods                 <---Net-->  <---Vat-->  <--Gross->", 2);
        print.after(" ", 1);
        lineCnt = 5;
    }
}
