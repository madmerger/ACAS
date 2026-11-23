package jp.co.acas.pl;

/** pl900.cbl: 小切手サブシステムメニュー。 */
public class Pl900 extends PlBase {
    static final String PROG_NAME = "PL900 (3.01.02)";

    @Override
    public void run(Object... args) {
        init();
        while (true) {
            int reply = 0;
            clearScreen();
            display(1, 1, PROG_NAME);
            display(1, 36, "Cheque Menu");
            show(1, 71, fromUk(toDay()), 2);
            display(5, 1, "Select one of the following by number :- [ ]");
            display(8, 11, "(1)  Generate payments to be made");
            display(10, 11, "(2)  Amend payments");
            display(12, 11, "(3)  Proof payments");
            display(14, 11, "(4)  Generate cheques");
            display(16, 11, "(5)  Print cheque register");
            display(18, 11, "(6)  Print remittance advices");
            display(21, 11, "(9)  Return to system menu");
            do {
                reply = Pl010.digit(acceptUpdate(5, 43, 1, Integer.toString(reply), AUTO));
                if (reply == 9) return;
            } while (reply < 1 || reply > 6);
            call("pl9" + reply + "0");
        }
    }
}
