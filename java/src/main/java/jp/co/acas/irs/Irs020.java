package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;

import java.util.ArrayList;
import java.util.List;

/** irs020.cbl: 既定勘定（Posting Defaults）と決算書見出しの設定・修正・表示・印刷。 */
public class Irs020 extends IrsBase {
    static final String PROG_NAME = "irs020 (3.01.10)";
    private static final class ExitProgram extends RuntimeException { }
    private Rec sys, nl, def, fin;
    private FileAccess fa;
    private int menuReply, w, y, lin, cole;
    private String wsReply = " ", wsCodes = "  ", wsCodes2 = "  ", wsVat = " ", wsVat2 = " ";

    private void irsub1(int fn) { fa.fileFunction = fn; call("irsub1", nl, fa); }
    private void irsub3(int fn) { fa.fileFunction = fn; call("irsub3", def, fa); }
    private void irsub5(int fn) { fa.fileFunction = fn; call("irsub5", fin, fa); }
    private static String n2(int v) { return Num.z9(v, 2); }
    private static long toNum(String s) { return Num.parse(s).longValue(); }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        nl = newNlRecord(); def = newDefaultRecord(); fin = newFinalRecord();
        fa = fa();
        fa.fileNames = sys.str("system-files");
        term().exceptionsEnabled = true; term().escEnabled = true;
        try {
            while (true) {
                menuReply = 0;
                clearScreen();
                show(1, 1, PROG_NAME, 2);
                display(1, 29, "Default File Utilities", 7);
                show(1, 73, sys.str("run-date"), 2);
                clientLine(29);
                display(5, 1, "Select the required function by number    [");
                display(5, 45, "]");
                display(8, 6, "(1)  Set-Up Default Accounts");
                display(10, 6, "(2)  Amend  Default Accounts");
                display(12, 6, "(3)  Display the Defaults");
                display(14, 6, "(4)  Print   the Defaults");
                display(17, 6, "(5)  Set-Up Final Accounts");
                display(20, 6, "(9)  Return to System Menu");
                display(23, 1, "F1 to F5 = options 1 to 5;  Return to Accept data;   Escape to quit", 7);
                Terminal.Field r = new Terminal.Field(5, 44, 1, "0", AUTO);
                acceptScreen(List.of(r));
                menuReply = (int) toNum(r.value);
                int st = crtStatus();
                if (menuReply == 1 || st == 1001) setUp();
                else if (menuReply == 2 || st == 1002) amend();
                else if (menuReply == 3 || st == 1003) showDefaults();
                else if (menuReply == 4 || st == 1004) listing();
                else if (menuReply == 5 || st == 1005) setUpFinished();
                else if (menuReply == 9 || st == 2005) return;
            }
        } catch (ExitProgram e) {
            // go to main01-exit in init01
        }
    }

    private void clientLine(int clientSize) {
        display(3, 1, "Client -");
        show(3, 10, pad(sys.str("client"), clientSize).substring(0, Math.min(clientSize, 28)), 6);
        display(3, 39, "Start date -");
        show(3, 52, sys.str("start-date"), 6);
        display(3, 62, "End date -");
        show(3, 73, sys.str("end-date"), 6);
    }
    private void title(String text, int col) {
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, col, text, 7);
        show(1, 73, sys.str("run-date"), 2);
    }
    private void setupAmendScreen3() {
        clientLine(24);
        display(5, 4, "A/C Nos");
        display(5, 14, "Description");
        display(5, 33, "Code VAT   A/C Nos");
        display(5, 54, "Description");
        display(5, 73, "Code VAT");
        eraseEol(6, 1);
        // OCCURS 16 ... LINE PLUS 1 は GnuCOBOL では 1 行（7 行目）にのみ描画される（レガシー実測）
        display(7, 1, "01 [00000]                      [AB] [C]17 [00000]                      [DE] [F");
    }
    private void numberRows() {
        for (w = 1; w <= 16; w++) {
            y = w + 16;
            lin = 6 + w;
            show(lin, 1, n2(w), 2);
            show(lin, 41, n2(y), 2);
        }
        cole = 41;
    }

    /** set-up section。 */
    private void setUp() {
        while (true) {
            title("Default Accounts Setup", 29);
            clientLine(24);
            display(5, 1, "Add to Existing Defaults (Y/N) ? - [");
            display(5, 38, "]");
            display(7, 1, "N.B. (1) If first time setup for this client answer no (N)", 7);
            display(8, 6, "(2) Answering no (N)", 7);
            display(8, 27, "destroys", 7);
            display(8, 36, "the existing defaults", 7);
            display(23, 1, "Escape to quit;    Return to Accept data", 7);
            Terminal.Field r = new Terminal.Field(5, 37, 1, " ", AUTO);
            acceptScreen(List.of(r));
            wsReply = r.value;
            if (crtStatus() == 2005) return;
            if (up(wsReply).equals("N")) fileInit();
            if (up(wsReply).equals("Y") || up(wsReply).equals("N")) break;
        }
        title("Default Accounts Setup", 29);
        setupAmendScreen3();
        numberRows();
        inputHeadings();
        while (true) {
            // get-input
            show(lin, cole, n2(w), 2);
            long acs = toNum(acceptUpdate(lin, cole + 4, 5, Num.z9(def.longv("def-acs", w), 5)));
            def.setNum("def-acs", acs, w);
            if (acs == 0) { cole = 41; w = 30; lin = 20; continue; }
            nl.setNum("nl-owning", acs); nl.setNum("nl-sub-nominal", 0);
            irsub1(4);
            if (fa.weError == 2) continue;
            show(lin, cole + 10, nl.str("nl-name"), 6);
            show(lin, cole + 32, "[  ]", 2);
            wsCodes = def.str("def-codes", w);
            if (w < 30) wsCodes = acceptUpdate(lin, cole + 33, 2, wsCodes);
            else wsCodes = w == 30 ? "OB" : w == 31 ? "VI" : "VO";
            def.set("def-codes", up(wsCodes), w);
            show(lin, cole + 33, wsCodes, 6);
            do {
                wsVat2 = def.str("def-vat", w);
                if (w < 30) wsVat2 = accept(lin, cole + 38, 1);
                else { wsVat2 = "N"; show(lin, cole + 38, wsVat2); }
                wsVat = up(wsVat2);
                def.set("def-vat", wsVat, w);
            } while (!wsVat.equals("I") && !wsVat.equals("N") && !wsVat.equals("O"));
            w++;
            if (w > 32) break;
            if (w == 17) { cole = 41; lin = 6; }
            lin++;
        }
        irsub1(2);
        irsub3(5);
        amend();
    }

    /** amend section。 */
    private void amend() {
        title("Default Accounts Amendments", 28);
        setupAmendScreen3();
        numberRows();
        inputHeadings();
        while (true) {
            y = 0;
            display(24, 20, "Give Default to amend - [  ]  (Use 00 to quit)");
            y = (int) toNum(acceptUpdate(24, 45, 2, n2(y)));
            if (y == 0) break;
            if (y < 1 || y > 32) continue;
            w = y;
            if (y > 16) { y -= 16; cole = 41; } else cole = 1;
            lin = y + 6;
            show(lin, cole, n2(w), 2);
            long acs = toNum(acceptUpdate(lin, cole + 4, 5, Num.z9(def.longv("def-acs", w), 5)));
            def.setNum("def-acs", acs, w);
            if (acs == 0) break;
            nl.setNum("nl-owning", acs); nl.setNum("nl-sub-nominal", 0);
            irsub1(4);
            if (fa.weError == 2) continue;
            show(lin, cole + 10, nl.str("nl-name"), 6);
            show(lin, cole + 32, "[  ]", 2);
            wsCodes = def.str("def-codes", w);
            wsCodes2 = acceptUpdate(lin, cole + 33, 2, wsCodes2);
            wsCodes = up(wsCodes2);
            def.set("def-codes", wsCodes, w);
            show(lin, cole + 32, "[", 2);
            show(lin, cole + 33, wsCodes, 6);
            show(lin, cole + 35, "]", 2);
            do {
                wsVat2 = def.str("def-vat", w);
                wsVat2 = acceptUpdate(lin, cole + 38, 1, wsVat2);
                wsVat = up(wsVat2);
                def.set("def-vat", wsVat, w);
            } while (!wsVat.equals("I") && !wsVat.equals("N") && !wsVat.equals("O"));
        }
        irsub1(2);
        irsub3(5);
    }

    private static final int[] LEFT = {6, 7, 8, 9, 11, 12, 13, 14, 16, 17, 19, 20, 21, 22};
    private static final int[] RIGHT = {6, 7, 8, 0, 11, 12, 13, 0, 16, 17, 19, 20, 21, 22};

    /** Set-Up-Finished section。 */
    private void setUpFinished() {
        irsub5(3);
        if (fa.weError != 0) {
            eraseEol(23, 1);
            display(23, 1, "Failure to on Final File -", 4);
            show(23, 30, String.valueOf(fa.weError), 4);
            eraseEol(24, 1);
            display(24, 1, "Hit return to go back to menu");
            accept(24, 32, 1);
            return;
        }
        fa.accessType = 1;
        irsub1(1);
        while (true) {
            if (!sys.str("pl-app-created").equals("1")) { sys.set("pl-app-created", "0"); sys.setNum("pl-approp-ac", 0); }
            clearScreen();
            display(1, 1, "Client ");
            show(1, 8, sys.str("client"), 6);
            display(1, 34, "Finished Accounts Setup", 7);
            show(1, 73, sys.str("run-date"), 2);
            display(3, 4, "Trading and Profit & Loss Account                 Balance Sheet");
            display(4, 10, "--------Heading---------  Sign          --------Heading---------  Sign");
            display(5, 1, "Income Accounts");
            display(5, 41, "Fixed     Assets");
            display(10, 1, "Direct Cost Accounts");
            display(10, 41, "Current Assets");
            display(15, 1, "Sundry Income Accounts");
            display(15, 41, "Current Liabilities");
            display(18, 1, "Indirect Cost Accounts");
            display(18, 41, "Capital Accounts");
            List<Terminal.Field> fields = new ArrayList<>();
            List<int[]> map = new ArrayList<>();
            int r = 14;
            for (int i = 0; i < 14; i++) {
                int line = LEFT[i];
                show(line, 3, "<" + (char) ('A' + i) + ">   [", 2);
                fields.add(field(line, 10, 24, fin.str("ar1", i + 1))); map.add(new int[] {1, i + 1});
                show(line, 34, "] [", 2);
                fields.add(field(line, 37, 1, fin.str("ar2", i + 1))); map.add(new int[] {2, i + 1});
                if (RIGHT[i] == 0) { show(line, 38, "]", 2); continue; }
                r++;
                show(line, 38, "]    <" + (char) ('A' + r - 1) + ">   [", 2);
                fields.add(field(line, 50, 24, fin.str("ar1", r))); map.add(new int[] {1, r});
                show(line, 74, "] [", 2);
                fields.add(field(line, 77, 1, fin.str("ar2", r))); map.add(new int[] {2, r});
                show(line, 78, "]", 2);
            }
            display(23, 1, "P & L Appropriation Account [");
            Terminal.Field pl = field(23, 30, 5, Num.z9(sys.longv("pl-approp-ac"), 5));
            fields.add(pl);
            display(23, 35, "]");
            acceptScreen(fields);
            for (int i = 0; i < map.size(); i++) fin.set(map.get(i)[0] == 1 ? "ar1" : "ar2", fields.get(i).value, map.get(i)[1]);
            sys.setNum("pl-approp-ac", toNum(pl.value));
            if (sys.longv("pl-approp-ac") != 0) {
                sys.set("pl-app-created", "1");
                nl.setNum("nl-owning", sys.longv("pl-approp-ac")); nl.setNum("nl-sub-nominal", 0);
                irsub1(4);
                if (fa.weError == 2) {
                    display(24, 1, "Account not found. Try again!", 4);
                    display(24, 31, "Hit return to continue");
                    wsReply = accept(24, 55, 1);
                    continue;
                }
            }
            break;
        }
        irsub5(5);
        irsub1(2);
    }

    /** Show section。 */
    private void showDefaults() {
        title("Default Accounts Display", 27);
        setupAmendScreen3();
        inputHeadings();
        eraseEol(23, 1);
        display(24, 1, "End of listing. Hit return for Menu.", 7);
        wsReply = accept(24, 79, 1);
        irsub1(2);
    }

    /** listing section。 */
    private void listing() {
        eraseEos(1, 1);
        CobFile prt = openPrint();
        fa.accessType = 1;
        irsub1(1);
        writeAfter(prt, pad(sys.str("suser"), 24) + " ".repeat(5) + "Incomplete Records System" + " ".repeat(17) + sys.str("run-date"), 1);
        writeAfter(prt, pad(sys.str("client"), 24) + " ".repeat(9) + "Posting Defaults", 2);
        writeAfter(prt, "             A/C Nos     ------Description------    Code VAT", 2);
        writeAfter(prt, "", 2);
        irsub3(3);
        for (w = 1; w <= 32; w++) {
            long acs = def.longv("def-acs", w);
            String desc = " ".repeat(25), code = "  ", vat = " ";
            nl.setNum("nl-owning", acs); nl.setNum("nl-sub-nominal", 0);
            if (acs != 0) {
                irsub1(4);
                desc = pad(nl.str("nl-name"), 25); code = def.str("def-codes", w); vat = def.str("def-vat", w);
            }
            writeAfter(prt, " ".repeat(10) + Num.edit(w, "z9") + "  " + (acs == 0 ? "      " : Num.edit(acs, "zzzz9") + " ")
                    + " ".repeat(5) + desc + "   " + code + " ".repeat(5) + vat, 1);
        }
        irsub1(2);
        printReport(sys, prt);
    }

    /** file-init section。 */
    private void fileInit() {
        display(5, 51, "Enter pass-word - [    ]");
        String wsPass = accept(5, 70, 4, SECURE);
        if (!wsPass.equals(sys.str("pass-word"))) { wsReply = "Z"; return; }
        byte[] b = def.bytes();
        java.util.Arrays.fill(b, (byte) '0');
        irsub3(5);
    }

    /** Input-Headings section。 */
    private void inputHeadings() {
        fa.accessType = 1;
        irsub1(1);
        if (fa.weError != 0) {
            display(23, 1, "You must Setup Chart of Accounts first (Selection no. 2)");
            display(24, 1, "Hit return for return to Main Menu", 7);
            wsReply = accept(24, 43, 1);
            throw new ExitProgram();
        }
        w = 1; cole = 1; lin = 7;
        irsub3(3);
        while (true) {
            show(lin, cole, n2(w), 2);
            long acs = def.longv("def-acs", w);
            show(lin, cole + 4, Num.z9(acs, 5), 6);
            nl.setNum("nl-owning", acs); nl.setNum("nl-sub-nominal", 0);
            if (acs != 0) {
                irsub1(4);
                show(lin, cole + 10, nl.str("nl-name").substring(0, 22), 6);
            }
            wsCodes = def.str("def-codes", w);
            show(lin, cole + 33, wsCodes, 6);
            wsVat = def.str("def-vat", w);
            show(lin, cole + 38, wsVat, 6);
            show(lin, cole + 39, "]", 2);
            w++;
            if (w > 32) break;
            if (w == 17) { cole = 41; lin = 6; }
            lin++;
        }
        w = 1; cole = 1; lin = 7;
    }
}
