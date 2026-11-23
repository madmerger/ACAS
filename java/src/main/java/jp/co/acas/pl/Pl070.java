package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

/** pl070.cbl: 仕入分析コードの設定・保守。 */
public class Pl070 extends PlBase {
    static final String PROG_NAME = "PL070 (3.01.11)";
    private static final int L23 = 23, L22 = 22, L21 = 21, L20 = 20, L19 = 19, L18 = 18, L17 = 17, LINES = 24;
    private Rec anal, val;
    private CobFile analysisFile, valueFile;
    private int menuReply, lin;
    private String escapeCode = " ";

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        boolean func1 = args.length > 0 && Integer.valueOf(1).equals(args[0]);
        anal = analRec();
        val = Layout.of("copybooks/fdval.cob", "value-record").newRec();
        java.util.Arrays.fill(val.bytes(), (byte) 0);
        analysisFile = analysisFile(anal);
        valueFile = CobFile.indexed(ctx.store, ctx.path("value.dat"), val, "va-code");
        if (!func1) clearScreen();
        if (sys.intv("file-status", 15) == 0) paSetup(func1);
        if (func1) return;
        while (true) {
            menuReply = 0;
            displayHeading();
            do {
                display(7, 1, "Select one of the following by number :- [ ]");
                display(10, 4, "(1)  Set-up P/A records");
                display(12, 4, "(2)  Amend/Delete P/A records");
                display(14, 4, "(3)  Print P/A records");
                display(16, 4, "(4)  Print All P/A records");
                display(18, 4, "(5)  Display P/A records");
                display(20, 4, "(9)  Return to system menu");
                menuReply = Pl010.digit(acceptUpdate(7, 43, 1, Integer.toString(menuReply), AUTO));
                if (menuReply == 9) return;
            } while (menuReply < 1 || menuReply > 5);
            displayHeading();
            switch (menuReply) {
                case 1 -> create();
                case 2 -> amend();
                case 3 -> report1(false);
                case 4 -> report1(true);
                default -> showRecs();
            }
        }
    }

    private boolean blankGroup() { return anal.str("pa-group").replace('\0', ' ').isBlank(); }

    private void create() {
        analysisFile.open(Mode.IO);
        displayOutline();
        lin = 6;
        while (true) {
            anal.set("pa-group", acceptUpdate(lin, 2, 2, "  "));
            if (blankGroup()) break;
            anal.set("pa-system", "P");
            if (analysisFile.read(anal).equals("00")) {
                productDisplay();
                display(L23, 1, "PL008 P.A. Code Already Exists!!", 3);
                continue;
            }
            String save = anal.str("pa-code");
            if (!anal.str("pa-second").equals(" ")) {
                anal.set("pa-second", " ");
                if (invalid(analysisFile.read(anal))) {
                    display(L23, 1, "PL009 P.A. Group Code Does Not Exist!!", 3);
                    continue;
                }
                if (anal.longv("pa-gl") != 0) {
                    display(L23, 1, "PL010 P.A. Group Code Used As Analysis Code!!", 3);
                    continue;
                }
                eraseEol(L23, 1);
            }
            anal.set("pa-code", save);
            anal.setNum("pa-gl", 0);
            anal.set("pa-desc", "");
            analysisData(1);
            acceptEscape();
            if (escapeCode.equals("B")) analysisData(2);
            if (escapeCode.equals("Q") || escapeCode.equals("K")) break;
            analysisFile.write(anal);
            lin++;
            if (lin > L22) { displayOutline(); lin = 6; }
        }
        analysisFile.close();
    }

    private void acceptEscape() {
        escapeCode = "S";
        show(L18, 77, escapeCode, 6);
        escapeCode = upper(acceptUpdate(L18, 77, 1, escapeCode));
    }

    private void amend() {
        analysisFile.open(Mode.IO);
        displayOutline();
        lin = 6;
        while (true) {
            anal.set("pa-group", acceptUpdate(lin, 2, 2, "  "));
            if (blankGroup()) break;
            anal.set("pa-system", "P");
            if (invalid(analysisFile.read(anal))) {
                display(L23, 1, "PL009 P.A. Group Code Does Not Exist!!", 3);
                continue;
            }
            eraseEol(L23, 1);
            productDisplay();
            analysisData(1);
            acceptEscape();
            if (escapeCode.equals("B")) analysisData(2);
            if (escapeCode.equals("Q")) break;
            if (escapeCode.equals("K")) analysisFile.delete(anal); else analysisFile.rewrite(anal);
            lin++;
            if (lin > L21) { displayOutline(); lin = 6; }
        }
        analysisFile.close();
    }

    private long gl() {
        try { return anal.longv("pa-gl"); } catch (RuntimeException e) { return 0; }
    }

    private void report1(boolean all) {
        analysisFile.open(Mode.INPUT);
        Printer prt = new Printer("prt-1");
        int page = 0, lineCnt;
        boolean err = false, irs = sys.str("irs-instead").equals("Y");
        String line1 = pad(PROG_NAME, 33) + pad("Product Analysis Codes", 39) + "Page ";
        String line2 = pad(sys.str("usera"), 30) + pad("", 40) + fromUk(toDay());
        String line4 = pad(all ? "Lgr" : "", 4) + pad("Code    GL.No.      <-----Description------>   Print", 59) + "-Type-";
        page++;
        prt.before(line1 + Num.edit(page, "zz9"), 1);
        prt.after(line2, 1);
        prt.after(line4, 2);
        lineCnt = 5;
        while (true) {
            String st = analysisFile.readNext(anal);
            if (st.equals("10")) break;
            // レガシーは AT END 以外の異常状態（47 など）でも読み続け、全件印刷では無限に印字し続ける。
            // Web 版では異常状態のときは印字を打ち切る。
            if (!st.equals("00") && all) break;
            if (!anal.str("pa-system").equals("P") && !all) break;
            String type, ledger = " ";
            if (anal.str("pa-second").equals(" ") && gl() == 0) {
                prt.after("", 1);
                lineCnt++;
                type = "Group";
                if (all) ledger = anal.str("pa-system");
            } else type = "Detail";
            if (lineCnt > 70) {
                page++;
                prt.afterPage(line1 + Num.edit(page, "zz9")); prt.after("", 1);
                prt.after(line2, 1); prt.after(line4, 2);
                lineCnt = 5;
            }
            if (!anal.str("pa-second").equals(" ") && gl() == 0) err = true;
            long g = irs ? gl() : gl() / 100;
            prt.after(" " + ledger + "   " + pad(anal.str("pa-group"), 7) + (g == 0 ? pad("", 6) : Num.z9(g, 6)) + pad("", 7)
                    + pad(anal.str("pa-desc"), 24) + pad("", 4) + pad(anal.str("pa-print"), 3) + pad("", 7) + pad(type, 6), 1);
            lineCnt++;
            if (lineCnt > 70) {
                page++;
                prt.afterPage(line1 + Num.edit(page, "zz9")); prt.after("", 1);
                prt.after(line2, 1); prt.after(line4, 2);
                lineCnt = 5;
            }
        }
        if (err) prt.after("Warning: One or more P.A. codes contain a zero value for General Ledger numbers", 2);
        prt.close();
        spoolPrt1Portrait();
        analysisFile.close();
    }

    private void showRecs() {
        analysisFile.open(Mode.INPUT);
        displayOutline();
        lin = 6;
        display(L23, 31, "Enter <X> to exit or <Return> to continue...[ ]");
        while (true) {
            if (lin > L21) break;
            if (!analysisFile.readNext(anal).equals("00") || !anal.str("pa-system").equals("P")) lin = LINES;
            else productDisplay();
            lin++;
            if (lin < L22) continue;
            String reply = upper(acceptUpdate(L23, 76, 1, " "));
            if (lin > L23) break;
            if (!reply.equals("X")) { displayOutline(); lin = 6; continue; }
            break;
        }
        analysisFile.close();
    }

    private void productDisplay() {
        show(lin, 2, anal.str("pa-group"), 3);
        show(lin, 8, Num.z9(gl(), 6), 3);
        show(lin, 20, anal.str("pa-desc"), 3);
        String type = anal.str("pa-second").equals(" ") && gl() == 0 ? "Group " : "Detail";
        show(lin, 48, anal.str("pa-print"), 3);
        display(lin, 55, type, 3);
    }

    private void displayHeading() {
        clearScreen();
        display(1, 1, PROG_NAME);
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
        for (int l = 6; l < L23; l++) display(l, 1, "[  ]  [      ]    [                        ]  [   ]          ");
        if (menuReply == 5) return;
        display(L17, 62, "*******************");
        for (int l = L18; l <= L22; l++) { display(l, 62, "*"); display(l, 80, "*"); }
        display(L23, 62, "*******************");
        display(L18, 64, "Escape Code [ ]");
        display(L19, 64, "<B> = Back");
        display(L20, 64, "<S> = Save");
        display(L21, 64, "<Q> = Quit");
        display(L22, 64, "<K> = Deleted");
    }

    /** analysis-data（from=1: G/L 番号から、2: 摘要から）。 */
    private void analysisData(int from) {
        if (from == 1) anal.setNum("pa-gl", acceptNum(lin, 8, 6, gl()));
        anal.set("pa-desc", acceptUpdate(lin, 20, 24, anal.str("pa-desc")));
        if (menuReply == 1) anal.set("pa-print", anal.str("pa-group"));
        anal.set("pa-print", acceptUpdate(lin, 48, 3, anal.str("pa-print")));
    }

    private void paSetup(boolean func1) {
        if (!valueFile.open(Mode.INPUT).equals("00")) {
            valueFile.close();
            sys.setNum("file-status", 1, 13);
            valueFile.open(Mode.OUTPUT);
        }
        valueFile.close();
        valueFile.open(Mode.IO);
        analysisFile.open(Mode.OUTPUT);
        anal.setNum("pa-gl", 0);
        anal.set("pa-print", "");
        String[][] recs = {
            {"S", "v ", "VAT Control", null}, {"P", "v ", "VAT Control", null},
            {"P", "vi", "VAT Input Invoices/CN's", null}, {"P", "vj", "VAT Input Receipts", null},
            {"S", "z ", "Computer Control", null}, {"P", "z ", "Computer Control", null},
            {"P", "za", "Purchase Carriage Charges", "P&P"}, {"P", "zb", "Purchase Late Charges", "LCG"},
            {"S", "zc", "Sales Carriage Charges", "P&P"}, {"S", "zd", "Sales Late Charges", "LCG"},
            {"S", "vo", "VAT Output Invoices/CN's", ""}, {"S", "vp", "VAT Output Receipts", null},
            {"P", "a ", "Default Group", null}, {"P", "a1", "Default Purchases", null},
            {"S", "a ", "Default Group", null}, {"S", "a1", "Default Sales", null}};
        for (String[] r : recs) {
            anal.set("pa-system", r[0]);
            anal.set("pa-group", r[1]);
            anal.set("pa-desc", r[2]);
            if (r[3] != null) anal.set("pa-print", r[3]);
            val.set("va-code", anal.str("pa-code"));
            if (invalid(valueFile.read(val))) {
                byte[] v = val.bytes();
                java.util.Arrays.fill(v, (byte) ' ');
                System.arraycopy(anal.bytes(), 0, v, 0, 36);
                for (String f : new String[]{"va-v-this", "va-v-last", "va-v-year", "va-t-this", "va-t-last", "va-t-year"}) val.setNum(f, 0);
                valueFile.write(val);
            }
            analysisFile.write(anal);
        }
        analysisFile.close(); valueFile.close();
        sys.setNum("file-status", 1, 15);
        if (!func1) eraseEol(L23, 1);
    }
}
