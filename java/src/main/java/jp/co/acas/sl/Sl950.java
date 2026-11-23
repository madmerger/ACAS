package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl950.cbl: 納品書／ピッキングリスト印刷。 */
public class Sl950 extends SlProgram {
    static final String PROG_NAME = "SL950 (3.01.05)";

    private Rec sys, sales, deliv, inv, sih, bodies, stock;
    private CobFile salesFile, delivFile, invFile, stockFile;
    private Prt print;
    private int lineSize, i, k, j, count1, count2;
    private boolean firstTime = true;
    private String printPath = "P";
    private final String[] company = new String[7];
    private String l0Type = " ".repeat(12);
    private final String[] iLine = new String[6], dLine = new String[6];
    // line-8 は印字間で内容を保持する
    private String l8Abrev = " ".repeat(9), l8Product = " ".repeat(15), l8Desc = " ".repeat(34), l8Qty = " ".repeat(6), l8Loc = " ".repeat(12);

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
        stock = fdRec("copybooks/fdstock.cob", "Stock-Record");
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv);
        invFile = CobFile.indexed(ctx.store, ctx.path(F_INVOICE), inv, "invoice-key");
        stockFile = CobFile.indexed(ctx.store, ctx.path(F_STOCK), stock, "stock-key")
            .alt(stock.offset("stock-abrev-key"), stock.size("stock-abrev-key"), false)
            .alt(stock.offset("stock-desc"), stock.size("stock-desc"), true);
        print = new Prt(ctx, "prt-3");
        setupCompanyDetails();
        clearScreen();
        show(1, 1, PROG_NAME);
        display(1, 26, "Delivery / Picking Note Print");
        show(1, 71, fromUk(toDay()), 2);
        stockFile.open(CobFile.Mode.INPUT);
        invFile.open(CobFile.Mode.IO);
        salesFile.open(CobFile.Mode.INPUT); delivFile.open(CobFile.Mode.INPUT);
        print.openOutput();
        if (sys.intv("pass-value") == 3) single(); else allPrint();
        invFile.close(); salesFile.close(); delivFile.close(); stockFile.close();
        print.close();
        ctx.spool("prt-3", "lpr -r -o 'orientation-requested=3 page-left=36 page-top=24 page-right=24 cpi=12 lpi=8' -P "
            + sys.str("print-spool-name3").stripTrailing() + " prt-3");
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
        if (pending()) { printRoutine(); return; }
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
                if (sih.str("sih-status-p").equals("P")) continue;
                if (pending()) { printRoutine(); continue; }
                if (printPath.equals("P")) continue;
                if (sih.intv("sih-type") > 2) continue;
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

    private String line8() { return "  " + l8Abrev + l8Product + l8Desc + l8Qty + " ".repeat(6) + l8Loc; }
    private void clearLine8() {
        l8Abrev = " ".repeat(9); l8Product = " ".repeat(15); l8Desc = " ".repeat(34); l8Qty = " ".repeat(6); l8Loc = " ".repeat(12);
    }
    private static String bwz(BigDecimal v, String pic) {
        String s = Num.edit(v, pic);
        return v.signum() == 0 ? " ".repeat(s.length()) : s;
    }

    private void printRoutine() {
        long itemCount = 0;
        i = 1;
        for (int n = sih.intv("sih-lines"); n > 0; n--) {
            invFile.readNext(inv);
            if (!invFile.status.equals("00")) break;
            if (inv.intv("item-nos") == 0) break;
            System.arraycopy(inv.bytes(), 0, bodies.bytes(), (i - 1) * lineSize, lineSize);
            if (bodies.str("sil-type", i).equals("D")) break;
            i++;
        }
        i = Math.abs(i - 1) % 100;
        l0Type = " ".repeat(12);
        int ii = Math.abs(i - 1);
        if (ii == 0) ii = 1;
        count2 = (ii / 15 + 1) % 10;
        count1 = 1;
        if (sih.intv("sih-type") == 1) l0Type = "Receipt Pick"; else if (sih.intv("sih-type") == 2) l0Type = "Invoice Pick";
        sales.set("sales-key", sih.str("sih-customer"));
        salesFile.read(sales);
        if (sales.intv("delivery-tag") > 0) {
            deliv.set("deliv-key-type", "D"); deliv.set("deliv-sales-key", sales.str("sales-key"));
            delivFile.read(deliv);
        }
        String delim = pad(sys.str("sl-delim"), 1);
        split(sales.str("sales-name"), sales.str("sales-address"), delim, iLine, 31);
        if (sales.intv("delivery-tag") == 0) java.util.Arrays.fill(dLine, " ".repeat(30));
        else split(deliv.str("deliv-name"), deliv.str("deliv-address"), delim, dLine, 30);
        headings1();
        k = 1; j = 25;
        boolean level2 = sys.intv("invoicer") == 2;
        while (true) {
            int kx = Math.max(1, Math.min(40, k));
            boolean comment = bodies.str("sil-product", kx).startsWith("/");
            if (comment) clearLine8();
            if (level2) l8Desc = pad(bodies.str("sil-description", kx), 32) + "  ";
            if (!comment && level2) {
                l8Qty = bwz(bodies.num("sil-qty", kx), "z(5)9");
                itemCount = (itemCount + Math.abs(bodies.longv("sil-qty", kx))) % 10000;
                l8Product = pad(bodies.str("sil-product", kx), 13) + "  ";
                stock.set("stock-key", bodies.str("sil-product", kx));
                if (sys.str("sl-stock-link").equals("Y")) {
                    stockFile.read(stock);
                    if (invalidKey(stockFile)) {
                        stock.set("stock-abrev-key", bodies.str("sil-product", kx));
                        stockFile.readAlt(stock, 0);
                        if (invalidKey(stockFile)) stock.set("stock-key", " ");
                    }
                    if (!stock.str("stock-key").isBlank()) {
                        l8Product = pad(stock.str("stock-key"), 13) + "  ";
                        l8Abrev = pad(stock.str("stock-abrev-key"), 7) + "  ";
                        l8Loc = pad(stock.str("stock-location"), 10) + "  ";
                        l8Desc = pad(stock.str("stock-desc"), 32) + "  ";
                    }
                }
            }
            print.after(line8(), 1);
            k++;
            if (k > i) { k = Math.abs(count2 * 25 - i + 2) % 100; break; }
            if (k > j) { j += 25; count1 = (count1 + 1) % 10; headings1(); }
        }
        clearLine8();
        l8Qty = bwz(BigDecimal.valueOf(itemCount), "z(5)9");
        l8Desc = pad("                Total Item Count", 34);
        print.after(line8(), 3);
        if (!sih.str("sih-status-p").equalsIgnoreCase("P")) {
            sih.set("sih-status-p", "P");
            move(sih, inv);
            invFile.rewrite(inv);
        }
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
        if (sys.str("sl-comp-head-pick").equals("Y")) {
            if (firstTime) print.after(company[0], 1); else print.afterPage(company[0]);
            for (int n = 1; n < 7; n++) print.after(company[n], 1);
            print.after(l0Type, 1);
        } else {
            if (!firstTime) print.afterPage("");
            print.after(l0Type, 4);
        }
        print.after("", 2);
        print.after(" ".repeat(18) + "Picking/Delivery Note" + " ".repeat(18) + "Page " + count1 + " of " + count2 + " " + binToDate(sih.longv("sih-date"))
            + " " + z(now.getHour(), 2) + ":" + z(now.getMinute(), 2), 1);
        print.after(" ".repeat(71) + "Inv: " + Num.edit(sih.longv("sih-invoice"), "z(7)9"), 2);
        print.after(iLine[0] + "    " + dLine[0], 1);
        print.after(iLine[1] + "    " + dLine[1], 1);
        print.after(iLine[2] + "    " + dLine[2] + " ".repeat(5) + "Order: " + pad(sih.str("sih-order"), 11), 1);
        print.after(iLine[3] + "    " + dLine[3] + " ".repeat(5) + " Ref : " + pad(sih.str("sih-ref"), 11), 1);
        print.after(iLine[4] + "    " + dLine[4] + " ".repeat(5) + " A/C : " + sih.str("sih-customer"), 1);
        print.after(iLine[5] + "    " + dLine[5], 1);
        print.after("", 2);
        print.after(pad("  Abrev #", 11) + pad("Product Code", 15) + pad("Item Description", 34) + pad("   Qty", 12) + "Location", 1);
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
