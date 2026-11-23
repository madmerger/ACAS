package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;
import jp.co.acas.sys.Maps09;

import java.math.BigDecimal;
import java.util.List;

/** pl025.cbl: 請求書入力中の仕入先新規登録（pl020 / pl030 から呼ばれる）。 */
public class Pl025 extends PlBase {
    private Rec purch, deliv;
    private CobFile purchaseFile, deliveryFile;
    private String notes1 = "", notes2 = "", d2402 = " ", d2403 = " ";

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        purch = purchRec(); deliv = delivRec();
        purchaseFile = purchaseFile(purch); deliveryFile = deliveryFile(deliv);
        purchaseFile.open(Mode.IO);
        if (!deliveryFile.open(Mode.IO).equals("00")) {
            deliveryFile.close();
            deliveryFile.open(Mode.OUTPUT);
            deliveryFile.close();
            deliveryFile.open(Mode.IO);
        }
        eraseEos(3, 1);
        setupSuppliers();
        purchaseFile.close(); deliveryFile.close();
    }

    private static String disc4(BigDecimal v) { return Num.z9(v.movePointRight(2).longValue() % 10000, 4); }

    private void display02() {
        display(4, 6, "Supplier Nos : [");
        show(4, 28, d2402, 2);
        show(4, 29, d2403, 2);
        show(4, 31, pad("", 15), 2);
        display(6, 6, "Supplier Name: [");
        show(6, 22, purch.str("purch-name"), 2);
        display(6, 52, "]");
        display(7, 15, "Addr: [");
        show(7, 22, purch.str("purch-addr1"), 2);
        display(7, 70, "]");
        display(8, 21, "[");
        show(8, 22, purch.str("purch-addr2"), 2);
        display(8, 70, "]");
        display(9, 6, "Suppliers Bank Details");
        display(10, 8, "Sort Code  : [");
        show(10, 22, Num.z9(purch.longv("purch-sortcode"), 6), 2);
        display(10, 28, "]");
        display(11, 8, "Account No : [");
        show(11, 22, Num.z9(purch.longv("purch-accountno"), 8), 2);
        display(11, 30, "]");
        display(12, 6, "Supplier Note: [");
        show(12, 22, pad(notes1, 48), 2);
        display(12, 70, "]");
        display(13, 21, "[");
        show(13, 22, pad(notes2, 48), 2);
        display(13, 70, "]");
        display(14, 6, "Telephone    : [");
        show(14, 22, purch.str("purch-phone"), 2);
        display(14, 35, "]");
        display(14, 37, "Ext: [");
        show(14, 43, purch.str("purch-ext"), 2);
        display(14, 47, "]");
        display(14, 50, "Fax : [");
        show(14, 57, purch.str("purch-fax"), 2);
        display(14, 70, "]");
        display(15, 6, "Email Sales  : [");
        show(15, 22, purch.str("purch-email"), 2);
        display(15, 52, "]");
        display(18, 6, "Credit Period: [");
        show(18, 22, Num.z9(purch.intv("purch-credit"), 2), 2);
        display(18, 24, "]");
        display(19, 6, "Credit limit : [");
        show(19, 22, Num.z9(purch.longv("purch-limit"), 7), 2);
        display(19, 29, "] Discount : [");
        show(19, 43, disc4(purch.num("purch-discount")), 2);
        display(19, 47, "]");
        display(19, 61, "*******************");
        display(20, 6, "Unapplied Bal: {");
        display(20, 34, "}");
        display(20, 61, "* Escape Code [");
        display(20, 77, "] *");
        display(21, 6, "Current Bal  : {");
        display(21, 34, "}");
        display(21, 61, "* <B> = Back      *");
        display(22, 6, "Last invoice : {");
        display(22, 30, "}");
        display(22, 61, "* <S> = Save      *");
        display(23, 6, "Last payment : {");
        display(23, 30, "}");
        display(23, 61, "* <Q> = Quit      *");
        display(24, 61, "*******************");
    }

    private void setupSuppliers() {
        notes1 = ""; notes2 = ""; d2403 = " ";
        d2402 = "]";
        display02();
        String code;
        while (true) {
            String nos = accept(4, 22, 6);
            if (nos.isBlank()) return;
            nos = upper(nos);
            show(4, 22, nos);
            int cd = Maps09.checkDigit(nos);
            if (cd < 0) continue;
            show(4, 44, String.valueOf(cd));
            d2403 = "]";
            code = nos + cd;
            purch.set("purch-key", code);
            if (!purchaseFile.read(purch).equals("00")) break;
            maps99(22);
        }
        initialize(purch); initialize(deliv);
        purch.setNum("purch-create-date", sys.longv("run-date"));
        purch.setNum("purch-status", 1);
        purch.set("purch-key", code);
        purch.setNum("purch-credit", sys.intv("age-to-pay"));
        String esc;
        do {
            supplierData();
            esc = "S";
            show(20, 76, esc, 6);
            do { esc = upper(acceptUpdate(20, 76, 1, esc)); } while (!esc.equals("B") && !esc.equals("S") && !esc.equals("Q"));
        } while (esc.equals("B"));
        if (esc.equals("Q")) return;
        purchaseFile.write(purch);
        if (purch.intv("purch-notes-tag") != 0) {
            deliv.set("deliv-key-type", "D");
            deliv.set("deliv-purchase-key", purch.str("purch-key"));
            deliv.set("deliv-name", "");
            deliv.set("deliv-addr1", notes1); deliv.set("deliv-addr2", notes2);
            deliveryFile.write(deliv);
        }
    }

    private void supplierData() {
        while (true) {
            Terminal.Field name = afield(6, 22, 30, purch.str("purch-name")),
                    a1 = afield(7, 22, 48, purch.str("purch-addr1")), a2 = afield(8, 22, 48, purch.str("purch-addr2")),
                    sort = field(10, 22, 6, Num.z9(purch.longv("purch-sortcode"), 6)),
                    acc = field(11, 22, 8, Num.z9(purch.longv("purch-accountno"), 8)),
                    n1 = afield(12, 22, 48, notes1), n2 = afield(13, 22, 48, notes2),
                    phone = afield(14, 22, 13, purch.str("purch-phone")), ext = afield(14, 43, 4, purch.str("purch-ext")),
                    fax = afield(14, 57, 13, purch.str("purch-fax")), email = afield(15, 22, 30, purch.str("purch-email")),
                    credit = field(18, 22, 2, Num.z9(purch.intv("purch-credit"), 2)),
                    limit = field(19, 22, 7, Num.z9(purch.longv("purch-limit"), 7)),
                    discount = field(19, 43, 4, disc4(purch.num("purch-discount")));
            acceptScreen(List.of(name, a1, a2, sort, acc, n1, n2, phone, ext, fax, email, credit, limit, discount));
            purch.set("purch-name", aval(name));
            purch.set("purch-addr1", aval(a1)); purch.set("purch-addr2", aval(a2));
            purch.setNum("purch-sortcode", numOf(sort.value));
            purch.setNum("purch-accountno", numOf(acc.value));
            notes1 = aval(n1); notes2 = aval(n2);
            purch.set("purch-phone", aval(phone)); purch.set("purch-ext", aval(ext));
            purch.set("purch-fax", aval(fax)); purch.set("purch-email", aval(email));
            purch.setNum("purch-credit", numOf(credit.value));
            purch.setNum("purch-limit", numOf(limit.value));
            purch.setNum("purch-discount", BigDecimal.valueOf(numOf(discount.value), 2));
            String test = pad(purch.str("purch-address"), 92), d = sys.str("pl-delim");
            int a = 0;
            for (int k = 0; k < test.length(); k++) if (test.startsWith(d, k)) a++;
            int b = test.indexOf(d);
            if (b < 0) b = test.length();
            if (a > 4 || a < 1 || b > 30) { display(7, 71, "Addr Err", 4); continue; }
            eraseEol(7, 71);
            purch.setNum("purch-notes-tag", (notes1 + notes2).isBlank() ? 0 : 1);
            return;
        }
    }
}
