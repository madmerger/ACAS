package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Terminal;
import jp.co.acas.sys.Maps04;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.SystemFile;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/** PL 買掛プログラム共通の補助（システムレコード・日付変換・maps99 エラー表示など）。 */
abstract class PlBase extends Program {
    protected Rec sys;

    protected void init() { sys = SystemFile.shared(ctx); }

    /** 共有 system-record-4（system.dat の rrn 4）。 */
    protected Rec sys4() {
        return (Rec) ctx.shared.computeIfAbsent("system-record-4", k -> Layout.of("copybooks/wssys4.cob", "System-Record-4").newRec());
    }
    protected void readSys4() {
        CobFile f = SystemFile.file(ctx);
        if (!f.open(CobFile.Mode.IO).equals("00")) return;
        f.rrn = 4;
        f.read(sys4());
        f.close();
    }
    protected void rewriteSys4() {
        CobFile f = SystemFile.file(ctx);
        if (!f.open(CobFile.Mode.IO).equals("00")) return;
        f.rrn = 4;
        f.rewrite(sys4());
        f.close();
    }

    /** INVALID KEY 条件（FILE STATUS 2x）。39/47 などは該当しない。 */
    protected static boolean invalid(String status) { return status.startsWith("2"); }

    protected int termCode() { return (int) ctx.shared.getOrDefault("ws-term-code", 0); }
    protected void termCode(int v) { ctx.shared.put("ws-term-code", v); }
    protected String toDay() { return (String) ctx.shared.getOrDefault("to-day", "01/01/2000"); }
    protected void toDay(String v) { ctx.shared.put("to-day", v); }

    protected String hhmmss() {
        LocalDateTime n = ctx.now();
        return String.format("%02d:%02d:%02d", n.getHour(), n.getMinute(), n.getSecond());
    }

    /** UK 形式 dd/mm/ccyy → 設定された日付形式（zz060/zz070-Convert-Date）。 */
    protected String fromUk(String uk) {
        int form = sys.intv("date-form");
        if (form == 2) return uk.substring(3, 5) + "/" + uk.substring(0, 2) + uk.substring(5);
        if (form == 3) return uk.substring(6, 10) + "/" + uk.substring(3, 5) + "/" + uk.substring(0, 2);
        return uk;
    }

    /** 設定された日付形式 → UK 形式 dd/mm/ccyy（zz050-Validate-Date の前段）。 */
    protected String toUk(String d) {
        d = pad(d, 10);
        int form = sys.intv("date-form");
        if (form == 2) return d.substring(3, 5) + "/" + d.substring(0, 2) + d.substring(5);
        if (form == 3) return d.substring(8, 10) + "/" + d.substring(5, 7) + "/" + d.substring(0, 4);
        return d;
    }

    /** zz050-Validate-Date: 入力日付（設定形式）→ 通算日。不正は 0。 */
    protected long validateDate(String d) {
        d = pad(d, 10).replace('.', '/').replace(',', '/').replace('-', '/');
        return Maps04.toBin(toUk(d));
    }

    /** zz060-Convert-Date: 通算日 → 設定形式の日付文字列。 */
    protected String binToDate(long bin) { return fromUk(Maps04.toDate(bin)); }

    /** SCREEN SECTION の英数字入力項目は空白をプロンプト文字 '_' で表示する。 */
    protected static Terminal.Field afield(int line, int col, int size, String value) {
        return new Terminal.Field(line, col, size, pad(value, size).replace(' ', '_'));
    }
    protected static String aval(Terminal.Field f) { return f.value.replace('_', ' '); }

    protected CobFile purchaseFile(Rec r) { return CobFile.indexed(ctx.store, ctx.path("purchled.dat"), r, "purch-key"); }
    protected CobFile deliveryFile(Rec r) { return CobFile.indexed(ctx.store, ctx.path("delivery.dat"), r, "deliv-key"); }
    protected static Rec purchRec() { return fdRec(Layout.of("copybooks/fdpl.cob", "Purch-Record")); }
    protected static Rec delivRec() { return fdRec(Layout.of("copybooks/fddel.cob", "delivery-record")); }

    protected static Rec oiRec() { return Layout.of("purchase/wsoi.cob", "oi-header").newRec(); }
    /** open-item-file-5（openitm5.dat、キー = 仕入先 7 桁 + 請求書番号 binary-long）。oi-header をそのまま読み書きする。 */
    protected CobFile oi5File() { return CobFile.indexed(ctx.store, ctx.path("openitm5.dat"), 0, 11); }
    /** invoice-file（pinvoice.dat、キー = 請求書番号 9(8) + 行番号 binary-char）。 */
    protected CobFile invoiceFile() { return CobFile.indexed(ctx.store, ctx.path("pinvoice.dat"), 0, 9); }
    protected static Rec invHeaderRec() { return fdRec(Layout.of("purchase/fdpinv2.cob", "invoice-header")); }
    protected static Rec invLineRec() { return fdRec(Layout.of("purchase/fdpinv2.cob", "invoice-line")); }

    /** analysis-file（analysis.dat、キー = pa-code 3 桁）。レコード領域は初期状態 LOW-VALUE。 */
    protected CobFile analysisFile(Rec r) { return CobFile.indexed(ctx.store, ctx.path("analysis.dat"), r, "pa-code"); }
    protected static Rec analRec() {
        Rec r = Layout.of("copybooks/fdanal.cob", "analysis-record").newRec();
        java.util.Arrays.fill(r.bytes(), (byte) 0);
        return r;
    }

    /** グループ項目（9(n) + "." + v99）の金額 ACCEPT ... UPDATE。 */
    protected BigDecimal acceptMoney(int line, int col, int pounds, BigDecimal cur) {
        long c = cur.movePointRight(2).longValue();
        String shown = Num.z9(c / 100, pounds) + "." + Num.z9(c % 100, 2);
        show(line, col, shown);
        String in = pad(acceptUpdate(line, col, pounds + 3, shown), pounds + 3);
        long pd = numOf(in.substring(0, pounds)), pc = numOf(in.substring(pounds + 1));
        return BigDecimal.valueOf(pd * 100 + pc, 2);
    }

    /** 英数字 → 数字項目への MOVE 相当（数字以外は無視）。 */
    protected static long numOf(String s) {
        String d = s.replaceAll("[^0-9]", "");
        return d.isEmpty() ? 0 : Long.parseLong(d);
    }

    /** PIC 9(n) の ACCEPT ... UPDATE（現在値を表示）。 */
    protected long acceptNum(int line, int col, int digits, long cur) {
        return numOf(acceptUpdate(line, col, digits, Num.z9(cur, digits)));
    }

    /** UNSTRING ... DELIMITED BY delim を繰り返したときの各片（最後の要素は残り全体）。 */
    protected static String[] pieces(String src, String delim, int n) {
        String[] out = new String[n + 1];
        int p = 0;
        for (int i = 0; i < n; i++) {
            if (p > src.length()) { out[i] = ""; continue; }
            int q = src.indexOf(delim, p);
            if (q < 0) { out[i] = src.substring(p); p = src.length() + 1; }
            else { out[i] = src.substring(p, q); p = q + delim.length(); }
        }
        out[n] = p > src.length() ? "" : src.substring(p);
        return out;
    }

    /** call "SYSTEM" using Print-Report（縦置き版）。 */
    protected void spoolPrt1Portrait() {
        ctx.spool("prt-1", "lpr -r -o 'orientation-requested=3 page-left=36 page-top=24 page-right=24 "
                + "sides=two-sided-long-edge cpi=12 lpi=8' -P " + sys.str("print-spool-name").trim() + " prt-1");
    }

    protected static BigDecimal bd(String s) { return new BigDecimal(s); }

    /** FD レコード領域: FILLER は初期状態（LOW-VALUE）のまま残る。 */
    protected static Rec fdRec(Layout l) {
        Rec r = l.newRec();
        fillers(l.root, 0, r.bytes(), null);
        return r;
    }

    /** INITIALIZE: FILLER は変更しない（COBOL の規則）。 */
    protected static void initialize(Rec r) {
        byte[] save = r.copyBytes();
        r.initialize();
        fillers(r.layout.root, 0, r.bytes(), save);
    }

    private static void fillers(Layout.Field f, int delta, byte[] data, byte[] from) {
        for (int i = 0; i < f.occurs; i++) {
            int d = delta + i * (f.occurs > 1 ? f.size : 0);
            if (f.kind == Layout.Kind.GROUP && !"filler".equals(f.name)) {
                for (Layout.Field c : f.children) if (c.redefines == null) fillers(c, d, data, from);
            } else if ("filler".equals(f.name) && f.redefines == null) {
                for (int j = 0; j < f.size; j++) data[f.offset + d + j] = from == null ? 0 : from[f.offset + d + j];
            }
        }
    }

    /** 印刷ファイル（WRITE ... AFTER/BEFORE ADVANCING の再現）。close で行順ファイルへ書き出す。 */
    protected final class Printer {
        private final String name;
        private final StringBuilder sb = new StringBuilder();
        private final int width;
        Printer(String name) { this(name, 132); }
        /** width は印刷レコード長（固定長レコードのため改ページ時は前行の直後に続く）。 */
        Printer(String name, int width) { this.name = name; this.width = width; }
        void after(String line, int n) { sb.append("\n".repeat(n)).append(pad(line, width)); }
        void before(String line, int n) { sb.append(pad(line, width)).append("\n".repeat(n)); }
        void afterPage(String line) { sb.append("\f").append(pad(line, width)); }
        void close() {
            CobFile f = CobFile.lineSequential(ctx.store, ctx.path(name));
            f.open(CobFile.Mode.OUTPUT);
            String t = sb.toString();
            String[] lines = t.split("\n", -1);
            int n = lines.length;
            if (n > 0 && lines[n - 1].isEmpty()) n--;
            for (int i = 0; i < n; i++) f.writeLine(lines[i]);
            f.close();
        }
    }

    /** call "SYSTEM" using Print-Report（prt-1 の印刷指示）。 */
    protected void spoolPrt1() {
        ctx.spool("prt-1", "lpr -r -o 'orientation-requested=4 page-left=21 page-top=48 page-right=10 "
                + "sides=two-sided-long-edge cpi=12 lpi=8' -P " + sys.str("print-spool-name").trim() + " prt-1");
    }

    protected static String rtrim(String s) { return s.replaceAll("\\s+$", ""); }

    /** 帳票行の組立て（桁位置は 1 始まり）。 */
    protected static String at(String line, int col, String text) {
        StringBuilder b = new StringBuilder(line);
        while (b.length() < col - 1 + text.length()) b.append(' ');
        b.replace(col - 1, col - 1 + text.length(), text);
        return b.toString();
    }

    protected static String pad(String s, int n) {
        if (s == null) s = "";
        if (s.length() >= n) return s.substring(0, n);
        return s + " ".repeat(n - s.length());
    }

    /** maps99: error.txt を持たない構成ではコードのみ表示して応答を待つ。 */
    protected void maps99(int code) {
        if (call("maps99", code)) return;
        termCode(0);
        display(23, 1, "T-", 4);
        show(23, 6, " ", 4);
        show(23, 3, Num.z9(code, 3), 4);
        display(23, 7, "Error not in error.txt. Hit return to close", 4);
        show(23, 50, "       ", 4);
        accept(24, 79, 1);
    }
}
