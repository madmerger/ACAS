package jp.co.acas.irs;

import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/** irs.cbl: IRS（簡易会計）システムメニューとシステムファイル設定。 */
public class Irs extends IrsBase {
    static final String PROG_NAME = "IRS (3.01.18)";
    private Rec sys;
    private FileAccess fa;
    private String wsPass = "    ";
    /** data-files（system-files と同じ 49 桁。末尾 1 桁が op-system）。 */
    private String dataFiles = "acnts.dat" + "system.dat" + "dflt.dat" + "post.dat" + pad("prn", 12) + " " + "0";
    private String exitToSystem = "to Linux";
    private String batchText = "";

    private int opSystem() { char c = dataFiles.charAt(48); return c >= '0' && c <= '9' ? c - '0' : 0; }
    private void opSystem(int v) { dataFiles = dataFiles.substring(0, 48) + v; }
    private boolean validOs() { int o = opSystem(); return o >= 1 && o <= 6; }

    private String today() {
        LocalDate d = ctx.today();
        return Num.z9(d.getDayOfMonth(), 2) + "/" + Num.z9(d.getMonthValue(), 2) + "/" + Num.z9(d.getYear() % 100, 2);
    }

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        sys = newSystemRecord();
        fa = fa();
        sys.set("fn-2", "system.dat");
        fa.fileFunction = 3;
        call("irsub2", sys, fa);
        if (fa.weError == 1) {
            sys.setNum("next-post", 0);
            sys.set("run-date", today());
            setUp();
        }
        dataFiles = sys.str("system-files");
        char sp = sys.str("print-spool-name").charAt(0);
        if (!(sp >= 'A' && sp <= 'Z' || sp >= 'a' && sp <= 'z' || sp >= '0' && sp <= '9')) {
            sys.set("print-spool-name", "");
            setUp();
        }
        exitToSystem = switch (opSystem()) {
            case 1 -> "to Dos"; case 2 -> "to Windows"; case 3 -> "to Mac OS/X";
            case 4 -> "to OS/2"; case 5 -> "to Unix"; case 6 -> "to Linux";
            default -> "to Unknown System";
        };
        if (!today().equals(sys.str("run-date"))) {
            sys.set("run-date", today());
            setUp();
        }
        // バックアップスクリプト（irsbakup.sh 等）は Web 版には存在しない
        batchText = "Back Up Script Not Found";
        ctx.shared.put("irs.system-record", sys);
        mainLoop();
        // eoj
        fa.fileFunction = 5;
        call("irsub2", sys, fa);
        fa.fileFunction = 2;
        call("irsub2", sys, fa);
        stopRun();
    }

    private void mainLoop() {
        while (true) {
            // Menu-Screen-1
            clearScreen();
            show(1, 1, PROG_NAME, 2);
            display(1, 31, "S Y S T E M   M E N U", 7);
            show(1, 73, sys.str("run-date"), 2);
            display(3, 1, "Client -");
            show(3, 10, pad(sys.str("client"), 29), 6);
            display(3, 39, "Start date -");
            show(3, 52, sys.str("start-date"), 6);
            display(3, 62, "End date -");
            show(3, 73, sys.str("end-date"), 6);
            display(5, 1, "Select the required function    [");
            display(5, 35, "]");
            display(7, 6, "(1)  System Set-Up & Maintenance");
            display(8, 6, "(2)  Accounts Set-Up & Maintenance");
            display(9, 6, "(3)  Default A/Cs Set-Up & Maintenance");
            display(10, 6, "(4)  Posting");
            display(11, 6, "(5)  Trial Balance");
            display(12, 6, "(6)  Audit Trail");
            display(13, 6, "(7)  Accounts Production");
            display(14, 6, "(8)  Posting Amendments");
            display(15, 6, "(9)  Analysis Report");
            display(16, 6, "(A)  Nominal File Fix up");
            display(20, 6, "(X)  Exit");
            display(20, 16, pad(exitToSystem, 18));
            display(20, 41, pad(batchText, 28), 3);
            display(23, 1, "F1 to F10 = options 1 to A;  Return to Accept data;   Escape to quit", 7);
            Terminal.Field reply = new Terminal.Field(5, 34, 1, " ", AUTO);
            acceptScreen(List.of(reply));
            String r = reply.value;
            int st = crtStatus();
            if (r.equals("1") || st == 1001) { setUp(); continue; }
            if (r.equals("2") || st == 1002) { call("irs010", sys); continue; }
            if (r.equals("3") || st == 1003) { call("irs020", sys); continue; }
            if (r.equals("4") || st == 1004) { call("irs030", sys); continue; }
            if (r.equals("5") || st == 1005) { call("irs040", sys); continue; }
            if (r.equals("6") || st == 1006) { call("irs050", sys); continue; }
            if (r.equals("7") || st == 1007) { call("irs065", sys); call("irs060", sys); continue; }
            if (r.equals("8") || st == 1008) { call("irs070", sys); continue; }
            if (r.equals("9") || st == 1009) { call("irs085", sys); call("irs090", sys); continue; }
            if (r.equals("|")) {
                String prog = accept(1, 1, 6);
                call(prog.trim(), sys);
                continue;
            }
            if (r.equalsIgnoreCase("a") || st == 1010) { call("irs080", sys); continue; }
            if (!r.equalsIgnoreCase("x") && st != 2005) continue;
            return;
        }
    }

    /** set-up section。 */
    private void setUp() {
        // Menu-Screen-2
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 32, "SYSTEM FILE SET-UP", 7);
        show(1, 73, sys.str("run-date"), 2);
        display(4, 6, "Date - {");
        show(4, 14, sys.str("run-date"));
        display(4, 22, "}");
        display(4, 46, "Pass Word - {");
        show(4, 59, "****");
        display(4, 63, "}");
        // get-run-date
        while (true) {
            sys.set("run-date", acceptUpdate(4, 14, 8, sys.str("run-date")));
            if (crtStatus() == 2005) return;
            Object[] v = dateValidate(sys.str("run-date"));
            if ((int) v[1] == 0) { display(4, 24, "Date error", 4); continue; }
            show(4, 24, " ".repeat(10));
            sys.set("run-date", (String) v[0]);
            break;
        }
        show(4, 59, "    ");
        wsPass = accept(4, 59, 4, SECURE);
        if (crtStatus() == 2005) return;
        if (!wsPass.equals(sys.str("pass-word"))) return;
        display(4, 65, "New ", 3);
        sys.set("pass-word", acceptUpdate(4, 59, 4, sys.str("pass-word"), SECURE));
        if (crtStatus() == 2005) return;
        eraseEol(4, 65);
        if (!validOs()) opSystem(0);
        // Menu-Screen-3
        display(6, 6, "User - [");
        display(6, 38, "]");
        display(6, 46, "VAT Rate  - [");
        display(6, 63, "]");
        display(8, 6, "Client        Name - [");
        display(8, 52, "]");
        display(9, 20, "Addr - [");
        display(9, 52, "]");
        display(10, 27, "["); display(10, 52, "]");
        display(11, 27, "["); display(11, 52, "]");
        display(12, 27, "["); display(12, 52, "]");
        display(14, 6, "Period");
        display(14, 20, "Start Date - [");
        display(14, 42, "]");
        display(15, 20, "End   Date - [");
        display(15, 42, "]");
        display(17, 2, "Operating System ");
        display(17, 20, "- [");
        display(17, 24, "]");
        display(17, 26, pad(pad(exitToSystem, 18).substring(2, 12), 10));
        display(18, 2, "(1=Dos, 2=Windows, 3=Mac OS/10, 4=OS/2, 5=Unix, 6=Linux)");
        display(20, 2, "Cups Spool Name - [");
        display(20, 53, "]");
        display(23, 1, "Escape to quit;  Tab for next field  Ret. to Accept data", 7);
        Terminal.Field fUser = field(6, 14, 24, sys.str("suser"));
        Terminal.Field fVat = field(6, 59, 4, Num.z9(sys.num("vat").movePointRight(2).longValue(), 4));
        Terminal.Field fClient = field(8, 28, 24, sys.str("client"));
        Terminal.Field fA1 = field(9, 28, 24, sys.str("address-1"));
        Terminal.Field fA2 = field(10, 28, 24, sys.str("address-2"));
        Terminal.Field fA3 = field(11, 28, 24, sys.str("address-3"));
        Terminal.Field fA4 = field(12, 28, 24, sys.str("address-4"));
        Terminal.Field fStart = field(14, 34, 8, sys.str("start-date"));
        Terminal.Field fEnd = field(15, 34, 8, sys.str("end-date"));
        Terminal.Field fOs = field(17, 23, 1, String.valueOf(opSystem()));
        Terminal.Field fSpool = field(20, 21, 32, sys.str("print-spool-name"));
        acceptScreen(List.of(fUser, fVat, fClient, fA1, fA2, fA3, fA4, fStart, fEnd, fOs, fSpool));
        sys.set("suser", fUser.value);
        // 画面の数字項目（99v99）は入力文字列を整数として MOVE するため小数部は 00、上位桁は切り捨てられる
        sys.setNum("vat", new BigDecimal(Num.parse(fVat.value).toBigInteger().mod(java.math.BigInteger.valueOf(100))));
        sys.set("client", fClient.value);
        sys.set("address-1", fA1.value);
        sys.set("address-2", fA2.value);
        sys.set("address-3", fA3.value);
        sys.set("address-4", fA4.value);
        sys.set("start-date", fStart.value);
        sys.set("end-date", fEnd.value);
        opSystem(Num.parse(fOs.value).intValue() % 10);
        sys.set("print-spool-name", fSpool.value);
        // get-startd
        while (true) {
            Object[] v = dateValidate(sys.str("start-date"));
            if ((int) v[1] == 0) {
                display(14, 44, "Date error", 3);
                sys.set("start-date", acceptUpdate(14, 34, 8, sys.str("start-date")));
                continue;
            }
            show(14, 44, " ".repeat(10));
            sys.set("start-date", (String) v[0]);
            break;
        }
        // get-endd
        while (true) {
            Object[] v = dateValidate(sys.str("end-date"));
            if ((int) v[1] == 0) {
                display(15, 44, "Date error", 3);
                sys.set("end-date", acceptUpdate(15, 34, 8, sys.str("end-date")));
                continue;
            }
            show(15, 44, " ".repeat(10));
            sys.set("end-date", (String) v[0]);
            break;
        }
        // get-os
        while (!validOs()) {
            display(17, 26, "Invalid option", 3);
            opSystem(Num.parse(acceptUpdate(17, 23, 1, String.valueOf(opSystem()))).intValue() % 10);
        }
        display(17, 30, switch (opSystem()) {
            case 1 -> "DOS"; case 2 -> "Windows"; case 3 -> "Mac OSX"; case 4 -> "OS/2"; case 5 -> "Unix"; default -> "Linux";
        }, 3);
        sys.set("system-files", dataFiles);
        sys.set("system-work-group", "");
        sys.setNum("pass-value", 0); sys.setNum("save-sequ", 0); sys.setNum("first-time-flag", 0);
        if (!numeric(sys.str("next-post"))) sys.setNum("next-post", 0);
        fa.fileFunction = 5;
        call("irsub2", sys, fa);
        wsPass = "    ";
        dataFiles = sys.str("system-files");
    }
}
