package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl085.cbl: 入金修正（入金の取消・充当の戻し）。 */
public class Sl085 extends SlProgram {
    static final String PROG_NAME = "SL085 (3.01.06)";
    static final String SL003 = "SL003 Hit Return To Continue";
    static final String SL140 = "SL140 Not Yet Supporting Corrections";
    static final String SL141 = "SL141 Amount Approp Or Deduct Amt Not Zero";
    private static final BigDecimal Z = BigDecimal.ZERO;

    private Rec sys, sales, oi, oi3;
    private CobFile salesFile, oi3File;
    private int k, displayN, transactionType;
    private String payCustomer = "", saveCustomer = "";
    private BigDecimal payValue = Z, holdPay = Z, approp = Z, siDeduct = Z;
    private String amtWk = "000000000";
    private char tail = '0';

    private static BigDecimal digits(String s) {
        long v = 0;
        for (char c : s.toCharArray()) v = v * 10 + (c & 0x0F);
        return BigDecimal.valueOf(v, 2);
    }
    /** accept-money2: 表示 10 桁（9(7) "." v99 の再定義）に対し先頭 9 桁の集団を受け入れる（レガシーどおり）。 */
    private BigDecimal acceptMoney2(int line, int col, BigDecimal cur) {
        amtWk = z(cur.abs().movePointRight(2).longValue(), 9);
        show(line, col, amtWk + tail, 3);
        amtWk = pad(term().accept(line, col, 9, amtWk, 0, 3), 9);
        return digits(amtWk);
    }
    /** accept-money: 表示 "000.00"（6 桁）に対し先頭 5 桁を受け入れる。 */
    private BigDecimal acceptMoney(int line, int col) {
        show(line, col, "000.00", 2);
        return digits(pad(term().accept(line, col, 5, "000.0", 0, 2), 5));
    }

    @Override
    public void run(Object... args) {
        sys = sys();
        if (sys.intv("s-flag-p") == 0) { maps99(30); maps99(15); return; }
        term().exceptionsEnabled = true; term().escEnabled = true;
        sales = salesRec(); oi = oiHeader(); oi3 = oi3Rec();
        salesFile = salesFile(sales); oi3File = oi3File(oi3);
        displayHeads();
        k = 0;
        salesFile.open(CobFile.Mode.IO); oi3File.open(CobFile.Mode.IO);
        newPayment();
        salesFile.close(); oi3File.close();
        sys.set("oi-3-flag", "Y");
        displayHeads();
    }

    private void displayHeads() {
        eraseEos(1, 1);
        display(2, 2, PROG_NAME);
        display(2, 33, "Payment Data Amend");
        show(2, 71, fromUk(toDay()), 2);
    }

    private void newPayment() {
        newPayment:
        while (true) {
            displayHeads();
            display(4, 41, "****************************************");
            display(5, 41, "*Date    [  /  /    ]                  *");
            display(6, 41, "*A/C Nos    [       ]                ***");
            display(7, 41, "*Value   {          }*Batch [     /   ]*");
            display(8, 41, "****************************************");
            show(5, 51, fromUk(toDay()), 3);
            getBatch:
            while (true) {
                saveCustomer = upper(pad(term().accept(6, 54, 7, null, 0, 3), 7));
                show(6, 54, saveCustomer, 3);
                if (saveCustomer.isBlank()) return;
                while (true) {
                    // customer-input
                    displayN = intOf(term().accept(7, 70, 5, "00000", 0, 3));
                    if (displayN == 0) return;
                    k = intOf(term().accept(7, 76, 3, z(k, 3), 0, 3));
                    if (k == 0) continue;
                    long saveInvoice = displayN * 1000L + k;
                    oi3.set("oi3-customer", saveCustomer);
                    oi3.setNum("oi3-invoice", saveInvoice);
                    oi3File.start(oi3, ">=");
                    boolean found = false;
                    while (oi3File.readNext(oi3).equals("00")) {
                        move(oi3, oi);
                        if (!oi.str("oi-customer").equals(saveCustomer) || oi.longv("oi-invoice") != saveInvoice) break;
                        int t = oi.intv("oi-type");
                        if (oi.longv("oi-b-nos") != displayN || oi.longv("oi-b-item") != k || (t != 5 && t != 6)) continue;
                        found = true;
                        break;
                    }
                    if (!found) continue getBatch;
                    break getBatch;
                }
            }
            if (oi.intv("oi-type") == 6) display(6, 45, "Warning Unapplied Balance Journal");
            transactionType = oi.intv("oi-type");
            payCustomer = oi.str("oi-customer");
            payValue = oi.num("oi-paid"); holdPay = payValue;
            approp = oi.num("oi-net");
            show(5, 72, payCustomer, 2);
            sales.set("sales-key", payCustomer);
            salesFile.read(sales);
            String addr = pad(sales.str("sales-address"), 96), delim = pad(sys.str("sl-delim"), 1);
            show(4, 1, sales.str("sales-name"), 2);
            int p = 1;
            for (int n = 0; n < 4; n++) {
                String line = " ".repeat(36);
                if (n < 3) {
                    Object[] r = unstring(addr, delim, p, 36);
                    if (r[0] != null) { line = (String) r[0]; p = (int) r[1]; }
                } else if (p >= 1 && p <= addr.length()) line = pad(addr.substring(p - 1), 36);
                show(5 + n, 1, line, 2);
            }
            display(10, 1, "Current Balance - ");
            show(10, 19, Num.edit(sales.num("sales-current"), "z(5)9.99cr"), 2);
            while (true) {
                // value-input
                payValue = acceptMoney2(7, 51, payValue);
                if (payValue.compareTo(oi.num("oi-paid")) == 0) {
                    display(12, 1, "Confirm No Action? i.e. Request Cancelled (Y/N)..[ ]");
                    String r;
                    do { r = upper(term().accept(12, 51, 1, null, 0, 6)); } while (!r.equals("Y") && !r.equals("N"));
                    if (r.equals("Y")) continue newPayment;
                }
                if (payValue.signum() == 0) break;
                display(12, 1, SL140); eraseEol(12, 37);
            }
            oi3File.delete(oi3);
            if (oi.num("oi-net").signum() != 0) {
                siDeduct = oi.num("oi-deduct-amt");
                paymentAppropriate();
            }
            if (transactionType == 6) {
                sales.setNum("sales-unapplied", sales.num("sales-unapplied").add(holdPay));
                salesFile.rewrite(sales);
            }
            eraseEos(14, 1);
            display(16, 29, "Make Further Corrections (Y/N) ? [Y]");
            while (true) {
                String r = upper(term().accept(16, 63, 1, "Y", 0, 6));
                if (r.equals("Y")) break;
                if (r.equals("N")) return;
            }
        }
    }

    private void paymentAppropriate() {
        display(11, 1, "Reversing Please Wait");
        oi3.set("oi3-customer", saveCustomer);
        oi3.setNum("oi3-invoice", 0);
        oi3File.start(oi3, ">=");
        while (oi3File.readNext(oi3).equals("00")) {
            move(oi3, oi);
            if (oi.intv("oi-type") != 2) continue;
            if (!oi.str("oi-customer").equals(payCustomer)) break;
            if (oi.longv("oi-b-nos") != displayN || oi.longv("oi-b-item") != k) continue;
            BigDecimal work1 = BigDecimal.valueOf(oi.longv("oi-cr"), 2).abs();
            oi.setNum("oi-paid", oi.num("oi-paid").subtract(work1));
            oi.setNum("oi-p-c", oi.num("oi-p-c").subtract(work1));
            approp = approp.subtract(work1);
            for (String f : new String[] {"oi-b-nos", "oi-b-item", "oi-cr", "oi-status"}) oi.setNum(f, 0);
            if (siDeduct.signum() != 0 && oi.num("oi-deduct-amt").signum() == 0) {
                while (true) {
                    // get-deduct
                    display(13, 1, "For Invoice No. ");
                    show(13, 17, Num.edit(oi.longv("oi-invoice"), "z(7)9"), 2);
                    display(12, 1, "Enter Deduct Amount - [      ]");
                    display(12, 40, "Amount Available = ");
                    show(12, 59, Num.edit(siDeduct, "-zz9.99"), 3);
                    oi.setNum("oi-deduct-amt", acceptMoney(12, 24));
                    if (oi.num("oi-deduct-amt").compareTo(siDeduct) > 0) continue;
                    siDeduct = siDeduct.subtract(oi.num("oi-deduct-amt"));
                    break;
                }
                eraseEol(12, 1); eraseEol(13, 1);
            }
            move(oi, oi3); oi3File.rewrite(oi3);
            if (approp.signum() == 0 && siDeduct.signum() == 0) break;
        }
        if (approp.signum() != 0 || siDeduct.signum() != 0) {
            display(12, 1, SL141, 4);
            show(13, 4, Num.edit(approp, "-(5)9.99"), 2);
            show(13, 17, Num.edit(siDeduct, "z(5)9.99cr"), 2);
            display(13, 31, SL003, 4);
            term().accept(13, 54, 1, null, 0, 2);
        }
    }
}
