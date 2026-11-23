package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;

/** GL プログラム共通の基底（数値 ACCEPT、日付形式、印刷ファイル）。 */
abstract class GlProgram extends Program {
    static final int ESC = 2005;
    protected Rec sys;
    protected int weError;

    protected void init() {
        term().exceptionsEnabled = true; term().escEnabled = true;
        sys = GlCommon.sys(ctx);
    }
    protected String toDay() { return GlCommon.toDay(ctx); }
    /** zz070-Convert-Date: to-day を設定形式へ。 */
    protected String wsDate() {
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        return GlCommon.ukToForm(sys, toDay());
    }
    protected boolean profitCentres() { return sys.str("p-c").equals("P"); }
    protected boolean branches() { return sys.str("p-c").equals("B"); }
    protected boolean pcOrBranch() { return profitCentres() || branches(); }

    /** 英数字 → 数字項目への MOVE 相当（数字以外は 0 とみなす、右詰め size 桁）。 */
    static long digits(String s, int size) {
        String t = s.stripTrailing();
        StringBuilder b = new StringBuilder();
        for (char c : t.toCharArray()) b.append(c >= '0' && c <= '9' ? c : (c == ' ' || c == '.' || c == ',' || c == '-' || c == '+') ? "" : "0");
        String d = b.toString();
        if (d.length() > size) d = d.substring(d.length() - size);
        return d.isEmpty() ? 0 : Long.parseLong(d);
    }
    /** ACCEPT 数字項目（pic 9(size)）UPDATE なし。 */
    protected long acceptNum(int line, int col, int size) { return acceptNum(line, col, size, 0); }
    /** ACCEPT 数字項目（pic 9(size)）WITH UPDATE。 */
    protected long acceptNum(int line, int col, int size, long cur) {
        return digits(acceptUpdate(line, col, size, Num.z9(cur, size)), size);
    }
    protected void showNum(int line, int col, long v, int size) { show(line, col, Num.z9(v, size), 2); }
    protected boolean esc() { return crtStatus() == ESC; }
    protected static String latin(byte[] b) { return new String(b, StandardCharsets.ISO_8859_1); }
    protected static byte[] latin(String s) { return s.getBytes(StandardCharsets.ISO_8859_1); }
    protected static String pad(String s, int n) { return GlCommon.pad(s, n); }
    protected static String sp(int n) { return " ".repeat(n); }

    /** print-spool-command.cob の Print-Report（lpr 呼出し）。 */
    protected String printReport() {
        return "lpr -r -o 'orientation-requested=4 page-left=21 page-top=48 page-right=10 sides=two-sided-long-edge cpi=12 lpi=8' -P "
                + pad(sys.str("print-spool-name"), 48) + "prt-1";
    }

    /** 印刷ファイル（WRITE ... AFTER n / AFTER PAGE）。レガシーは改行 n 個の後に 132 桁の行を書く。 */
    protected final class Printer {
        private final CobFile f; private final int width;
        private String cur = ""; private boolean any;
        Printer(String file, int width) { f = CobFile.lineSequential(ctx.store, ctx.path(file)); this.width = width; }
        void open() { f.open(CobFile.Mode.OUTPUT); cur = ""; any = false; }
        void after(String text, int n) {
            for (int i = 0; i < n; i++) { f.writeLine(cur); cur = ""; }
            cur = pad(text, width); any = true;
        }
        void afterPage(String text) { cur = (any ? cur : "") + "\f" + pad(text, width); any = true; }
        /** WRITE ... BEFORE n。 */
        void before(String text, int n) {
            cur = cur + pad(text, width);
            for (int i = 0; i < n; i++) { f.writeLine(cur); cur = ""; }
            any = true;
        }
        void close() { if (!cur.isEmpty()) f.writeLine(cur); cur = ""; f.close(); }
    }
}
