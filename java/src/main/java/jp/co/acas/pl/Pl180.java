package jp.co.acas.pl;

import jp.co.acas.core.Num;

/** pl180.cbl: 仕入伝票メニュー・固定データ保守。 */
public class Pl180 extends PlBase {
    static final String PROG_NAME = "PL180 (3.00.02)";

    @Override
    public void run(Object... args) {
        init();
        if (sys.longv("next-folio") == 0) fixedData();
        while (true) {
            clearScreen();
            display(1, 1, PROG_NAME);
            display(1, 34, "Invoicing Menu");
            show(1, 71, toDay(), 2);
            display(5, 1, "Select one of the following by number :- [ ]");
            display(8, 11, "(1)  Amend Invoicing Fixed Data");
            display(10, 11, "(2)  Enter Invoices");
            display(12, 11, "(3)  Amend Invoices");
            display(14, 11, "(4)  Delete Invoices");
            display(16, 11, "(5)  Invoice Proof Report");
            display(20, 11, "(9)  Return to System Menu");
            int reply = Pl010.digit(acceptUpdate(5, 43, 1, "0", AUTO));
            switch (reply) {
                case 9 -> { return; }
                case 1 -> fixedData();
                case 2 -> call("pl020");
                case 3 -> call("pl030");
                case 4 -> call("pl040");
                case 5 -> call("pl050");
                default -> { }
            }
        }
    }

    private void fixedData() {
        boolean gl = sys.intv("level-1") == 1;
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 31, "Invoicing Fixed Data");
        show(1, 71, toDay(), 2);
        display(5, 11, "Next Folio");
        display(5, 45, "- [        ]");
        if (gl) {
            display(7, 11, "Vat Account");
            display(7, 45, "- [      ]");
        }
        display(10, 11, "Details ok to file (Y/N) ...........[Y]");
        while (true) {
            do {
                long nf = sys.longv("next-folio") % 100000000L;
                show(5, 48, Num.z9(nf, 8), 3);
                sys.setNum("next-folio", acceptNum(5, 48, 8, nf));
            } while (sys.longv("next-folio") == 0);
            if (gl) {
                long va = sys.longv("vat-ac") % 1000000L;
                show(7, 48, Num.z9(va, 6), 3);
                sys.setNum("vat-ac", acceptNum(7, 48, 6, va));
            }
            String r;
            do { r = upper(acceptUpdate(10, 48, 1, "Y")); } while (!r.equals("N") && !r.equals("Y"));
            if (r.equals("Y")) return;
        }
    }
}
