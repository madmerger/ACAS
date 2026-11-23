package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl085.cbl: 支払データ修正（取消）。 */
public class Pl085 extends PlBase {
    static final String PROG_NAME = "PL085 (3.01.04)";
    private Rec purch, oi;
    private CobFile purchaseFile, oi5;
    private int k;
    private long batch;
    private String payCustomer = "";
    private BigDecimal approp = BigDecimal.ZERO, siDeduct = BigDecimal.ZERO;

    @Override
    public void run(Object... args) {
        init();
        if (sys.intv("p-flag-p") == 0) {
            maps99(30);
            maps99(15);
            return;
        }
        term().exceptionsEnabled = true; term().escEnabled = true;
        displayHeads();
        k = 0;
        purch = purchRec(); oi = oiRec();
        purchaseFile = purchaseFile(purch); oi5 = oi5File();
        purchaseFile.open(Mode.IO); oi5.open(Mode.IO);
        while (newPayment()) { }
        purchaseFile.close(); oi5.close();
        sys.set("oi-5-flag", "Y");
        displayHeads();
    }

    private void displayHeads() {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 33, "Payment Data Amend");
        show(1, 71, fromUk(toDay()), 2);
    }

    private boolean newPayment() {
        displayHeads();
        display(4, 41, "****************************************");
        display(5, 41, "*Date  [  /  /    ]*A/C Nos   [       ]*");
        display(6, 41, "***                                  ***");
        display(7, 41, "*Value [          ]*Batch   [     /   ]*");
        display(8, 41, "****************************************");
        show(5, 49, fromUk(toDay()), 3);
        boolean getBatch = true;
        String supplier = "";
        BigDecimal payValue, holdPay;
        int type;
        find:
        while (true) {
            if (getBatch) {
                supplier = upper(pad(acceptUpdate(5, 72, 7, pad("", 7)), 7));
                show(5, 72, supplier, 3);
                if (supplier.isBlank()) return false;
            }
            getBatch = true;
            batch = acceptNum(7, 70, 5, 0);
            if (batch == 0) return false;
            k = (int) acceptNum(7, 76, 3, k);
            if (k == 0) { getBatch = false; continue; }
            long invoice = batch * 1000 + k;
            Rec key = oiRec();
            key.set("oi-supplier", supplier);
            key.setNum("oi-invoice", invoice);
            oi5.start(key, ">=");
            while (true) {
                if (!oi5.readNext(oi).equals("00")) continue find;
                if (!oi.str("oi-supplier").equals(supplier) || oi.longv("oi-invoice") != invoice) continue find;
                type = oi.intv("oi-type");
                if (oi.longv("oi-b-nos") != batch || oi.intv("oi-b-item") != k || (type != 5 && type != 6)) continue;
                break find;
            }
        }
        if (type == 6) display(6, 45, "Warning Unapplied Balance Journal");
        payCustomer = oi.str("oi-supplier");
        payValue = holdPay = oi.num("oi-paid");
        approp = oi.num("oi-approp");
        show(5, 72, payCustomer, 3);
        purch.set("purch-key", payCustomer);
        purchaseFile.read(purch);
        show(4, 1, purch.str("purch-name"), 3);
        String[] ad = pieces(purch.str("purch-address"), sys.str("pl-delim"), 3);
        for (int i = 0; i < 4; i++) show(5 + i, 1, pad(ad[i], 36), 3);
        display(10, 1, "Current Balance - ");
        show(10, 19, Num.edit(purch.num("purch-current"), "z(6)9.99cr"), 3);
        while (true) {
            payValue = acceptMoney(7, 49, 7, payValue);
            if (payValue.compareTo(oi.num("oi-paid")) == 0) {
                display(12, 1, "Confirm No action? i.e. Request cancelled (Y/N)..[ ]");
                String reply;
                do {
                    reply = upper(accept(12, 51, 1));
                    if (reply.equals("Y")) return true;
                } while (!reply.equals("N"));
            }
            if (payValue.signum() == 0) break;
            eraseEol(12, 1);
            display(12, 1, "PL140 Not Yet Supporting Corrections");
        }
        oi5.delete(Pl080.oi5Bytes(oi));
        if (oi.num("oi-approp").signum() != 0) {
            siDeduct = oi.num("oi-deduct-amt");
            paymentAppropriate();
        }
        if (type == 6) {
            purch.add("purch-unapplied", holdPay);
            purchaseFile.rewrite(purch);
        }
        eraseEos(14, 1);
        display(16, 29, "Make further corrections? (Y/N)  [Y]");
        while (true) {
            String reply = upper(acceptUpdate(16, 63, 1, "Y"));
            if (reply.equals("Y")) return true;
            if (reply.equals("N")) return false;
        }
    }

    private void paymentAppropriate() {
        display(11, 1, "Reversing please wait");
        Rec key = oiRec();
        key.set("oi-supplier", payCustomer);
        key.setNum("oi-invoice", 0);
        oi5.start(key, ">=");
        while (true) {
            if (!oi5.readNext(oi).equals("00")) break;
            if (oi.intv("oi-type") != 2) continue;
            if (!oi.str("oi-supplier").equals(payCustomer)) break;
            if (oi.longv("oi-b-nos") != batch || oi.intv("oi-b-item") != k) continue;
            BigDecimal work1 = BigDecimal.valueOf(oi.longv("oi-cr"), 2);
            oi.sub("oi-paid", work1);
            oi.sub("oi-p-c", work1);
            approp = approp.subtract(work1).abs();
            for (String f : new String[]{"oi-b-nos", "oi-b-item", "oi-cr", "oi-status"}) oi.setNum(f, 0);
            if (siDeduct.signum() != 0 && oi.num("oi-deduct-amt").signum() == 0) {
                while (true) {
                    display(13, 1, "For Folio  No.  ");
                    show(13, 17, Num.z9(oi.longv("oi-invoice"), 8), 3);
                    display(12, 1, "Enter deduct amount - [      ]");
                    display(12, 40, "Amount Available = ");
                    show(12, 59, Num.edit(siDeduct, "zz9.99"), 3);
                    BigDecimal a = acceptMoney(12, 24, 3, BigDecimal.ZERO);
                    oi.setNum("oi-deduct-amt", a);
                    if (a.compareTo(siDeduct) > 0) continue;
                    oi.add("oi-net", a);
                    siDeduct = siDeduct.subtract(a);
                    break;
                }
                eraseEol(12, 1);
                eraseEol(13, 1);
            }
            oi5.rewrite(Pl080.oi5Bytes(oi));
            if (approp.signum() == 0 && siDeduct.signum() == 0) break;
        }
        if (approp.signum() != 0 || siDeduct.signum() != 0) {
            display(12, 1, "PL141 Amount Approp Or Deduct Amt Not Zero");
            show(13, 4, Num.edit(approp, "z(6)9.99"), 3);
            show(13, 17, Num.edit(siDeduct, "z(6)9.99cr"), 3);
            display(14, 1, "PL003 Hit Return To Continue");
            accept(14, 30, 1);
        }
    }
}
