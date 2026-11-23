package jp.co.acas.pl;

import jp.co.acas.core.Num;
import jp.co.acas.sys.Maps04;

import java.time.LocalDateTime;

/** pl000.cbl: 買掛 業務開始（処理日入力）。 */
public class Pl000 extends PlBase {
    static final String PROG_NAME = "PL000 (3.01.01)";

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        LocalDateTime now = ctx.now();
        String uDate = String.format("%02d/%02d/20%02d", now.getDayOfMonth(), now.getMonthValue(), now.getYear() % 100);
        toDay(uDate);
        clearScreen();
        display(1, 1, "Client -");
        show(1, 10, sys.str("usera"));
        display(3, 1, PROG_NAME);
        display(3, 28, "Purchase Ledger  Start Of Day");
        show(24, 74, sys.str("maps-ser-xx"), 2);
        show(24, 76, Num.z9(sys.intv("maps-ser-nn"), 4), 2);
        display(3, 60, "at ");
        show(3, 63, hhmmss(), 2);
        long bin;
        while (true) {
            int form = sys.intv("date-form");
            if (form < 1 || form > 3) { sys.setNum("date-form", 1); form = 1; }
            uDate = fromUk(uDate);
            if (form == 1) display(8, 12, "Enter todays date as dd/mm/yyyy - [          ]");
            if (form == 2) display(8, 12, "Enter todays date as mm/dd/yyyy - [          ]");
            if (form == 3) display(8, 12, "Enter todays date as yyyy/mm/dd - [          ]");
            show(8, 47, uDate);
            uDate = toUk(acceptUpdate(8, 47, 10, uDate));
            bin = Maps04.toBin(uDate);
            if (bin == 0) { display(8, 60, "PL005 Invalid Date", 4); continue; }
            eraseEol(8, 60);
            break;
        }
        sys.setNum("run-date", bin);
        toDay(uDate);
        termCode(0);
    }
}
