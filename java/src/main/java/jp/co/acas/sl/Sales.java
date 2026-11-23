package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

/** sales.cbl: 売掛元帳システムメニュー。 */
public class Sales extends SlProgram {
    static final String PROG_NAME = "Sales (3.01.18)";
    private Rec sys;
    private String toDay = "";
    /** menu-reply の初期値 "A": 実行単位で最初の 1 回だけ日付入力（sl000）へ直行する。 */
    private boolean firstTime = true;

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        while (true) {
            // Open-System
            if (!SystemFile.read(ctx).equals("00")) {
                if (!call("mapser")) { display(12, 1, "SL009 Environment variables not yet set up : ABORTING", 3); stopRun(); }
                SystemFile.read(ctx);
            }
            sys = sys();
            readSys4();
            if (sys.intv("scycle") == 0) { callSystemSetup(); continue; }
            toDay = Acas_convert(Maps04.toDate(sys.longv("run-date")));
            toDay(toDay);
            if (sys.intv("level-3") != 1) {
                ctx.shared.put("error-code", 1); call("maps99");
                ctx.shared.put("error-code", 15); call("maps99");
                return;
            }
            ctx.shared.put("ws-process-func", 0); ctx.shared.put("ws-sub-function", 0);
            if (firstTime) { firstTime = false; if (load(1)) { overrewrite(); stopRun(); } }
            int r = menu();
            if (r == 1) continue;
            return;
        }
    }

    private String Acas_convert(String uk) { return fromUk(uk); }

    private void readSys4() {
        CobFile f = SystemFile.file(ctx);
        f.open(CobFile.Mode.IO);
        if (!f.ok()) return;
        f.rrn = 4;
        f.read(sys4());
        f.close();
    }

    private void callSystemSetup() {
        termCode(0);
        SystemFile.rewrite(ctx);
        ctx.shared.put("ws-called", "sys002");
        if (!call("sys002")) { display(23, 31, "Sorry not available"); stopRun(); }
        if (termCode() > 7) stopRun();
    }

    /** overrewrite: システムレコード（rrn 1）と system-record-4（rrn 4）を書き戻す。 */
    private void overrewrite() {
        SystemFile.rewrite(ctx);
        CobFile f = SystemFile.file(ctx);
        f.open(CobFile.Mode.IO);
        if (f.ok()) { f.rrn = 4; f.rewrite(sys4()); f.close(); }
    }

    private String opDisplay() {
        return switch (sys.intv("op-system")) {
            case 0 -> "O/S"; case 1 -> "Dos"; case 2 -> "Windows"; case 3 -> "Mac"; case 4 -> "OS/2"; case 5 -> "Unix"; case 6 -> "Linux";
            default -> "";
        };
    }
    /** レガシーの Conv-date（表示用に u-date を日付形式へ）。 */
    private String convDate(String u) {
        int form = sys.intv("date-form");
        if (form == 2) return u.substring(3, 5) + u.substring(2, 3) + u.substring(0, 2) + u.substring(5);
        if (form == 3) return u.substring(6, 10) + "/" + u.substring(3, 5) + "/" + u.substring(0, 2);
        return u;
    }

    /** display-menu 〜 accept-loop。戻り値 1: Open-System からやり直す、0: 終了（goback）。 */
    private int menu() {
        while (true) {
            clearScreen();
            toDay = toDay();
            ctx.shared.put("ws-caller", "sales"); ctx.shared.put("ws-called", ""); ctx.shared.put("ws-del-link", "");
            termCode(0);
            showMapsSer(3);
            var now = ctx.now();
            display(24, 1, "Copyright (c) 1976-", 3);
            show(24, 20, z(now.getYear(), 4));
            display(24, 24, " Applewood Computers", 3);
            show(1, 1, sys.str("usera"));
            show(1, 71, convDate(toDay));
            display(3, 1, PROG_NAME);
            display(3, 29, "Sales Ledger System Menu");
            display(3, 55, "at ");
            show(3, 58, timeNow(), 2);
            display(3, 67, "on ");
            // wsa-yy を u-year（集団項目）へ転記するため年は 2 桁＋空白 2 桁になる
            String u = String.format("%02d/%02d/%02d  ", now.getDayOfMonth(), now.getMonthValue(), now.getYear() % 100);
            show(3, 70, convDate(u), 2);
            display(6, 1, "Select one of the following by letter  :- [ ]");
            display(10, 4, "(A)  Date Entry");
            display(11, 4, "(B)  Customer File Maintenance");
            display(12, 4, "(C)  Sales Ledger Enquiry");
            display(13, 4, "(D)  Sales Transactions Input");
            display(14, 4, "(E)  Sales Transactions Amend");
            display(15, 4, "(F)  Sales Transactions Proof");
            display(16, 4, "(G)  Sales Transactions Post");
            display(17, 4, "(H)  Payment Input");
            display(18, 4, "(I)  Payment Amend");
            display(19, 4, "(J)  Payment Proof");
            display(20, 4, "(K)  Payment Post");
            display(21, 4, "(L)  Set-Up Sales Analysis Codes");
            display(22, 4, "(M)  Sales Analysis Report");
            display(10, 44, "(N)  Sales Day Book");
            display(11, 44, "(O)  Statement Production");
            display(12, 44, "(P)  Dunning Letters Generation");
            display(13, 44, "(Q)  Aged Debtors Analysis");
            display(14, 44, "(R)  Alphabetical Customer List");
            display(15, 44, "(S)  Customer Turnover Report");
            display(16, 44, "(T)  Invoice Sub-System");
            display(17, 44, "(U)  End of Cycle Processing");
            display(18, 44, "(V)  Customer File Dump");
            display(20, 44, "(X)  Exit To ");
            show(20, 57, pad(opDisplay(), 6), 2);
            // レガシーは ACAS_BIN のバックアップスクリプト有無を表示する（Web 版は DB 保存のためスクリプト実行はしない）
            int os = sys.intv("op-system");
            String script = os == 1 || os == 2 ? "acasbkup.bat" : os == 4 ? "acasbkup.cmd" : os == 3 || os == 5 || os == 6 ? "acasbkup.sh" : "";
            display(21, 49, "Using ");
            show(21, 55, pad(script, 22), 2);
            display(23, 44, "(Z)  System Setup");
            while (true) {
                String reply = upper(accept(6, 44, 1, AUTO));
                if (reply.equals("X")) { clearScreen(); overrewrite(); return 0; }
                int z = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(reply) + 1;
                if (z == 0 || reply.isBlank()) continue;
                if (z == 25) { display(23, 31, "Sorry not available"); continue; }
                if (z == 26) { callSystemSetup(); return 1; }
                if (z == 23 || z == 24) break;
                if (load(z)) { overrewrite(); stopRun(); }
                break;
            }
        }
    }

    /** load00 / load000: CALL ws-called。true は ws-term-code > 7（overrewrite して終了）。 */
    private boolean load00(String name) {
        termCode(0);
        ctx.shared.put("ws-called", name);
        call(name);
        return termCode() > 7;
    }

    /** load01 〜 load22。true は異常終了（ws-term-code > 7）。 */
    private boolean load(int z) {
        switch (z) {
            case 1: return load00("sl000");
            case 2: return load00("sl010");
            case 3: return load00("sl020");
            case 4: sys.setNum("pass-value", 2); return load00("sl910");
            case 5: sys.setNum("pass-value", 4); return load00("sl920");
            case 6: return load00("sl050");
            case 7:
                if (load00("sl055")) return true;
                if (termCode() != 0) return false;
                return load00("sl060");
            case 8: return load00("sl080");
            case 9: return load00("sl085");
            case 10: if (load00("sl090")) return true; return load00("sl095");
            case 11: return load00("sl100");
            case 12: return load00("sl070");
            case 13: return load00("sl130");
            case 14: return load00("sl140");
            case 15: if (load00("sl115")) return true; return load00("sl110");
            case 16: if (load00("sl115")) return true; return load00("sl190");
            case 17: if (load00("sl115")) return true; return load00("sl120");
            case 18: if (load00("sl165")) return true; return load00("sl160");
            case 19: return load00("sl180");
            case 20: return load00("sl900");
            case 21:
                if (load00("sl140")) return true;
                while (true) {
                    if (load00("xl150")) return true;
                    if (termCode() == 2 || termCode() == 3) return false;
                    if (termCode() == 1) { if (load00("sl130")) return true; termCode(0); continue; }
                    return false;
                }
            case 22: return load00("sl170");
            default: return false;
        }
    }
}
