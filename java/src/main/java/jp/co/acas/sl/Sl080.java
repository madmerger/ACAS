package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl080.cbl: 入金入力・消込。 */
public class Sl080 extends SlProgram {
    static final String PROG_NAME = "SL080 (3.01.08)";
    private static final BigDecimal Z = BigDecimal.ZERO;
    private static final int ESC = 2005;

    private Rec sys, sales, oi, oi3;
    private CobFile salesFile, oi3File;
    private String toDay, payCustomer = "";
    private long payDate;
    private int k, transactionType, curLine, curCol;
    private BigDecimal payValue = Z, batchValue = Z;
    /** ws-amount-screen-display（10 桁）と ws-amount-work（9 桁）。受入は先頭 9 桁の集団項目（レガシーの再定義どおり）。 */
    private final char[] scr = "0000000.00".toCharArray();
    private String amtWk = "000000000";

    private static int d(char c) { return c & 0x0F; }
    /** amt-ok（9(7)v99 の表示形式。数字以外の文字は下位 4 ビットを数字として扱う GnuCOBOL の変換に合わせる）。 */
    private BigDecimal amtOk() {
        long v = 0;
        for (char c : amtWk.toCharArray()) v = v * 10 + d(c);
        return BigDecimal.valueOf(v, 2);
    }
    private void setAmtOk(BigDecimal v) { amtWk = z(v.movePointRight(2).longValue(), 9); }
    private void acceptScr() {
        show(curLine, curCol, new String(scr), 3);
        String r = pad(term().accept(curLine, curCol, 9, new String(scr, 0, 9), 0, 3), 9);
        r.getChars(0, 9, scr, 0);
        amtWk = r;
    }
    private void acceptMoney() {
        "0000000.00".getChars(0, 10, scr, 0); amtWk = "000000000";
        acceptScr();
    }
    private void acceptMoney2() {
        amtWk.getChars(0, 9, scr, 0);
        acceptScr();
    }

    @Override
    public void run(Object... args) {
        sys = sys();
        toDay = toDay();
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("s-flag-i") == 1) { maps99(28); maps99(15); return; }
        if (sys.intv("file-status", 19) != 1) { maps99(19); maps99(15); return; }
        sales = salesRec(); oi = oiHeader(); oi3 = oi3Rec();
        salesFile = salesFile(sales); oi3File = oi3File(oi3);
        displayHeads();
        k = 0;
        salesFile.open(CobFile.Mode.IO); oi3File.open(CobFile.Mode.IO);
        newPayment();
        salesFile.close(); oi3File.close();
        displayHeads();
        sys.setNum("first-sl-batch", sys.longv("first-sl-batch") + 1);
        sys.set("oi-3-flag", "Y");
    }

    private void displayHeads() {
        eraseEos(1, 1);
        show(1, 1, PROG_NAME);
        display(1, 33, "Payment Data Entry");
        show(1, 71, fromUk(toDay), 2);
    }

    private void newPayment() {
        int st = 0; // 0 new-payment, 1 date-input, 2 customer-input, 3 value-input, 4 set-batch-item
        while (true) {
            switch (st) {
                case 0 -> {
                    displayHeads();
                    display(4, 41, "****************************************");
                    display(5, 41, "*Date    [  /  /    ]*A/C Nos [       ]*");
                    display(6, 41, "***                                  ***");
                    display(7, 41, "*Value   {          }*Batch [     /   ]*");
                    display(8, 41, "****************************************");
                    st = 1;
                }
                case 1 -> {
                    show(5, 51, fromUk(toDay), 3);
                    String wd = term().accept(5, 51, 10, fromUk(toDay), 0, 3);
                    if (wd.isBlank() || term().crtStatus == ESC) return;
                    long bin = validateDate(wd);
                    if (bin == 0) continue;
                    payDate = bin;
                    toDay = toUk(wd);
                    st = 2;
                }
                case 2 -> {
                    if (k == 999) { display(10, 41, "Batch Closed..It is Full!  "); return; }
                    payCustomer = upper(pad(term().accept(5, 72, 7, " ".repeat(7), 0, 3), 7));
                    show(5, 72, payCustomer, 3);
                    if (payCustomer.isBlank()) { st = 1; continue; }
                    if (term().crtStatus == ESC) return;
                    sales.set("sales-key", payCustomer);
                    salesFile.read(sales);
                    if (invalidKey(salesFile)) continue;
                    String addr = pad(sales.str("sales-address"), 96), delim = pad(sys.str("sl-delim"), 1);
                    show(4, 1, sales.str("sales-name"), 3);
                    int p = 1;
                    for (int n = 0; n < 4; n++) {
                        String line = " ".repeat(36);
                        if (n < 3) {
                            Object[] r = unstring(addr, delim, p, 36);
                            if (r[0] != null) { line = (String) r[0]; p = (int) r[1]; }
                        } else if (p >= 1 && p <= addr.length()) line = pad(addr.substring(p - 1), 36);
                        show(5 + n, 1, line, 3);
                    }
                    display(10, 1, "Current Balance - ");
                    show(10, 19, Num.edit(sales.num("sales-current"), "z(6)9.99cr"), 3);
                    transactionType = 5;
                    st = 3;
                    if (sales.num("sales-unapplied").signum() == 0) continue;
                    show(6, 65, Num.edit(sales.num("sales-unapplied"), "z(6)9.99"), 3);
                    setAmtOk(sales.num("sales-unapplied"));
                    display(6, 45, "Unapplied Balance - ");
                    display(16, 1, "Do you wish to allocate the Unapplied Balance to this account?  [Y]");
                    String reply = "Y";
                    boolean esc = false;
                    do {
                        term().crtStatus = 0;
                        reply = upper(term().accept(16, 66, 1, reply, 0, 6));
                        if (term().crtStatus == ESC) { esc = true; break; }
                    } while (!reply.equals("Y") && !reply.equals("N"));
                    if (esc) { st = 0; continue; }
                    eraseEol(16, 1);
                    if (reply.equals("N")) continue;
                    transactionType = 6;
                    curLine = 7; curCol = 49;
                    boolean back = false;
                    while (true) {
                        acceptMoney2();
                        if (amtOk().signum() == 0) { back = true; break; }
                        if (amtOk().compareTo(sales.num("sales-unapplied")) <= 0) break;
                    }
                    if (back) { st = 0; continue; }
                    sales.setNum("sales-unapplied", sales.num("sales-unapplied").subtract(amtOk()));
                    payValue = amtOk();
                    salesFile.rewrite(sales);
                    st = 4;
                }
                case 3 -> {
                    curLine = 7; curCol = 49;
                    acceptMoney();
                    payValue = amtOk();
                    if (payValue.signum() == 0) { st = 2; continue; }
                    if (term().crtStatus == ESC) return;
                    sys.setNum("s-flag-p", 1);
                    batchValue = batchValue.add(payValue);
                    display(10, 41, "Batch Total - ");
                    show(10, 55, Num.edit(batchValue, "z(6)9.99cr"), 3);
                    st = 4;
                }
                default -> {
                    if (sys.longv("first-sl-batch") == 0) sys.setNum("first-sl-batch", 1);
                    k++;
                    show(7, 70, Num.edit(sys.longv("first-sl-batch"), "z(4)9"), 3);
                    show(7, 76, z(k, 3), 3);
                    paymentAppropriate();
                    eraseScreen(14);
                    display(16, 29, "Enter further payments (Y/N) ? [Y]");
                    while (true) {
                        String r = upper(term().accept(16, 61, 1, "Y", 0, 6));
                        if (r.equals("Y")) break;
                        if (r.equals("N")) return;
                    }
                    st = 0;
                }
            }
        }
    }

    private void eraseScreen(int lin) { eraseEos(lin, 1); }
    private BigDecimal n(String f) { return oi.num(f); }

    private void paymentAppropriate() {
        display(11, 1, "-".repeat(80));
        display(12, 2, "Inv.Nos  --Date--  --Amount--");
        display(12, 33, "Deductable  ---Paid----");
        display(12, 58, "Deduction Taken");
        BigDecimal approp = Z, deductTaken = Z;
        int lin = 14;
        long firstBatch = sys.longv("first-sl-batch");
        oi3.setNum("oi3-invoice", 0);
        oi3.set("oi3-customer", payCustomer);
        oi3File.start(oi3, ">=");
        while (oi3File.readNext(oi3).equals("00")) {
            move(oi3, oi);
            if (oi.intv("oi-type") != 2) continue;
            if (!oi.str("oi-customer").equals(payCustomer)) break;
            if (oi.longv("oi-b-nos") != 0) continue;
            BigDecimal workNet = n("oi-net").add(n("oi-extra")).add(n("oi-carriage")).add(n("oi-vat")).add(n("oi-c-vat")).add(n("oi-discount")).add(n("oi-e-vat"));
            BigDecimal workDed = n("oi-deduct-amt").add(n("oi-deduct-vat")).abs();
            BigDecimal test = workNet.add(workDed);
            if (test.compareTo(n("oi-paid")) == 0 && oi.intv("oi-status") == 0) {
                oi.setNum("oi-date-cleared", payDate); oi.setNum("oi-status", 1);
                move(oi, oi3); oi3File.rewrite(oi3);
                continue;
            }
            if (test.compareTo(n("oi-paid")) <= 0) continue;
            BigDecimal payPaid, work1, work2;
            boolean endLine;
            while (true) {
                // pay-details
                eraseEol(lin, 1);
                show(lin, 1, Num.edit(oi.longv("oi-invoice"), "z(7)9"), 3);
                show(lin, 11, jp.co.acas.sys.Maps04.toDate(oi.longv("oi-date")), 3);
                work1 = workNet.abs(); work2 = workDed;
                long ubin = oi.longv("oi-date") + 1 + oi.longv("oi-deduct-days");
                work1 = work1.add(work2);
                BigDecimal d5 = Z;
                if (ubin > payDate) { work1 = work1.subtract(work2).abs(); d5 = work2; }
                work1 = work1.subtract(n("oi-paid")).abs();
                payPaid = work1;
                show(lin, 21, Num.edit(work1, "z(6)9.99"), 3);
                show(lin, 35, Num.edit(d5, "zz9.99"), 3);
                if (payPaid.signum() == 0) display(lin, 65, "....Fully Paid  "); else eraseEol(lin, 65);
                if (payPaid.compareTo(payValue) > 0) payPaid = payValue.subtract(approp);
                setAmtOk(payPaid.abs());
                curLine = lin; curCol = 46;
                acceptMoney2();
                payPaid = amtOk();
                if (payPaid.signum() == 0) {
                    show(lin, 46, Num.edit(Z, "z(6)9.99cr"), 3);
                    display(lin, 65, "....No Change  ");
                    endLine = false;
                    break;
                }
                oi.setNum("oi-b-nos", firstBatch); oi.setNum("oi-b-item", k);
                // get-agreement
                approp = approp.add(payPaid);
                boolean high = false;
                if (approp.compareTo(payValue) > 0) high = true;
                else if (payPaid.compareTo(work1) == 0) {
                    oi.setNum("oi-date-cleared", payDate); oi.setNum("oi-status", 1);
                    if (ubin > payDate) { oi.setNum("oi-deduct-amt", 0); oi.setNum("oi-deduct-vat", 0); deductTaken = deductTaken.add(work2); }
                } else {
                    if (ubin <= payDate) work1 = work1.subtract(work2).abs();
                    if (payPaid.compareTo(work1) > 0) {
                        work1 = work1.add(work2);
                        if (payPaid.compareTo(work1) > 0) high = true;
                    } else if (payPaid.compareTo(work1) == 0) {
                        show(lin, 65, "Y", 6);
                        if (upper(term().accept(lin, 65, 1, "Y", 0, 6)).equals("Y")) {
                            oi.setNum("oi-date-cleared", payDate); oi.setNum("oi-status", 1);
                            deductTaken = deductTaken.add(work2);
                            oi.setNum("oi-deduct-amt", 0); oi.setNum("oi-deduct-vat", 0);
                        }
                    }
                }
                if (!high) { endLine = true; break; }
                approp = approp.subtract(payPaid);
                display(lin, 65, "Payment Too High");
            }
            if (endLine) {
                oi.setNum("oi-paid", n("oi-paid").add(payPaid));
                oi.setNum("oi-p-c", n("oi-p-c").add(payPaid));
                oi.setNum("oi-cr", payPaid.movePointRight(2).longValue());
                workNet = workNet.add(n("oi-deduct-amt")).add(n("oi-deduct-vat"));
                if (n("oi-paid").compareTo(workNet) == 0) { oi.setNum("oi-date-cleared", payDate); oi.setNum("oi-status", 1); }
                move(oi, oi3); oi3File.rewrite(oi3);
            }
            lin++;
            if (lin > 23) lin = 14;
            if (approp.compareTo(payValue) >= 0) break;
        }
        // main-end
        for (String f : new String[] {"oi-extra", "oi-carriage", "oi-vat", "oi-discount", "oi-e-vat", "oi-c-vat", "oi-status", "oi-cr", "oi-days",
            "oi-deduct-vat", "oi-deduct-days", "oi-p-c"}) oi.setNum(f, 0);
        for (String f : new String[] {"oi-description", "oi-applied", "oi-unapl", "oi-hold-flag"}) oi.set(f, " ");
        oi.set("oi-customer", payCustomer);
        oi.setNum("oi-date", payDate);
        oi.setNum("oi-type", transactionType);
        oi.setNum("oi-paid", payValue);
        oi.setNum("oi-net", approp);
        oi.setNum("oi-deduct-amt", deductTaken);
        oi.setNum("oi-b-nos", firstBatch); oi.setNum("oi-b-item", k);
        oi.setNum("oi-invoice", firstBatch * 1000 + k);
        move(oi, oi3);
        oi3File.write(oi3);
    }
}
