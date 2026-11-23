package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;

/** gl120.cbl: 損益計算書・貸借対照表の印刷（レベル 1 勘定を final.dat に集計して印刷）。 */
public class Gl120 extends GlProgram {
    static final String PROG_NAME = "gl120 (3.00.04)";
    private static final BigDecimal Z = BigDecimal.ZERO, MOD = new BigDecimal("100000000");
    private static final String FINAL_LAYOUT = """
             01  final-record.
                 03  final-key.
                     05  l-place     pic x.
                     05  l-nos       pic 9(6).
                     05  l-pc        pic 99.
                 03  l-name          pic x(24).
                 03  l-balance       pic s9(8)v99  comp-3.
                 03  l-last          pic s9(8)v99  comp-3.
            """;
    private static final String ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ", ALPHA_NOS = "11112222334444555666778888";
    private static final String[] PLACE_NAME = {"Sales Income", "Direct Costs", "Sundry Income", "Indirect Costs",
            "Fixed Assets", "Current Assets", "Current Liabilities", "Shareholders Funds"};
    private static final String LINE5 = sp(50) + pad("<--------This  Year-------->", 40) + "<--------Last  Year-------->";
    private static final String LINE8 = sp(50) + "=".repeat(11) + sp(29) + "=".repeat(11);
    private static final String LINE10 = sp(66) + "=".repeat(11) + sp(29) + "=".repeat(11);

    private Rec led, fin; private CobFile ledger, finalFile; private Printer print;
    private final BigDecimal[] lDr = new BigDecimal[6], lCr = new BigDecimal[6];
    private final int[] store = new int[6];
    private BigDecimal totDr = Z, totCr = Z, totalThis = Z, totalLast = Z, runThis = Z, runLast = Z,
            gpThis = Z, gpLast = Z, npThis = Z, npLast = Z;
    private String storePlace = " ", storeName = sp(30), datePl, l3Date, l11Name = sp(66);
    private int a, xx;

    private static BigDecimal u8(BigDecimal v) { return v.abs().remainder(MOD); }
    private static BigDecimal s8(BigDecimal v) { return v.remainder(MOD); }
    private static String cr(BigDecimal v, boolean blankZero) {
        if (blankZero && v.signum() == 0) return sp(13);
        return Num.edit(v.abs(), "zzzzzzz9.99") + (v.signum() < 0 ? "CR" : "  ");
    }

    @Override
    public void run(Object... args) {
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        fin = Layout.ofSource(FINAL_LAYOUT, "final-record").newRec();
        finalFile = CobFile.indexed(ctx.store, ctx.path("final.dat"), fin, "final-key");
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 31, "P&L and Balance Sheet");
        String wsDate = wsDate();
        l3Date = wsDate; datePl = wsDate;
        show(1, 71, wsDate, 2);
        while (true) {
            display(5, 21, "Enter P&L Date  (space to abort) - [");
            display(5, 67, "]");
            datePl = pad(acceptUpdate(5, 57, 10, datePl), 10);
            if (datePl.isBlank()) return;
            // レガシー実測: 入力値は直後に ws-date（当日）で上書きされる
            datePl = wsDate;
            String test = datePl.replace('.', '/').replace(',', '/').replace('-', '/');
            if (Maps04.toBin(GlCommon.formToUk(sys, test)) == 0) continue;
            l3Date = test; datePl = test;
            display(7, 21, "Ok to continue ? (Y/N)");
            display(7, 46, "[Y]");
            String r = pad(acceptUpdate(7, 47, 1, "Y"), 1);
            if (!r.equals("N") && !r.equals("n")) break;
        }
        if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
            display(9, 1, "GL106 Ledger File Does Not Exist", 4);
            display(10, 1, "GL012 Hit Return to Quit");
            accept(10, 26, 1);
            return;
        }
        finalFile.open(CobFile.Mode.OUTPUT);
        for (int i = 1; i <= 5; i++) { lDr[i] = Z; lCr[i] = Z; store[i] = 0; }
        while (true) {
            String st = ledger.readNext(led);
            if (!st.equals("00") && !st.equals("10")) runaway();
            if (st.equals("10") || led.intv("ledger-n") == 9999) {
                rollUp(5); rollUp(4); rollUp(3); rollUp(2); total1();
                break;
            }
            int nos = led.intv("ledger-nos"), level = led.intv("ledger-level");
            if (nos != store[5] && store[5] != 0) {
                rollUp(5);
                if (level == 0) store[5] = nos;
            }
            if (nos == store[4] || nos == store[3] || nos == store[2] || nos == store[1]) continue;
            if (level >= 1 && level <= 4) {
                if (store[level] != 0) {
                    for (int l = 4; l > Math.max(level - 1, 1); l--) rollUp(l);
                    if (level == 1) total1();
                }
                store[level] = nos;
                if (level == 1) { storePlace = led.str("ledger-place"); storeName = pad(led.str("ledger-name"), 30); }
                continue;
            }
            BigDecimal bal = led.num("ledger-balance");
            if (nos == store[5]) {
                if (bal.signum() < 0) lCr[5] = u8(lCr[5].subtract(bal)); else lDr[5] = u8(lDr[5].add(bal));
                continue;
            }
            if (bal.signum() < 0) lCr[5] = bal.abs(); else lDr[5] = bal;
            store[5] = nos;
        }
        finalFile.close(); ledger.close();
        report();
    }

    /** detail-print / total4〜2-print: 上位レベル（無ければ総合計）へ繰り上げてクリアする。 */
    private void rollUp(int level) {
        boolean done = false;
        for (int up = Math.min(level - 1, 4); up >= 1 && !done; up--) {
            if (store[up] != 0) {
                lDr[up] = u8(lDr[up].add(lDr[level])); lCr[up] = u8(lCr[up].add(lCr[level]));
                done = true;
            }
        }
        if (!done) {
            if (lDr[level].compareTo(lCr[level]) > 0) totDr = u8(u8(totDr.add(lDr[level])).subtract(lCr[level]));
            else totCr = u8(u8(totCr.add(lCr[level])).subtract(lDr[level]));
        }
        if (level != 5) store[level] = 0;
        lDr[level] = Z; lCr[level] = Z;
    }

    private void total1() {
        fin.set("l-place", storePlace);
        fin.setNum("l-nos", store[1]);
        fin.setNum("l-pc", 0);
        fin.set("l-name", storeName);
        fin.setNum("l-balance", lDr[1].subtract(lCr[1]));
        fin.setNum("l-last", 0);
        finalFile.write(fin);
        store[1] = 0; lDr[1] = Z; lCr[1] = Z;
    }

    private String line0() { return pad(sys.str("usera"), 32); }
    private String line7(String name, BigDecimal thisYear, BigDecimal last) {
        return sp(20) + pad(name, 30) + cr(thisYear, false) + sp(27) + cr(last, true);
    }
    private String line11(BigDecimal thisYear, BigDecimal last) {
        return pad(l11Name, 66) + cr(thisYear, false) + sp(27) + cr(last, true);
    }

    private void report() {
        print = new Printer("prt-1", 132);
        print.open();
        finalFile.open(CobFile.Mode.INPUT);
        print.after(line0(), 1);
        print.after(sp(32) + "Profit & Loss Account    For the period to " + datePl, 2);
        print.after(sp(33) + "*".repeat(52), 1);
        print.after(LINE5, 3);
        storePlace = " ";
        while (finalFile.readNext(fin).equals("00")) {
            if (!fin.str("l-place").equals(storePlace)) placeChange();
            BigDecimal bal = fin.num("l-balance"), last = fin.num("l-last");
            if (a == 1 || a == 3 || a == 5) { bal = bal.negate(); last = last.negate(); }
            totalThis = s8(totalThis.add(bal)); totalLast = s8(totalLast.add(last));
            print.after(line7(fin.str("l-name"), bal, last), 1);
        }
        print.after(line7("Net Profit  ", npThis, npLast), 1);
        runThis = s8(runThis.add(npThis)); runLast = s8(runLast.add(npLast));
        print.after(LINE10, 2);
        print.after(line11(runThis, runLast), 1);
        print.after(LINE10, 1);
        print.close(); finalFile.close();
        ctx.spool("prt-1", printReport());
    }

    private void placeChange() {
        String place = fin.str("l-place");
        int j = ALPHABET.indexOf(place.isEmpty() ? ' ' : place.charAt(0));
        storePlace = place;
        // 表に無い場合 SEARCH は j=27 で抜け、place-number(27) は alpha-names の先頭 "S"（数字として 3）を参照する
        a = j < 0 ? 3 : ALPHA_NOS.charAt(j) - '0';
        if (a != xx && xx != 0) numberChange();
        if (a != xx) {
            print.after(pad(PLACE_NAME[a - 1], 24), 1);
            xx = a;
            totalThis = Z; totalLast = Z;
        }
    }

    private void numberChange() {
        print.after(LINE8, 2);
        print.after(sp(50) + cr(totalThis, false) + sp(3) + cr(totalThis, false) + sp(11) + cr(totalLast, true) + sp(3) + cr(totalLast, true), 1);
        print.after(LINE8, 1);
        if (xx == 1 || xx == 3 || xx == 5) { runThis = s8(runThis.add(totalThis)); runLast = s8(runLast.add(totalLast)); }
        else { runThis = s8(runThis.subtract(totalThis)); runLast = s8(runLast.subtract(totalLast)); }
        BigDecimal t = runThis, l = runLast;
        if (a == 3) { l11Name = "Gross Profit"; gpThis = runThis; gpLast = runLast; }
        if (a == 5) {
            l11Name = "Net Profit  ";
            npThis = s8(runThis.add(gpThis)); npLast = s8(runLast.add(gpLast));
            t = npThis; l = npLast;
        }
        if (a == 8) l11Name = "Net Current Value";
        if (a != 3 && a != 5 && a != 8) return;
        print.after(LINE10, 2);
        print.after(line11(t, l), 1);
        if (a == 5) {
            print.after(LINE10, 1);
            print.after(line0(), 1);
            print.after(sp(42) + pad("Balance Sheet as at  ", 22) + l3Date, 2);
            print.after(sp(44) + "*".repeat(30), 1);
            print.after(LINE5, 3);
        } else print.after("", 2);
        runThis = Z; runLast = Z;
    }
}
