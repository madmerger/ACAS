package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;

/** pl950.cbl: 小切手・BACS 台帳の印刷と未決済明細への支払反映。 */
public class Pl950 extends Pl100 {
    static final String PROG_NAME = "PL950 (3.01.09)";
    private int p, lineCnt;
    private String line1, line2, line3;

    @Override
    public void run(Object... args) {
        init();
        String wsDate = fromUk(toDay());
        line1 = pad(PROG_NAME, 33) + pad("Cheque/Bacs Register", 39) + "Page ";
        line2 = pad(sys.str("usera"), 33) + pad("", 37) + wsDate;
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 32, "Cheque Register");
        show(1, 71, wsDate, 2);
        while (true) {
            display(12, 1, "Warning: Updating Open Item File. Do You Wish to Continue (YES/NO) [   ]");
            String r = upper(pad(accept(12, 69, 3), 3));
            if (r.equals("NO ")) return;
            if (r.equals("YES")) break;
        }
        term().eraseEol(12, 1);
        purch = purchRec();
        purchaseFile = purchaseFile(purch);
        Rec pay = PlPay.payRec();
        CobFile payFile = CobFile.indexed(ctx.store, ctx.path("pay.dat"), pay, "pay-key");
        purchaseFile.open(Mode.INPUT);
        payFile.open(Mode.INPUT);
        prt = new Printer("prt-1");
        int pageLines = sys.intv("page-lines");
        boolean first = true;
        BigDecimal balT = BigDecimal.ZERO;
        while (payFile.readNext(pay).equals("00")) {
            if (first) {
                line3 = pad("Cheques Date - ", 16) + binToDate(pay.longv("pay-date"));
                headings();
                first = false;
            }
            readPurch(pay);
            String head = pay.longv("pay-cheque") != 0
                    ? Num.edit(pay.longv("pay-cheque"), "z(9)9") + pad("", 6)
                    : Num.z9(pay.longv("pay-sortcode") % 1_000_000, 6) + " " + Num.z9(pay.longv("pay-account") % 100_000_000, 8) + " ";
            prt.after(head + pad(purch.str("purch-key"), 9) + pad(purch.str("purch-name"), 30)
                    + Num.edit(pay.num("pay-gross"), "z(7)9.99"), 1);
            balT = PlPay.u9(balT.add(pay.num("pay-gross")));
            lineCnt++;
            if (lineCnt > pageLines) headings();
        }
        String line6 = pad("", 55) + "=".repeat(11);
        prt.after(line6, 2);
        prt.after(pad("", 25) + pad("    total", 30) + Num.edit(balT, "z(7)9.99"), 1);
        prt.after(line6, 1);
        prt.close();
        payFile.close();
        spoolPrt1Portrait();

        payFile.open(Mode.INPUT);
        oi5 = oi5File();
        oi5.open(Mode.IO);
        oi = oiRec();
        gl = sys.intv("level-1") == 1;
        irs = sys.str("irs-instead").equals("Y");
        if (gl) blOpen();
        if (sys.longv("bl-next-batch") == 0) sys.setNum("bl-next-batch", 1);
        int paySeries = 0;
        long nDeduct = 0;
        BigDecimal tDeduct = BigDecimal.ZERO, deductTaken = BigDecimal.ZERO;
        while (payFile.readNext(pay).equals("00")) {
            String key = pay.str("pay-supl-key");
            readPurch(pay);
            BigDecimal aprop = BigDecimal.ZERO;
            if (++paySeries > 999) {
                paySeries = 1;
                sys.setNum("bl-next-batch", sys.longv("bl-next-batch") + 1);
            }
            long batchNo = sys.longv("bl-next-batch");
            for (int z = 1; z <= 9; z++) {
                BigDecimal v = pay.num("pay-value", z);
                if (v.signum() == 0) continue;
                Rec r = oiRec();
                r.set("oi-supplier", key);
                r.setNum("oi-invoice", pay.longv("pay-folio", z));
                if (invalid(oi5.read(r))) continue;
                oi.load(r.bytes());
                if (oi.intv("oi-type") != 2) {
                    display(24, 1, "PL904 PE 950-01:Hit return to continue", 4);
                    accept(24, 41, 3);
                    continue;
                }
                if (!oi.str("oi-supplier").equals(key) || oi.longv("oi-invoice") != pay.longv("pay-folio", z)) {
                    display(24, 1, "PL905 PE 950-02:Hit return to continue", 4);
                    accept(24, 41, 3);
                    continue;
                }
                BigDecimal ded = pay.num("pay-deduct", z);
                oi.add("oi-paid", v);
                BigDecimal work1 = oi.num("oi-net").add(oi.num("oi-carriage")).add(oi.num("oi-vat")).add(oi.num("oi-c-vat"))
                        .subtract(ded).remainder(BigDecimal.valueOf(1_000_000));
                if (oi.num("oi-paid").compareTo(work1) == 0) {
                    oi.setNum("oi-status", 1);
                    oi.sub("oi-net", ded);
                    deductTaken = deductTaken.add(ded);
                    oi.setNum("oi-deduct-amt", 0);
                    oi.setNum("oi-b-nos", batchNo);
                    oi.setNum("oi-b-item", paySeries);
                    oi.setNum("oi-date-cleared", pay.longv("pay-date"));
                }
                oi5.rewrite(Pl080.oi5Bytes(oi));
                aprop = aprop.add(v);
                oi.add("oi-p-c", v);
                oi.setNum("oi-cr", v.movePointRight(2).longValue());
            }
            oi.setNum("oi-invoice", batchNo * 1000 + paySeries);
            for (String f : new String[]{"oi-carriage", "oi-c-vat", "oi-vat", "oi-discount", "oi-status", "oi-p-c", "oi-extra",
                    "oi-e-vat", "oi-cr", "oi-deduct-days", "oi-days", "oi-deduct-vat"})
                oi.setNum(f, 0);
            oi.set("oi-order", ""); oi.set("oi-hold-flag", ""); oi.set("oi-applied", "");
            oi.set("oi-supplier", key);
            oi.setNum("oi-b-nos", batchNo);
            oi.setNum("oi-b-item", paySeries);
            oi.setNum("oi-date", pay.longv("pay-date"));
            oi.setNum("oi-date-cleared", pay.longv("pay-date"));
            uDate = Maps04.toDate(oi.longv("oi-date"));
            oi.setNum("oi-paid", pay.num("pay-gross"));
            oi.setNum("oi-approp", aprop);
            oi.setNum("oi-deduct-amt", deductTaken);
            if (oi.num("oi-deduct-amt").signum() != 0) nDeduct++;
            oi.set("oi-ref", Num.z9(pay.longv("pay-cheque"), 10));
            oi.setNum("oi-type", 5);
            oi5.write(Pl080.oi5Bytes(oi));
            if (gl) blWrite();
            tDeduct = tDeduct.add(deductTaken);
            deductTaken = BigDecimal.ZERO;
        }
        sys.setNum("bl-next-batch", sys.longv("bl-next-batch") + 1);
        oi5.close(); payFile.close(); purchaseFile.close();
        payFile.open(Mode.OUTPUT);
        payFile.close();
        if (tDeduct.signum() != 0) analiseDeductions(nDeduct, tDeduct);
        if (gl) blClose();
    }

    private void readPurch(Rec pay) {
        purch.set("purch-key", pay.str("pay-supl-key"));
        if (invalid(purchaseFile.read(purch))) purch.set("purch-name", "Record Missing");
    }

    private void headings() {
        p = (p + 1) % 100;
        String l1 = line1 + Num.edit(p, "zz9");
        if (p != 1) {
            prt.afterPage(l1);
            prt.after(line2, 1);
            prt.after("", 1);
        } else {
            prt.before(l1, 1);
            prt.before(line2, 1);
        }
        prt.after(line3, 1);
        prt.after("Cheque Nos     <------------ Payee ------------->      <--Value-->", 2);
        prt.after(pad(" Sort  Account", 16) + "Account             Name", 1);
        prt.after("", 1);
        lineCnt = 8;
    }
}
