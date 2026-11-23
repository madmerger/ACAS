package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** gl050.cbl: 仕訳入力（新規バッチ登録・明細入力）。 */
public class Gl050 extends GlProgram {
    static final String PROG_NAME = "gl050 (3.00.03)";
    private static final int PGUP = 2001, PGDN = 2002, UP = 2003, DOWN = 2004;
    private static final String SPACE44 = " ".repeat(44);
    // レガシーの posting-array は occurs 11 だが a は 12 まで進む（領域越え）。ここでは 12 件分を安全に保持する。
    private static final int MAX = 13;

    private Rec dflt, led, bat, post; private CobFile ledger, batchFile, postingFile;
    private int a, saveA, v, w, y, z, truth, vatFlag, vatFlag2, lin, cole;
    private String wsDate = sp(10), tranDate = sp(8), escapeCode = " ", arrayVat = " ";
    private BigDecimal wsVatRate = BigDecimal.ZERO;
    private long accountIn; private int arrayPc; private long uBin;
    private final StringBuilder pcb = new StringBuilder(sp(107));
    private final String[] arDate = new String[MAX], arLegend = new String[MAX], arVatSide = new String[MAX], arCode = new String[MAX];
    private final long[] arDr = new long[MAX], arCr = new long[MAX], arAmount = new long[MAX], arVatAc = new long[MAX], arVatAmount = new long[MAX];
    private final int[] arDrPc = new int[MAX], arCrPc = new int[MAX], arVatPc = new int[MAX];

    private static final class ExitProgram extends RuntimeException {
        ExitProgram() { super(null, null, false, false); }
    }

    @Override
    public void run(Object... args) {
        init();
        dflt = GlCommon.dflt(ctx);
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        bat = GlCommon.batchRec(); batchFile = GlCommon.batchFile(ctx, bat);
        post = GlCommon.postingRec(); postingFile = GlCommon.postingFile(ctx);
        for (int i = 0; i < MAX; i++) { arDate[i] = sp(10); arLegend[i] = sp(32); arVatSide[i] = "  "; arCode[i] = "  "; }
        if (!batchFile.open(CobFile.Mode.INPUT).equals("00")) {
            batchFile.open(CobFile.Mode.OUTPUT);
            bat.initialize();
            bat.set("description", "");
            bat.setNum("ledger", 9); bat.setNum("batch-nos", 99999); bat.setNum("bcycle", 99);
            batchFile.write(bat);
        }
        batchFile.close();
        batchFile.open(CobFile.Mode.IO);
        if (!postingFile.open(CobFile.Mode.INPUT).equals("00")) {
            postingFile.open(CobFile.Mode.OUTPUT);
            post.initialize();
            // レガシー実測: rrn が 0 のままのため WRITE は不成立となり、空の posting.dat だけが作られる
        }
        postingFile.close();
        try {
            while (true) {
                display(1, 1, PROG_NAME); eraseEos(1, 16);
                display(1, 27, "Transaction Entry Functions");
                wsDate = wsDate();
                show(1, 71, wsDate, 2);
                show(3, 1, sys.str("usera"), 2);
                display(8, 1, "Select one of the following by number :- [1]");
                a = 1;
                display(10, 1, "(1)  Set up New Batch");
                display(13, 1, "(9)  Exit to system menu");
                int menu = (int) acceptNum(8, 43, 1, 1);
                if (menu == 9) break;
                if (menu != 1) continue;
                bat.setNum("ledger", 1);
                bat.setNum("batch-nos", sys.intv("next-batch"));
                sys.setNum("next-batch", sys.intv("next-batch") + 1);
                gl050a();
                if (bat.intv("bdefault") == 0) break;
                gl050b();
                if (z == 9) sys.setNum("next-batch", sys.intv("next-batch") - 1);
                else batchFile.write(bat);
            }
            batchFile.close();
        } catch (ExitProgram e) {
            // program-exit
        }
    }

    private long acs(int i) { return dflt.num("def-acs", i).movePointRight(2).longValue(); }
    private static String acsEdit(long v) { return Num.z9(v / 100, 4) + "." + Num.z9(v % 100, 2); }
    private static String amtEdit(long v, int n) { long u = Math.abs(v); return Num.z9(u / 100, n) + "." + Num.z9(u % 100, 2); }
    private static long money(String s, int n) { s = pad(s, n + 3); return digits(s.substring(0, n), n) * 100 + digits(s.substring(n + 1, n + 3), 2); }

    private long acceptMoney9(int line, int col) {
        show(line, col, amtEdit(0, 9));
        return money(acceptUpdate(line, col, 12, amtEdit(0, 9)), 9);
    }
    private long acceptMoney8s(int line, int col) {
        show(line, col, amtEdit(0, 8));
        return money(acceptUpdate(line, col, 11, amtEdit(0, 8)), 8);
    }
    private long acceptMoney8s2(int line, int col, long cur) { return money(acceptUpdate(line, col, 11, amtEdit(cur, 8)), 8); }
    private long acceptAccount(int line, int col) {
        show(line, col, acsEdit(0));
        return money(acceptUpdate(line, col, 7, acsEdit(0)), 4);
    }

    private void gl020cShow() {
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 26, "Default Accounts Display");
        show(1, 71, wsDate, 2);
        show(3, 1, sys.str("usera"), 2);
        display(5, 4, "A/C Nos"); display(5, 33, "Code Vat");
        display(5, 44, "A/C Nos"); display(5, 73, "Code Vat");
        lin = 7; cole = 1;
        for (w = 1; w <= 32; w++) {
            if (w == 17) { lin = 7; cole = 41; }
            show(lin, cole, Num.z9(w, 2), 7);
            display(lin, cole + 2, "[       ]");
            display(lin, cole + 32, "[  ] [ ]");
            lin++;
        }
        lin = 7; cole = 1;
        for (w = 1; w <= 32; w++) {
            if (w == 17) { lin = 7; cole = 41; }
            show(lin, cole + 3, acsEdit(acs(w)));
            if (acs(w) != 0) {
                led.setNum("ledger-nos", acs(w)); led.setNum("ledger-pc", 0);
                if (ledger.read(led).equals("00")) {
                    show(lin, cole + 12, led.str("ledger-name"));
                    display(lin, cole + 32, "[  ] ");
                }
            }
            show(lin, cole + 33, dflt.str("def-codes", w));
            show(lin, cole + 38, dflt.str("def-vat", w));
            lin++;
        }
        w = 1; cole = 1; lin = 7;
        display(23, 1, "End of listing. Hit return for Menu.");
        accept(23, 79, 1);
    }

    private boolean autoVat() { return sys.str("vat").equals("Y"); }
    private boolean preserveBatch() { return sys.str("batch-id").equals("Y"); }

    /** get-description（gl050a）: truth により P/C を切り替えて勘定を読む。 */
    private void getDescription() {
        weError = 0;
        led.setNum("ledger-nos", acs(a));
        led.setNum("ledger-pc", truth == 0 ? 0 : bat.intv("batch-def-pc"));
        if (!ledger.read(led).equals("00")) weError = 255;
        truth = weError == 255 ? 0 : 1;
    }

    private void batchOutline() {
        for (int l = 16; l <= 23; l++) show(l, 1, SPACE44, 7);
        display(15, 1, "*".repeat(46)); display(23, 1, "*".repeat(46));
        for (lin = 16; lin <= 22; lin++) { display(lin, 1, "*"); display(lin, 46, "*"); }
        lin = 22;
    }
    private void helpOutlineA() {
        display(15, 50, "+".repeat(31)); display(23, 50, "+".repeat(31));
        for (lin = 16; lin <= 22; lin++) { display(lin, 50, "+"); display(lin, 80, "+"); }
        lin = 22;
        display(16, 61, "Help Data");
    }

    private void defSetUp() {
        for (int l = 16; l <= 22; l++) show(l, 2, SPACE44, 7);
        display(17, 16, "Default Set-Up");
        display(19, 3, "A/C  - [       ]");
        display(20, 3, "VAT  - [ ]");
        display(21, 3, "Code - [  ]");
        int st = 0;
        while (true) {
            if (st == 0) {              // get-ac
                truth = 0;
                long acc = acceptAccount(19, 11);
                dflt.setNum("def-acs", BigDecimal.valueOf(acc, 2), 33);
                if (acc == 0) return;
                a = 33;
                bat.setNum("batch-def-pc", 0);
                getDescription();
                if (truth == 0) continue;
                show(19, 20, led.str("ledger-name"));
                st = 1;
            } else if (st == 1) {       // get-vat
                display(18, 51, "<I> - Input  VAT             ");
                display(19, 51, "<O> - Output VAT             ");
                display(20, 51, "<N> - No     VAT             ");
                String v2 = dflt.str("def-vat", 33);
                show(20, 11, v2);
                String vat = upper(pad(acceptUpdate(20, 11, 1, v2), 1));
                if (esc()) { st = 0; continue; }
                if (!vat.equals("I") && !vat.equals("O") && !vat.equals("N")) continue;
                dflt.set("def-vat", vat, 33);
                st = 2;
            } else {                    // get-code
                eraseEol(18, 51); eraseEol(19, 51); eraseEol(20, 51);
                String c2 = dflt.str("def-codes", 33);
                show(21, 11, c2);
                c2 = pad(acceptUpdate(21, 11, 2, c2), 2);
                if (esc()) { st = 1; continue; }
                dflt.set("def-codes", upper(c2), 33);
                if (preserveBatch()) batchOutline();
                truth = 1;
                return;
            }
        }
    }

    private void validatePc() {
        int pc = bat.intv("batch-def-pc");
        if (pc == 0) truth = 1;
        else { char c = pcb.charAt(8 + pc - 1); truth = (c == 'Y' || c == 'E') ? 1 : 0; }
        if (truth == 1) getDescription();
        if (truth == 1) show(4, 41, led.str("ledger-name"));
        else display(4, 41, "Unrecognised Account/P.C.");
    }

    private void valDate() {
        String t = pad(tranDate, 10).replace('.', '/').replace(',', '/').replace('-', '/');
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        wsDate = GlCommon.formToUk(sys, t);
        uBin = Maps04.toBin(wsDate);
        if (uBin == 0) truth = 0;
        else { truth = 1; bat.setNum("entered", uBin); }
    }

    private void gl050a() {
        ledger.open(CobFile.Mode.INPUT);
        if (pcOrBranch()) {
            led.setNum("ledger-nos", 999999); led.setNum("ledger-pc", 0);
            if (!ledger.read(led).equals("00")) {
                display(1, 1, "GL107 Set Up P/C Branches First", 4); eraseEos(1, 32);
                display(2, 11, "GL010 Hit Return", 7);
                accept(2, 34, 1);
                ledger.close();
                throw new ExitProgram();
            }
            pcb.setLength(0); pcb.append(pad(latin(led.bytes()), 107));
        }
        final int INIT = 0, DEF_IN = 1, POST_IN = 2, DEF_PC = 3, DEF_DATE = 4, BATCH_IN = 5, CYCLE_IN = 6, ITEMS_IN = 7, GROSS_IN = 8, VAT_IN = 9, DESC_IN = 10;
        int st = INIT;
        while (true) {
            switch (st) {
                case INIT -> {
                    display(1, 1, PROG_NAME); eraseEos(1, 16);
                    display(1, 26, "General Ledger - Posting Set-Up");
                    show(1, 71, wsDate, 2);
                    if (preserveBatch()) { batchOutline(); display(16, 18, "Batch Data"); }
                    helpOutlineA();
                    display(4, 1, "select default number          :- [  ]");
                    display(7, 1, "select posting convention      :- [CR]");
                    if (profitCentres()) display(10, 1, "Select Default Profit Centre   :- [  ]");
                    if (branches()) display(10, 1, "Select Default Branch          :- [  ]");
                    display(13, 1, "Enter Transaction Posting Date :- [        ]");
                    st = DEF_IN;
                }
                case DEF_IN -> {
                    display(18, 51, " 0 - Return to System Menu   ");
                    display(19, 51, "33 - Set-up Temporary Default");
                    display(20, 51, "99 - Display current Defaults");
                    eraseEol(21, 51); eraseEol(22, 51);
                    a = (int) acceptNum(4, 36, 2);
                    if (a == 99) { gl020cShow(); st = INIT; break; }
                    if (a == 0) { bat.setNum("bdefault", 0); ledger.close(); return; }
                    if (a > 33) break;
                    bat.setNum("batch-def-pc", 0);
                    if (a == 33) defSetUp();
                    if (a < 33) { truth = acs(a) == 0 ? 0 : 1; getDescription(); }
                    if (truth == 0) break;
                    bat.setNum("bdefault", a);
                    vatFlag = (acs(a) == acs(31) || acs(a) == acs(32)) ? 1 : 0;
                    st = POST_IN;
                }
                case POST_IN -> {
                    display(18, 51, "Enter <DR> or <CR>           ");
                    display(19, 51, "DR - Debits the A/c posted to");
                    display(20, 51, "   & Credits the default A/c ");
                    display(21, 51, "<Esc> - to back-up one field ");
                    String c2 = pad(acceptUpdate(7, 36, 2, "CR"), 2);
                    bat.set("convention", upper(c2));
                    if (esc()) { st = DEF_IN; break; }
                    String c = bat.str("convention");
                    if (!c.equals("DR") && !c.equals("CR")) break;
                    st = DEF_PC;
                }
                case DEF_PC -> {
                    eraseEol(18, 51); eraseEol(19, 51); eraseEol(20, 51); eraseEol(21, 51);
                    if (!pcOrBranch()) { st = DEF_DATE; break; }
                    show(10, 36, Num.z9(bat.intv("batch-def-pc"), 2));
                    bat.setNum("batch-def-pc", acceptNum(10, 36, 2, bat.intv("batch-def-pc")));
                    if (esc()) { st = POST_IN; break; }
                    validatePc();
                    if (truth == 0) break;
                    st = DEF_DATE;
                }
                case DEF_DATE -> {
                    bat.setNum("batch-def-ac", acs(a));
                    bat.set("batch-def-vat", dflt.str("def-vat", a));
                    bat.set("batch-def-code", dflt.str("def-codes", a));
                    if (autoVat()) {
                        String bv = bat.str("batch-def-vat");
                        if (bv.equals("I")) display(4, 70, "Input VAT");
                        if (bv.equals("O")) display(4, 70, "Output VAT");
                        if (bv.equals("N")) display(4, 70, "No VAT");
                    }
                    tranDate = pad(wsDate, 8);
                    show(13, 36, tranDate);
                    tranDate = pad(acceptUpdate(13, 36, 8, tranDate), 8);
                    if (esc()) { st = pcOrBranch() ? DEF_PC : POST_IN; break; }
                    valDate();
                    if (truth == 0) break;
                    st = BATCH_IN;
                }
                case BATCH_IN -> {
                    bat.setNum("ledger", 1);
                    for (String f : new String[]{"batch-status", "cleared-status", "proofed", "posted", "stored", "actual-gross", "actual-vat"}) bat.setNum(f, 0);
                    bat.setNum("bcycle", sys.intv("scycle"));
                    bat.setNum("batch-start", sys.intv("postings") + 1);
                    show(17, 3, SPACE44, 7); show(18, 3, SPACE44, 7); show(19, 3, SPACE44, 7);
                    display(17, 1, "Assigned Batch :- {     }");
                    display(18, 1, "Enter Cycle    :- [  ]");
                    display(19, 1, "Number of Items:- [  ]");
                    display(20, 1, "Gross Amount   :- [            ]");
                    display(21, 1, "Vat   Amount   :- [            ]");
                    display(22, 1, "Batch Desc.    :- [");
                    display(22, 45, "]");
                    show(17, 20, Num.edit(bat.intv("batch-nos"), "zzzz9"));
                    st = CYCLE_IN;
                }
                case CYCLE_IN -> {
                    show(18, 20, Num.z9(bat.intv("bcycle"), 2));
                    bat.setNum("bcycle", acceptNum(18, 20, 2, bat.intv("bcycle")));
                    if (esc()) { st = DEF_DATE; break; }
                    if (bat.intv("bcycle") < sys.intv("scycle")) { display(18, 24, "GL108 Invalid. Too early", 4); break; }
                    y = bat.intv("bcycle") - sys.intv("scycle");
                    if (y > 1) { display(18, 24, "GL109 Invalid. Too forward", 4); break; }
                    show(18, 24, sp(20), 7);
                    st = ITEMS_IN;
                }
                case ITEMS_IN -> {
                    bat.setNum("items", acceptNum(19, 20, 2, bat.intv("items")));
                    if (esc()) { st = CYCLE_IN; break; }
                    if (bat.intv("items") == 0) display(19, 24, "GL110 No check on items.");
                    st = GROSS_IN;
                }
                case GROSS_IN -> {
                    long amt = acceptMoney9(20, 20);
                    if (esc()) { st = ITEMS_IN; break; }
                    bat.setNum("input-gross", BigDecimal.valueOf(amt, 2));
                    st = VAT_IN;
                }
                case VAT_IN -> {
                    if (!autoVat()) { st = DESC_IN; break; }
                    long amt = acceptMoney9(21, 20);
                    if (esc()) { st = GROSS_IN; break; }
                    bat.setNum("input-vat", BigDecimal.valueOf(amt, 2));
                    st = DESC_IN;
                }
                default -> {
                    bat.set("description", acceptUpdate(22, 20, 24, bat.str("description")));
                    if (!esc()) { ledger.close(); return; }
                    st = autoVat() ? VAT_IN : GROSS_IN;
                }
            }
        }
    }

    private void helpOutlineB() {
        show(14, 54, "+".repeat(27), 7); show(23, 54, "+".repeat(27), 7);
        for (lin = 15; lin <= 22; lin++) { display(lin, 54, "+"); display(lin, 80, "+"); }
        lin = 22;
        display(16, 56, "Option :- [ ]");
        display(18, 56, "B - Back-up one field");
        display(19, 56, "E - End");
        display(20, 56, "F - Force Write");
        display(21, 56, "Q - Quit Batch");
        display(22, 56, "n - Back-up n records");
    }

    private void regetVatRate() {
        while (true) {
            v = 1;
            display(4, 1, "VAT Rate :- [ ]");
            show(4, 14, "1");
            v = (int) acceptNum(4, 14, 1, 1);
            if (v < 1 || v > 3) continue;
            wsVatRate = sys.num("vat-rate", v);
            show(4, 17, Num.edit(wsVatRate, "z9.99"));
            display(4, 22, "% OK (Y/N) :- [Y]");
            String r = pad(acceptUpdate(4, 37, 1, "Y"), 1);
            if (r.equals("N") || r.equals("n")) continue;
            return;
        }
    }

    private void gl050b() {
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 26, "General Ledger - Posting Input");
        show(1, 71, wsDate, 2);
        helpOutlineB();
        ledger.open(CobFile.Mode.INPUT);
        w = 0;
        String bv = bat.str("batch-def-vat");
        if (bv.equals("O")) w = 32;
        if (bv.equals("I")) w = 31;
        if (w != 0) regetVatRate();
        display(4, 56, "Batch      - ");
        show(4, 69, Num.edit(bat.intv("batch-nos"), "zzzz9"), 2);
        display(4, 74, "/");
        display(6, 56, "Default    - ");
        show(6, 69, Num.z9(bat.intv("bdefault"), 2), 2);
        display(8, 56, "Contra A/C - ");
        show(8, 69, Num.z9(bat.intv("batch-def-ac"), 6), 2);
        if (!bat.str("batch-def-pc").matches("[0-9]{2}")) bat.setNum("batch-def-pc", 0);
        if (bat.intv("batch-def-pc") != 0) { display(8, 75, "/"); show(8, 76, Num.z9(bat.intv("batch-def-pc"), 2)); }
        if (w != 0) { display(10, 56, "VAT A/C    - "); show(10, 69, acsEdit(acs(w))); }
        else display(10, 56, "No VAT on this Batch.");
        display(12, 56, "Convention - ");
        show(12, 69, bat.str("convention"));
        display(6, 1, "Date           [          ]");
        display(8, 1, "Account        [       ]");
        if (profitCentres()) display(10, 1, "Profit Centre  [  ]");
        if (branches()) display(10, 1, "Branch         [  ]");
        display(12, 1, "Amount         [           ]");
        if (autoVat() && w != 0) display(14, 1, "VAT Code       [ ]  {p or m or space}");
        display(16, 1, "VAT Amount     [           ]");
        display(18, 1, "Narrative      [");
        display(18, 49, "]");
        saveA = 0; a = 1;
        final int MAIN = 0, ACCOUNT = 1, PC = 2, AMOUNT = 3, VAT = 4, VAT_AMT = 5, NARR = 6, END = 7;
        int st = MAIN;
        loop:
        while (true) {
            int cs;
            switch (st) {
                case MAIN -> {
                    show(4, 75, Num.z9(a, 2));
                    show(6, 17, wsDate);
                    wsDate = pad(acceptUpdate(6, 17, 10, wsDate), 10);
                    arDate[a] = wsDate;
                    cs = crtStatus();
                    if (cs == PGUP || (cs == UP && w != 0)) { regetVatRate(); break; }
                    if (cs == PGUP || cs == UP || cs == ESC || cs == PGDN || cs == DOWN) break;
                    if (z > 0) break;
                    uBin = 0;
                    String t = arDate[a].replace('.', '/').replace(',', '/').replace('-', '/');
                    if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
                    wsDate = GlCommon.formToUk(sys, t);
                    uBin = Maps04.toBin(wsDate);
                    arDate[a] = t;
                    if (uBin == 0) { display(6, 36, "Invalid Date", 4); break; }
                    show(6, 26, sp(29), 7);
                    st = ACCOUNT;
                }
                case ACCOUNT -> {
                    accountIn = acceptAccount(8, 17);
                    cs = crtStatus();
                    if (cs == PGUP || cs == UP || cs == PGDN || cs == DOWN || z != 0) { st = MAIN; break; }
                    if (cs == ESC) break loop;
                    led.setNum("ledger-nos", accountIn); led.setNum("ledger-pc", arrayPc);
                    if (ledger.read(led).equals("00")) show(8, 26, led.str("ledger-name"));
                    else { display(8, 26, "Invalid A/C number", 4); break; }
                    vatFlag2 = (vatFlag == 1 || accountIn == acs(31) || accountIn == acs(32)) ? 1 : 0;
                    st = PC;
                }
                case PC -> {
                    arrayPc = 0;
                    if (!pcOrBranch()) { st = AMOUNT; break; }
                    show(10, 17, "00");
                    arrayPc = (int) acceptNum(10, 17, 2, 0);
                    cs = crtStatus();
                    if (cs == PGDN || cs == DOWN || z != 0) { st = MAIN; break; }
                    if (cs == PGUP || cs == UP) { st = ACCOUNT; break; }
                    if (cs == ESC) break loop;
                    st = AMOUNT;
                }
                case AMOUNT -> {
                    if (vatFlag2 == 0) arAmount[a] = acceptMoney8s(12, 17);
                    else arAmount[a] = 0;
                    show(12, 17, amtEdit(arAmount[a], 8));
                    cs = crtStatus();
                    if (cs == PGDN || cs == DOWN || z != 0) { st = MAIN; break; }
                    if (cs == PGUP || (cs == UP && !pcOrBranch())) { st = ACCOUNT; break; }
                    if (cs == PGUP || cs == UP) { st = PC; break; }
                    if (cs == ESC) break loop;
                    st = VAT;
                }
                case VAT -> {
                    if (!autoVat() || w == 0) { arVatAmount[a] = 0; st = VAT_AMT; break; }
                    arrayVat = " ";
                    if (vatFlag2 == 1) { arVatAmount[a] = 0; st = VAT_AMT; break; }
                    show(14, 17, arrayVat);
                    arrayVat = upper(pad(acceptUpdate(14, 17, 1, arrayVat), 1));
                    cs = crtStatus();
                    if (cs == PGDN || cs == DOWN || z != 0) { st = MAIN; break; }
                    if (cs == PGUP || cs == UP) { st = AMOUNT; break; }
                    if (cs == ESC) break loop;
                    if (arrayVat.equals("P")) { net(); st = VAT_AMT; break; }
                    if (arrayVat.equals("M")) { gross(); st = VAT_AMT; break; }
                    if (arrayVat.equals(" ")) { arVatAmount[a] = 0; st = NARR; break; }
                    display(14, 39, "Invalid code", 4);
                }
                case VAT_AMT -> {
                    if (w == 0) { st = NARR; break; }
                    long amt = acceptMoney8s2(16, 17, arVatAmount[a]);
                    if (amt != arVatAmount[a] && arAmount[a] != 0 && arrayVat.equals("M")) arAmount[a] += arVatAmount[a] - amt;
                    arVatAmount[a] = amt;
                    cs = crtStatus();
                    if (cs == DOWN || cs == PGDN || z != 0) { st = MAIN; break; }
                    if (cs == UP || cs == PGUP) { st = VAT; break; }
                    if (cs == ESC) break loop;
                    st = NARR;
                }
                case NARR -> {
                    if (arAmount[a] == 0 && arVatAmount[a] == 0) { st = MAIN; break; }
                    show(14, 39, sp(12), 7);
                    arLegend[a] = pad(acceptUpdate(18, 17, 32, sp(32)), 32);
                    cs = crtStatus();
                    if (cs == PGDN || cs == DOWN || z != 0) { st = MAIN; break; }
                    if (cs == PGUP || (cs == UP && autoVat())) { st = VAT; break; }
                    if (cs == PGUP || cs == UP) { st = AMOUNT; break; }
                    if (cs == ESC) break loop;
                    st = END;
                }
                default -> {
                    boolean dr = bat.str("convention").equals("DR");
                    if (dr) { arDr[a] = accountIn; arDrPc[a] = arrayPc; arVatSide[a] = "DR"; }
                    else { arCr[a] = accountIn; arCrPc[a] = arrayPc; arVatSide[a] = "CR"; }
                    if (dr) { arCr[a] = bat.intv("batch-def-ac"); arCrPc[a] = bat.intv("batch-def-pc"); }
                    else { arDr[a] = bat.intv("batch-def-ac"); arDrPc[a] = bat.intv("batch-def-pc"); arCode[a] = bat.str("batch-def-code"); }
                    arVatAc[a] = w != 0 ? acs(w) : 0;
                    arVatPc[a] = bat.intv("batch-def-pc");
                    a++;
                    if (a > 12) writeOut();
                    st = MAIN;
                }
            }
        }
        ledger.close();
        if (esc()) quitBatch();
        else sys.setNum("postings", sys.intv("postings") + saveA);
    }

    private void net() {
        arVatAmount[a] = BigDecimal.valueOf(arAmount[a]).multiply(wsVatRate).divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP).longValue();
        show(16, 17, amtEdit(arVatAmount[a], 8));
    }
    private void gross() {
        BigDecimal amt = BigDecimal.valueOf(arAmount[a]);
        BigDecimal div = wsVatRate.add(BigDecimal.valueOf(100)).divide(BigDecimal.valueOf(100));
        arVatAmount[a] = amt.subtract(amt.divide(div, 20, RoundingMode.DOWN)).setScale(0, RoundingMode.HALF_UP).longValue();
        arAmount[a] -= arVatAmount[a];
        show(16, 17, amtEdit(arVatAmount[a], 8));
    }

    private void writeOut() {
        if (a < 1) return;
        postingFile.open(CobFile.Mode.IO);
        if (!escapeCode.equals("F")) a--;
        for (y = 1; y <= a; y++) {
            post.setNum("batch", bat.intv("batch-nos"));
            post.setNum("post-number", saveA + y);
            postingFile.rrn = bat.intv("batch-start") + saveA + y;
            post.set("post-code", bat.str("batch-def-code"));
            post.set("post-date", arDate[y]);
            post.setNum("post-dr", arDr[y]); post.setNum("dr-pc", arDrPc[y]);
            post.setNum("post-cr", arCr[y]); post.setNum("cr-pc", arCrPc[y]);
            post.setNum("post-amount", BigDecimal.valueOf(arAmount[y], 2));
            post.set("post-legend", arLegend[y]);
            post.setNum("vat-ac", arVatAc[y]);
            post.setNum("vat-pc", arVatPc[y]);
            post.set("post-vat-side", arVatSide[y]);
            post.setNum("vat-amount", BigDecimal.valueOf(arVatAmount[y], 2));
            postingFile.write(post);
        }
        postingFile.close();
        saveA += a;
        a = 1;
    }

    private void quitBatch() {
        postingFile.open(CobFile.Mode.IO);
        postingFile.rrn = bat.intv("batch-start");
        boolean have = postingFile.read(post).equals("00");
        while (true) {
            if (have && post.intv("batch") == bat.intv("batch-nos")) postingFile.delete(post);
            if (!postingFile.readNext(post).equals("00")) break;
            have = true;
        }
        postingFile.close();
        z = 9;
    }
}
