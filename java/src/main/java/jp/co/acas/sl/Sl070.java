package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

/** sl070.cbl: 売上（製品）分析コードの登録・保守。 */
public class Sl070 extends SlProgram {
    static final String PROG_NAME = "SL070 (3.01.11)";
    static final String SL008 = "SL008 P.A. Code Already Exists!!", SL009 = "SL009 P.A. Group Code Does Not Exist!!",
        SL010 = "SL010 P.A. Group Code Used As Analysis Code!!";

    private Rec sys, pa, va;
    private CobFile analysisFile, valueFile;
    private Prt print;
    private int menuReply, a, wsErrFlag, lineCnt, lin;
    private String escapeCode = " ", printMode = " ", l5LedLit = "Lgr", l6Ledger = " ", l6Type = "", wsReply = " ";

    @Override
    public void run(Object... args) {
        sys = sys();
        linkFileDefs(args);
        pa = analysisRec(); va = valueRec();
        analysisFile = analysisFile(pa); valueFile = valueFile(va);
        print = new Prt(ctx, "prt-1");
        term().exceptionsEnabled = true; term().escEnabled = true;
        boolean byStock = sharedInt("ws-process-func") == 1;
        if (!byStock) clearScreen();
        if (sys.intv("file-status", 15) == 0) paSetup(byStock);
        if (byStock) return;
        while (true) {
            menuReply = 0;
            displayHeading();
            while (true) {
                display(7, 1, "Select one of the following by number :- [ ]");
                display(10, 4, "(1)  Set-up P/A records");
                display(12, 4, "(2)  Amend/Delete P/A records");
                display(14, 4, "(3)  Print P/A records");
                display(16, 4, "(4)  Print All P/A records");
                display(18, 4, "(5)  Display P/A records");
                display(20, 4, "(9)  Return to system menu");
                menuReply = intOf(term().accept(7, 43, 1, z(menuReply, 1), AUTO | NUMERIC, 6));
                if (menuReply == 9) return;
                if (menuReply >= 1 && menuReply <= 5) break;
            }
            displayHeading();
            switch (menuReply) {
                case 1 -> create();
                case 2 -> amend();
                case 3 -> { l5LedLit = ""; report1(); }
                case 4 -> { l5LedLit = "Lgr"; printMode = "A"; report1(); }
                default -> showRecords();
            }
        }
    }

    private void acceptEscape() {
        escapeCode = "S";
        show(18, 77, escapeCode, 6);
        escapeCode = upper(term().accept(18, 77, 1, escapeCode, 0, 6));
    }
    private void getPaDesc() {
        pa.set("pa-desc", acceptUpdate(lin, 20, 24, pa.str("pa-desc")));
        if (menuReply == 1) pa.set("pa-print", pa.str("pa-group"));
        pa.set("pa-print", acceptUpdate(lin, 48, 3, pa.str("pa-print")));
    }
    private void analysisData() {
        pa.setNum("pa-gl", intOf(acceptUpdate(lin, 8, 6, z(pa.longv("pa-gl"), 6), NUMERIC)));
        getPaDesc();
    }

    private void create() {
        analysisFile.open(CobFile.Mode.IO);
        displayOutline();
        lin = 6;
        while (true) {
            pa.set("pa-group", acceptUpdate(lin, 2, 2, "  "));
            if (pa.str("pa-group").isBlank()) break;
            pa.set("pa-system", "S");
            analysisFile.read(pa);
            if (!invalidKey(analysisFile)) { productDisplay(); display(23, 1, SL008, 3); continue; }
            String saveCode = pa.str("pa-code");
            if (!pa.str("pa-second").equals(" ")) {
                pa.set("pa-second", " ");
                analysisFile.read(pa);
                if (invalidKey(analysisFile)) { display(23, 1, SL009, 3); continue; }
                if (pa.longv("pa-gl") != 0) { display(23, 1, SL010, 3); continue; }
                eraseEol(23, 1);
            }
            pa.set("pa-code", saveCode);
            pa.setNum("pa-gl", 0);
            pa.set("pa-desc", "");
            analysisData();
            acceptEscape();
            if (escapeCode.equals("B")) getPaDesc();
            if (escapeCode.equals("Q") || escapeCode.equals("K")) break;
            analysisFile.write(pa);
            lin++;
            if (lin > 22) { displayOutline(); lin = 6; }
        }
        analysisFile.close();
    }

    private void amend() {
        analysisFile.open(CobFile.Mode.IO);
        displayOutline();
        lin = 6;
        while (true) {
            pa.set("pa-group", acceptUpdate(lin, 2, 2, "  "));
            if (pa.str("pa-group").isBlank()) break;
            pa.set("pa-system", "S");
            analysisFile.read(pa);
            if (invalidKey(analysisFile)) { display(23, 1, SL009, 3); continue; }
            eraseEol(23, 1);
            productDisplay();
            analysisData();
            acceptEscape();
            if (escapeCode.equals("B")) getPaDesc();
            if (escapeCode.equals("Q")) break;
            if (escapeCode.equals("K")) analysisFile.delete(pa); else analysisFile.rewrite(pa);
            lin++;
            if (lin > 21) { displayOutline(); lin = 6; }
        }
        analysisFile.close();
    }

    private void headings() {
        a = (a + 1) % 100;
        String line1 = pad(PROG_NAME, 33) + pad("Product Analysis Codes", 39) + "Page " + Num.edit(a, "zz9");
        if (a != 1) { print.afterPage(line1); print.after("", 1); }
        else print.before(line1, 1);
        print.after(pad(sys.str("usera"), 70) + fromUk(toDay()), 1);
        print.after(pad(l5LedLit, 4) + pad("Code    Gl.Nos.      <-----Description------>   Print", 59) + "-Type-", 2);
        lineCnt = 5;
    }

    private void report1() {
        analysisFile.open(CobFile.Mode.INPUT);
        print.openOutput();
        a = 0;
        headings();
        while (true) {
            analysisFile.readNext(pa);
            if (!analysisFile.status.equals("00")) break;
            boolean all = printMode.equals("A");
            if (!pa.str("pa-system").equals("S") && !all) continue;
            if (pa.str("pa-second").equals(" ") && pa.longv("pa-gl") == 0) {
                print.after("", 1);
                lineCnt++;
                l6Type = "Group";
                if (all) l6Ledger = pa.str("pa-system");
            } else { l6Type = "Detail"; l6Ledger = " "; }
            if (lineCnt > 70) headings();
            if (!pa.str("pa-second").equals(" ") && pa.longv("pa-gl") == 0) wsErrFlag = 1;
            long gl = sys.intv("irs-instead") == 1 || sys.str("irs-instead").equals("Y") ? pa.longv("pa-gl") : pa.longv("pa-gl") / 100;
            print.after(" " + l6Ledger + "   " + pad(pa.str("pa-group"), 7) + (gl == 0 ? " ".repeat(6) : z(gl, 6))
                + " ".repeat(7) + pa.str("pa-desc") + " ".repeat(4) + pa.str("pa-print") + " ".repeat(7) + pad(l6Type, 6), 1);
            lineCnt++;
            if (lineCnt > 70) headings();
        }
        if (wsErrFlag != 0)
            print.after("Warning: One or more P.A. codes contain a zero value for General Ledger numbers", 2);
        print.close();
        analysisFile.close();
        spoolReport("prt-1", sys.str("print-spool-name"), false);
    }

    private void productDisplay() {
        show(lin, 2, pa.str("pa-group"));
        show(lin, 8, z(pa.longv("pa-gl"), 6));
        show(lin, 20, pa.str("pa-desc"));
        l6Type = pa.str("pa-second").equals(" ") && pa.longv("pa-gl") == 0 ? "Group" : "Detail";
        show(lin, 48, pa.str("pa-print"));
        show(lin, 55, pad(l6Type, 6));
    }

    private void showRecords() {
        analysisFile.open(CobFile.Mode.INPUT);
        displayOutline();
        lin = 6;
        display(23, 31, "Enter <X> to exit or <Return> to continue...[ ]");
        outer:
        while (true) {
            // show-read
            if (lin > 21) break;
            boolean eof = false;
            while (true) {
                analysisFile.readNext(pa);
                if (!analysisFile.status.equals("00")) { lin = 24; eof = true; break; }
                if (pa.str("pa-system").equals("S")) break;
            }
            if (!eof) productDisplay();
            // accept-of-show
            lin++;
            if (lin < 22) continue;
            wsReply = upper(term().accept(23, 76, 1, wsReply, 0, 6));
            if (lin > 23) break outer;
            if (wsReply.equals("X")) break;
            displayOutline();
            lin = 6;
        }
        analysisFile.close();
    }

    private void displayHeading() {
        clearScreen();
        show(1, 1, PROG_NAME);
        show(1, 71, fromUk(toDay()), 2);
        switch (menuReply) {
            case 0 -> { display(1, 20, "Product Analysis File Set-Up & Maintenance"); display(4, 34, "Function  Menu"); }
            case 1 -> display(1, 32, "Set-Up P/A Records");
            case 2 -> display(1, 29, "Amend/Delete P/A Records");
            case 3 -> display(1, 32, "Print P/A Records");
            case 4 -> display(1, 32, "Print All P/A Records");
            case 5 -> display(1, 31, "Display P/A Records");
            default -> { }
        }
    }

    private void displayOutline() {
        display(4, 1, "Code   G/L Nos          Description");
        display(4, 48, "Ref");
        display(4, 56, "Type");
        for (int l = 6; l < 23; l++) show(l, 1, "[  ]  [      ]    [                        ]  [   ]          ", 2);
        if (menuReply != 5) {
            display(17, 62, "*******************");
            for (int l = 18; l <= 22; l++) { show(l, 62, "*", 2); show(l, 80, "*", 2); }
            display(23, 62, "*******************");
            display(18, 64, "Escape Code [ ]");
            display(19, 64, "<B> = Back");
            display(20, 64, "<S> = Save");
            display(21, 64, "<Q> = Quit");
            display(22, 64, "<K> = Deleted");
        }
    }

    private void createValue() {
        va.set("va-code", pa.str("pa-code"));
        valueFile.read(va);
        if (invalidKey(valueFile)) {
            va.set("value-record", pa.str("analysis-record"));
            for (String f : new String[] {"va-v-this", "va-v-last", "va-v-year", "va-t-this", "va-t-last", "va-t-year"}) va.setNum(f, 0);
            valueFile.write(va);
        }
        analysisFile.write(pa);
    }
    private void cv(String system, String group, String desc, String print) {
        pa.set("pa-system", system); pa.set("pa-group", group); pa.set("pa-desc", desc); pa.set("pa-print", print);
        createValue();
    }

    /** p-a-setup: 分析コード・集計ファイルの初期作成。 */
    private void paSetup(boolean byStock) {
        valueFile.open(CobFile.Mode.INPUT);
        if (!valueFile.status.equals("00")) { valueFile.close(); sys.setNum("file-status", 1, 13); valueFile.open(CobFile.Mode.OUTPUT); }
        valueFile.close();
        valueFile.open(CobFile.Mode.IO);
        analysisFile.open(CobFile.Mode.OUTPUT);
        pa.setNum("pa-gl", 0);
        cv("S", "v ", "VAT Control", "");
        cv("P", "v ", "VAT Control", "");
        cv("P", "vi", "VAT Input Invoices/CN's", "");
        cv("P", "vj", "VAT Input Receipts", "");
        cv("S", "z ", "Computer Control", "");
        cv("P", "z ", "Computer Control", "");
        cv("P", "za", "Purchase Carriage Charges", "P&P");
        cv("P", "zb", "Purchase Late Charges", "LCG");
        cv("S", "zc", "Sales Carriage Charges", "P&P");
        cv("S", "zd", "Sales Late Charges", "LCG");
        cv("S", "vo", "VAT Output Invoices/CN's", "");
        cv("S", "vp", "VAT Output Receipts", "");
        cv("P", "a ", "Default Group", "");
        cv("P", "a1", "Default Purchases", "");
        cv("S", "a ", "Default Group", "");
        cv("S", "a1", "Default Sales", "");
        analysisFile.close(); valueFile.close();
        sys.setNum("file-status", 1, 15);
        if (!byStock) eraseEol(23, 1);
    }
}
