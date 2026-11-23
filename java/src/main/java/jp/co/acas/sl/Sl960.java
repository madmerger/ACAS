package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps09;

/** sl960.cbl: 請求入力中の新規顧客簡易登録。 */
public class Sl960 extends SlProgram {
    static final String PROG_NAME = "SL960 (3.01.03)";

    private Rec sys, sales, deliv;
    private CobFile salesFile, delivFile;
    private Scr display02;
    private String escapeCode = " ", lateCharg = " ", dunLetter = " ";
    private int z;

    @Override
    public void run(Object... args) {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        sales = salesRec(); deliv = deliveryRec();
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv);
        display02 = new Scr()
            .value(4, 6, "Customer Nos : [").from(4, 28, 1, () -> " ").from(4, 29, 1, () -> " ").from(4, 31, 15, () -> "Check Digit { }")
            .value(6, 6, "Customer Name: [").using(6, 22, 30, () -> sales.str("sales-name"), v -> sales.set("sales-name", v)).value(6, 52, "]")
            .value(7, 15, "Addr: [").using(7, 22, 48, () -> sales.str("sales-addr1"), v -> sales.set("sales-addr1", v)).value(7, 70, "]")
            .value(8, 21, "[").using(8, 22, 48, () -> sales.str("sales-addr2"), v -> sales.set("sales-addr2", v)).value(8, 70, "]")
            .value(9, 6, "Delivery name: [").using(9, 22, 30, () -> deliv.str("deliv-name"), v -> deliv.set("deliv-name", v)).value(9, 52, "]")
            .value(10, 15, "Addr: [").using(10, 22, 48, () -> deliv.str("deliv-addr1"), v -> deliv.set("deliv-addr1", v)).value(10, 70, "]")
            .value(11, 21, "[").using(11, 22, 48, () -> deliv.str("deliv-addr2"), v -> deliv.set("deliv-addr2", v)).value(11, 70, "]")
            .value(13, 6, "Telephone    : [").using(13, 22, 13, () -> sales.str("sales-phone"), v -> sales.set("sales-phone", v)).value(13, 35, "]")
            .value(13, 37, "Ext: [").using(13, 43, 4, () -> sales.str("sales-ext"), v -> sales.set("sales-ext", v)).value(13, 47, "]")
            .value(13, 50, "Fax : [").using(13, 57, 13, () -> sales.str("sales-fax"), v -> sales.set("sales-fax", v)).value(13, 70, "]")
            .value(14, 6, "Email Sales  : [").using(14, 22, 30, () -> sales.str("sales-email"), v -> sales.set("sales-email", v)).value(14, 52, "]")
            .value(15, 6, "Late charges : [").using(15, 22, 1, () -> lateCharg, v -> lateCharg = v).value(15, 23, "]")
            .value(15, 31, "Minimum balance before late charge : [")
            .usingNum(15, 69, 4, () -> z(sales.longv("sales-late-min"), 4), v -> sales.setNum("sales-late-min", intOf(v))).value(15, 73, "]")
            .value(16, 6, "Late letters : [").using(16, 22, 1, () -> dunLetter, v -> dunLetter = v).value(16, 23, "]")
            .value(16, 31, "Maximum late charge").value(16, 66, ": [")
            .usingNum(16, 69, 4, () -> z(sales.longv("sales-late-max"), 4), v -> sales.setNum("sales-late-max", intOf(v))).value(16, 73, "]")
            .value(17, 6, "Credit period: [").usingNum(17, 22, 2, () -> z(sales.longv("sales-credit"), 2), v -> sales.setNum("sales-credit", intOf(v))).value(17, 24, "]")
            .value(18, 6, "Credit limit : [").usingNum(18, 22, 7, () -> z(sales.longv("sales-limit"), 7), v -> sales.setNum("sales-limit", intOf(v)))
            .value(18, 29, "] Discount : [")
            .usingNum(18, 43, 4, () -> z(sales.num("sales-discount").movePointRight(2).longValue(), 4),
                v -> sales.setNum("sales-discount", java.math.BigDecimal.valueOf(intOf(v), 2)))
            .value(18, 47, "]")
            .value(19, 6, "Unapplied Bal: {").value(19, 34, "}").value(19, 61, "*******************")
            .value(20, 6, "Current Bal  : {").value(20, 34, "}").value(20, 61, "* Escape Code [")
            .using(20, 76, 1, () -> escapeCode, v -> escapeCode = v).value(20, 77, "] *")
            .value(21, 6, "Last invoice : {").value(21, 30, "}").value(21, 61, "* <B> = Back      *")
            .value(22, 6, "Last payment : {").value(22, 30, "}").value(22, 61, "* <S> = Save      *")
            .value(23, 61, "* <Q> = Quit      *")
            .value(24, 61, "*******************");
        clearScreen();
        show(1, 1, PROG_NAME);
        salesFile.open(CobFile.Mode.IO);
        delivFile.open(CobFile.Mode.IO);
        if (!delivFile.status.equals("00")) {
            delivFile.close(); delivFile.open(CobFile.Mode.OUTPUT); delivFile.close(); delivFile.open(CobFile.Mode.IO);
        }
        eraseEos(3, 1);
        setupCustomers();
        salesFile.close(); delivFile.close();
    }

    private void setupCustomers() {
        String code;
        input:
        while (true) {
            display02.display();
            String nos = " ".repeat(6);
            while (true) {
                nos = acceptUpdate(4, 22, 6, nos);
                if (nos.isBlank()) return;
                nos = upper(nos);
                show(4, 22, nos);
                eraseEol(23, 1);
                int cd = Maps09.checkDigit(nos);
                if (cd < 0) continue input;
                show(4, 44, String.valueOf(cd));
                code = nos + cd;
                sales.set("sales-key", code);
                salesFile.read(sales);
                if (invalidKey(salesFile)) break input;
                maps99(5);
            }
        }
        initialize(sales); initialize(deliv);
        sales.set("sales-key", code);
        sales.setNum("sales-late", sys.longv("sl-charges"));
        sales.setNum("sales-dunning", sys.longv("sl-dunning"));
        sales.setNum("sales-credit", sys.longv("sl-credit"));
        sales.setNum("sales-discount", sys.num("sl-disc"));
        sales.setNum("sales-late-min", sys.longv("sl-min"));
        sales.setNum("sales-late-max", sys.longv("sl-max"));
        sales.setNum("sales-limit", sys.longv("sl-limit"));
        sales.setNum("sales-create-date", sys.longv("run-date"));
        sales.setNum("sales-status", 1);
        do {
            customerData();
            escapeCode = "S";
            show(20, 76, escapeCode, 6);
            do { escapeCode = upper(term().accept(20, 76, 1, escapeCode, 0, 6)); }
            while (!escapeCode.equals("B") && !escapeCode.equals("S") && !escapeCode.equals("Q"));
        } while (escapeCode.equals("B"));
        if (escapeCode.equals("Q")) return;
        salesFile.write(sales);
        if (sales.intv("delivery-tag") != 0) {
            deliv.set("deliv-key-type", "D"); deliv.set("deliv-sales-key", sales.str("sales-key"));
            delivFile.write(deliv);
        }
    }

    private void customerData() {
        while (true) {
            int errorFlag = 0;
            display02.accept();
            if (!validAddress(sales.str("sales-address"))) { display(7, 71, "Addr Err", 4); errorFlag = 1; }
            else show(7, 71, " ".repeat(10));
            if (deliv.str("deliv-name").isBlank()) sales.setNum("delivery-tag", 0);
            else {
                if (!validAddress(deliv.str("deliv-address"))) { display(10, 71, "Addr Err", 4); errorFlag = 1; }
                else show(10, 71, " ".repeat(10));
                sales.setNum("delivery-tag", 1);
            }
            if (validResponse(lateCharg)) { sales.setNum("sales-late", z); show(15, 24, " ".repeat(7)); }
            else { display(15, 24, "Error", 4); errorFlag = 1; }
            if (validResponse(dunLetter)) { show(16, 24, " ".repeat(7)); sales.setNum("sales-dunning", z); }
            else { display(16, 24, "Error", 4); continue; }
            if (errorFlag == 0) return;
        }
    }

    private boolean validAddress(String addr) {
        String delim = pad(sys.str("sl-delim"), 1);
        String t = pad(addr, 92).substring(0, 92);
        int a = 0;
        for (int p = t.indexOf(delim); p >= 0; p = t.indexOf(delim, p + 1)) a++;
        boolean truth = a <= 4 && a >= 1;
        int first = t.indexOf(delim);
        if ((first < 0 ? t.length() : first) > 30) truth = false;
        return truth;
    }

    private boolean validResponse(String reply) {
        String r = upper(reply);
        if (r.equals("Y")) z = 1;
        else if (r.equals("N")) z = 0;
        else { maps99(18); return false; }
        eraseEol(24, 1);
        return true;
    }
}
