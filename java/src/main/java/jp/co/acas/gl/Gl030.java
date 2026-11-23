package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** gl030.cbl: 勘定科目表ユーティリティ（部門設定、科目登録・変更・削除、照会、印刷）。 */
public class Gl030 extends GlProgram {
    static final String PROG_NAME = "GL030 (3.00.04)";
    private static final String[] LEDGER_DESC = {"Header ", "Detail ", "Sales  ", "Purch. ", "Special"};
    private static final String[] PLACE = {"Direct Income", "Direct Costs ", "Sundry Income", "Indirect Cost",
            "Fixed Assets ", "Current Asset", "Current Liab.", "Capital A/Cs "};
    private static final int LINES = 24, L23 = 23, L22 = 22;

    private Rec led; private CobFile ledger; private Printer print;
    private StringBuilder pcb = new StringBuilder(sp(107));   // p-c-branches（pc-key 8 桁 + p-b-codes 99 個）
    private int wsMenu, est, lin, lin2, y, z, truth, gateSw = 1, saveS, saveType, pageNos, lineCnt;
    private String pcCode = "  ", aTest = " ", savePlace = " ", saveCode = "  ", seek = " ";
    private String ledgerCheck = "000000";
    private long saveLedger;

    @Override
    public void run(Object... args) {
        if (resumed(args)) return;
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        print = new Printer("prt-1", 132);
        while (true) {
            display(1, 1, PROG_NAME); eraseEos(1, 16);
            display(1, 28, "Chart Of Account Utilities");
            show(1, 71, wsDate(), 2);
            show(3, 1, sys.str("usera"));
            display(8, 1, "Select one of the following by number :- [ ]");
            lin = 10; int a = 1;
            if (profitCentres()) { item(a, "Set-up or Amend Profit Centres"); lin++; a++; }
            if (branches()) { item(a, "Set-up or Amend Branch Codes"); lin++; a++; }
            item(a, "Add New Accounts"); lin++; a++;
            item(a, "Amend/Delete Existing Accounts"); lin++; a++;
            if (index2()) { item(a, "Print Alphabetic List"); lin++; a++; }
            item(a, "Display Chart of Accounts"); lin++; a++;
            item(a, "Print Chart of Accounts"); lin++; a++;
            if (profitCentres()) item(a, "Print Report on Profit Centres");
            if (branches()) item(a, "Print Report on Branch Codes");
            lin += 3;
            item(9, "Exit to system menu");
            wsMenu = (int) acceptNum(8, 43, 1);
            if (wsMenu == 9) return;
            if (sys.str("p-c").equals(" ")) wsMenu++;
            if (wsMenu == 1) { gl030a(); continue; }
            if (wsMenu == 2) { gl030b(); continue; }
            if (wsMenu == 3) { gl030c(); continue; }
            if (!index2()) wsMenu++;
            if (wsMenu == 4) { gl030e(); continue; }
            if (wsMenu == 5 || wsMenu == 6) { gl030f(); continue; }
            if (wsMenu == 7) gl030g();
        }
    }
    private boolean index2() { return sys.str("ledger-2nd-index").equals("Y"); }
    private void item(int a, String text) {
        display(lin, 1, "("); showNum(lin, 2, a, 1); display(lin, 3, ")"); display(lin, 6, text);
    }
    private char code(int i) { return i >= 1 && i <= 99 ? pcb.charAt(7 + i) : ' '; }
    private void code(int i, char c) { if (i >= 1 && i <= 99) pcb.setCharAt(7 + i, c); }
    private boolean ey(int i) { return code(i) == 'E' || code(i) == 'Y'; }
    private void head(int col, String title) {
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        show(1, 71, wsDate(), 2);
        if (title != null) display(1, col, title);
    }
    private void zeroAmounts() {
        for (String f : new String[]{"ledger-balance", "ledger-last", "ledger-q1", "ledger-q2", "ledger-q3", "ledger-q4"}) led.setNum(f, 0);
    }
    /** 999999/00 の部門コード表を読み、est（E の位置）を求める。 */
    private void readPcb() {
        led.setNum("ledger-nos", 999999); led.setNum("ledger-pc", 0);
        if (!ledger.read(led).equals("00")) weError = 255;
        pcb = new StringBuilder(weError == 255 ? sp(107) : latin(led.bytes()).substring(0, 107));
    }
    private void findEst() {
        pcb.replace(0, 8, "99999900");
        est = 0;
        for (int i = 1; i <= 99; i++) if (code(i) == 'E') { est = i; break; }
    }

    // ---- gl030a: 部門（Profit Centre / Branch）設定 ----
    private void gl030aMain() {
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
            ledger.open(CobFile.Mode.OUTPUT);
            led.setRaw("ledger-name", new byte[24]);
            led.setNum("ledger-nos", 999999); led.setNum("ledger-pc", 99);
            led.setNum("ledger-type", 0); led.set("ledger-place", "0"); led.setNum("ledger-level", 0);
            zeroAmounts();
            ledger.write(led);
        }
    }
    private void gl030a() {
        gl030aMain();
        ledger.close();
        ledger.open(CobFile.Mode.IO);
        readPcb(); findEst();
        head(0, null);
        if (profitCentres()) display(1, 27, "Set-Up for Profit Centres"); else display(1, 30, "Set-Up for Branches");
        while (true) {
            display(4, 1, "Establishment Code :- [  ]");
            showNum(4, 24, est, 2);
            est = (int) acceptNum(4, 24, 2, est);
            if (est == 0) { display(5, 1, "GL101 A code for Establishment must be input"); continue; }
            break;
        }
        code(est, 'E');
        eraseEol(5, 1);
        while (true) {
            // re-input
            int l = 7, c = 1; y = 1;
            while (true) {
                showNum(l, c, y, 3); display(l, c + 3, ". ["); show(l, c + 6, String.valueOf(code(y))); display(l, c + 7, "]");
                l++; y++;
                if (l < L23 && y < 100) continue;
                if (y < 100) { l = 7; c += 11; continue; }
                break;
            }
            l = 7; c = 7; y = 1;
            display(L23, 1, "Enter <Y> to select the code. Space to de-select the code.<Q> to finish");
            boolean quit = false;
            while (true) {
                if (code(y) != 'E') {
                    while (true) {
                        String w = upper(acceptUpdate(l, c, 1, String.valueOf(code(y))));
                        code(y, w.charAt(0));
                        if (w.equals("Q")) { code(y, ' '); quit = true; break; }
                        if (code(y) == ' ' || code(y) == 'Y') break;
                    }
                    if (quit) break;
                }
                l++; y++;
                if (l < L23 && y < 100) continue;
                if (y < 100) { l = 7; c += 11; continue; }
                break;
            }
            eraseEol(L23, 1);
            display(L23, 1, "Details OK to file ? (Y/N) :- [Y]");
            String r = acceptUpdate(L23, 32, 1, "Y");
            if (r.equalsIgnoreCase("N")) continue;
            break;
        }
        led.load(latin(pad(pcb.toString(), 126)));
        if (weError == 255) ledger.write(led); else ledger.rewrite(led);
        weError = 0;
        head(0, null);
        if (profitCentres()) display(1, 28, "Name the Profit Centres"); else display(1, 31, "Name the Branches");
        lin = 4; y = 1;
        led.setNum("ledger-pc", 0); led.setNum("ledger-type", 0); zeroAmounts(); led.set("ledger-place", " ");
        loop3:
        while (true) {
            if (code(y) != ' ') {
                led.setNum("ledger-nos", 999999); led.setNum("ledger-pc", y);
                if (!ledger.read(led).equals("00")) weError = 255;
                if (weError == 255) led.set("ledger-name", "");
                while (true) {
                    display(lin, 1, "Code - "); showNum(lin, 8, y, 3); display(lin, 11, " Name :- ["); display(lin, 45, "]");
                    show(lin, 21, led.str("ledger-name"), 2);
                    led.set("ledger-name", acceptUpdate(lin, 21, 24, led.str("ledger-name")));
                    String nm = led.trim("ledger-name");
                    if (nm.equals("QUIT") || nm.equals("quit") || esc()) break loop3;
                    if (weError == 255 && nm.isEmpty()) continue;
                    break;
                }
                if (weError == 255) ledger.write(led); else ledger.rewrite(led);
                weError = 0;
                lin++;
            }
            y++;
            if (y > 99) break;
            if (lin < L22) continue;
            for (lin = 4; lin < L22; lin++) eraseEol(lin, 1);
            lin = 4;
        }
        ledger.close();
    }

    // ---- gl030b: 科目登録 ----
    private void headings() {
        display(4, 1, "Ledger    Sub");
        if (profitCentres()) display(4, 17, "P/C");
        if (branches()) display(4, 15, "Branch");
        display(4, 23, "-----------Name-----------  Type  Placement  Level");
    }
    private void gl030b() {
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) gl030aMain();
        ledger.close();
        ledger.open(CobFile.Mode.IO);
        if (pcOrBranch()) { readPcb(); findEst(); }
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        show(1, 71, toDay(), 2);
        display(1, 29, "Chart of Accounts Set-Up");
        headings();
        lin = 6;
        loop:
        while (true) {
            display(lin, 1, "[    ]   [  ]");
            if (pcOrBranch()) display(lin, 16, "[  ]");
            display(lin, 23, "[");
            display(lin, 48, "]  [ ]      [ ]      [ ]");
            led.setNum("ledger-nos", 0);
            acceptLedger:
            while (true) {
                led.setNum("ledger-n", acceptNum(lin, 2, 4, led.longv("ledger-n")));
                if (led.intv("ledger-n") == 0) break loop;
                lin2 = lin + 1;
                if (led.intv("ledger-n") < 1000) { display(lin2, 1, "GL102 Error! Ledger Code must be not less 1000"); continue; }
                eraseEol(lin2, 1);
                led.setNum("ledger-s", acceptNum(lin, 11, 2, led.longv("ledger-s")));
                ledgerCheck = led.str("ledger-nos");
                int first = ledgerCheck.charAt(0) - '0';
                if (first == sys.intv("sales-range") || first == sys.intv("purchase-range")) { display(lin2, 1, "Invalid start number!"); continue; }
                if (ledgerCheck.startsWith("9999")) { display(lin2, 1, "<9999>  Is reserved!"); continue; }
                if (!pcOrBranch()) led.setNum("ledger-pc", 0);
                else {
                    while (true) {
                        pcCode = acceptUpdate(lin, 17, 2, "  ");
                        pcCodeCheck();
                        if (truth == 0) { display(lin2, 17, "Invalid! Code must be numeric or <n*>."); continue; }
                        break;
                    }
                }
                led.set("ledger-name", acceptUpdate(lin, 24, 24, ""));
                boolean toEnd = sub() != 0;
                if (!toEnd) {
                    while (true) {
                        led.setNum("ledger-type", 0);
                        display(lin, 52, "0");
                        led.setNum("ledger-type", acceptNum(lin, 52, 1, 0));
                        int t = led.intv("ledger-type");
                        if (t != 0 && t != 1 && t != 9) { display(lin2, 52, "Invalid type!"); continue; }
                        break;
                    }
                    show(lin, 61, " ");
                    if (led.intv("ledger-type") == 0) {
                        boolean restart = false;
                        while (true) {
                            led.set("ledger-place", upper(acceptUpdate(lin, 61, 1, " ")));
                            char p = led.str("ledger-place").charAt(0);
                            if (p < 'A' || p > 'Z') { display(lin2, 61, "Invalid Placement!."); continue; }
                            if (revenueOnly() && p > 'N' && !pcCode.equals("00")) {
                                display(lin2, 61, "Profit centres/branches only valid for Revenue Accounts!");
                                restart = true;
                            }
                            break;
                        }
                        if (restart) continue acceptLedger;
                        while (true) {
                            led.setNum("ledger-level", 0);
                            show(lin, 70, " ");
                            led.setNum("ledger-level", acceptNum(lin, 70, 1, 0));
                            int lv = led.intv("ledger-level");
                            if (lv < 1 || lv > 4) { display(lin2, 70, "Invalid!"); continue; }
                            break;
                        }
                    }
                }
                zeroAmounts();
                if (led.intv("ledger-s") != 0) { saveS = led.intv("ledger-s"); detailCheck(); }
                else headerCheck();
                showNum(lin, 52, led.intv("ledger-type"), 1);
                showNum(lin, 70, led.intv("ledger-level"), 1);
                if (truth == 1) continue;
                break;
            }
            multi(this::ledgerWrite);
            y = 0; ledgerWrite();
            lin++;
            eraseEol(lin, 1);
            eraseEol(L23, 1);
            if (lin < L22) continue;
            for (lin = 6; lin < L22; lin++) eraseEol(lin, 1);
            lin = 6;
        }
        ledger.close();
    }
    private boolean revenueOnly() { return sys.str("p-c-level").equals("R"); }
    private int sub() { return Integer.parseInt(ledgerCheck.substring(4, 6)); }
    private void setCheck(int from, int to, int v) {
        ledgerCheck = ledgerCheck.substring(0, from) + Num.z9(v, to - from) + ledgerCheck.substring(to);
    }
    private int check(int from, int to) { return Integer.parseInt(ledgerCheck.substring(from, to)); }

    /** loop-end / multi-add: 部門コード指定（nn / n* / **）に従い op を実行。 */
    private void multi(Runnable op) {
        if (pcCode.charAt(1) != '*') { y = (int) digits(pcCode, 3); op.run(); return; }
        led.setNum("ledger-pc", 0); y = 0;
        if (pcCode.charAt(0) == '*') { y = 1; for (int i = 0; i < 99; i++) loopAdd(op); return; }
        y = (int) digits(pcCode.substring(0, 1), 3) * 10;
        if (y > 0) for (int i = 0; i < 10; i++) loopAdd(op);
        else { y++; for (int i = 0; i < 9; i++) loopAdd(op); }
    }
    private void loopAdd(Runnable op) { if (ey(y)) op.run(); y++; }

    private void detailCheck() {
        setCheck(4, 6, 0);
        aTest = "D"; ledgerRead(); aTest = " ";
        setCheck(4, 6, saveS); led.setNum("ledger-s", saveS);
        if (truth == 0) { display(lin2, 1, "INVALID! Header Missing"); truth = 1; }
        else ledgerRead();
        if (led.intv("ledger-type") != 9) led.setNum("ledger-type", 1);
        led.setNum("ledger-level", 0);
    }
    private void headerCheck() {
        if (check(1, 4) == 0) { ledgerRead(); led.setNum("ledger-level", 1); }
        if (check(1, 4) != 0 && check(2, 4) == 0) { led.setNum("ledger-level", 2); parentCheck(1, 4); }
        if (check(2, 4) != 0 && check(3, 4) == 0) { led.setNum("ledger-level", 3); parentCheck(2, 4); }
        if (check(3, 4) != 0) { led.setNum("ledger-level", 4); parentCheck(3, 4); }
    }
    private void parentCheck(int from, int to) {
        int save = check(from, to);
        setCheck(from, to, 0);
        ledgerRead();
        setCheck(from, to, save);
        if (truth == 1) ledgerRead();
        else { display(lin2, 1, "INVALID! Header Missing"); truth = 1; }
    }
    private void ledgerRead() {
        truth = 0;
        led.set("ledger-nos", ledgerCheck);
        if (pcCode.charAt(1) == '*') led.setNum("ledger-pc", 0);
        else led.setNum("ledger-pc", digits(pcCode, 2));
        byte[] dummy = led.copyBytes();
        weError = 0;
        // P/C 未選択の初回呼出では pc-code が空白のままでキーが数字にならず、読込みは必ず不成立になる
        boolean numericPc = pcCode.charAt(1) == '*' || pcCode.matches("[0-9]{2}");
        if (!numericPc || !ledger.read(led).equals("00")) weError = 255;
        if (weError != 255) truth = 1;
        if (aTest.equals("D")) {
            savePlace = led.str("ledger-place");
            String t = led.str("ledger-type");
            saveType = t.charAt(0) >= '0' && t.charAt(0) <= '9' ? t.charAt(0) - '0' : 0;
        }
        led.load(dummy);
        if (aTest.equals("D")) { led.setNum("ledger-type", saveType); led.set("ledger-place", savePlace); }
    }
    private void ledgerWrite() { led.setNum("ledger-pc", y); ledger.write(led); }

    private void pcCodeCheck() {
        truth = 1;
        if (pcCode.equals("  ")) pcCode = "00";
        if (pcCode.equals("**")) return;
        if (pcCode.compareTo("00") >= 0 && pcCode.compareTo("99") <= 0) return;
        if (pcCode.charAt(1) != '*') { truth = 0; return; }
        char c1 = pcCode.charAt(0);
        if (c1 < '0' || c1 > '9') { truth = 0; return; }
        z = (c1 - '0') * 10;
        truth = 0;
        if (z > 0) { for (int i = 0; i < 10; i++) { if (ey(z)) truth = 1; z++; } }
        else { z++; for (int i = 0; i < 9; i++) { if (ey(z)) truth = 1; z++; } }
    }

    // ---- gl030c: 科目変更・削除 ----
    private void gl030c() {
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
            clearScreen();
            display(9, 1, "GL103 No Ledger File to update");
            return;
        }
        ledger.close();
        ledger.open(CobFile.Mode.IO);
        if (pcOrBranch()) readPcb();
        head(29, "Chart Of Accounts Update");
        headings();
        lin = 6;
        loop:
        while (true) {
            display(lin, 1, "[    ]");
            display(lin, 11, "[  ]");
            if (pcOrBranch()) display(lin, 16, "[  ]");
            display(lin, 23, "[");
            display(lin, 48, "]  [ ]      [ ]      [ ]");
            boolean deleted = false;
            acceptLedger:
            while (true) {
                led.setNum("ledger-nos", 0);
                led.setNum("ledger-n", acceptNum(lin, 2, 4, 0));
                if (led.intv("ledger-n") == 0) break loop;
                led.setNum("ledger-s", acceptNum(lin, 12, 2, 0));
                lin2 = lin;
                if (!pcOrBranch()) pcCode = "00";
                else {
                    while (true) {
                        pcCode = acceptUpdate(lin, 17, 2, pcCode);
                        pcCodeCheck();
                        lin2++;
                        if (truth == 0) { display(lin2, 17, "Invalid! Code must be numeric or <n*>"); continue; }
                        break;
                    }
                }
                eraseEol(lin2, 1);
                weError = 0;
                if (pcCode.charAt(1) == '*') { aTest = "A"; saveCode = pcCode; pcCode = "00"; }
                led.setNum("ledger-pc", digits(pcCode, 2));
                if (!ledger.read(led).equals("00")) weError = 255;
                if (weError == 255) {
                    show(lin2, 1, led.str("ledger-nos"), 2);
                    display(lin2, 7, "/");
                    show(lin2, 8, led.str("ledger-pc"), 2);
                    display(lin2, 11, "Does not exist!");
                    continue;
                }
                if (aTest.equals("A")) { pcCode = saveCode; aTest = " "; }
                display(lin2, 24, "Enter <+> only to Delete");
                show(lin, 24, led.str("ledger-name"), 2);
                led.set("ledger-name", acceptUpdate(lin, 24, 24, led.str("ledger-name")));
                if (led.str("ledger-name").charAt(0) == '+') { deletion(); deleted = true; break; }
                while (true) {
                    eraseEol(lin2, 1);
                    show(lin, 52, led.str("ledger-type"), 2);
                    led.setNum("ledger-type", acceptNum(lin, 52, 1, led.intv("ledger-type")));
                    int t = led.intv("ledger-type");
                    if (t == 0 || t == 1 || t == 9) break;
                    display(lin2, 52, "Invalid type!");
                }
                if (led.intv("ledger-type") == 0) {
                    boolean restart = false;
                    while (true) {
                        led.set("ledger-place", upper(acceptUpdate(lin, 61, 1, led.str("ledger-place"))));
                        char p = led.str("ledger-place").charAt(0);
                        if (p < 'A' || p > 'Z') { display(lin2, 61, "Invalid Placement!"); continue; }
                        if (revenueOnly() && p > 'N' && led.intv("ledger-pc") != 0) {
                            display(lin2, 61, "Profit centres/branches only valid for Revenue Accounts!");
                            restart = true;
                        }
                        break;
                    }
                    if (restart) continue acceptLedger;
                    while (true) {
                        show(lin, 70, led.str("ledger-level"), 2);
                        led.setNum("ledger-level", acceptNum(lin, 70, 1, led.intv("ledger-level")));
                        int lv = led.intv("ledger-level");
                        if (lv < 1 || lv > 4) { display(lin2, 70, "Invalid!"); continue; }
                        break;
                    }
                }
                break;
            }
            if (!deleted) {
                multi(this::ledgerRewrite);
                y = 0; ledgerRewrite();
            }
            lin++;
            eraseEol(lin, 1);
            if (lin < L22) continue;
            for (lin = 6; lin < L22; lin++) eraseEol(lin, 1);
        }
        ledger.close();
    }
    private void deletion() {
        multi(this::ledgerDelete);
        y = 0; ledgerDelete();
        truth = 1;
    }
    private void ledgerRewrite() {
        led.setNum("ledger-pc", y);
        if (!ledger.rewrite(led).equals("00")) {
            display(L23, 1, "GL104 Rewrite ERR 030-01. hit return to finish", 4);
            accept(L23, 48, 1);
            ledger.write(led);
        }
    }
    private void ledgerDelete() {
        led.setNum("ledger-pc", y);
        if (led.num("ledger-balance").signum() != 0) {
            truth = 0;
            display(lin2, LINES, "Deletion Request Denied! Current Balance Not Zero");
            return;
        }
        ledger.delete(led);
    }

    // ---- 印刷共通 ----
    private String line1() { return pad(PROG_NAME, 14) + sp(28) + "Chart of Accounts" + sp(31); }
    private String line3() { return pad(sys.str("usera"), 32) + sp(60) + "Page -" + Num.edit(pageNos, "z9"); }
    private String pcFiller() { return profitCentres() ? "Profit Centre    " : branches() ? "   Branch        " : sp(17); }
    private void pageHeading(String l1, String heading) {
        pageNos++;
        if (pageNos != 1) print.afterPage(l1); else print.after(l1, 1);
        print.after(line3(), 1);
        print.after(heading, 2);
        print.after("", 1);
        lineCnt = 5;
    }
    private void endReport() {
        print.close();
        ctx.spool("prt-1", printReport());
    }
    private int computePlacement() {
        char p = led.str("ledger-place").charAt(0);
        return p < 'E' ? 1 : p < 'I' ? 2 : p < 'K' ? 3 : p < 'O' ? 4 : p < 'R' ? 5 : p < 'U' ? 6 : p < 'W' ? 7 : 8;
    }
    private String amt(boolean on) {
        if (!on) return sp(7);
        BigDecimal v = new BigDecimal(led.longv("ledger-nos")).movePointLeft(2);
        return v.signum() == 0 ? sp(7) : Num.edit(v, "zzz9.99");
    }
    private String pcEdit() { int p = led.intv("ledger-pc"); return p == 0 ? sp(7) : sp(5) + Num.edit(p, "z9"); }
    private String levelFiller() {
        StringBuilder b = new StringBuilder(sp(10));
        int lv = led.intv("ledger-level");
        if (lv != 0) { int i = (lv * 2 + 1) % 10; if (i >= 1) b.setCharAt(i - 1, (char) ('0' + lv)); }
        return b.toString();
    }

    // ---- gl030e: 名称順印刷 ----
    private void gl030e() {
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
            display(LINES, 1, "GL105 Deletion Request Denied! Current Balance Not Zero");
            return;
        }
        head(23, "Chart Of Accounts Alphabetic Print");
        truth = 0;
        print.open();
        String l1 = line1() + wsDate();
        String l4 = "----------Name----------" + "---Level---   Header       Detail   " + sp(4) + pcFiller() + pad("--Placement--", 19);
        pageNos = 0;
        pageHeading(l1, l4);
        while (ledger.readNext(led).equals("00")) {
            if (led.intv("ledger-n") == 9999) continue;
            boolean header = led.intv("ledger-level") != 0;
            String line = led.str("ledger-name") + levelFiller() + sp(3) + amt(header) + sp(7) + amt(!header) + sp(6) + pcEdit()
                    + sp(10) + PLACE[computePlacement() - 1] + sp(6);
            print.after(line, 1);
            lineCnt++;
            if (lineCnt > sys.intv("page-lines")) pageHeading(l1, l4);
        }
        endReport();
        ledger.close();
    }

    // ---- gl030f: 科目表の表示・印刷 ----
    private void dHead1() { head(27, "Chart Of Accounts Display"); }
    private void askClear() {
        display(L23, 1, "Press Return for next screen "); eraseEol(L23, 30);
        accept(L23, 41, 1);
    }
    private void screenClear() {
        if (gateSw == 2) askClear();
        gateSw = 2;
        for (int l = lin; l < L23; l++) eraseEol(l, 1);
    }
    private void secondHead() {
        display(lin, 1, "Ledger    ");
        display(lin, 11, "Sub    ");
        if (profitCentres()) display(lin, 18, "  P/C   ");
        else if (branches()) display(lin, 18, "Branch  ");
        else show(lin, 18, sp(8));
        display(lin, 26, "<---------Name--------->    Type    Level --Placement--");
    }
    private void displayChart() {
        if (truth == 1) { secondHead(); return; }
        show(lin, 2, led.str("ledger-n"), 2);
        show(lin, 11, led.str("ledger-s"), 2);
        if (pcOrBranch()) show(lin, 20, led.str("ledger-pc"), 2);
        show(lin, 25, led.str("ledger-name"), 2);
        int t = led.intv("ledger-type");
        t = t == 9 ? 5 : t + 1;
        led.setNum("ledger-type", t);
        t = led.intv("ledger-type");
        // 種別名はデータ表の固定文言（対応表で日本語化）
        display(lin, 53, t < 1 || t > 5 ? "ERROR? " : LEDGER_DESC[t - 1]);
        if (led.intv("ledger-level") != 0) {
            show(lin, 64, led.str("ledger-level"), 2);
            display(lin, 68, PLACE[computePlacement() - 1]);
        }
    }
    private void gl030f() {
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
            clearScreen();
            display(9, 1, "GL106 Ledger File Does Not Exist");
            return;
        }
        dHead1();
        truth = 0;
        mainTarget:
        while (true) {
            if (wsMenu == 6) { display(1, 45, "Print Out"); printOut(); break; }
            lin = 3;
            screenClear();
            led.setNum("ledger-nos", 0);
            display(4, 1, "Enter the start Account - [      ]");
            if (pcOrBranch()) display(4, 34, "/  ]");
            eraseEol(L23, 1);
            display(L23, 1, "Press <Esc> key to exit");
            show(4, 28, led.str("ledger-nos"), 2);
            led.setNum("ledger-nos", acceptNum(4, 28, 6, led.longv("ledger-nos")));
            if (esc()) { seek = "Q"; truth = 0; break; }
            led.setNum("ledger-pc", 0);
            if (pcOrBranch()) {
                show(4, 35, led.str("ledger-pc"), 2);
                led.setNum("ledger-pc", acceptNum(4, 35, 2, 0));
            }
            saveLedger = led.longv("ledger-nos");
            lin = 4; truth = 1; gateSw = 1;
            displayChart();
            if (!ledger.start(led, ">=").equals("00")) weError = 255;
            if (weError == 0 && !ledger.readNext(led).equals("00")) weError = 255;
            if (weError == 255) { display(8, 41, "No match found !"); continue; }
            truth = 0;
            lin += 2;
            while (true) {
                display(L23, 1, "<N> Next; <I> Next ignore same code; <C> Cont; <Q> Quit :- [I]");
                seek = "I";
                displayChart();
                seek = upper(acceptUpdate(L23, 61, 1, seek));
                if (seek.equals("Q")) { truth = 0; break mainTarget; }
                while (true) {
                    gateSw = 2;
                    if (!ledger.readNext(led).equals("00")) weError = 255;
                    if (weError == 255 || led.intv("ledger-n") == 9999) continue mainTarget;
                    if (seek.equals("I") && led.longv("ledger-nos") == saveLedger) continue;
                    saveLedger = led.longv("ledger-nos");
                    lin++;
                    if (lin == L22) {
                        askClear();
                        if (esc()) { gateSw = 1; continue mainTarget; }
                        dHead1(); lin = 4; secondHead(); lin = 6;
                    }
                    if (!seek.equals("C") && !seek.equals("I")) break;
                    displayChart();
                }
            }
        }
        ledger.close();
    }
    private void printOut() {
        print.open();
        String l1 = line1() + toDay();
        String l6 = "---Level---   Header       Detail   " + sp(4) + pcFiller() + "--Placement--      ----------Name----------";
        pageNos = 0;
        pageHeading(l1, l6);
        while (true) {
            if (!ledger.readNext(led).equals("00")) weError = 255;
            if (weError == 255 || led.intv("ledger-n") == 9999) break;
            boolean header = led.intv("ledger-level") != 0;
            String line = levelFiller() + sp(3) + amt(header) + sp(7) + amt(!header) + sp(6) + pcEdit() + sp(10)
                    + (header ? PLACE[computePlacement() - 1] : sp(13)) + sp(6) + led.str("ledger-name");
            print.after(line, 1);
            lineCnt++;
            if (lineCnt > sys.intv("page-lines")) pageHeading(l1, l6);
        }
        endReport();
    }

    // ---- gl030g: 部門一覧印刷 ----
    private void gl030g() {
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
            clearScreen();
            display(9, 1, "GL106 Ledger File Does Not Exist");
            return;
        }
        head(27, "Profit Centres Report");
        truth = 0;
        readPcb(); findEst();
        print.open();
        // レガシーは line-11 を組み立てるが見出しには line-1 を出力する（忠実に再現）
        String l1 = pad(pad(PROG_NAME, 14) + sp(28) + "Chart of Accounts" + sp(31), 100);
        String l14 = "Number        Name";
        pageNos = 0;
        pageHeading13(l1, l14);
        for (y = 1; ; ) {
            if (code(y) != ' ') {
                led.setNum("ledger-nos", 999999); led.setNum("ledger-pc", y);
                if (!ledger.read(led).equals("00")) weError = 255;
                if (weError == 255) led.set("ledger-name", "");
                print.after(Num.edit(led.intv("ledger-pc"), "z9") + sp(10) + pad(led.str("ledger-name"), 32), 1);
                lineCnt++;
                if (lineCnt > sys.intv("page-lines")) pageHeading13(l1, l14);
                lin++;
            }
            y++;
            if (y < 99) continue;
            break;
        }
        endReport();
        ledger.close();
    }
    private void pageHeading13(String l1, String l14) { pageHeading(l1, l14); }
}
