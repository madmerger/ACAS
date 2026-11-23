package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** irs040.cbl: 試算表（Trial Balance）の表示・印刷（要約 / 明細）。 */
public class Irs040 extends IrsBase {
    static final String PROG_NAME = "irs040 (3.01.12)";
    private static final int LINES = 24, ACCEPT_LINES = 23, L22 = 22, SHOW_LINES = 21;
    private static final String LINE_4 = " Account     ----------Name----------" + pad("   Type", 19) + "   --Debit--   --Credit-";
    private static final String LINE_6 = " ".repeat(57) + "=========== ===========";

    private Rec sys, nl;
    private FileAccess fa;
    private char tipe = 'D', empty = ' ';
    private int counter, wsSubNot, lineCnt = 99, mainAc;
    private BigDecimal totalDr = BigDecimal.ZERO, totalCr = BigDecimal.ZERO, mainDr = BigDecimal.ZERO, mainCr = BigDecimal.ZERO;
    private String mainName = " ".repeat(24), pReport = "", pPage = "   ";

    private void irsub1(int fn) { fa.fileFunction = fn; call("irsub1", nl, fa); }
    private boolean summary() { return tipe == 'S'; }
    private boolean doPrint() { return empty == 'Y'; }
    private static String money(BigDecimal v) { return v.signum() == 0 ? " ".repeat(12) : Num.edit(v, "z(8)9.99"); }
    private static String acct(long v) { return v == 0 ? " ".repeat(6) : " " + Num.edit(BigDecimal.valueOf(v), "zzzz9"); }
    private char reply(int line, int col) {
        String r = up(accept(line, col, 1, AUTO));
        return r.isEmpty() ? ' ' : r.charAt(0);
    }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        nl = newNlRecord();
        fa = fa();
        fa.fileNames = sys.str("system-files");
        term().exceptionsEnabled = true; term().escEnabled = true;
        while (true) {
            totalDr = totalCr = BigDecimal.ZERO; wsSubNot = 0;
            clearScreen();
            show(1, 1, PROG_NAME, 2);
            display(1, 31, "Trial Balance", 7);
            show(1, 73, sys.str("run-date"), 2);
            display(5, 1, "Summary or Detail <S> or <D>......[ ]");
            display(7, 1, "Zero balances to Print (Y/N)......[ ]");
            display(7, 41, "Press <Return> to exit");
            display(9, 1, "Display or Print  <D> or <P>......[ ]");
            tipe = reply(5, 36);
            if (tipe == ' ') return;
            if (!summary() && tipe != 'D') continue;
            pReport = summary() ? "Summary " : "Detail  ";
            do {
                empty = reply(7, 36);
                if (empty == ' ') return;
            } while (empty != 'Y' && empty != 'N');
            char out;
            do { out = reply(9, 36); } while (out != 'D' && out != 'P');
            mainCr = mainDr = BigDecimal.ZERO; mainAc = 0; wsSubNot = 0;
            mainName = " ".repeat(24);
            if (out == 'D') displayTb(); else printTb();
        }
    }

    /**
     * main-loop / main-loop-p の共通部。次に出力する line-5 を返す。合計へ進む場合は null。
     * 明細の残高ゼロ行の抑止は画面表示のみ（レガシーの印刷側には無い）。
     */
    private String nextLine(boolean screen) {
        while (true) {
            if (fa.weError == 3) return null;
            irsub1(3);
            if (fa.weError == 3) { nl.setNum("nl-owning", 0); nl.setNum("nl-cr", 0); nl.setNum("nl-dr", 0); }
            if (fa.weError == 3 && !summary()) return null;
            long owning = nl.longv("nl-owning"), sub = nl.longv("nl-sub-nominal");
            BigDecimal dr = nl.num("nl-dr"), cr = nl.num("nl-cr");
            String pDebit, pCredit, legend, name; long account;
            if (summary()) {
                if (sub == 0) {
                    boolean emit = mainAc != 0 && !(mainDr.compareTo(mainCr) == 0 && !doPrint());
                    BigDecimal d = mainDr, c = mainCr; int ac = mainAc; String nm = mainName;
                    mainAc = (int) owning; mainDr = dr; mainCr = cr; mainName = nl.str("nl-name");
                    if (!emit) continue;
                    if (d.compareTo(c) > 0) { BigDecimal w = d.subtract(c); pDebit = money(w); pCredit = money(BigDecimal.ZERO); totalDr = totalDr.add(w); }
                    else { BigDecimal w = c.subtract(d); pCredit = money(w); pDebit = money(BigDecimal.ZERO); totalCr = totalCr.add(w); }
                    legend = "Main"; account = ac; name = nm;
                } else {
                    mainDr = mainDr.add(dr); mainCr = mainCr.add(cr);
                    if (owning != mainAc) wsSubNot = (wsSubNot + 1) % 10000;
                    continue;
                }
            } else {
                if (screen && dr.compareTo(cr) == 0 && !doPrint()) continue;
                if (dr.compareTo(cr) > 0) { BigDecimal w = dr.subtract(cr); pDebit = money(w); pCredit = money(BigDecimal.ZERO); totalDr = totalDr.add(w); }
                else { BigDecimal w = cr.subtract(dr); pCredit = money(w); pDebit = money(BigDecimal.ZERO); totalCr = totalCr.add(w); }
                if (sub == 0) { legend = "Main"; account = owning; } else { legend = "Sub"; account = sub; }
                name = nl.str("nl-name");
            }
            nl.setNum("nl-dr", 0); nl.setNum("nl-cr", 0);
            return acct(account) + " ".repeat(6) + pad(name, 24) + " ".repeat(4) + pad(legend, 16) + pDebit + pCredit;
        }
    }

    private void dispHead1() {
        clearScreen();
        show(1, 1, pad(sys.str("suser"), 24), 2);
        display(1, 30, pReport, 7);
        display(1, 38, "Trial Balance", 7);
        show(1, 57, sys.str("run-date"), 2);
        display(1, 72, "Page ");
        show(1, 77, pPage, 2);
        show(3, 1, pad(sys.str("client"), 24));
        show(3, 42, sys.str("start-date"));
        show(3, 72, sys.str("end-date"));
        display(3, 29, "Start Date -");
        display(3, 61, "End Date -");
        display(5, 1, LINE_4);
        display(LINES, 1, "Enter <N> for next screen <X> to exit....[ ]");
    }

    private void showLine5(int lin, String l) {
        show(lin, 1, l.substring(0, 40));
        display(lin, 41, l.substring(40, 56), 3);
        show(lin, 57, l.substring(56));
    }

    private void displayTb() {
        fa.fileFunction = 1; fa.accessType = 1;
        call("irsub1", nl, fa);
        totalCr = totalDr = BigDecimal.ZERO; counter = 0;
        pPage = "  1";
        dispHead1();
        int lin = 6;
        counter = (counter + 1) % 100;
        while (true) {
            String l = nextLine(true);
            if (l == null) break;
            showLine5(lin, l);
            if (fa.weError == 3) break;
            lin++;
            if (lin < SHOW_LINES) continue;
            lin = 6;
            if (reply(LINES, 43) == 'X') { irsub1(2); return; }
            counter = (counter + 1) % 100;
            pPage = Num.edit(BigDecimal.valueOf(counter), "zz9");
            dispHead1();
        }
        display(SHOW_LINES, 1, LINE_6);
        show(L22, 1, " ".repeat(41));
        display(L22, 42, "T o t a l      ", 3);
        show(L22, 57, Num.edit(totalDr, "z(8)9.99") + Num.edit(totalCr, "z(8)9.99"));
        display(ACCEPT_LINES, 1, LINE_6);
        eraseEol(LINES, 1);
        display(LINES, 1, "Press Return for menu");
        if (wsSubNot != 0) show(LINES, 26, Num.z9(wsSubNot, 4));
        accept(LINES, 23, 1);
        irsub1(2);
    }

    private CobFile prt;

    private void printTb() {
        clearScreen();
        totalCr = totalDr = BigDecimal.ZERO;
        prt = openPrint();
        counter = 0;
        headings();
        fa.fileFunction = 1; fa.accessType = 1;
        call("irsub1", nl, fa);
        while (true) {
            String l = nextLine(false);
            if (l == null) break;
            writeAfter(prt, l, 1);
            lineCnt = (lineCnt + 1) % 100;
            if (lineCnt > 75) headings();
            if (fa.weError == 3) break;
        }
        writeAfter(prt, LINE_6, 3);
        String line7 = (wsSubNot != 0 ? Num.edit(BigDecimal.valueOf(wsSubNot), "zzzz") : "    ") + " ".repeat(37) + "T o t a l      "
                + Num.edit(totalDr, "z(8)9.99") + Num.edit(totalCr, "z(8)9.99");
        writeAfter(prt, line7, 1);
        writeAfter(prt, LINE_6, 1);
        printReport(sys, prt);
        irsub1(2);
    }

    private void headings() {
        counter = (counter + 1) % 100;
        String line1 = pad(sys.str("suser"), 24) + " ".repeat(5) + pReport + "Trial Balance" + " ".repeat(6) + pad(sys.str("run-date"), 8)
                + " ".repeat(7) + "Page " + Num.edit(BigDecimal.valueOf(counter), "zz9");
        if (counter == 1) writeAfter(prt, line1, 1); else writeAfterPage(prt, line1);
        writeAfter(prt, pad(sys.str("client"), 24) + "    Start Date - " + pad(sys.str("start-date"), 8) + "           End Date - " + pad(sys.str("end-date"), 8), 2);
        writeAfter(prt, LINE_4, 2);
        writeAfter(prt, "", 1);
        lineCnt = 6;
    }
}
