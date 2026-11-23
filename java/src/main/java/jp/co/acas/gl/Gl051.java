package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** gl051.cbl: 仕訳の検証・修正（バッチ修正、検証帳票、全仕訳印刷）。 */
public class Gl051 extends GlProgram {
    static final String PROG_NAME = "gl051 (3.00.04)";
    private static final int PGUP = 2001, PGDN = 2002, UP = 2003, DOWN = 2004;

    private Rec led, bat, post; private CobFile ledger, batchFile, postingFile; private Printer print;
    private int wsMenu, z, trutht, firstTimeFlag, lineCnt, pageNos, saveBatch, arrayPc;
    private long uBin, accountIn;
    private String wsDate = sp(10), l3Date = sp(10), l3User = sp(32), arrayVat = " ", drError = sp(12), crError = sp(12);
    private BigDecimal wsVatRate = BigDecimal.ZERO;

    @Override
    public void run(Object... args) {
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        bat = GlCommon.batchRec(); batchFile = GlCommon.batchFile(ctx, bat);
        post = GlCommon.postingRec(); postingFile = GlCommon.postingFile(ctx);
        // FD レコード域は未使用時 low-values
        bat.load(new byte[bat.bytes().length]);
        post.load(new byte[post.bytes().length]);
        print = new Printer("prt-1", 132);
        while (true) {
            wsDate = wsDate();
            l3Date = wsDate; l3User = sys.str("usera");
            z = 0;
            display(1, 1, PROG_NAME); eraseEos(1, 16);
            display(1, 23, "Batch Amendment / Reporting Functions");
            show(1, 71, wsDate, 2);
            show(3, 1, sys.str("usera"), 2);
            display(8, 1, "Select one of the following by number :- [ ]");
            display(10, 1, "(1)  Amend existing Batch");
            display(11, 1, "(2)  Print Proof Reports - All Batches");
            display(12, 1, "(3)  Print Proof Reports - One Batch");
            display(13, 1, "(4)  Print all Transactions");
            display(16, 1, "(9)  Exit to system menu");
            wsMenu = (int) acceptNum(8, 43, 1);
            if (wsMenu == 9) return;
            batchFile.open(CobFile.Mode.IO);
            if (wsMenu == 1 || wsMenu == 3) {
                getBatch();
                if (bat.str("batch-nos").equals("00000")) { batchFile.close(); continue; }
            }
            if (wsMenu == 1) gl050c();
            if (wsMenu == 3) gl050d();
            if (wsMenu == 2) proofAll();
            if (wsMenu == 4) { saveBatch = 0; bat.setNum("batch-start", 1); z = 99; gl050d(); }
            if (wsMenu != 1) bat.setNum("proofed", uBin);
            batchFile.rewrite(bat);
            batchFile.close();
        }
    }

    private void getBatch() {
        while (true) {
            bat.set("ledger", "1");
            display(18, 1, "Enter Batch Number :- [     ]");
            String cur = bat.str("batch-nos");
            String in;
            if (cur.indexOf('\0') >= 0) {
                // batch-file が無い場合レコード域は low-values。curses は NUL を "^@" と表示する（レガシー実測）
                show(18, 24, "^@".repeat(5));
                in = acceptUpdate(18, 24, 5, "^@^@^");
            } else {
                show(18, 24, cur);
                in = acceptUpdate(18, 24, 5, cur);
            }
            bat.setNum("batch-nos", digits(in, 5));
            if (bat.intv("batch-nos") == 0) return;
            if (batchFile.read(bat).startsWith("2")) continue;
            return;
        }
    }

    private static String acsEdit(long v) { return Num.z9(v / 100, 4) + "." + Num.z9(v % 100, 2); }
    private static String amtEdit(long v, int n) { long u = Math.abs(v); return Num.z9(u / 100, n) + "." + Num.z9(u % 100, 2); }
    private static long money(String s, int n) { s = pad(s, n + 3); return digits(s.substring(0, n), n) * 100 + digits(s.substring(n + 1, n + 3), 2); }
    private static long cents(BigDecimal v) { return v.movePointRight(2).longValue(); }
    private long acceptMoney(int line, int col, long cur, int n) {
        show(line, col, amtEdit(cur, n));
        return money(acceptUpdate(line, col, n + 3, amtEdit(cur, n)), n);
    }
    private boolean autoVat() { return sys.str("vat").equals("Y"); }
    private boolean up() { int c = crtStatus(); return c == PGUP || c == UP; }

    private void proofAll() {
        while (true) {
            String st = batchFile.readNext(bat);
            if (st.equals("10")) return;
            if (!st.equals("00")) runaway();
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            if (bat.intv("cleared-status") != 0) continue;
            gl050d();
            batchFile.rewrite(bat);
        }
    }

    private void helpOutline() {
        display(14, 54, "+".repeat(27)); display(23, 54, "+".repeat(27));
        for (int l = 15; l <= 22; l++) { display(l, 54, "+"); display(l, 80, "+"); }
        display(16, 56, "Option :- [ ]");
        display(18, 56, "B - Back-up one field");
        display(19, 56, "E - End");
    }

    private void gl050c() {
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 26, "General Ledger - Batch Amendment");
        wsDate = wsDate();
        show(1, 71, wsDate, 2);
        helpOutline();
        batchAmendment();
        if (trutht == 1) { ledger.close(); postingFile.close(); return; }
        ledger.open(CobFile.Mode.INPUT);
        int v;
        while (true) {
            display(4, 1, "VAT Rate :- [1]");
            v = (int) acceptNum(4, 14, 1, 1);
            if (v < 1 || v > 3) continue;
            wsVatRate = sys.num("vat-rate", v);
            show(4, 17, Num.edit(wsVatRate, "z9.99"), 2);
            display(4, 22, "% ok (Y/N) :- [Y]");
            String r = pad(accept(4, 37, 1), 1);
            if (r.equals("N") || r.equals("n")) continue;
            break;
        }
        display(4, 56, "Batch      - ");
        show(4, 69, Num.edit(bat.intv("batch-nos"), "zzzz9"), 2);
        display(4, 74, "/");
        display(6, 56, "Default    - ");
        show(6, 69, bat.str("bdefault"), 2);
        display(8, 56, "Contra A/C - ");
        show(8, 69, bat.str("batch-def-ac"), 2);
        if (bat.intv("batch-def-pc") != 0) { display(8, 75, "/"); show(8, 76, bat.str("batch-def-pc"), 2); }
        display(10, 56, "Vat A/C    - ");
        show(10, 69, bat.str("batch-def-vat"), 2);
        display(12, 56, "Convention - ");
        show(12, 69, bat.str("convention"), 2);
        postingFile.open(CobFile.Mode.IO);
        final int LOOP = 0, DATE = 1, ACCOUNT = 2, PC = 3, AMOUNT = 4, VAT = 5, VAT_AMT = 6, NARR = 7;
        int st = LOOP;
        loop:
        while (true) {
            boolean dr = bat.str("convention").equals("DR");
            switch (st) {
                case LOOP -> {
                    display(6, 1, "Date           [          ]");
                    display(8, 1, "Account        [       ]");
                    if (profitCentres()) display(10, 1, "Profit Centre  [  ]");
                    if (branches()) display(10, 1, "Branch         [  ]");
                    display(12, 1, "Amount         [           ]");
                    if (autoVat()) display(14, 1, "VAT Code       [ ]  {P or M or space}");
                    display(16, 1, "VAT Amount     [           ]");
                    display(18, 1, "Narrative      [");
                    display(18, 49, "]");
                    while (true) {
                        String s = postingFile.readNext(post);
                        if (s.equals("10")) break loop;
                        if (!s.equals("00")) runaway();
                        if (post.intv("batch") == bat.intv("batch-nos")) break;
                    }
                    st = DATE;
                }
                case DATE -> {
                    String d = post.str("post-date");
                    show(6, 17, d);
                    post.set("post-date", acceptUpdate(6, 17, 8, d));
                    if (esc()) break loop;
                    String t = pad(post.str("post-date"), 10).replace('.', '/').replace(',', '/').replace('-', '/');
                    if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
                    wsDate = GlCommon.formToUk(sys, t);
                    uBin = Maps04.toBin(wsDate);
                    post.set("post-date", t);
                    if (uBin == 0) { trutht = 0; display(6, 36, "GL011 Invalid Date", 4); break; }
                    show(6, 26, sp(29), 7);
                    accountIn = dr ? post.intv("post-dr") : post.intv("post-cr");
                    arrayPc = dr ? post.intv("dr-pc") : post.intv("cr-pc");
                    st = ACCOUNT;
                }
                case ACCOUNT -> {
                    show(8, 17, acsEdit(accountIn));
                    accountIn = money(acceptUpdate(8, 17, 7, acsEdit(accountIn)), 4);
                    int cs = crtStatus();
                    if (up() || cs == PGDN || cs == DOWN || z != 0) { st = DATE; break; }
                    if (esc()) break loop;
                    led.setNum("ledger-nos", accountIn); led.setNum("ledger-pc", arrayPc);
                    if (ledger.read(led).equals("00")) show(8, 26, led.str("ledger-name"));
                    else { trutht = 0; display(8, 26, "Invalid A/C number"); break; }
                    st = PC;
                }
                case PC -> {
                    if (!pcOrBranch()) { st = AMOUNT; break; }
                    show(10, 17, Num.z9(arrayPc, 2));
                    arrayPc = (int) acceptNum(10, 17, 2, arrayPc);
                    if (up()) { st = ACCOUNT; break; }
                    if (esc()) break loop;
                    st = AMOUNT;
                }
                case AMOUNT -> {
                    if (dr) { post.setNum("post-dr", accountIn); post.setNum("dr-pc", arrayPc); }
                    else { post.setNum("post-cr", accountIn); post.setNum("cr-pc", arrayPc); }
                    // レガシー: 符号なし作業域を経由するため絶対値になる
                    post.setNum("post-amount", BigDecimal.valueOf(acceptMoney(12, 17, cents(post.num("post-amount")), 8), 2));
                    if (up()) { st = pcOrBranch() ? PC : ACCOUNT; break; }
                    if (esc()) break loop;
                    st = VAT;
                }
                case VAT -> {
                    if (!autoVat()) { st = VAT_AMT; break; }
                    arrayVat = " ";
                    show(14, 17, arrayVat);
                    arrayVat = upper(pad(acceptUpdate(14, 17, 1, arrayVat), 1));
                    show(14, 39, sp(18), 7);
                    if (up()) { st = AMOUNT; break; }
                    if (esc()) break loop;
                    BigDecimal amt = post.num("post-amount");
                    if (arrayVat.equals("P")) {
                        post.setNum("vat-amount", amt.multiply(wsVatRate).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP));
                        st = VAT_AMT; break;
                    }
                    if (arrayVat.equals("M")) {
                        BigDecimal div = wsVatRate.add(BigDecimal.valueOf(100)).divide(BigDecimal.valueOf(100));
                        BigDecimal vat = amt.subtract(amt.divide(div, 20, RoundingMode.DOWN)).setScale(2, RoundingMode.HALF_UP);
                        post.setNum("vat-amount", vat);
                        post.setNum("post-amount", amt.subtract(vat));
                        st = VAT_AMT; break;
                    }
                    if (arrayVat.equals(" ")) { post.setNum("vat-amount", 0); st = NARR; break; }
                    display(14, 39, "GL111 Invalid code");
                }
                case VAT_AMT -> {
                    long vat = cents(post.num("vat-amount")), abs = Math.abs(vat);
                    long in = acceptMoney(16, 17, abs, 8);
                    if (in != vat && post.num("post-amount").signum() != 0 && arrayVat.equals("M"))
                        post.setNum("post-amount", post.num("post-amount").add(BigDecimal.valueOf(vat - in, 2)));
                    post.setNum("vat-amount", BigDecimal.valueOf(in, 2));
                    if (up()) { st = VAT; break; }
                    if (esc()) break loop;
                    st = NARR;
                }
                default -> {
                    show(14, 39, sp(18), 7);
                    String lg = post.str("post-legend");
                    show(18, 17, lg);
                    post.set("post-legend", acceptUpdate(18, 17, 32, lg));
                    if (up()) { st = autoVat() ? VAT : AMOUNT; break; }
                    if (esc()) break loop;
                    postingFile.rrn = bat.intv("batch-start") + post.intv("post-number");
                    postingFile.rewrite(post);
                    st = LOOP;
                }
            }
        }
        ledger.close(); postingFile.close();
    }

    private void batchAmendment() {
        display(8, 1, "Amend Batch Header ? (Y/N) :- [N]");
        String r = upper(pad(acceptUpdate(8, 32, 1, "N"), 1));
        if (r.equals("N")) { trutht = 0; eraseEol(8, 1); return; }
        display(15, 1, "*".repeat(46)); display(23, 1, "*".repeat(46));
        for (int l = 16; l <= 23; l++) { display(l, 1, "*"); display(l, 46, "*"); }
        display(16, 18, "Batch Data");
        display(17, 2, "Batch         :- {     }");
        show(17, 20, Num.edit(bat.intv("batch-nos"), "zzzz9"), 2);
        display(18, 2, "Cycle         :- [  ]");
        display(19, 2, "Items         :- [  ]");
        display(20, 2, "Gross Value   :- [            ]");
        display(21, 2, "VAT Value     :- [            ]");
        display(22, 2, "Description   :- [");
        display(22, 44, "]");
        final int CYCLE = 0, ITEMS = 1, GROSS = 2, VAT = 3, DESC = 4;
        int st = CYCLE;
        while (true) {
            switch (st) {
                case CYCLE -> {
                    show(18, 20, bat.str("bcycle"));
                    bat.setNum("bcycle", acceptNum(18, 20, 2, bat.intv("bcycle")));
                    if (esc()) { trutht = 0; return; }
                    if (bat.intv("bcycle") < sys.intv("scycle")) { display(18, 24, "GL108 Invalid. Too early"); break; }
                    if (bat.intv("bcycle") - sys.intv("scycle") > 1) { display(18, 24, "GL109 Invalid. Too forward"); break; }
                    show(18, 24, sp(27), 7);
                    st = ITEMS;
                }
                case ITEMS -> {
                    show(19, 20, bat.str("items"));
                    bat.setNum("items", acceptNum(19, 20, 2, bat.intv("items")));
                    if (esc()) { st = CYCLE; break; }
                    if (bat.intv("items") == 0) display(19, 24, "GL110 No check on items.");
                    st = GROSS;
                }
                case GROSS -> {
                    bat.setNum("input-gross", BigDecimal.valueOf(acceptMoney(20, 20, cents(bat.num("input-gross")), 9), 2));
                    if (esc()) { st = ITEMS; break; }
                    st = VAT;
                }
                case VAT -> {
                    if (!autoVat()) { st = DESC; break; }
                    bat.setNum("input-vat", BigDecimal.valueOf(acceptMoney(21, 20, cents(bat.num("input-vat")), 9), 2));
                    if (esc()) { st = GROSS; break; }
                    st = DESC;
                }
                default -> {
                    String d = bat.str("description");
                    show(22, 20, d);
                    bat.set("description", acceptUpdate(22, 20, 24, d));
                    if (esc()) { st = autoVat() ? VAT : GROSS; break; }
                    display(8, 1, "Amend Batch Details? (Y/N) :- [N]");
                    String r2 = upper(pad(acceptUpdate(8, 32, 1, "N"), 1));
                    trutht = r2.equals("N") ? 1 : 0;
                    eraseEol(8, 1);
                    eraseEos(15, 1);
                    helpOutline();
                    return;
                }
            }
        }
    }

    // ---------- 検証帳票 ----------
    private String ukDate(long bin) {
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        return GlCommon.ukToForm(sys, Maps04.toDate(bin));
    }
    private String line4() {
        return "Batch - " + Num.edit(bat.intv("batch-nos"), "zzzz9") + sp(8) + pad(bat.str("description"), 24)
                + pad("    Date Entered - ", 20) + pad(ukDate(bat.num("entered").longValue()), 10);
    }
    private static String amt13(BigDecimal v, int z) { return Num.edit(v.abs(), "z".repeat(z) + "9.99") + "  "; }

    private void headings() {
        pageNos++;
        print.after(pad(PROG_NAME, 14) + sp(41) + "Transaction Proof Report" + sp(45) + "Page  " + Num.edit(pageNos, "z9"), 1);
        print.after(pad(l3User, 32) + sp(90) + pad(l3Date, 10), 1);
        lineCnt = 6;
        if (z != 99) { print.after(line4(), 2); lineCnt += 2; }
        print.after("Number  Code  ---Date--- --Debit--   --Credit-    Net Amount    VAT Amount  VAT Account  VAT Side   ----------"
                + "--Narative------------", 2);
        print.after("------  ----              A/C  P/C    A/C  P/C    ----------    ----------    A/C  P/C   --------", 1);
        print.after("", 1);
    }

    private void gl050d() {
        print.open();
        pageNos = 0;
        trutht = 1;
        if (firstTimeFlag == 0) {
            display(1, 1, PROG_NAME); eraseEos(1, 16);
            display(1, 27, "General Ledger - Proof Report");
            wsDate = wsDate();
            show(1, 71, wsDate, 2);
            display(12, 12, "Printing......please wait");
            if (wsMenu == 2) firstTimeFlag = 1;
        }
        postingFile.open(CobFile.Mode.INPUT);
        ledger.open(CobFile.Mode.INPUT);
        bat.setNum("actual-gross", 0); bat.setNum("actual-vat", 0);
        batchPrint();
        postingFile.close(); ledger.close(); print.close();
        ctx.spool("prt-1", printReport());
    }

    private void batchPrint() {
        headings();
        bat.set("ledger", "1");
        while (true) {
            String s = postingFile.readNext(post);
            if (s.equals("10")) break;
            // レガシーは未 OPEN の posting-file を読み続け、不定内容を印字し続ける（暴走）
            if (!s.equals("00")) runaway();
            if (post.intv("batch") == 0) continue;
            if (z == 99 && saveBatch != post.intv("batch")) {
                saveBatch = post.intv("batch");
                bat.setNum("batch-nos", saveBatch);
                if (batchFile.read(bat).startsWith("2")) bat.setNum("batch-nos", 99999);
                uBin = bat.num("entered").longValue();
                wsDate = ukDate(uBin);
                String l4 = "Batch - " + Num.edit(saveBatch, "zzzz9") + sp(8) + pad(bat.str("description"), 24)
                        + pad("    Date Entered - ", 20) + pad(wsDate, 10);
                print.after(l4, 2);
                lineCnt += 2;
            } else if (z != 99 && post.intv("batch") != bat.intv("batch-nos")) continue;
            long vatAc = post.intv("vat-ac");
            String l7 = Num.edit(post.intv("post-number"), "zzzz9") + sp(4)
                    + pad(post.str("post-code"), 5) + pad(post.str("post-date"), 12)
                    + Num.edit(BigDecimal.valueOf(post.intv("post-dr"), 2), "zzz9.99") + " " + Num.z9(post.intv("dr-pc"), 2) + "  "
                    + Num.edit(BigDecimal.valueOf(post.intv("post-cr"), 2), "zzz9.99") + " " + Num.z9(post.intv("cr-pc"), 2) + "  "
                    + amt13(post.num("post-amount"), 8) + amt13(post.num("vat-amount"), 8)
                    + (vatAc == 0 ? sp(7) : Num.edit(BigDecimal.valueOf(vatAc, 2), "zzz9.99"))
                    + (post.intv("vat-pc") == 0 ? sp(9) : " " + Num.edit(post.intv("vat-pc"), "z9") + sp(6))
                    + pad(vatAc != 0 ? post.str("post-vat-side") : "", 8)
                    + pad(post.str("post-legend"), 32);
            print.after(l7, 1);
            lineCnt++;
            getDescription();
            if (!crError.isBlank() || !drError.isBlank()) { print.after(sp(24) + drError + crError, 1); lineCnt++; }
            if (lineCnt > sys.intv("page-lines") - 6) headings();
            bat.setNum("actual-gross", bat.num("actual-gross").add(post.num("post-amount")));
            bat.setNum("actual-vat", bat.num("actual-vat").add(post.num("vat-amount")));
        }
        // end-batch
        if (z == 99) return;
        if (trutht != 1) { bat.setNum("batch-status", 0); return; }
        BigDecimal l9 = bat.num("input-gross").subtract(bat.num("input-vat"));
        BigDecimal l10a = bat.num("actual-gross"), l10v = bat.num("actual-vat");
        bat.setNum("actual-gross", l10a.add(l10v));
        if (lineCnt > sys.intv("page-lines") - 12) headings();
        print.after(sp(20) + "Batch              ----Net----    ----VAT----", 3);
        print.after(sp(20) + pad("Header", 17) + amt13(l9, 9) + amt13(bat.num("input-vat"), 9), 2);
        print.after(sp(20) + pad("Actual", 17) + amt13(l10a, 9) + amt13(l10v, 9), 2);
        boolean ok = bat.num("input-gross").compareTo(bat.num("actual-gross")) == 0
                && bat.num("input-vat").compareTo(bat.num("actual-vat")) == 0;
        bat.setNum("batch-status", ok ? 1 : 0);
        print.after(sp(20) + "*********************", 3);
        print.after(sp(20) + (ok ? "* Batch Verified Ok *" : "*  Batch In ERROR   *"), 1);
        print.after(sp(20) + "*********************", 1);
    }

    private void getDescription() {
        led.setNum("ledger-nos", post.intv("post-dr")); led.setNum("ledger-pc", post.intv("dr-pc"));
        if (ledger.read(led).equals("00")) drError = sp(12); else { drError = pad("^^^^^^^^^^", 12); trutht = 0; }
        led.setNum("ledger-nos", post.intv("post-cr")); led.setNum("ledger-pc", post.intv("cr-pc"));
        if (ledger.read(led).equals("00")) crError = sp(12); else { crError = pad("^^^^^^^^^^", 12); trutht = 0; }
    }
}
