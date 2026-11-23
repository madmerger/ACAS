package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl910.cbl: 支払予定の生成（Payments Due Report と pay.dat 作成）。 */
public class Pl910 extends PlPay {
    static final String PROG_NAME = "PL910 (3.01.07)";
    private String line1, line2;
    private static final String LINE4 = pad(" Number   Supplier", 38)
            + "Folio M    Date     Invoice      Current       30 +        60 +        90 +       Total to Pay";

    @Override
    public void run(Object... args) {
        init();
        String wsDate = fromUk(toDay());
        term().exceptionsEnabled = true;
        term().escEnabled = true;
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 32, "Cheque Due Reporting");
        show(1, 71, wsDate, 2);
        display(5, 1, "Current Age to Pay on is - [  ]");
        int age = Math.floorMod(sys.intv("age-to-pay"), 100);
        show(5, 29, Num.z9(age, 2));
        display(7, 1, "is this correct (Y/N) ?  - [ ]");
        String reply = upper(pad(accept(7, 29, 1), 1));
        if (reply.equals("N")) {
            age = (int) numOf(accept(5, 29, 2));
            sys.setNum("age-to-pay", age);
        }
        long runDate = sys.longv("run-date");
        long toBePaid = runDate - sys.intv("age-to-pay");
        line1 = pad(PROG_NAME, 56) + pad("Payments Due Report", 24) + pad("Prior To", 9) + pad(binToDate(toBePaid), 10)
                + pad("", 25) + "Page ";
        line2 = pad(sys.str("usera"), 56) + pad("", 66) + wsDate;

        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        CobFile oi5 = oi5File();
        Rec pay = payRec();
        CobFile payFile = payFile(pay);
        purchaseFile.open(Mode.INPUT);
        oi5.open(Mode.INPUT);
        prt = new Printer("prt-1");
        payFile.open(Mode.OUTPUT);
        headings(line1, line2, LINE4);
        int pageLines = sys.intv("page-lines");
        Rec oi = oiRec();
        long uBin = toBePaid;
        while (purchaseFile.readNext(purch).equals("00")) {
            if (purch.num("purch-current").signum() <= 0) continue;
            initialize(pay);
            String key = purch.str("purch-key");
            l5Key = key;
            pay.set("pay-supl-key", key);
            pay.setNum("pay-nos", 1);
            pay.setNum("pay-date", uBin);
            l5Supplier = pad(purch.str("purch-name"), 25);
            if (purch.longv("purch-sortcode") != 0) {
                pay.setNum("pay-sortcode", purch.longv("purch-sortcode"));
                pay.setNum("pay-account", purch.longv("purch-accountno"));
                l5Method = "B";
            } else l5Method = "C";
            int a = 1;
            Rec k = oiRec();
            k.set("oi-supplier", key);
            k.setNum("oi-invoice", 0);
            oi5.start(k, ">=");
            while (true) {
                if (!oi5.readNext(oi).equals("00")) break;
                if (oi.intv("oi-status") == 1 || oi.str("oi-hold-flag").equals("H") || oi.longv("oi-b-nos") != 0) continue;
                if (!oi.str("oi-supplier").equals(key)) break;
                if (oi.intv("oi-type") != 2) continue;
                if (oi.longv("oi-date") > toBePaid) continue;
                l5Folio = Num.edit(oi.longv("oi-invoice"), "z(7)9");
                pay.setNum("pay-folio", oi.longv("oi-invoice"), a);
                uBin = oi.longv("oi-date");
                l5Date = binToDate(uBin);
                l5Invoice = oi.str("oi-ref");
                pay.set("pay-invoice", oi.str("oi-ref"), a);
                BigDecimal amountOut = oi.num("oi-net").add(oi.num("oi-carriage")).add(oi.num("oi-vat"))
                        .add(oi.num("oi-c-vat")).subtract(oi.num("oi-paid"));
                if (amountOut.signum() == 0) continue;
                long work1 = runDate - oi.longv("oi-date");
                if (oi.intv("oi-deduct-days") >= work1) {
                    amountOut = amountOut.subtract(oi.num("oi-deduct-amt"));
                    pay.setNum("pay-deduct", oi.num("oi-deduct-amt"), a);
                    if (amountOut.signum() == 0) continue;
                    if (amountOut.signum() < 0) {
                        display(23, 1, "PL901 PE 910-01: Note and hit return", 4);
                        accept(23, 38, 1);
                        continue;
                    }
                }
                pay.setNum("pay-value", amountOut, a);
                int period;
                if (work1 < 30) { bal0 = u9(bal0.add(amountOut)); period = 0; }
                else if (work1 < 60) { bal30 = u9(bal30.add(amountOut)); period = 30; }
                else if (work1 < 90) { bal60 = u9(bal60.add(amountOut)); period = 60; }
                else { bal90 = u9(bal90.add(amountOut)); period = 90; }
                pay.setNum("pay-period", period, a);
                balT = u9(balT.add(amountOut));
                pay.setNum("pay-gross", balT);
                tot0 = u9(tot0.add(bal0)); tot30 = u9(tot30.add(bal30));
                tot60 = u9(tot60.add(bal60)); tot90 = u9(tot90.add(bal90));
                prt.after(line5(10), 1);
                lineCnt++;
                if (lineCnt > pageLines) headings(line1, line2, LINE4);
                bal0 = bal30 = bal60 = bal90 = BigDecimal.ZERO;
                l5Key = ""; l5Supplier = "";
                if (++a > 9) {
                    a = 1;
                    pay.set("pay-cont", "C");
                    payFile.write(pay);
                    pay.setNum("pay-gross", 0);
                    pay.setNum("pay-nos", pay.intv("pay-nos") + 1);
                }
            }
            if (a != 1) payFile.write(pay);
            if (lineCnt > pageLines) headings(line1, line2, LINE4);
            balT = BigDecimal.ZERO;
        }
        prt.after(line7(), 1);
        prt.after(line6(u9(tot0.add(tot30).add(tot60).add(tot90))), 1);
        prt.close();
        oi5.close(); purchaseFile.close(); payFile.close();
        spoolPrt1();
    }
}
