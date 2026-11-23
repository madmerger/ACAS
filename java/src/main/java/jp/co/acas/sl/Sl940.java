package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;

/** sl940.cbl: 請求書削除。 */
public class Sl940 extends SlProgram {
    static final String PROG_NAME = "SL940 (3.01.04)";
    static final String SL194 = "SL194 Invoice Not Found!!!!", SL195 = "SL195 Invoice Details Already Passed To Sales Ledger!";

    private Rec sys, sales, deliv, inv, sih, dnos;
    private CobFile salesFile, delivFile, invFile, dnosFile;
    private String escapeCode = " ";

    @Override
    public void run(Object... args) {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("file-status", 16) != 1) { maps99(17); maps99(15); return; }
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 31, "Invoicing Data Deletion");
        show(1, 71, fromUk(toDay()), 2);
        sales = salesRec(); deliv = deliveryRec();
        inv = fdRec("sales/fdinv.cob", "invoice-record");
        sih = Layout.of("sales/wsinv.cob", "sinvoice-header").newRec();
        dnos = fdRec("sales/fddnos.cob", "del-inv-nos-record");
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv);
        invFile = CobFile.indexed(ctx.store, ctx.path(F_INVOICE), inv, "invoice-key");
        dnosFile = CobFile.sequential(ctx.store, ctx.path(F_DELINV));
        invFile.open(CobFile.Mode.IO);
        salesFile.open(CobFile.Mode.INPUT); delivFile.open(CobFile.Mode.INPUT);
        dnosFile.open(CobFile.Mode.EXTEND);
        if (!dnosFile.status.equals("00")) { dnosFile.close(); dnosFile.open(CobFile.Mode.OUTPUT); }
        while (true) {
            escapeCode = " ";
            invoiceDetails();
            if (escapeCode.equals("Q")) break;
            eraseEos(16, 1);
            display(16, 29, "Delete Further Invoices (Y/N) ? [Y]");
            String r = upper(term().accept(16, 62, 1, "Y", 0, 6));
            eraseEol(16, 1);
            if (!r.equals("Y")) break;
        }
        salesFile.close(); delivFile.close(); dnosFile.close(); invFile.close();
    }

    private void box(int line, String text) { eraseEol(line, 41); display(line, 41, text); }

    private void invoiceDetails() {
        box(4, "****************************************");
        box(5, "*Date   [  /  /    ]*                  *");
        box(6, "*A/C Nos   [       ]*                 **");
        box(7, "*Invoice [         ]*Order [          ]*");
        box(8, "****************************************");
        display(10, 1, "Type [ ]  <1> = Receipt; <2> = Account; <3> = CrediT Note; <4> = Pro-Forma");
        while (true) {
            long n = intOf(acceptUpdate(7, 51, 8, z(sih.longv("sih-invoice"), 8), NUMERIC));
            sih.setNum("sih-invoice", n);
            eraseEol(16, 1);
            if (n == 0) { escapeCode = "Q"; return; }
            display(16, 1, "Now give Invoice letter (A, B, C or return for space)");
            sih.set("sih-letter", term().accept(7, 59, 1, " ", 0, 6));
            inv.set("invoice-let", sih.str("sih-letter"));
            eraseEol(16, 1);
            inv.setNum("invoice-nos", n);
            inv.setNum("item-nos", 0);
            invFile.read(inv);
            if (invalidKey(invFile)) { display(16, 40, SL194, 4); continue; }
            move(inv, sih);
            if (sih.str("sih-status").equals("z")) { eraseEol(16, 1); display(16, 1, SL195, 4); continue; }
            break;
        }
        String wsDate = binToDate(sih.longv("sih-date"));
        show(6, 53, sih.str("sih-customer"));
        sales.set("sales-key", sih.str("sih-customer"));
        salesFile.read(sales);
        String addr;
        if (sales.intv("delivery-tag") == 0) addr = sales.str("sales-address");
        else {
            deliv.set("deliv-key-type", "D"); deliv.set("deliv-sales-key", sales.str("sales-key"));
            delivFile.read(deliv);
            if (invalidKey(delivFile)) { sales.setNum("delivery-tag", 0); addr = sales.str("sales-address"); }
            else addr = deliv.str("deliv-address");
        }
        show(4, 1, sales.intv("delivery-tag") == 0 ? sales.str("sales-name") : deliv.str("deliv-name"));
        String delim = pad(sys.str("sl-delim"), 1);
        int p = 1;
        String line = " ".repeat(36);
        for (int l = 5; l <= 7; l++) {
            Object[] r = unstring(addr, delim, p, 36);
            if (r[0] != null) { line = (String) r[0]; p = (int) r[1]; }
            show(l, 1, line);
            line = " ".repeat(36);
        }
        if (p >= 1 && p <= addr.length()) line = pad(addr.substring(p - 1, Math.min(addr.length(), p + 35)), 36);
        show(8, 1, line);
        show(5, 50, wsDate);
        show(7, 69, sih.str("sih-order"));
        show(10, 7, sih.str("sih-type"));
        display(16, 1, "Invoice To Be Deleted (Y/N) - [ ]");
        if (!upper(term().accept(16, 32, 1, "N", 0, 6)).equals("Y")) return;
        invFile.delete(inv);
        int j = 0;
        for (int n = sih.intv("sih-lines"); n > 0; n--) {
            j++;
            inv.setNum("invoice-nos", sih.longv("sih-invoice")); inv.set("invoice-let", sih.str("sih-letter")); inv.setNum("item-nos", j);
            invFile.delete(inv);
        }
        dnos.setNum("del-inv-nos", sih.longv("sih-invoice"));
        dnos.setNum("del-inv-dat", sih.longv("sih-date"));
        dnos.set("del-inv-cus", sih.str("sih-customer"));
        dnosFile.write(dnos);
    }
}
