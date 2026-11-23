package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;

import java.util.List;

/** irs010.cbl: 勘定科目表（Chart of Accounts）の設定・修正・表示・印刷・エクスポート・インポート。 */
public class Irs010 extends IrsBase {
    static final String PROG_NAME = "irs010 (3.01.11)";
    static final String ROW = "[     ]           [ ]             [     ]   [                        ]   [ ]";
    private Rec sys, nl;
    private FileAccess fa;
    private String menuReply = " ", wsReply = " ", inputType = " ", inputType2 = " ", nlAc2 = " ";
    private String archiveName = pad("coa-archived.txt", 32), exportFormat = "T";
    private int lin, cole, counter;
    private final int wsLines = 24;
    private int acceptLines;

    private void irsub1(int fn) { fa.fileFunction = fn; call("irsub1", nl, fa); }
    private void irsub1(int fn, int access) { fa.accessType = access; irsub1(fn); }
    private boolean subInput() { return inputType.equalsIgnoreCase("y"); }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        nl = newNlRecord();
        fa = fa();
        fa.fileNames = sys.str("system-files");
        term().exceptionsEnabled = true; term().escEnabled = true;
        while (true) {
            if (sys.intv("first-time-flag") == 0) {
                clearNl();
                if (menuReply.equals("0")) sys.setNum("first-time-flag", 1);
            }
            menuReply = "0";
            clearScreen();
            show(1, 1, PROG_NAME, 2);
            display(1, 29, "Accounts File Utilities", 7);
            show(1, 73, sys.str("run-date"), 2);
            clientLine();
            display(5, 1, "Select the required function by number    [");
            display(5, 45, "]");
            display(8, 6, "(1)  Set-Up Chart of Accounts");
            display(10, 6, "(2)  Amend  Chart of Accounts");
            display(12, 6, "(3)  Display the Chart");
            display(14, 6, "(4)  Print   the Chart");
            display(15, 6, "(5)  Export  the Chart");
            display(16, 6, "(6)  Import  the Chart");
            display(18, 6, "(9)  Return to System Menu");
            display(23, 1, "F1 to F4 = options 1 to 4;  Return to Accept data;   Escape to quit", 7);
            Terminal.Field r = new Terminal.Field(5, 44, 1, menuReply, AUTO);
            acceptScreen(List.of(r));
            menuReply = r.value;
            int st = crtStatus();
            if (menuReply.equals("1") || st == 1001) setUp();
            else if (menuReply.equals("2") || st == 1002) amend();
            else if (menuReply.equals("3") || st == 1003) showChart();
            else if (menuReply.equals("4") || st == 1004) listing();
            else if (menuReply.equals("5") || st == 1005) exportCoa();
            else if (menuReply.equals("6") || st == 1006) importCoa();
            else if (menuReply.equals("9") || st == 2005) return;
        }
    }

    private void clientLine() {
        display(3, 1, "Client -");
        show(3, 10, sys.str("client"), 6);
        display(3, 39, "Start date -");
        show(3, 52, sys.str("start-date"), 6);
        display(3, 62, "End date -");
        show(3, 73, sys.str("end-date"), 6);
    }
    private void setupScreen1() {
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 30, "Chart of Accounts Setup", 7);
        show(1, 73, sys.str("run-date"), 2);
    }
    private void amendScreen1() {
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 28, "Chart of Accounts Amendments", 7);
        show(1, 73, sys.str("run-date"), 2);
    }
    private void setupAmendScreen3() {
        clientLine();
        display(4, 2, "Main A/C      Sub-Nominal       Sub-Account       Description          A/C Type");
        eraseEol(5, 1);
        // OCCURS 16 ... LINE PLUS 1 の行は GnuCOBOL では 6 行目に重ねて描画される（レガシー実測）
        display(6, 2, ROW);
    }
    /** setup-display 段落。 */
    private void setupDisplay() { for (int l = 22; l <= acceptLines; l++) display(l, 2, ROW); }

    private String acceptNum5(int line, int col, long cur) { return acceptUpdate(line, col, 5, Num.z9(cur, 5)); }

    /** set-up section。 */
    private void setUp() {
        while (true) {
            setupScreen1();
            clientLine();
            display(5, 1, "Add to Existing Chart (Y/N) ? - [");
            display(5, 35, "]");
            display(7, 1, "N.B. (1) If first time setup for this client answer no (N)", 7);
            display(8, 6, "(2) Answering no (N)", 7);
            display(8, 27, "destroys", 7);
            display(8, 36, "the existing chart", 7);
            display(23, 1, "Escape to quit;    Return to Accept data", 7);
            Terminal.Field r = new Terminal.Field(5, 34, 1, " ", AUTO);
            acceptScreen(List.of(r));
            menuReply = r.value;
            acceptLines = wsLines - 1;
            if (crtStatus() == 2005) return;
            if (up(menuReply).equals("N")) fileInit();
            if (up(menuReply).equals("Y") || up(menuReply).equals("N")) { fa.accessType = 2; break; }
        }
        irsub1(1);
        setupScreen1();
        setupAmendScreen3();
        setupDisplay();
        lin = 6;
        while (true) {
            // input02-loop
            display(lin, 1, " " + ROW);
            boolean output = false;
            if (!subInput()) {
                nl.setNum("nl-owning", 0); nl.setNum("nl-sub-nominal", 0);
                nl.setNum("nl-owning", Num.parse(acceptNum5(lin, 3, 0)).longValue());
                if (nl.longv("nl-owning") == 0) break;
                boolean isNew = fa.accessType == 3;
                if (!isNew) {
                    irsub1(4);
                    if (fa.weError == 2) { show(wsLines, 1, " ".repeat(78)); isNew = true; }
                }
                if (!isNew) {
                    show(lin, 47, nl.str("nl-name"));
                    display(wsLines, 1, "Record already exists re-enter!", 7);
                    continue;
                }
                do {
                    inputType2 = acceptUpdate(lin, 21, 1, inputType2);
                    inputType = up(inputType2);
                } while (!inputType.equals("N") && !inputType.equals("Y"));
                nl.set("nl-name", "");
                nl.set("nl-name", acceptUpdate(lin, 47, 24, nl.str("nl-name")));
                acceptAc(lin);
                nl.set("nl-type", "O");
                sys.setNum("first-time-flag", 1);
                output = true;
            } else {
                // input02-sub
                boolean ret = false;
                while (true) {
                    nl.setNum("nl-sub-nominal", 0);
                    nl.setNum("nl-sub-nominal", Num.parse(acceptNum5(lin, 37, 0)).longValue());
                    if (nl.longv("nl-sub-nominal") == 0) { inputType = "N"; lin--; ret = true; break; }
                    irsub1(4);
                    if (fa.weError == 2) { show(wsLines, 1, " ".repeat(78)); break; }
                    show(lin, 37, nl.str("nl-name"), 2);
                    display(wsLines, 1, "Record already exists re-enter!   Key is - ", 7);
                    show(wsLines, 45, nl.str("nl-key"), 3);
                }
                if (!ret) {
                    nl.set("nl-name", "");
                    nl.set("nl-name", acceptUpdate(lin, 47, 24, nl.str("nl-name")));
                    nl.set("nl-type", "S");
                    output = true;
                }
            }
            if (output) { zeroAmounts(nl); irsub1(5); }
            // main02-return
            lin++;
            show(lin, 1, " ".repeat(80));
            if (lin < acceptLines) continue;
            for (lin = 6; lin < acceptLines; lin++) show(lin, 1, " ".repeat(80));
            // return02-loop は最終行 (lin = accept-lines - 1 の次) まで消去する
            lin = 6;
        }
        irsub1(2);
    }

    private void acceptAc(int line) {
        do {
            nlAc2 = acceptUpdate(line, 76, 1, nlAc2);
            nl.set("nl-ac", up(nlAc2));
        } while (nl.str("nl-ac").compareTo("A") < 0 || nl.str("nl-ac").compareTo("Z") > 0);
    }

    /** amend section。 */
    private void amend() {
        amendScreen1();
        setupAmendScreen3();
        acceptLines = wsLines - 1;
        setupDisplay();
        irsub1(1, 2);
        lin = 6;
        while (true) {
            // input03-loop
            inputType = " ";
            nl.setNum("nl-owning", 0); nl.setNum("nl-sub-nominal", 0);
            nl.setNum("nl-owning", Num.parse(acceptNum5(lin, 3, 0)).longValue());
            if (nl.longv("nl-owning") == 0) break;
            irsub1(4);
            if (fa.weError == 2) continue;
            show(lin, 47, nl.str("nl-name"));
            boolean again = false, ret = false;
            while (true) {
                inputType2 = acceptUpdate(lin, 21, 1, inputType2);
                inputType = up(inputType2);
                if (inputType.equals("D")) { deleteRecord(); again = true; break; }
                if (inputType.equals("N") || inputType.equals("Y")) break;
            }
            if (again) continue;
            if (inputType.equals("N")) {
                nl.set("nl-name", acceptUpdate(lin, 47, 24, nl.str("nl-name")));
                acceptAc(lin);
                nl.set("nl-type", "O"); inputType = "O";
            } else {
                // input03-sub
                nl.setNum("nl-sub-nominal", 0);
                nl.setNum("nl-sub-nominal", Num.parse(acceptNum5(lin, 37, 0)).longValue());
                if (nl.longv("nl-sub-nominal") == 0) { inputType = "N"; lin--; ret = true; }
                else {
                    irsub1(4);
                    if (fa.weError != 2) {
                        show(lin, 47, nl.str("nl-name"));
                        inputType = "O"; nl.set("nl-type", "O");
                        nl.set("nl-name", acceptUpdate(lin, 47, 24, nl.str("nl-name")));
                        acceptAc(lin);
                    } else {
                        nl.set("nl-name", acceptUpdate(lin, 47, 24, nl.str("nl-name")));
                        nl.set("nl-type", "S"); inputType = "S";
                        zeroAmounts(nl);
                    }
                }
            }
            if (!ret) irsub1(inputType.equals("S") ? 5 : 7);
            // main03-return
            lin++;
            if (lin < acceptLines) continue;
            lin = 6;
            amendScreen1();
            setupAmendScreen3();
            acceptLines = wsLines - 1;
        }
        irsub1(2);
    }

    /** show section。 */
    private void showChart() {
        counter = 0; lin = 7;
        acceptLines = wsLines - 2;
        irsub1(1, 1);
        boolean openErr = fa.weError == 1;
        displayScreen1();
        if (!openErr) {
            while (true) {
                irsub1(3);
                if (fa.weError == 3) break;
                long own = nl.longv("nl-sub-nominal") != 0 ? 0 : nl.longv("nl-owning");
                show(lin, 12, own == 0 ? "     " : Num.edit(own, "zzzzz"), 6);
                show(lin, 23, nl.longv("nl-sub-nominal") == 0 ? "     " : Num.edit(nl.longv("nl-sub-nominal"), "zzzzz"), 6);
                show(lin, 36, nl.str("nl-name"), 6);
                show(lin, 66, nl.str("nl-ac"), 6);
                lin++;
                if (lin < acceptLines) continue;
                display(wsLines, 18, "Enter <N> for Next screen or <X> to Quit.......[ ]", 3);
                wsReply = up(accept(wsLines, 66, 1, AUTO));
                if (wsReply.equals("X")) { irsub1(2); return; }
                clearScreen();
                lin = 7;
                displayScreen1();
            }
        }
        eraseEol(wsLines, 18);
        display(wsLines, 18, "End of display. Hit return for Menu.", 3);
        wsReply = accept(wsLines, 56, 1);
        irsub1(2);
    }
    private void displayScreen1() {
        counter++;
        clearScreen();
        show(1, 1, sys.str("suser"), 2);
        display(1, 28, "Incomplete Records System", 7);
        show(1, 73, sys.str("run-date"), 2);
        display(3, 1, "Client -");
        show(3, 10, sys.str("client"), 6);
        display(3, 32, "Accounts Directory");
        display(3, 73, "Page");
        show(3, 78, Num.edit(counter, "zz9"), 6);
        display(5, 11, "  Main       Sub             Description              Type ", 7);
    }

    /** listing section。 */
    private void listing() {
        counter = 0;
        irsub1(1, 1);
        CobFile prt = openPrint();
        int lineCnt = 85;
        while (true) {
            irsub1(3);
            if (fa.weError == 3) break;
            if (lineCnt > 80) {
                counter++;
                String l1 = pad(sys.str("suser"), 24) + "    " + pad("Incomplete Records System", 26) + " ".repeat(18) + sys.str("run-date");
                String l3 = pad(sys.str("client"), 24) + " ".repeat(7) + "Accounts Directory" + " ".repeat(22) + "Page -" + Num.edit(counter, "zz9");
                String l4 = " ".repeat(11) + "  Main A/C       Sub-Account     ------Description------" + "    A/C Type";
                if (counter != 1) writeAfterPage(prt, l1); else writeAfter(prt, l1, 1);
                writeAfter(prt, l3, 2);
                writeAfter(prt, l4, 2);
                writeAfter(prt, "", 1);
                lineCnt = 6;
            }
            long own = nl.longv("nl-sub-nominal") != 0 ? 0 : nl.longv("nl-owning"), sub = nl.longv("nl-sub-nominal");
            writeAfter(prt, " ".repeat(14) + (own == 0 ? "     " : Num.edit(own, "zzzz9")) + " ".repeat(12)
                    + (sub == 0 ? "     " : Num.edit(sub, "zzzz9")) + " ".repeat(8) + nl.str("nl-name") + " ".repeat(7) + nl.str("nl-ac"), 1);
            lineCnt++;
        }
        irsub1(2);
        printReport(sys, prt);
    }

    /** file-init section。 */
    private void fileInit() {
        display(5, 51, "Enter Pass-word - [    ]");
        String wsPass = accept(5, 70, 4, SECURE);
        if (wsPass.equals(sys.str("pass-word"))) { irsub1(1, 3); irsub1(2); }
        else wsReply = "Z";
        fa.accessType = 2;
    }

    /** delete-record section。 */
    private void deleteRecord() {
        irsub1(4);
        if (fa.weError == 2) return;
        irsub1(8);
        long saveOwning = nl.longv("nl-owning");
        irsub1(9, 6);
        while (nl.longv("nl-owning") == saveOwning) {
            irsub1(8);
            saveOwning = nl.longv("nl-owning");
            if (nl.longv("nl-sub-nominal") != 0) {
                nl.setNum("nl-owning", nl.longv("nl-sub-nominal"));
                nl.setNum("nl-sub-nominal", 0);
                call("irsub1", nl, fa);
                nl.setNum("nl-owning", saveOwning);
            }
            irsub1(2);
            irsub1(1, 2);
            nl.setNum("nl-sub-nominal", 0);
            irsub1(9, 6);
            if (fa.weError != 0) break;
        }
    }

    private CobFile archive() { return CobFile.lineSequential(ctx.store, ctx.irsPath(archiveName.trim())); }

    /** ea-Export-CoA section。 */
    private void exportCoa() {
        eraseEos(1, 1);
        display(1, 1, "This process will export a copy of the current CoA (Chart of Accounts)", 3);
        display(2, 21, "overwriting any copy of the file if it exists.", 3);
        display(4, 1, "Continue Y/N [ ]", 7);
        menuReply = accept(4, 15, 1);
        if (menuReply.equalsIgnoreCase("n")) { menuReply = "1"; return; }
        display(6, 1, "File name to be created [12345678901234567890123456789012]", 3);
        archiveName = acceptUpdate(6, 26, 32, archiveName);
        if (archiveName.isBlank() || crtStatus() == 2005) { eraseEol(10, 1); display(10, 1, "Quiting to menu"); return; }
        display(8, 1, "Format: T(xt) or (C)omma delimited?  [T]", 3);
        exportFormat = up(acceptUpdate(8, 39, 1, exportFormat));
        if (!exportFormat.equals("T") && !exportFormat.equals("C")) return;
        CobFile out = archive();
        if (!out.open(CobFile.Mode.OUTPUT).equals("00")) {
            display(23, 1, "Problem opening Export File, hit return to quit action");
            wsReply = accept(23, 60, 1);
            return;
        }
        counter = 0;
        irsub1(1, 1);
        fa.fileFunction = 3;
        while (true) {
            call("irsub1", nl, fa);
            if (fa.weError == 3) break;
            if (nl.longv("nl-sub-nominal") != 0) nl.set("nl-type", "S");
            if (exportFormat.equals("T")) {
                out.writeLine("T" + nl.str("nl-owning") + nl.str("nl-sub-nominal") + nl.str("nl-type") + nl.str("nl-name") + nl.str("nl-ac"));
            } else {
                out.writeLine("C" + pad(nl.str("nl-owning") + "," + nl.str("nl-sub-nominal") + ",\"" + nl.str("nl-name") + "\","
                        + nl.str("nl-ac") + "," + nl.str("nl-type") + " ", 43));
            }
            counter++;
        }
        display(20, 1, "Total record count written out = ");
        show(20, 34, Num.z9(counter, 4));
        display(22, 1, "Note count & hit return to continue");
        wsReply = accept(22, 37, 1);
        irsub1(2);
        out.close();
    }

    /** fa-Import-CoA section。 */
    private void importCoa() {
        eraseEos(1, 1);
        display(1, 1, "This process will import a CoA (Chart of Accounts) in TEXT format ", 3);
        display(2, 1, "overwriting any existing IRS Chart of Accounts.", 3);
        display(3, 1, "This must only be done for a new set of accounts for a new client.", 3);
        display(4, 1, "OTherwise, If you have not made a back up of it you should quit this process.", 3);
        warning();
        menuReply = accept(12, 15, 1);
        if (menuReply.equalsIgnoreCase("n")) { menuReply = "1"; return; }
        display(15, 1, "File name to be Imported [12345678901234567890123456789012]", 3);
        archiveName = acceptUpdate(15, 27, 32, archiveName);
        if (archiveName.isBlank() || crtStatus() == 2005) { eraseEol(15, 1); display(15, 1, "Quiting to menu"); return; }
        CobFile in = archive();
        if (!in.open(CobFile.Mode.INPUT).equals("00")) {
            display(23, 1, "Problem opening Import File, hit return to quit action");
            wsReply = accept(23, 60, 1);
            return;
        }
        irsub1(1, 3);
        if (fa.weError == 1) { openProblem(); return; }
        irsub1(2);
        irsub1(1, 2);
        if (fa.weError != 0) { openProblem(); return; }
        counter = 0;
        zeroAmounts(nl);
        String line;
        while ((line = in.readLine()) != null) {
            line = pad(line, 44);
            if (!line.startsWith("T")) {
                display(20, 1, "Error: Can only import a Text file (.txt) as exported by this program", 7);
                display(21, 1, "Hit return for menu");
                wsReply = accept(21, 22, 1);
                return;
            }
            nl.setNum("nl-owning", Num.parse(line.substring(1, 6)).longValue());
            long sub = Num.parse(line.substring(6, 11)).longValue();
            nl.setNum("nl-sub-nominal", sub);
            nl.set("nl-type", sub == 0 ? "O" : "S");
            nl.set("nl-name", line.substring(12, 36));
            nl.set("nl-ac", line.substring(36, 37));
            irsub1(5);
            counter++;
        }
        display(20, 1, "Total records created = ");
        show(20, 26, Num.z9(counter, 4));
        display(22, 1, "Note count & hit return to continue");
        wsReply = accept(22, 37, 1);
        in.close();
        irsub1(2);
    }
    private void openProblem() {
        display(23, 1, "Problem opening Accounts for output, hit return to quit action");
        wsReply = accept(23, 65, 1);
    }
    private void warning() {
        display(7, 14, "Warning: This is NON RECOVERABLE, so think about it", 4);
        display(9, 1, "Before responding (Y)es ensure you have a back copy of the original file", 3);
        display(10, 1, "Otherwise respond (N)o and then exit the main menu to do so.", 3);
        display(12, 1, "Continue Y/N [ ]", 7);
    }

    /** zz000-clear-NL section。 */
    private void clearNl() {
        if (!ctx.store.exists(ctx.irsPath(sys.trim("fn-1")))) { menuReply = "0"; return; }
        if (ctx.store.exists(ctx.irsPath(sys.trim("fn-4")))) { menuReply = "0"; return; }
        eraseEos(1, 1);
        display(1, 1, "This appears to be the first time you are running IRS and there is a", 3);
        display(2, 21, "set of accounts (Nominal Ledger) present", 3);
        display(4, 1, "Can I clear down all amounts from these, so that you can start with a clean", 3);
        display(5, 33, "set of accounts", 3);
        warning();
        menuReply = accept(12, 15, 1);
        if (menuReply.equalsIgnoreCase("n")) { menuReply = "1"; return; }
        display(15, 1, "Wait while I clear the Chart of Accounts down ", 3);
        irsub1(1, 2);
        if (fa.weError != 0) { irsub1(2); menuReply = "1"; return; }
        while (true) {
            irsub1(3);
            if (fa.weError == 3) { irsub1(2); menuReply = "0"; return; }
            zeroAmounts(nl);
            irsub1(7);
        }
    }
}
