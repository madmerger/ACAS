package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl050.cbl: 仕入請求書 proof（未転記取引一覧）。 */
public class Pl050 extends PlBase {
    static final String PROG_NAME = "PL050 (3.01.04)";
    static final String[] LIT = {"Receipts", "Invoices", "Credit Notes"};
    static final String CR = "z(6)9.99cr";
    private Printer prt;
    private int page, lineCnt;
    private final BigDecimal[][] tot = new BigDecimal[3][6];   // ded gds car net vat grs
    private final BigDecimal[][] cvat = new BigDecimal[3][3];

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        String printOut = " ";
        for (BigDecimal[] t : tot) java.util.Arrays.fill(t, BigDecimal.ZERO);
        for (BigDecimal[] t : cvat) java.util.Arrays.fill(t, BigDecimal.ZERO);
        String wsDate = fromUk(toDay());
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 32, "Invoice Proof Report");
        show(1, 71, wsDate, 2);
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch), invoiceFile = invoiceFile();
        Rec fd = invHeaderRec();
        Rec ih = Layout.of("purchase/wspinv.cob", "invoice-header").newRec();
        Rec il = Layout.of("purchase/wspinv.cob", "Pinvoice-lines").newRec();
        purchaseFile.open(Mode.INPUT); invoiceFile.open(Mode.INPUT);
        prt = new Printer("prt-1");
        page = 0;
        headings(true);
        boolean purchaseMissing = false;
        int pageLines = sys.intv("page-lines");
        String lbA = "", lbAmount = "", ldA = "", ldAmount = "";
        int ldVat = 0;
        while (invoiceFile.readNext(fd).equals("00")) {
            System.arraycopy(fd.bytes(), 0, ih.bytes(), 0, 100);
            if (ih.intv("ih-test") != 0) continue;
            if (ih.str("ih-status").equalsIgnoreCase("z")) continue;
            purch.set("purch-key", ih.str("ih-supplier"));
            String name;
            if (!purchaseFile.read(purch).equals("00")) { name = "Supplier Unknown"; purchaseMissing = true; }
            else name = purch.str("purch-name");
            int type = ih.intv("ih-type");
            BigDecimal ded = ih.num("ih-deduct-amt");
            if (type == 3) for (String f : new String[]{"ih-net", "ih-carriage", "ih-vat", "ih-c-vat"}) ih.setNum(f, ih.num(f).negate());
            if (type == 2) ded = ded.negate();
            BigDecimal net = ih.num("ih-net"), car = ih.num("ih-carriage"), vat = ih.num("ih-vat"), cv = ih.num("ih-c-vat");
            if (ded.signum() == 0) { lbA = ""; lbAmount = Num.edit(BigDecimal.ZERO, CR); }
            else { lbA = "Prompt Pay  "; lbAmount = Num.edit(ded, CR); }
            if (car.signum() == 0) { ldA = ""; ldAmount = Num.edit(BigDecimal.ZERO, CR); ldVat = 0; }
            else { ldA = "Carriage    "; ldAmount = Num.edit(car, CR); ldVat = cv.signum() == 0 ? 0 : 1; }
            int a = type;   // 原文は a を添字に使う（type 0 は範囲外）
            int ai = Math.max(1, Math.min(3, a)) - 1;
            String l5type = type == 1 ? "Receipt" : type == 2 ? "Invoice" : "Cr. Note";
            cvat[ai][0] = cvat[ai][0].add(cv);
            String line5 = Num.edit(ih.longv("ih-invoice"), "z(7)9") + " " + pad(binToDate(ih.longv("ih-date")), 11)
                    + pad(ih.str("ih-supplier"), 9) + pad(name, 25) + pad("", 4) + pad(l5type, 14)
                    + Num.edit(net, CR) + pad("", 12) + Num.edit(net.add(car), CR) + Num.edit(vat.add(cv), CR)
                    + Num.edit(vat.add(cv).add(net).add(car), CR);
            tot[ai][1] = tot[ai][1].add(net);
            tot[ai][0] = tot[ai][0].add(ded);
            tot[ai][2] = tot[ai][2].add(car);
            tot[ai][4] = tot[ai][4].add(vat).add(cv);
            tot[ai][3] = tot[ai][3].add(net).add(car);
            tot[ai][5] = tot[ai][5].add(vat).add(cv).add(net).add(car);
            if (lineCnt > pageLines) headings(true);
            prt.after(line5, 2);
            lineCnt += 2;
            printOut = "Y";
            boolean firstTime = true;
            for (int n = 0; n < ih.intv("ih-lines"); n++) {
                // analysis-print
                if (invoiceFile.readNext(fd).equals("00")) System.arraycopy(fd.bytes(), 0, il.bytes(), 0, 75);
                if (il.str("il-product", 1).startsWith("/")) continue;
                if (type == 3) {
                    il.setNum("il-vat", il.num("il-vat", 1).negate(), 1);
                    il.setNum("il-net", il.num("il-net", 1).negate(), 1);
                }
                int k = il.intv("il-vat-code", 1);
                if (k > 0 && k <= 3) cvat[ai][k - 1] = cvat[ai][k - 1].add(il.num("il-vat", 1));
                String lineA = pad("", 46) + pad(firstTime ? "Analysis" : "", 12) + pad(il.str("il-pa", 1), 6)
                        + pad(firstTime ? "Value" : "", 8) + Num.edit(il.num("il-net", 1), CR) + "  "
                        + pad(firstTime ? "Vat Code" : "", 9) + k;
                firstTime = false;
                prt.after(lineA, 1);
                lineCnt++;
                if (lineCnt > pageLines) headings(true);
            }
            // extra-analysis
            if (lineCnt > pageLines - 2) headings(true);
            if (!lbA.isBlank()) {
                prt.after(pad("", 46) + pad(lbA, 12) + pad("", 6) + pad("", 8) + lbAmount, 1);
                lineCnt++;
                lbA = "";
            }
            if (!ldA.isBlank()) {
                prt.after(pad("", 46) + pad(ldA, 12) + pad("", 6) + pad("", 8) + ldAmount + "  " + pad("", 9) + ldVat, 1);
                lineCnt++;
                ldA = "";
            }
        }
        purchaseFile.close(); invoiceFile.close();
        headings(false);
        prt.after(pad("", 36) + "Goods    Carriage         Net         Vat       Gross  Prompt Pay", 2);
        prt.after("", 1);
        for (int a = 0; a < 3; a++) {
            lineCnt++;
            prt.after("   " + pad("    Total", 10) + pad(LIT[a], 18) + Num.edit(tot[a][1], CR) + Num.edit(tot[a][2], CR)
                    + Num.edit(tot[a][3], CR) + Num.edit(tot[a][4], CR) + Num.edit(tot[a][5], CR) + Num.edit(tot[a][0], CR), 1);
        }
        if (purchaseMissing) {
            prt.after("Warning: Record/s missing in Purchase File", 2);
            printOut = "Y";
        }
        prt.after("V.A.T. Reconciliation       Receipts       Invoices   Credit Notes", 5);
        prt.after("", 1);
        for (int i = 1; i <= 3; i++) {
            prt.after(pad("Vat Code", 9) + i + "   " + Num.edit(sys.num("vat-rate", i), "z9.99") + pad("%", 5)
                    + Num.edit(cvat[0][i - 1], "z(7)9.99cr") + Num.edit(cvat[1][i - 1], "z(9)9.99cr")
                    + Num.edit(cvat[2][i - 1], "z(9)9.99cr"), 1);
            lineCnt++;
        }
        prt.close();
        if (printOut.equals("Y")) spoolPrt1();
    }

    private void headings(boolean full) {
        page++;
        String line1 = pad(PROG_NAME, 49) + pad("Unapplied Purchase Transaction Report", 75) + "Page " + Num.edit(page, "zz9");
        String line2 = pad(sys.str("usera"), 49) + pad("", 73) + fromUk(toDay());
        if (page != 1) {
            prt.afterPage(line1);
            prt.after(line2, 1);
            prt.after("", 1);
        } else {
            prt.before(line1, 1);
            prt.before(line2, 1);
        }
        if (!full) return;
        prt.after(" Number  ---Date--- <------------Supplier------------>    --Type--" + "    "
                + "     Goods                 <---Net-->  <---Vat-->  <--Gross->", 1);
        prt.after("", 1);
        lineCnt = 5;
    }
}
