package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl920.cbl: 支払予定の修正。 */
public class Pl920 extends PlPay {
    static final String PROG_NAME = "PL920 (3.01.03)";

    @Override
    public void run(Object... args) {
        init();
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 32, "Cheque Due Amendment");
        show(1, 71, fromUk(toDay()), 2);
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        Rec pay = payRec();
        CobFile payFile = payFile(pay);
        purchaseFile.open(Mode.INPUT);
        payFile.open(Mode.IO);
        display(5, 1, "Supplier - [       /  ]");
        for (int z = 1; z <= 9; z++) {
            show(8 + z, 1, Num.z9(z, 2));
            display(8 + z, 3, "   {        } [          ]");
        }
        while (true) {
            String key = upper(pad(accept(5, 13, 7), 7));
            pay.set("pay-supl-key", key);
            if (key.isBlank()) break;
            int nos = (int) acceptNum(5, 21, 2, 1);
            pay.setNum("pay-nos", nos);
            if (invalid(payFile.read(pay))) continue;
            purch.set("purch-key", key);
            if (invalid(purchaseFile.read(purch))) continue;
            show(5, 26, purch.str("purch-name"));
            for (int z = 1; z <= 9; z++) {
                show(8 + z, 7, Num.edit(pay.longv("pay-folio", z), "z(7)9"));
                show(8 + z, 18, Num.edit(pay.num("pay-value", z), "z(6)9.99"));
                show(8 + z, 32, pay.str("pay-invoice", z));
            }
            while (true) {
                display(5, 56, "Gross - [           ]");
                show(5, 65, Num.edit(pay.num("pay-gross"), "z(6)9.99"));
                display(22, 1, "line to alter - [ ]");
                int y = (int) numOf(accept(22, 18, 1));
                if (y == 0) break;
                BigDecimal v = pay.num("pay-value", y);
                if (v.signum() == 0) continue;
                pay.sub("pay-gross", v);
                v = acceptMoney(8 + y, 18, 7, v.abs());
                pay.setNum("pay-value", v, y);
                pay.add("pay-gross", v);
            }
            payFile.rewrite(pay);
        }
        purchaseFile.close();
        payFile.close();
    }
}
