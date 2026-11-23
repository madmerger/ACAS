package jp.co.acas.pl;

import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.time.LocalDateTime;

/** purchase.cbl: 買掛元帳システムメニュー。 */
public class Purchase extends PlBase {
    static final String PROG_NAME = "Purchase (3.01.19)";
    private String toDay;

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        String menuReply = "A";
        while (true) {
            // Open-System
            if (!SystemFile.read(ctx).equals("00")) { call("mapser"); SystemFile.read(ctx); }
            init();
            readSys4();
            if (sys.intv("scycle") == 0) {
                termCode(0);
                SystemFile.rewrite(ctx);
                call("sys002");
                if (termCode() > 7) stopRun();
                continue;
            }
            toDay = fromUk(Maps04.toDate(sys.longv("run-date")));
            toDay(toDay);
            if (sys.intv("level-2") != 1) {
                maps99(1);
                maps99(15);
                return;
            }
            if (menuReply.equals("A")) {
                menuReply = " ";
                if (load("pl000")) return;
            }
            Boolean again = menu();
            if (again == null) return;
        }
    }

    private String opDisplay() {
        return switch (sys.intv("op-system")) {
            case 0 -> "O/S"; case 6 -> "Linux"; case 2 -> "Windows"; case 3 -> "Mac";
            case 4 -> "OS/2"; case 5 -> "Unix"; case 1 -> "Dos"; default -> "";
        };
    }

    /** display-menu 段落のみ（Conv-date の手前まで）。 */
    private void displayMenuPara() {
        clearScreen();
        toDay = toDay();
        termCode(0);
        LocalDateTime now = ctx.now();
        show(24, 74, sys.str("maps-ser-xx"));
        show(24, 76, Num.z9(sys.intv("maps-ser-nn"), 4));
        display(24, 1, "Copyright (c) 1976-", 3);
        show(24, 20, Num.z9(now.getYear(), 4));
        display(24, 24, " Applewood Computers", 3);
        show(1, 1, sys.str("usera"));
    }

    private void displayMenu() {
        displayMenuPara();
        LocalDateTime now = ctx.now();
        show(1, 71, fromUk(toDay));
        display(3, 1, PROG_NAME);
        display(3, 26, "Purchase Ledger System Menu");
        display(3, 55, "at ");
        show(3, 58, hhmmss(), 2);
        display(3, 67, "on ");
        String d8 = String.format("%02d/%02d/%02d", now.getDayOfMonth(), now.getMonthValue(), now.getYear() % 100);
        if (sys.intv("date-form") == 2) d8 = d8.substring(3, 5) + "/" + d8.substring(0, 2) + d8.substring(5);
        show(3, 70, d8, 2);
        display(6, 1, "Select one of the following by letter  :- [ ]");
        display(10, 4, "(A)  Date Entry");
        display(11, 4, "(B)  Supplier File Maintenance");
        display(12, 4, "(C)  Purchase Ledger Enquiry");
        display(13, 4, "(D)  Purchase Transactions Input");
        display(14, 4, "(E)  Purchase Transactions Amend");
        display(15, 4, "(F)  Purchase Transactions Delete");
        display(16, 4, "(G)  Purchase Transactions Proof");
        display(17, 4, "(H)  Purchase Transactions Post");
        display(18, 4, "(I)  Payment Input");
        display(19, 4, "(J)  Payment Amend");
        display(20, 4, "(K)  Payment Proof");
        display(21, 4, "(L)  Payment Post");
        display(22, 4, "(M)  Set-Up Purchase Analysis Codes");
        display(10, 44, "(N)  Purchase Analysis Report");
        display(11, 44, "(O)  Purchase Day Book");
        display(12, 44, "(P)  Aged Creditors Report");
        display(13, 44, "(Q)  Alphabetical Supplier List");
        display(14, 44, "(R)  Supplier Turnover Report");
        display(15, 44, "(S)  Cheque  Sub-System");
        display(16, 44, "(T)  End Of Cycle Processing");
        display(17, 44, "(U)  Invoice Parameter Amend");
        display(18, 44, "(V)  Supplier File Dump");
        display(19, 44, "(X)  Exit to ");
        show(19, 57, opDisplay(), 2);
        display(20, 49, "Using acasbkup.sh");
        display(22, 44, "(Z)  System Set Up");
    }

    /** load00/load000: true なら ws-term-code > 7 で overrewrite 済み（終了）。 */
    private boolean load(String name) {
        termCode(0);
        call(name);
        if (termCode() > 7) { overrewrite(); return true; }
        return false;
    }

    private void overrewrite() { SystemFile.rewrite(ctx); rewriteSys4(); }

    private void messageRun(int code) {
        displayMenuPara();
        maps99(code);
        maps99(15);
    }

    /** display-menu 〜 load-it。null: 終了、TRUE: Open-System からやり直し、FALSE は使わない。 */
    private Boolean menu() {
        while (true) {
            displayMenu();
            int z;
            while (true) {
                String reply = upper(accept(6, 44, 1, AUTO));
                if (reply.equals("X")) { clearScreen(); overrewrite(); return null; }
                z = reply.isBlank() ? 0 : "ABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(reply) + 1;
                if (z == 0) continue;
                if (z == 25) { display(23, 31, "Sorry not yet available"); continue; }
                break;
            }
            switch (z) {
                case 1 -> { if (load("pl000")) return null; }
                case 2 -> { if (load("pl010")) return null; }
                case 3 -> { if (load("pl015")) return null; }
                case 4 -> { if (load("pl020")) return null; }
                case 5 -> { if (load("pl030")) return null; }
                case 6 -> { if (load("pl040")) return null; }
                case 7 -> {
                    if (sys.intv("p-flag-i") != 1 || sys.intv("file-status", 26) == 0) { messageRun(14); break; }
                    if (load("pl050")) return null;
                }
                case 8 -> {
                    if (sys.intv("p-flag-i") != 1 || sys.intv("file-status", 26) == 0) { messageRun(14); break; }
                    if (load("pl055")) return null;
                    if (load("pl060")) return null;
                }
                case 9 -> {
                    if (sys.intv("p-flag-i") == 1) { messageRun(28); break; }
                    if (sys.intv("file-status", 29) == 0) { messageRun(25); break; }
                    if (load("pl080")) return null;
                }
                case 10 -> { if (load("pl085")) return null; }
                case 11 -> { if (load("pl090")) return null; if (load("pl095")) return null; }
                case 12 -> { if (load("pl100")) return null; }
                case 13 -> { if (load("pl070")) return null; }
                case 14 -> { if (load("pl130")) return null; }
                case 15 -> { if (load("pl140")) return null; }
                case 16 -> {
                    ctx.shared.put("pl-error-code", 0);
                    if (load("pl165")) return null;
                    ctx.shared.put("oi-5-flag", "Y");
                    if (load("pl115")) return null;
                    if ((int) ctx.shared.getOrDefault("pl-error-code", 0) == 0 && load("pl120")) return null;
                }
                case 17 -> { if (load("pl165")) return null; if (load("pl160")) return null; }
                case 18 -> { if (load("pl170")) return null; }
                case 19 -> { if (load("pl900")) return null; }
                case 20 -> {
                    boolean skip = termCode() == 3;
                    if (!skip && load("pl140")) return null;
                    while (true) {
                        if (load("xl150")) return null;
                        int t = termCode();
                        if (t == 1) { if (load("pl130")) return null; termCode(0); continue; }
                        break;
                    }
                }
                case 21 -> { if (load("pl180")) return null; }
                case 22 -> { if (load("pl190")) return null; }
                case 26 -> {
                    termCode(0);
                    SystemFile.rewrite(ctx);
                    call("sys002");
                    if (termCode() > 7) stopRun();
                    return Boolean.TRUE;
                }
                default -> { }
            }
        }
    }
}
