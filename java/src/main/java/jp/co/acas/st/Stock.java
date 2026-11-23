package jp.co.acas.st;

import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.time.LocalDateTime;

/** stock.cbl: 在庫管理システムメニュー。 */
public class Stock extends StProgram {
    static final String PROG_NAME = "Stock (3.01.19)";
    private Rec sys;
    private String toDay = "";
    private String menuReply = "A";

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        while (true) {
            // aa005-Open-System / aa010-get-system-recs
            if (!SystemFile.read(ctx).equals("00")) {
                if (!call("mapser")) { display(12, 1, "ST001 System 1 read err = ", 3); stopRun(); }
                if (!SystemFile.read(ctx).equals("00")) stopRun();
            }
            sys = SystemFile.shared(ctx);
            if (sys.intv("scycle") == 0) { callSystemSetup(); continue; }
            if (sys.intv("file-status", 14) == 0) {
                ctx.shared.put("ws-process-func", 1);
                call("sl070");
            }
            toDay = Maps04.toDate(sys.longv("run-date"));
            ctx.shared.put("to-day", toDay);
            if (sys.intv("level-4") != 1) {
                maps99(1);
                maps99(15);
                return;
            }
            String opDisplay = switch (sys.intv("op-system")) {
                case 0 -> "O/S"; case 1 -> "Dos"; case 2 -> "Windows"; case 3 -> "Mac";
                case 4 -> "OS/2"; case 5 -> "Unix"; case 6 -> "Linux"; default -> "";
            };
            int os = sys.intv("op-system");
            String script = os == 1 || os == 2 ? "acasbkup.bat" : os == 4 ? "acasbkup.cmd" : os == 3 || os == 5 || os == 6 ? "acasbkup.sh" : "";
            // バックアップスクリプトは Web 版では常に備わっているものとして扱う（実行はサーバー側運用に委ねる）
            String batchText = "Using " + script;
            if (menu(opDisplay, batchText)) continue;
            return;
        }
    }

    private void callSystemSetup() {
        ctx.shared.put("ws-term-code", 0);
        SystemFile.rewrite(ctx);
        if (!call("sys002")) { display(23, 27, "Sorry not yet available"); stopRun(); }
        if (termCode() > 7) stopRun();
    }

    private int termCode() { return (int) ctx.shared.getOrDefault("ws-term-code", 0); }

    /** aa030-display-menu 〜 load00。true: aa005-Open-System からやり直す。false: 終了（goback）。 */
    private boolean menu(String opDisplay, String batchText) {
        boolean first = menuReply.equals("A");
        while (true) {
            int z;
            if (first) { first = false; z = 1; }
            else {
                clearScreen();
                String uDate = (String) ctx.shared.get("to-day");
                toDay = uDate;
                ctx.shared.put("ws-caller", "stock");
                ctx.shared.put("ws-term-code", 0);
                show(24, 74, sys.str("maps-ser-xx"));
                show(24, 76, Num.z9(sys.intv("maps-ser-nn"), 4));
                LocalDateTime now = ctx.now();
                display(24, 1, "Copyright (c) 1976-", 3);
                show(24, 20, Num.z9(now.getYear(), 4));
                display(24, 24, " Applewood Computers", 3);
                show(1, 1, sys.str("usera"));
                int form = sys.intv("date-form");
                if (!(form > 0 && form < 4)) { sys.setNum("date-form", 1); form = 1; }
                if (form == 2) uDate = uDate.substring(3, 5) + "/" + uDate.substring(0, 2) + uDate.substring(5);
                if (form == 3) uDate = uDate.substring(6, 10) + "/" + uDate.substring(3, 5) + "/" + uDate.substring(0, 2);
                show(1, 71, uDate);
                display(3, 1, PROG_NAME);
                display(3, 28, "Stock Control System Menu");
                display(3, 55, "at ");
                show(3, 58, String.format("%02d:%02d:%02d", now.getHour(), now.getMinute(), now.getSecond()), 2);
                display(6, 1, "Select one of the following by letter  :- [ ]");
                display(10, 4, "(A)  Date Entry");
                display(11, 4, "(B)  Stock Item Maintenance");
                display(12, 4, "(C)  Stock Movements");
                display(13, 4, "(D)  Reports");
                display(10, 44, "(E)  End of Cycle Processing");
                display(12, 44, "(X)  Exit to ");
                show(12, 57, String.format("%-7s", opDisplay), 2);
                display(12, 49, batchText);
                display(13, 44, "(Y)  Stock File Compression");
                display(14, 44, "(Z)  System Set Up");
                while (true) {
                    String reply = upper(accept(6, 44, 1, AUTO));
                    if (reply.equals("X")) { clearScreen(); SystemFile.rewrite(ctx); return false; }
                    z = reply.isBlank() ? 0 : "ABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(reply) + 1;
                    if (z != 0) break;
                }
            }
            menuReply = " ";
            String called = switch (z) {
                case 1 -> "st000"; case 2 -> "st010"; case 3 -> "st020"; case 4 -> "st030"; case 5 -> "st040";
                case 25 -> "st050"; default -> null;
            };
            if (z == 24) { SystemFile.rewrite(ctx); return false; }
            if (z == 26) { callSystemSetup(); return true; }
            if (called == null) continue;
            ctx.shared.put("ws-term-code", 0);
            ctx.shared.put("ws-called", called);
            call(called);
            if (termCode() > 7) { SystemFile.rewrite(ctx); return false; }
        }
    }
}
