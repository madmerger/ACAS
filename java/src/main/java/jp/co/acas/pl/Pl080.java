package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;

/** pl080.cbl: 支払データ入力。 */
public class Pl080 extends PlBase {
    static final String PROG_NAME = "PL080 (3.01.04)";
    protected Rec purch, oi;
    protected CobFile purchaseFile, oi5;
    private int k, lin;
    private String payCustomer = "";
    private long payDate;
    private BigDecimal payValue = BigDecimal.ZERO, batchValue = BigDecimal.ZERO, approp = BigDecimal.ZERO,
            deductTaken = BigDecimal.ZERO;
    private int transactionType;

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("p-flag-i") == 1) {
            maps99(28);
            maps99(15);
            return;
        }
        displayHeads();
        k = 0;
        purch = purchRec(); oi = oiRec();
        purchaseFile = purchaseFile(purch); oi5 = oi5File();
        purchaseFile.open(Mode.IO); oi5.open(Mode.IO);
        while (newPayment()) { }
        purchaseFile.close(); oi5.close();
        displayHeads();
        sys.setNum("bl-next-batch", sys.longv("bl-next-batch") + 1);
        sys.set("oi-5-flag", "Y");
    }

    private void displayHeads() {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 33, "Payment Data Entry");
        show(1, 71, fromUk(toDay()), 2);
    }

    private boolean esc() { return crtStatus() == 2005; }

    static byte[] oi5Bytes(Rec oi) {
        byte[] b = new byte[109];
        java.util.Arrays.fill(b, (byte) ' ');
        System.arraycopy(oi.bytes(), 0, b, 0, Math.min(109, oi.bytes().length));
        return b;
    }

    /** new-payment。true = 次の支払へ（go to new-payment）、false = 終了。 */
    private boolean newPayment() {
        displayHeads();
        display(4, 41, "****************************************");
        display(5, 41, "*Date  [  /  /    ]*A/C Nos   [       ]*");
        display(6, 41, "***                                  ***");
        display(7, 41, "*Value [          ]*Batch   [     /   ]*");
        display(8, 41, "****************************************");
        boolean dateInput = true;
        while (true) {
            if (dateInput) {
                String d = fromUk(toDay());
                show(5, 49, d, 3);
                d = acceptUpdate(5, 49, 10, d);
                if (d.isBlank() || esc()) return false;
                payDate = validateDate(d);
                if (payDate == 0) continue;
                dateInput = false;
            }
            // customer-input
            if (k == 999) {
                display(10, 41, "Batch Closed........Full!  ");
                return false;
            }
            payCustomer = upper(pad(accept(5, 72, 7), 7));
            show(5, 72, payCustomer, 3);
            if (payCustomer.isBlank()) { dateInput = true; continue; }
            if (esc()) return false;
            purch.set("purch-key", payCustomer);
            if (!purchaseFile.read(purch).equals("00")) continue;
            show(4, 1, purch.str("purch-name"), 3);
            String[] ad = pieces(purch.str("purch-address"), sys.str("pl-delim"), 3);
            for (int i = 0; i < 4; i++) show(5 + i, 1, pad(ad[i], 36), 3);
            display(10, 1, "Current Balance - ");
            show(10, 19, Num.edit(purch.num("purch-current"), "z(6)9.99cr"), 3);
            transactionType = 5;
            if (purch.num("purch-unapplied").signum() != 0) {
                BigDecimal amt = purch.num("purch-unapplied");
                display(6, 45, "Unapplied Balance - ");
                show(6, 65, Num.edit(amt, "z(6)9.99"), 3);
                display(16, 1, "Do you wish to allocate the unapplied Balance to this account?  [Y]");
                String reply = "Y";
                do {
                    term().crtStatus = 0;
                    reply = upper(acceptUpdate(16, 66, 1, reply));
                    if (esc()) return true;
                } while (!reply.equals("Y") && !reply.equals("N"));
                eraseEol(16, 1);
                if (reply.equals("Y")) {
                    transactionType = 6;
                    do {
                        amt = acceptMoney(7, 49, 7, amt);
                        if (amt.signum() == 0) return true;
                    } while (amt.compareTo(purch.num("purch-unapplied")) > 0);
                    purch.sub("purch-unapplied", amt);
                    payValue = amt;
                    purchaseFile.rewrite(purch);
                    break;
                }
            }
            // value-input（accept-money は 2 回 ACCEPT する）
            BigDecimal amt = acceptMoney(7, 49, 7, BigDecimal.ZERO);
            amt = acceptMoney(7, 49, 7, amt);
            payValue = amt;
            if (payValue.signum() == 0) continue;
            if (esc()) return false;
            sys.setNum("p-flag-p", 1);
            batchValue = batchValue.add(payValue);
            display(10, 41, "Batch Total - ");
            show(10, 55, Num.edit(batchValue, "z(6)9.99cr"), 3);
            break;
        }
        // set-batch-item
        if (sys.longv("bl-next-batch") == 0) sys.setNum("bl-next-batch", 1);
        k++;
        show(7, 70, Num.edit(sys.longv("bl-next-batch"), "z(4)9"), 2);
        show(7, 76, Num.z9(k, 3), 2);
        paymentAppropriate();
        eraseEos(14, 1);
        display(16, 29, "Enter further payments? (Y/N)  [Y]");
        while (true) {
            String reply = upper(acceptUpdate(16, 61, 1, "Y"));
            if (reply.equals("Y")) return true;
            if (reply.equals("N")) return false;
        }
    }

    private void paymentAppropriate() {
        show(11, 1, "-".repeat(80), 2);
        display(12, 1, "Folio No  --Date--  --Amount--");
        display(12, 33, "Deductable  ---Paid----");
        display(12, 58, "Deduction taken");
        approp = BigDecimal.ZERO;
        lin = 14;
        Rec key = oiRec();
        key.set("oi-supplier", payCustomer);
        key.setNum("oi-invoice", 0);
        oi5.start(key, ">=");
        long batchNo = sys.longv("bl-next-batch");
        while (true) {
            if (!oi5.readNext(oi).equals("00")) break;
            if (oi.intv("oi-type") != 2) continue;
            if (!oi.str("oi-supplier").equals(payCustomer)) break;
            if (oi.longv("oi-b-nos") != 0) continue;
            BigDecimal workNet = oi.num("oi-net").add(oi.num("oi-carriage")).add(oi.num("oi-vat")).add(oi.num("oi-c-vat"));
            BigDecimal workDed = oi.num("oi-deduct-amt");
            if (workNet.compareTo(oi.num("oi-paid")) == 0 && oi.intv("oi-status") == 0) {
                oi.setNum("oi-date-cleared", payDate);
                oi.setNum("oi-status", 1);
                oi5.rewrite(oi5Bytes(oi));
                continue;
            }
            if (workNet.compareTo(oi.num("oi-paid")) <= 0) continue;
            boolean stop = false;
            while (true) {
                // pay-details
                eraseEol(lin, 1);
                show(lin, 1, Num.edit(oi.longv("oi-invoice"), "z(7)9"), 3);
                long uBin = oi.longv("oi-date");
                show(lin, 11, fromUk(Maps04.toDate(uBin)), 3);
                BigDecimal work1 = workNet, work2 = workDed;
                uBin += 1 + oi.intv("oi-deduct-days");
                String d5;
                if (uBin > payDate) { work1 = work1.subtract(work2).abs(); d5 = Num.edit(work2, "zz9.99"); }
                else d5 = Num.edit(BigDecimal.ZERO, "zz9.99");
                work1 = work1.subtract(oi.num("oi-paid")).abs();
                BigDecimal payPaid = work1;
                show(lin, 21, Num.edit(work1, "z(6)9.99"), 3);
                show(lin, 35, d5, 3);
                if (payPaid.signum() == 0) display(lin, 65, "....Fully Paid  "); else eraseEol(lin, 65);
                if (payPaid.compareTo(payValue) > 0) payPaid = payValue.subtract(approp);
                payPaid = acceptMoney(lin, 46, 7, payPaid.abs());
                if (payPaid.signum() == 0) {
                    show(lin, 46, Num.edit(BigDecimal.ZERO, "z(6)9.99cr"), 3);
                    display(lin, 65, "....no change  ");
                } else {
                    oi.setNum("oi-b-nos", batchNo);
                    oi.setNum("oi-b-item", k);
                    approp = approp.add(payPaid);
                    boolean tooHigh = approp.compareTo(payValue) > 0;
                    if (!tooHigh) {
                        if (payPaid.compareTo(work1) == 0) {
                            oi.setNum("oi-date-cleared", payDate);
                            oi.setNum("oi-status", 1);
                            if (uBin > payDate) takeDeduction(work2);
                        } else {
                            if (uBin <= payDate) work1 = work1.subtract(work2).abs();
                            if (payPaid.compareTo(work1) > 0) tooHigh = true;
                            else if (payPaid.compareTo(work1) == 0) {
                                show(lin, 65, "Y", 6);
                                if (upper(acceptUpdate(lin, 65, 1, "Y")).equals("Y")) {
                                    oi.setNum("oi-date-cleared", payDate);
                                    oi.setNum("oi-status", 1);
                                    takeDeduction(work2);
                                }
                            }
                        }
                    }
                    if (tooHigh) {
                        approp = approp.subtract(payPaid);
                        display(lin, 65, "Payment Too High", 4);
                        continue;
                    }
                    // end-line
                    oi.add("oi-paid", payPaid);
                    oi.add("oi-p-c", payPaid);
                    oi.setNum("oi-cr", payPaid.movePointRight(2).longValue());
                    workNet = workNet.subtract(oi.num("oi-deduct-amt"));
                    if (oi.num("oi-paid").compareTo(workNet) == 0) {
                        oi.setNum("oi-date-cleared", payDate);
                        oi.setNum("oi-status", 1);
                    }
                    oi5.rewrite(oi5Bytes(oi));
                }
                lin++;
                if (lin > 23) lin = 14;
                if (approp.compareTo(payValue) >= 0) stop = true;
                break;
            }
            if (stop) break;
        }
        for (String f : new String[]{"oi-carriage", "oi-vat", "oi-c-vat", "oi-status", "oi-cr", "oi-days", "oi-deduct-vat",
                "oi-discount", "oi-deduct-days", "oi-p-c"}) oi.setNum(f, 0);
        oi.set("oi-applied", " ");
        oi.set("oi-supplier", payCustomer);
        oi.setNum("oi-date", payDate);
        oi.setNum("oi-type", transactionType);
        oi.setNum("oi-paid", payValue);
        oi.setNum("oi-approp", approp);
        oi.setNum("oi-deduct-amt", deductTaken);
        oi.setNum("oi-b-nos", batchNo);
        oi.setNum("oi-b-item", k);
        oi.setNum("oi-invoice", batchNo * 1000 + k);
        oi5.write(oi5Bytes(oi));
        approp = BigDecimal.ZERO; deductTaken = BigDecimal.ZERO;
    }

    private void takeDeduction(BigDecimal work2) {
        oi.sub("oi-net", oi.num("oi-deduct-amt"));
        oi.setNum("oi-deduct-amt", 0);
        deductTaken = deductTaken.add(work2);
    }
}
