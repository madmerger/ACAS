package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl140.cbl: 仕入日記帳（Day Book）。 */
public class Pl140 extends PlBase {
    static final String PROG_NAME = "PL140 (3.01.07)";
    private static final String[] LITERAL = {"Receipts", "Invoices", "Credit Notes", "      Total"};
    private Printer prt;
    private int j, lineCnt, headType;
    private String wsDate;

    @Override
    public void run(Object... args) {
        init();
        wsDate = fromUk(toDay());
        BigDecimal[][] tot = new BigDecimal[5][6];
        for (BigDecimal[] t : tot) java.util.Arrays.fill(t, BigDecimal.ZERO);
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 36, "Day Book");
        show(1, 71, wsDate, 2);
        CobFile invoiceFile = invoiceFile();
        if (!invoiceFile.open(Mode.INPUT).equals("00")) { invoiceFile.close(); return; }
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        if (!purchaseFile.open(Mode.INPUT).equals("00")) { invoiceFile.close(); purchaseFile.close(); return; }
        prt = new Printer("prt-1");
        display(12, 12, "Printing.......Please wait");
        j = 0;
        headings();
        int pageLines = sys.intv("page-lines");
        Rec ih = invHeaderRec();
        while (invoiceFile.readNext(ih).equals("00")) {
            if (ih.intv("ih-test") != 0) continue;
            int type = ih.intv("ih-type");
            if (type > 3) continue;
            if (ih.str("ih-day-book-flag").equalsIgnoreCase("b") || !ih.str("ih-status").equalsIgnoreCase("z")) continue;
            if (lineCnt > pageLines) headings();
            purch.set("purch-key", ih.str("ih-supplier"));
            purchaseFile.read(purch);
            BigDecimal ded = ih.num("ih-deduct-amt");
            BigDecimal vat = ih.num("ih-vat"), cvat = ih.num("ih-c-vat"), net = ih.num("ih-net"), car = ih.num("ih-carriage");
            if (type == 3) { vat = vat.negate(); cvat = cvat.negate(); net = net.negate(); car = car.negate(); }
            BigDecimal v = vat.add(cvat), n = net.add(car), g = v.add(n);
            String tname = type == 1 ? "Receipt" : type == 2 ? "Invoice" : "Cr. Note";
            for (int z : new int[]{type, 4}) {
                tot[z][0] = tot[z][0].add(net); tot[z][1] = tot[z][1].add(car); tot[z][2] = tot[z][2].add(n);
                tot[z][3] = tot[z][3].add(v); tot[z][4] = tot[z][4].add(g); tot[z][5] = tot[z][5].add(ded);
            }
            prt.after(Num.edit(ih.longv("ih-invoice"), "z(7)9") + " " + pad(binToDate(ih.longv("ih-date")), 11)
                    + pad(ih.str("ih-supplier"), 8) + pad(purch.str("purch-name"), 25) + "   " + pad(tname, 11) + pad("", 6)
                    + Num.edit(n, "z(6)9.99cr") + Num.edit(v, "z(6)9.99cr") + Num.edit(g, "z(6)9.99cr") + pad("", 5)
                    + Pl095.bwz(ded, "z(6)9.99cr", 12), 1);
            lineCnt++;
        }
        purchaseFile.close(); invoiceFile.close();
        headType = 1;
        headings();
        prt.after(pad("", 23) + "Goods     Carriage          Net          Vat        Gross   Prompt Pay", 2);
        prt.after("", 1);
        for (int z = 1; z <= 4; z++) {
            StringBuilder sb = new StringBuilder(pad(LITERAL[z - 1], 17));
            for (int i = 0; i < 6; i++) sb.append(Num.edit(tot[z][i], "z(7)9.99cr"));
            prt.after(sb.toString(), 1);
        }
        prt.close();
        spoolPrt1();
    }

    private void headings() {
        j++;
        String l1 = pad(PROG_NAME, 54) + pad("Purchase Ledger Day Book", 70) + "Page " + Num.edit(j % 1000, "zz9");
        String l2 = pad(sys.str("usera"), 62) + pad("", 60) + wsDate;
        if (j != 1) {
            prt.afterPage(l1);
            prt.after(l2, 1);
            prt.after("", 1);
        } else {
            prt.before(l1, 1);
            prt.before(l2, 1);
        }
        lineCnt = 2;
        if (headType == 0) {
            lineCnt += 3;
            prt.after(pad(" Number  ---Date--- <------------Supplier------------>", 74)
                    + "<---Net-->  <---Vat-->  <--Gross->       Prompt Pay", 2);
            prt.after("", 1);
        }
    }
}
