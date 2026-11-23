package jp.co.acas.gl;

import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.time.LocalDateTime;

/** gl000.cbl: 総勘定元帳 開始処理（処理日入力）。 */
public class Gl000 extends Program {
    static final String PROG_NAME = "GL000 (3.00.04)";

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        Rec sys = GlCommon.sys(ctx);
        LocalDateTime now = ctx.now();
        // accept wsa-date from date → u-date（世紀は 20 固定）
        String uDate = String.format("%02d/%02d/20%02d", now.getDayOfMonth(), now.getMonthValue(), now.getYear() % 100);
        GlCommon.toDay(ctx, uDate);
        display(1, 1, "Client -"); eraseEos(1, 9);
        show(1, 10, sys.str("usera"));
        display(3, 1, PROG_NAME);
        display(3, 28, "General Ledger  Start Of Day");
        show(24, 74, sys.str("maps-ser-xx"), 2);
        show(24, 76, Num.z9(sys.intv("maps-ser-nn"), 4), 2);
        display(3, 70, "at ");
        show(3, 73, String.format("%02d:%02d:%02d", now.getHour(), now.getMinute(), now.getSecond()), 2);
        long uBin;
        while (true) {
            // date-entry
            int form = sys.intv("date-form");
            if (form < 1 || form > 3) sys.setNum("date-form", 1);
            uDate = GlCommon.ukToForm(sys, uDate);
            form = sys.intv("date-form");
            if (form == 1) display(8, 12, "Enter todays date as dd/mm/yyyy - [          ]");
            if (form == 2) display(8, 12, "Enter todays date as mm/dd/yyyy - [          ]");
            if (form == 3) display(8, 12, "Enter todays date as yyyy/mm/dd - [          ]");
            show(8, 47, uDate);
            uDate = acceptUpdate(8, 47, 10, uDate);
            uDate = GlCommon.formToUk(sys, uDate);
            uBin = Maps04.toBin(uDate);
            if (uBin == 0) { display(8, 60, "GL009 Invalid Date", 4); continue; }
            eraseEol(8, 60);
            break;
        }
        // chain-menu
        sys.setNum("run-date", uBin);
        GlCommon.toDay(ctx, uDate);
        GlCommon.termCode(ctx, 0);
    }
}
