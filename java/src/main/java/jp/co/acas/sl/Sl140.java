package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl140.cbl: 日計表（Day Book）。 */
public class Sl140 extends SlProgram {
    static final String PROG_NAME = "SL140 (3.01.09)";
    private static final String[] TOTAL_LITERAL = {"Receipts", "Invoices", "Credit Notes", "    Totals"};

    private Rec sys;
    private Prt print;
    private int headType, lineCnt, j;
    /** group-totals(1..4): gds, car, ded, net, vat, grs, dis（各 s9(8)v99）。 */
    private final BigDecimal[][] tot = new BigDecimal[4][7];
    private static final int GDS = 0, CAR = 1, DED = 2, NET = 3, VAT = 4, GRS = 5, DIS = 6;

    @Override
    public void run(Object... args) {
        sys = sys();
        for (BigDecimal[] t : tot) java.util.Arrays.fill(t, BigDecimal.ZERO);
        eraseEos(1, 1);
        show(1, 1, PROG_NAME, 2);
        display(1, 36, "Day Book", 2);
        show(1, 71, fromUk(toDay()), 2);
        Rec inv = invoiceRec(), sales = salesRec();
        Rec sih = Layout.of("sales/wsinv.cob", "sinvoice-header").newRec();
        CobFile invFile = invoiceFile(inv), salesFile = salesFile(sales);
        invFile.open(CobFile.Mode.INPUT);
        if (!invFile.status.equals("00")) { invFile.close(); return; }
        salesFile.open(CobFile.Mode.INPUT);
        if (!salesFile.status.equals("00")) { invFile.close(); salesFile.close(); return; }
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        display(12, 12, "Printing.......Please wait", 2);
        int pageLines = sys.intv("page-lines");
        j = 0;
        headings();
        String name = " ".repeat(25);
        while (invFile.readNext(inv).equals("00")) {
            if (inv.longv("item-nos") != 0) continue;
            if (inv.intv("invoice-type") > 3) continue;
            System.arraycopy(inv.bytes(), 0, sih.bytes(), 0, Math.min(inv.bytes().length, sih.bytes().length));
            if (sih.str("sih-day-book-flag").equals("B") || !sih.str("sih-status").equalsIgnoreCase("z")) continue;
            if (lineCnt > pageLines) headings();
            sales.set("sales-key", sih.str("sih-customer"));
            salesFile.read(sales);
            name = pad(sales.str("sales-name"), 25);
            int z = sih.intv("sih-type");
            String type = z == 1 ? "Receipt" : z == 2 ? "Invoice" : "Cr. Note";
            BigDecimal sign = z == 3 ? BigDecimal.ONE.negate() : BigDecimal.ONE;
            BigDecimal vat = sih.num("sih-vat").multiply(sign), cVat = sih.num("sih-c-vat").multiply(sign), eVat = sih.num("sih-e-vat").multiply(sign),
                net = sih.num("sih-net").multiply(sign), extra = sih.num("sih-extra").multiply(sign), carriage = sih.num("sih-carriage").multiply(sign),
                discount = sih.num("sih-discount").multiply(sign), deduct = sih.num("sih-deduct-amt").multiply(sign);
            BigDecimal vats = vat.add(cVat).add(eVat);
            BigDecimal nets = net.add(extra).add(carriage).add(discount).add(deduct);
            BigDecimal gross = vats.add(nets);
            add(z, GDS, net); add(z, DIS, discount.add(extra)); add(z, DED, deduct); add(z, CAR, carriage);
            add(z, VAT, vats); add(z, NET, nets); add(z, GRS, gross);
            print.after(Num.edit(sih.longv("sih-invoice"), "z(7)9") + "  " + pad(binToDate(sih.longv("sih-date")), 10) + " "
                + pad(sih.str("sih-customer"), 8) + name + "   " + pad(type, 11) + " ".repeat(6)
                + e7(nets) + e7(vats) + e7(gross), 1);
            lineCnt++;
        }
        salesFile.close(); invFile.close();
        headType = 1;
        headings();
        print.after(" ".repeat(23) + "Goods     Discount   Prompt Pay     Carriage          Net          Vat        Gross", 2);
        print.after("", 1);
        for (int z = 0; z < 4; z++)
            print.after(pad(TOTAL_LITERAL[z], 17) + e8(tot[z][GDS]) + e8(tot[z][DIS]) + e8(tot[z][DED]) + e8(tot[z][CAR])
                + e8(tot[z][NET]) + e8(tot[z][VAT]) + e8(tot[z][GRS]), 2);
        print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private static final BigDecimal M7 = new BigDecimal(10000000), M8 = new BigDecimal(100000000);
    private static String e7(BigDecimal v) { return Num.edit(v.remainder(M7), "z(6)9.99cr"); }
    private static String e8(BigDecimal v) { return Num.edit(v.remainder(M8), "z(7)9.99cr"); }

    private void add(int z, int col, BigDecimal v) {
        if (z >= 1 && z <= 3) tot[z - 1][col] = tot[z - 1][col].add(v);
        tot[3][col] = tot[3][col].add(v);
    }

    private void headings() {
        j++;
        String l1 = pad(PROG_NAME, 62) + pad("Day Book", 62) + "Page " + Num.edit(j, "zz9");
        String l2 = pad(sys.str("usera"), 62) + " ".repeat(60) + pad(fromUk(toDay()), 10);
        if (j != 1) { print.afterPage(l1); print.after(l2, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l2, 1); }
        lineCnt = 2;
        if (headType == 0) {
            lineCnt += 3;
            print.after(pad(" Number   ---Date--- <------------Customer------------>", 74) + "<---Net-->  <---Vat-->  <--Gross->", 2);
            print.after("", 1);
        }
    }
}
