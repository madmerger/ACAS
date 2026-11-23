package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.time.LocalDateTime;

/** general.cbl: 総勘定元帳システムメニュー。 */
public class General extends Program {
    static final String PROG_NAME = "General (3.00.11)";
    private Rec sys, dflt, sys4;
    private CobFile systemFile;
    private String menuReply = "A";   // 初回は必ず日付入力（gl000）
    private String opDisplay = "       ";
    private int wseYear;

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        sys = GlCommon.sys(ctx); dflt = GlCommon.dflt(ctx); sys4 = GlCommon.sys4(ctx);
        wseYear = ctx.now().getYear();
        while (true) {
            // Open-System
            systemFile = SystemFile.file(ctx);
            systemFile.open(CobFile.Mode.IO);
            if (!systemFile.ok()) {
                // mapser（システムファイル新規作成）は共通設定側（別セッション実装）へ委譲する
                if (!call("mapser")) {
                    display(11, 1, "Problem with opening system file. Hit return to clear", 4);
                    accept(11, 54, 1);
                    stopRun();
                }
                systemFile.open(CobFile.Mode.IO);
            }
            if (!getSystemRecs()) stopRun();
            if (sys.intv("scycle") == 0) { callSystemSetup(); continue; }
            GlCommon.toDay(ctx, Maps04.toDate(sys.longv("run-date")));
            if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);   // zz060-Convert-Date
            if (sys.intv("level-1") != 1) {
                // not G-L: maps99（エラー表示）後に終了
                call("maps99", 1); systemFile.close(); call("maps99", 15);
                return;
            }
            int os = sys.intv("op-system");
            if (os == 0) opDisplay = "O/S    ";
            opDisplay = switch (os) { case 6 -> "Linux  "; case 2 -> "Windows"; case 3 -> "Mac    "; case 4 -> "OS/2   "; case 5 -> "Unix   "; case 1 -> "Dos    "; default -> opDisplay; };
            if (menu()) continue;
            return;
        }
    }

    /** get-system-recs。false: 読込みエラー（STOP RUN）。 */
    private boolean getSystemRecs() {
        Rec buf = SystemFile.layout().newRec();
        systemFile.rrn = 4;
        if (!systemFile.read(buf).equals("00")) return sysErr("GL003 System 4 read err = ");
        sys4.load(buf.bytes());
        systemFile.rrn = 2;
        if (!systemFile.read(buf).equals("00")) return sysErr("GL002 System 2 read err = ");
        dflt.load(buf.bytes());
        systemFile.rrn = 1;
        if (!systemFile.read(sys).equals("00")) return sysErr("GL001 System 1 read err = ");
        return true;
    }
    private boolean sysErr(String msg) {
        clearScreen();
        display(1, 1, msg); show(1, 27, systemFile.status); display(1, 29, " hit return");
        accept(2, 1, 1);
        systemFile.close();
        return false;
    }

    private void callSystemSetup() {
        GlCommon.termCode(ctx, 0);
        systemFile.rrn = 1; systemFile.rewrite(sys);
        systemFile.close();
        if (!call("sys002")) { display(23, 27, "Sorry not yet available"); accept(6, 44, 1, AUTO); return; }
        if (GlCommon.termCode(ctx) > 7) stopRun();
    }

    private void overrewrite() {
        Rec buf = SystemFile.layout().newRec();
        systemFile.rrn = 1; systemFile.rewrite(sys);
        systemFile.rrn = 2; buf.load(dflt.bytes()); systemFile.rewrite(buf);
        systemFile.rrn = 4; buf.load(sys4.bytes()); systemFile.rewrite(buf);
    }
    private void overclose() { systemFile.close(); }

    /** conv-date: UK 形式の 10 桁を設定形式へ（年が 2 桁でもそのまま桁移動する）。 */
    private String convDate(String u) { return GlCommon.ukToForm(sys, u); }

    /** load00 / load000。false: ws-term-code > 7（overrewrite して終了）。 */
    private boolean load(String called) {
        GlCommon.termCode(ctx, 0);
        if (!call(called)) display(23, 27, "Sorry not yet available");
        return GlCommon.termCode(ctx) <= 7;
    }

    /** display-menu 〜 load-it。true: Open-System からやり直す。false: 終了（GOBACK）。 */
    private boolean menu() {
        boolean redisplay = true;
        while (true) {
            if (!menuReply.equals("A")) {
                if (redisplay) displayMenu();
                redisplay = true;
                menuReply = upper(accept(6, 44, 1, AUTO));
                if (menuReply.equals("X")) { clearScreen(); overrewrite(); overclose(); return false; }
            }
            int z = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(menuReply) + 1;
            if (z == 0) { redisplay = false; continue; }
            menuReply = " ";
            boolean ok = true;
            switch (z) {
                case 1 -> ok = load("gl000");
                case 2 -> ok = load("gl030");
                case 3 -> { ok = load("gl020"); if (ok) { overrewrite(); if (!getSystemRecs()) stopRun(); } }
                case 5 -> { ok = load("gl050"); if (ok) { overrewrite(); if (!getSystemRecs()) stopRun(); } }
                case 6 -> { ok = load("gl051"); if (ok) { overrewrite(); if (!getSystemRecs()) stopRun(); } }
                case 7 -> ok = load("gl060");
                case 8 -> {
                    ok = load("gl070");
                    if (ok && GlCommon.termCode(ctx) != 5) { ok = load("gl071"); if (ok) ok = load("gl072"); }
                }
                case 9 -> ok = load("gl080");
                case 10 -> ok = load("gl090");
                case 11 -> ok = load("gl120");
                case 12 -> {
                    ok = load("gl100");
                    if (ok) {
                        int tc = GlCommon.termCode(ctx);
                        if (tc == 5) { redisplay = false; }
                        else if (tc == 4) { call("maps99", 31); call("maps99", 15); }
                        else ok = load("gl105");
                    }
                }
                case 4, 25 -> { display(23, 27, "Sorry not yet available"); redisplay = false; }
                case 26 -> { callSystemSetup(); return true; }
                default -> { }
            }
            if (!ok) { overrewrite(); overclose(); return false; }
        }
    }

    private void displayMenu() {
        clearScreen();
        GlCommon.termCode(ctx, 0);
        show(24, 74, sys.str("maps-ser-xx"));
        show(24, 76, Num.z9(sys.intv("maps-ser-nn"), 4));
        display(24, 1, "Copyright (c) 1976-", 3);
        show(24, 20, Num.z9(wseYear, 4));
        display(24, 24, " Applewood Computers", 3);
        show(1, 1, sys.str("usera"));
        show(1, 71, convDate(GlCommon.toDay(ctx)));
        display(3, 1, PROG_NAME);
        display(3, 28, "General Ledger System Menu");
        LocalDateTime now = ctx.now();
        display(3, 55, "at ");
        show(3, 58, String.format("%02d:%02d:%02d", now.getHour(), now.getMinute(), now.getSecond()), 2);
        display(3, 67, "on ");
        // u-date の年 4 桁域へ 2 桁年を転記（"dd/mm/yy  "）してから形式変換
        show(3, 70, convDate(String.format("%02d/%02d/%02d  ", now.getDayOfMonth(), now.getMonthValue(), now.getYear() % 100)), 2);
        display(6, 1, "Select one of the following by letter  :- [ ]");
        display(10, 4, "(A)  Date Entry");
        display(11, 4, "(B)  Chart Of Accounts");
        display(12, 4, "(C)  Default Account Maintenance");
        display(13, 4, "(D)* Final Accounts Set-Up");
        display(14, 4, "(E)  Enter Transactions");
        display(15, 4, "(F)  Proof/Modify Transactions");
        display(16, 4, "(G)  Batch Status Report");
        display(17, 4, "(H)  Transaction Posting");
        display(18, 4, "(I)  End Of Cycle Processing");
        display(11, 44, "(J)  Print Trial Balance");
        display(12, 44, "(K)  Print P&L and Balance Sheet");
        display(13, 44, "(L)  Print Ledgers");
        display(14, 44, "(M)* Print Final Accounts");
        display(15, 44, "(X)  Exit to ");
        show(15, 57, opDisplay, 2);
        display(17, 44, "(Z)  System Set Up");
    }
}
