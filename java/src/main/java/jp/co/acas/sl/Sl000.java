package jp.co.acas.sl;

import jp.co.acas.sys.Maps04;

/** sl000.cbl: 売掛 業務開始（処理日入力）。 */
public class Sl000 extends SlProgram {
    static final String PROG_NAME = "SL000 (3.01.02)";

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        var now = ctx.now();
        String u = String.format("%02d/%02d/%04d", now.getDayOfMonth(), now.getMonthValue(), 2000 + now.getYear() % 100);
        toDay(u);
        clearScreen();
        display(1, 1, "Client -");
        show(1, 10, sys().str("usera"));
        display(3, 1, PROG_NAME);
        display(3, 28, "Sales Ledger  Start Of Day");
        showMapsSer(2);
        display(3, 60, "at ");
        show(3, 63, timeNow(), 2);
        long bin;
        while (true) {
            // date-entry
            if (!(sys().intv("date-form") > 0 && sys().intv("date-form") < 4)) sys().setNum("date-form", 1);
            u = fromUk(u);
            display(8, 12, "Enter todays date as " + dateFormName() + " - [          ]");
            show(8, 47, u);
            u = toUk(acceptUpdate(8, 47, 10, u));
            bin = Maps04.toBin(u);
            if (bin == 0) { display(8, 60, "SL005 Invalid Date", 4); continue; }
            eraseEol(8, 60);
            break;
        }
        // chain-menu
        sys().setNum("run-date", bin);
        toDay(u);
        termCode(0);
    }
}
