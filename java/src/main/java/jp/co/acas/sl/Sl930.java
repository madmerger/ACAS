package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl930.cbl: 請求書印刷。 */
public class Sl930 extends SlProgram {
    static final String PROG_NAME = "SL930 (3.01.12)";

    private Rec sys, sales, deliv, inv, sih, bodies;
    private CobFile salesFile, delivFile, invFile;
    private Prt print;
    private int lineSize, i, k, j, count1, count2;
    private boolean firstTime = true;
    private String printPath = "P", wsDate;
    private final String[] company = new String[7];
    private String l0Type, l0Xs, l0Desc, l7bDisc = "  Disc ";
    private final String[] iLine = new String[6], dLine = new String[6];
    // line-8 / line-9 は印字間で内容を保持する
    private String l8Product = " ".repeat(14), l8Desc = " ".repeat(30), l8Qty = " ".repeat(6), l8Unit = " ".repeat(10),
        l8Discount = " ".repeat(6), l8Percent = " ", l8Net = " ".repeat(10), l8Vat = " ".repeat(10);
    private String l9Terms = "Credit Terms: ", l9Desc = " ".repeat(24);
    private BigDecimal workN, workV;

    @Override
    public void run(Object... args) {
        sys = sys();
        if (sys.intv("full-invoicing") == 0) return;
        if (sys.intv("file-status", 15) != 1) { maps99(29); maps99(15); accept(24, 79, 1); return; }
        term().exceptionsEnabled = true; term().escEnabled = true;
        sales = salesRec(); deliv = deliveryRec();
        inv = fdRec("sales/fdinv.cob", "invoice-record");
        sih = Layout.of("sales/wsinv.cob", "sinvoice-header").newRec();
        bodies = Layout.of("sales/wsinv.cob", "sInvoice-Bodies").newRec();
        lineSize = bodies.bytes().length / 40;
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv);
        invFile = CobFile.indexed(ctx.store, ctx.path(F_INVOICE), inv, "invoice-key");
        print = new Prt(ctx, "prt-2");
        wsDate = fromUk(toDay());
        setupCompanyDetails();
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 34, "Invoice Printing");
        show(1, 71, wsDate, 2);
        invFile.open(CobFile.Mode.IO);
        salesFile.open(CobFile.Mode.INPUT); delivFile.open(CobFile.Mode.INPUT);
        print.openOutput();
        if (sys.intv("pass-value") == 3) single(); else allPrint();
        invFile.close(); salesFile.close(); delivFile.close();
        print.close();
        ctx.spool("prt-2", "lpr -r -o 'orientation-requested=3 page-left=36 page-top=24 page-right=24 cpi=12 lpi=8' -P "
            + sys.str("print-spool-name2").stripTrailing() + " prt-2");
        if (sys.intv("pass-value") == 3) sys.setNum("s-flag-i", 1);
    }

    private boolean pending() { return sih.str("sih-status").equals("P"); }
    private boolean sapplied() { return sih.str("sih-status").equalsIgnoreCase("z"); }

    private void single() {
        inv.setNum("invoice-nos", sys.longv("next-invoice") - 1);
        inv.setNum("item-nos", 0);
        inv.set("invoice-let", " ");
        invFile.read(inv);
        if (invalidKey(invFile)) return;
        move(inv, sih);
        if (pending() || !sih.str("sih-status-l").equals("L")) { printRoutine(); return; }
        display(5, 1, "Invoice Number - ");
        show(5, 18, z(sih.longv("sih-invoice"), 8));
        display(6, 1, "Already Invoiced!.....Re-Print  (Y/N) ? - [Y]");
        if (upper(term().accept(6, 44, 1, "Y", 0, 6)).equals("Y")) printRoutine();
        eraseEol(5, 1); eraseEol(6, 1);
    }

    private void allPrint() {
        display(7, 1, "Print Or Re-Print.............  (P/R) ? - [P]");
        printPath = term().accept(7, 44, 1, "P", 0, 6);
        boolean getInv = printPath.equals("R");
        boolean go = false;
        if (!getInv) {
            while (true) {
                display(9, 1, "Any Amended Invoices In This Batch? [N]");
                String r = upper(term().accept(9, 38, 1, "N", 0, 6));
                if (r.equals("Y")) { sys.setNum("first-sl-inv", 0); inv.setNum("item-nos", 0); break; }
                if (!r.equals("N")) continue;
                if (sys.longv("first-sl-inv") == 0) break;
                inv.setNum("invoice-nos", sys.longv("first-sl-inv"));
                go = true;
                break;
            }
        }
        while (true) {
            if (getInv) {
                eraseEol(13, 1);
                inv.setNum("invoice-nos", 0);
                display(13, 1, "Give Lowest Invoice No. [        ]");
                inv.setNum("invoice-nos", intOf(acceptUpdate(13, 26, 8, "00000000", NUMERIC)));
                go = true;
                getInv = false;
            }
            if (go) {
                sys.setNum("first-sl-inv", 0); inv.setNum("item-nos", 0);
                inv.set("invoice-let", " ");
                invFile.start(inv, ">=");
                go = false;
            }
            while (true) {
                invFile.readNext(inv);
                if (!invFile.status.equals("00")) return;
                if (inv.intv("item-nos") != 0) continue;
                move(inv, sih);
                if (sih.intv("sih-lines") == 0 && sapplied()) continue;
                if (pending()) { printRoutine(); continue; }
                if (printPath.equals("P")) continue;
                break;
            }
            display(11, 1, "Invoice Number - ");
            show(11, 18, z(sih.longv("sih-invoice"), 8));
            display(12, 1, "Already Invoiced!.....Re-Print  (Y/N) ? - [Y]");
            if (upper(term().accept(12, 44, 1, " ", 0, 6)).equals("Y")) printRoutine();
            eraseEol(11, 1); eraseEol(12, 1);
            while (true) {
                display(11, 1, "More To Print? [Y]");
                String r = upper(term().accept(11, 17, 1, "Y", 0, 6));
                if (r.equals("N")) return;
                if (r.equals("Y")) break;
            }
            getInv = true;
        }
    }

    private String silStr(String f, int n) { return bodies.str(f, n); }

    private void printRoutine() {
        i = 1;
        for (int n = sih.intv("sih-lines"); n > 0; n--) {
            invFile.readNext(inv);
            if (!invFile.status.equals("00")) break;
            if (inv.intv("item-nos") == 0) break;
            System.arraycopy(inv.bytes(), 0, bodies.bytes(), (i - 1) * lineSize, lineSize);
            if (silStr("sil-type", i).equals("D")) break;
            i++;
        }
        i = Math.abs(i - 1) % 100;
        l0Desc = " ".repeat(25);
        int ii = Math.abs(i - 1);
        if (ii == 0) ii = 1;
        count2 = (ii / 15 + 1) % 10;
        count1 = 1;
        l0Xs = "  =======";
        switch (sih.intv("sih-type")) {
            case 1 -> l0Type = "  Receipt";
            case 2 -> l0Type = "  Invoice";
            case 3 -> { l0Type = "Credit Note"; l0Xs = "==========="; }
            default -> { l0Type = "  Pro-Forma"; l0Xs = "  ========="; l0Desc = "This is not a VAT Invoice"; }
        }
        sales.set("sales-key", sih.str("sih-customer"));
        salesFile.read(sales);
        boolean hasDeliv = sales.intv("delivery-tag") > 0;
        if (hasDeliv) {
            deliv.set("deliv-key-type", "D"); deliv.set("deliv-sales-key", sales.str("sales-key"));
            delivFile.read(deliv);
        }
        String delim = pad(sys.str("sl-delim"), 1);
        split(sales.str("sales-name"), sales.str("sales-address"), delim, iLine, 31);
        if (sales.intv("delivery-tag") == 0) java.util.Arrays.fill(dLine, " ".repeat(30));
        else split(deliv.str("deliv-name"), deliv.str("deliv-address"), delim, dLine, 30);
        headings1();
        k = 1; j = 25;
        workN = BigDecimal.ZERO; workV = BigDecimal.ZERO;
        boolean level2 = sys.intv("invoicer") == 2;
        while (true) {
            boolean comment = k >= 1 && k <= 40 && silStr("sil-product", k).startsWith("/");
            int kx = Math.max(1, Math.min(40, k));
            if (comment) {
                l8Product = " ".repeat(14); l8Desc = " ".repeat(30); l8Qty = " ".repeat(6); l8Unit = " ".repeat(10);
                l8Discount = " ".repeat(6); l8Percent = " "; l8Net = " ".repeat(10); l8Vat = " ".repeat(10);
            }
            if (level2) l8Desc = pad(silStr("sil-description", kx), 30);
            if (comment) {
                l8Qty = " ".repeat(6); l8Unit = " ".repeat(10); l8Discount = " ".repeat(6); l8Vat = " ".repeat(10); l8Net = " ".repeat(10);
            } else {
                if (level2) {
                    l8Qty = bwz(bodies.num("sil-qty", kx), "z(5)9");
                    l8Unit = bwz(bodies.num("sil-unit", kx), "z(6)9.99");
                    l8Product = pad(silStr("sil-product", kx), 13) + " ";
                    l8Discount = bwz(bodies.num("sil-discount", kx), "zz9.99");
                } else { l8Qty = " ".repeat(6); l8Unit = " ".repeat(10); l8Discount = " ".repeat(6); l8Product = " ".repeat(14); }
                if (level2 && bodies.num("sil-discount", kx).signum() > 0) { l8Percent = "%"; l7bDisc = "  Disc "; }
                else { l7bDisc = " ".repeat(7); l8Percent = " "; }
                l8Net = bwz(bodies.num("sil-net", kx), "z(6)9.99");
                l8Vat = bwz(bodies.num("sil-vat", kx), "z(6)9.99");
            }
            print.after(l8Product + l8Desc + l8Qty + l8Unit + l8Discount + l8Percent + l8Net + l8Vat, 1);
            workN = workN.add(bodies.num("sil-net", kx));
            workV = workV.add(bodies.num("sil-vat", kx));
            k++;
            if (k > i) { k = Math.abs(count2 * 25 - i + 2) % 100; break; }
            if (k > j) {
                int kk = k;
                k = 2;
                j += 25;
                count1 = (count1 + 1) % 10;
                totalPrint();
                k = kk;
                print.after("", 13);
                headings1();
            }
        }
        totalPrint();
        BigDecimal dAmt = sih.num("sih-deduct-amt"), dVat = sih.num("sih-deduct-vat");
        if (dAmt.signum() == 0 && dVat.signum() == 0) print.after("", 1);
        else {
            l9Desc = pad("Late Payment Surcharge", 24);
            print.after(line9(0, dAmt, dVat), 1);
            l9Desc = " ".repeat(24);
        }
        BigDecimal ex = sih.num("sih-extra"), eVat = sih.num("sih-e-vat");
        if (sys.str("extra-print").equals("N") || (ex.signum() == 0 && eVat.signum() == 0)) print.after("", 1);
        else {
            l9Desc = pad(sys.str("extra-desc"), 24);
            print.after(line9(0, ex, eVat), 1);
        }
        l9Desc = " ".repeat(24);
        BigDecimal car = sih.num("sih-carriage"), cVat = sih.num("sih-c-vat");
        print.after(line9(0, car, cVat), 2);
        String l10Terms = "Prompt pay time:";
        long l10Days = sih.longv("sih-deduct-days");
        if (sales.longv("sales-credit") == 0) { l10Days = 0; l10Terms = " ".repeat(16); }
        if (dAmt.signum() == 0) { l10Terms = " ".repeat(16); l10Days = 0; }
        BigDecimal vat = sih.num("sih-vat").add(eVat).add(cVat).add(dVat);
        BigDecimal net = sih.num("sih-net").add(ex).add(car).add(dAmt);
        print.after(" ".repeat(14) + l10Terms + bwz(BigDecimal.valueOf(l10Days), "zz9"), 1);
        print.after(" ".repeat(13) + bwz(dAmt.add(dVat), "zzz9.99") + " ".repeat(45) + bwz(net, "z(7)9.99") + bwz(vat, "z(7)9.99"), 1);
        print.after(" ".repeat(65) + "Total Due: " + Num.edit(net.add(vat), "z(7)9.99"), 2);
        print.after("", 5);
        if (!sapplied()) {
            sih.set("sih-status", "I"); sih.set("sih-status-l", "L");
            move(sih, inv);
            invFile.rewrite(inv);
        }
    }

    private static String bwz(BigDecimal v, String pic) {
        String s = Num.edit(v, pic);
        return v.signum() == 0 ? " ".repeat(s.length()) : s;
    }

    private String line9(long days, BigDecimal net, BigDecimal vat) {
        return l9Terms + bwz(BigDecimal.valueOf(days), "zz9") + " ".repeat(24) + l9Desc + bwz(net, "-(7)9.99") + bwz(vat, "-(7)9.99");
    }

    private void totalPrint() {
        l9Desc = " ".repeat(24);
        l9Terms = "Credit Terms: ";
        print.after(line9(sih.longv("sih-days"), workN, workV), k);
        l9Terms = " ".repeat(14);
    }

    private void split(String name, String addr, String delim, String[] out, int size) {
        out[0] = pad(name, size);
        for (int n = 1; n < 6; n++) out[n] = " ".repeat(size);
        int p = 1;
        for (int n = 1; n < 6; n++) {
            Object[] r = unstring(addr, delim, p, size);
            if (r[0] == null) break;
            out[n] = (String) r[0]; p = (int) r[1];
        }
    }

    private void headings1() {
        var now = ctx.now();
        boolean pick = sys.str("sl-comp-head-pick").equals("Y");
        if (pick) {
            if (firstTime) print.after(company[0], 1); else print.afterPage(company[0]);
            for (int n = 1; n < 7; n++) print.after(company[n], 1);
            print.after(l0Type, 1);
        } else {
            if (!firstTime) print.afterPage("");
            print.after(l0Type, 4);
        }
        print.after(l0Xs, 1);
        print.after(" ".repeat(37) + l0Desc, 2);
        print.after(" ".repeat(25) + "INVOICE" + " ".repeat(25) + "Page " + count1 + " of " + count2 + " " + binToDate(sih.longv("sih-date"))
            + " " + z(now.getHour(), 2) + ":" + z(now.getMinute(), 2), 1);
        print.after(" ".repeat(72) + "Inv: " + Num.edit(sih.longv("sih-invoice"), "z(7)9"), 2);
        print.after(iLine[0] + "    " + dLine[0], 1);
        print.after(iLine[1] + "    " + dLine[1], 1);
        print.after(iLine[2] + "    " + dLine[2] + " ".repeat(5) + "Order: " + pad(sih.str("sih-order"), 11), 1);
        print.after(iLine[3] + "    " + dLine[3] + " ".repeat(5) + " Ref : " + pad(sih.str("sih-ref"), 11), 1);
        print.after(iLine[4] + "    " + dLine[4] + " ".repeat(5) + " A/C : " + sih.str("sih-customer"), 1);
        print.after(iLine[5] + "    " + dLine[5], 1);
        print.after("", 2);
        print.after("Product Code  " + pad("Item Description", 30) + "   Qty" + "      Cost" + l7bDisc + pad("      Net", 10) + pad("      Vat", 10), 1);
        firstTime = false;
    }

    private void setupCompanyDetails() {
        java.util.Arrays.fill(company, "");
        if (!sys.str("sl-comp-head-pick").equals("Y")) return;
        String[] src = {sys.str("usera"), sys.str("address-1"), sys.str("address-2"), sys.str("address-3"), sys.str("address-4"),
            sys.str("post-code"), sys.str("country")};
        for (int n = 0; n < 7; n++) {
            String s = src[n];
            int h = s.length();
            while (h > 1 && s.charAt(h - 1) == ' ') h--;
            int pos = 45 - (h / 2 + 1);
            company[n] = " ".repeat(pos - 1) + s.substring(0, h);
        }
    }
}
