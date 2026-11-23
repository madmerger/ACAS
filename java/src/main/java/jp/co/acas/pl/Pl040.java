package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;

/** pl040.cbl: 仕入請求書データ削除。 */
public class Pl040 extends PlBase {
    static final String PROG_NAME = "PL040 (3.01.01)";
    private Rec ih, purch, del;
    private CobFile invoiceFile, purchaseFile, delFile;
    private String escapeCode = " ";

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("file-status", 26) != 1) {
            maps99(17);
            maps99(15);
            return;
        }
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 31, "Invoice Data Deletion");
        show(1, 71, fromUk(toDay()), 2);
        ih = invHeaderRec(); purch = purchRec();
        del = fdRec(Layout.of("purchase/fdpdnos.cob", "del-inv-nos-record"));
        invoiceFile = invoiceFile(); purchaseFile = purchaseFile(purch);
        delFile = CobFile.sequential(ctx.store, ctx.path("delfolio.dat"));
        invoiceFile.open(Mode.IO);
        purchaseFile.open(Mode.INPUT);
        delFile.open(Mode.EXTEND, true);
        while (true) {
            escapeCode = " ";
            invoiceDetails();
            if (escapeCode.equals("Q")) break;
            eraseEos(16, 1);
            display(16, 29, "Delete further invoices? (Y/N)  [Y]");
            String r = upper(accept(16, 62, 1));
            eraseEos(16, 1);
            if (!r.equals("Y")) break;
        }
        purchaseFile.close(); delFile.close(); invoiceFile.close();
    }

    private void invoiceDetails() {
        display(4, 41, "****************************************"); eraseEol(4, 81);
        display(5, 41, "*Date [  /  /    ]*A/C Nos    [       ]*");
        display(6, 41, "**                *Order   [          ]*");
        display(7, 41, "*Folio  [        ]*Invoice [          ]*");
        display(8, 41, "****************************************");
        display(10, 1, "Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note");
        while (true) {
            long inv = acceptNum(7, 50, 8, ih.longv("ih-invoice"));
            ih.setNum("ih-invoice", inv);
            eraseEol(16, 40);
            if (inv == 0) { escapeCode = "Q"; return; }
            ih.setNum("ih-test", 0);
            if (!invoiceFile.read(ih).equals("00")) {
                display(16, 40, "PL187 Invoice Not Found!!!!", 4);
                continue;
            }
            if (ih.str("ih-status").equals("z")) {
                display(16, 1, "PL188 Invoice Details Already Passed To Purchase Ledger!", 4);
                continue;
            }
            break;
        }
        String wsDate = binToDate(ih.longv("ih-date"));
        show(5, 72, ih.str("ih-supplier"));
        purch.set("purch-key", ih.str("ih-supplier"));
        purchaseFile.read(purch);
        show(4, 1, purch.str("purch-name"));
        String[] ad = pieces(purch.str("purch-address"), sys.str("pl-delim"), 3);
        for (int n = 0; n < 4; n++) show(5 + n, 1, pad(ad[n], 36));
        show(5, 48, wsDate);
        show(6, 69, ih.str("ih-order"));
        show(7, 69, ih.str("ih-ref"));
        show(10, 7, ih.str("ih-type"));
        display(16, 1, "Invoice to be deleted (Y/N) - [ ]");
        if (!upper(acceptUpdate(16, 32, 1, "N")).equals("Y")) return;
        invoiceFile.delete(ih);
        Rec l = invLineRec();
        for (int j = 1; j <= ih.intv("ih-lines"); j++) {
            l.setNum("il-invoice", ih.longv("ih-invoice"));
            l.setNum("il-line", j);
            invoiceFile.delete(l);
        }
        del.setNum("del-inv-nos", ih.longv("ih-invoice"));
        del.setNum("del-inv-dat", ih.longv("ih-date"));
        del.set("del-inv-cus", ih.str("ih-supplier"));
        delFile.write(del);
    }
}
