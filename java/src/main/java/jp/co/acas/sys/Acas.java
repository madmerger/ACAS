package jp.co.acas.sys;

import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;

import java.time.LocalDateTime;

/** ACAS.cbl: ACAS システムメニュー（最上位）。 */
public class Acas extends Program {
    static final String PROG_NAME = "ACAS (3.00.05)";
    private Rec sys;
    private String toDay = "";

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        while (true) {
            // Open-System
            if (!SystemFile.read(ctx).equals("00")) {
                if (!call("mapser")) { display(12, 1, "SY009 Environment variables not yet set up : ABORTING", 3); stopRun(); }
                SystemFile.read(ctx);
            }
            sys = SystemFile.shared(ctx);
            if (sys.intv("scycle") == 0) { callSystemSetup(); continue; }
            toDay = convertDate(sys, Maps04.toDate(sys.longv("run-date")));
            ctx.shared.put("to-day", toDay);
            if (menu()) continue;
            return;
        }
    }

    /** zz060-Convert-Date: UK 形式 dd/mm/ccyy を設定された日付形式（1=UK, 2=USA, 3=Intl）へ。 */
    public static String convertDate(Rec sys, String uk) {
        int form = sys.intv("date-form");
        if (form == 2) return uk.substring(3, 5) + "/" + uk.substring(0, 2) + uk.substring(5);
        if (form == 3) return uk.substring(6, 10) + "/" + uk.substring(3, 5) + "/" + uk.substring(0, 2);
        return uk;
    }

    private void callSystemSetup() {
        ctx.shared.put("ws-term-code", 0);
        if (!call("sys002")) { display(23, 31, "Sorry, not yet available"); stopRun(); }
        if ((int) ctx.shared.getOrDefault("ws-term-code", 0) > 7) stopRun();
    }

    /** display-menu 〜 accept-loop。true: Open-System からやり直す。false: 終了。 */
    private boolean menu() {
        while (true) {
            clearScreen();
            ctx.shared.put("ws-term-code", 0);
            show(24, 74, sys.str("maps-ser-xx"));
            show(24, 76, Num.z9(sys.intv("maps-ser-nn"), 4));
            LocalDateTime now = ctx.now();
            display(24, 1, "Copyright (c) 1976-", 3);
            show(24, 20, Num.z9(now.getYear(), 4));
            display(24, 24, " Applewood Computers", 3);
            show(1, 1, sys.str("usera"));
            show(1, 71, toDay);
            display(3, 1, PROG_NAME);
            display(3, 33, "ACAS System Menu");
            display(3, 55, "at ");
            show(3, 58, String.format("%02d:%02d:%02d", now.getHour(), now.getMinute(), now.getSecond()), 2);
            display(3, 67, "on ");
            String d8 = String.format("%02d/%02d/%02d", now.getDayOfMonth(), now.getMonthValue(), now.getYear() % 100);
            // レガシーは u-date 上位 8 桁（dd/mm/yy）を日付形式変換して表示する
            int form = sys.intv("date-form");
            if (form == 2) d8 = d8.substring(3, 5) + "/" + d8.substring(0, 2) + d8.substring(5);
            show(3, 70, d8, 2);
            display(6, 1, "Select one of the following by letter  :- [ ]");
            display(10, 4, "(A)  General Ledger");
            display(11, 4, "(B)  Sales Ledger");
            display(12, 4, "(C)  Purchase Ledger");
            display(13, 4, "(D)  Stock Control");
            display(14, 4, "(E)  Order Entry");
            display(15, 4, "(F)  Payroll");
            display(16, 4, "(G)  Epos");
            display(14, 44, "(X)  Exit To system");
            display(16, 44, "(Z)  System Setup");
            while (true) {
                String reply = upper(accept(6, 44, 1, AUTO));
                if (reply.equals("X")) { clearScreen(); return false; }
                int z = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(reply) + 1;
                if (z == 0) continue;
                String called = switch (z) { case 1 -> "general"; case 2 -> "sales"; case 3 -> "purchase"; case 4 -> "stock"; default -> null; };
                if (called != null) {
                    ctx.shared.put("ws-term-code", 0);
                    if (!call(called)) { display(23, 31, "Sorry, not yet available"); continue; }
                    if ((int) ctx.shared.getOrDefault("ws-term-code", 0) > 7) { stopRun(); }
                    break;
                }
                if (z >= 5 && z <= 7) { display(23, 31, "Sorry, not available"); continue; }
                if (z == 8 || z == 25) { display(23, 31, "Sorry, not yet available"); continue; }
                if (z == 26) { callSystemSetup(); return true; }
                if (z == 23) continue;
                break; // loaderror: メニュー再表示
            }
        }
    }
}
