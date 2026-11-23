package jp.co.acas.st;

import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.time.LocalDateTime;

/** st000.cbl: 在庫管理 業務開始（日付入力）。 */
public class St000 extends Program {
    static final String PROG_NAME = "ST000 (3.01.03)";

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        Rec sys = SystemFile.shared(ctx);
        LocalDateTime now = ctx.now();
        String uDate = String.format("%02d/%02d/%04d", now.getDayOfMonth(), now.getMonthValue(), 2000 + now.getYear() % 100);
        ctx.shared.put("to-day", uDate);
        clearScreen();
        display(1, 1, "Client -");
        show(1, 10, sys.str("usera"));
        display(3, 1, PROG_NAME);
        display(3, 27, "Stock Control - Start Of Day");
        show(24, 74, sys.str("maps-ser-xx"), 2);
        show(24, 76, Num.z9(sys.intv("maps-ser-nn"), 4), 2);
        display(3, 60, "at ");
        show(3, 63, String.format("%02d:%02d:%02d", now.getHour(), now.getMinute(), now.getSecond()), 2);
        long uBin;
        while (true) {
            // aa020-Date-Entry
            int form = sys.intv("date-form");
            if (!(form > 0 && form < 4)) { sys.setNum("date-form", 1); form = 1; }
            uDate = St.fromUk(uDate, form);
            if (form == 1) display(8, 12, "Enter todays date as dd/mm/yyyy - [          ]");
            if (form == 2) display(8, 12, "Enter todays date as mm/dd/yyyy - [          ]");
            if (form == 3) display(8, 12, "Enter todays date as yyyy/mm/dd - [          ]");
            uDate = acceptUpdate(8, 47, 10, uDate);
            uDate = St.toUk(uDate, form);
            uBin = Maps04.toBin(uDate);
            if (uBin == 0) { display(8, 60, "ST005 Invalid Date", 4); continue; }
            eraseEol(8, 60);
            break;
        }
        sys.setNum("run-date", uBin);
        ctx.shared.put("to-day", uDate);
        ctx.shared.put("ws-term-code", 0);
    }
}
