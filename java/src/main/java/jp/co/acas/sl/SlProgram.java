package jp.co.acas.sl;

import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Terminal;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;
import java.util.function.Supplier;

/**
 * SL 売掛プログラム共通の基底クラス（レガシーの LINKAGE 領域と共通段落）。
 * ws-calling-data は ctx.shared の "ws-term-code" / "ws-caller" / "ws-called" / "ws-del-link" /
 * "ws-process-func" / "ws-sub-function"、to-day は "to-day"、system-record-4 は "system-record-4" で共有する。
 */
public abstract class SlProgram extends Program {
    protected Rec sys() { return SystemFile.shared(ctx); }
    /** system-record-4（システムファイル rrn 4。SL/PL の月次集計）。 */
    protected Rec sys4() {
        return (Rec) ctx.shared.computeIfAbsent("system-record-4", k -> Layout.of("copybooks/wssys4.cob", "System-Record-4").newRec());
    }
    protected int termCode() { return (int) ctx.shared.getOrDefault("ws-term-code", 0); }
    protected void termCode(int v) { ctx.shared.put("ws-term-code", v); }
    protected String toDay() { return (String) ctx.shared.getOrDefault("to-day", "00/00/0000"); }
    protected void toDay(String v) { ctx.shared.put("to-day", v); }
    protected String shared(String key) { return (String) ctx.shared.getOrDefault(key, ""); }
    protected int sharedInt(String key) { return (int) ctx.shared.getOrDefault(key, 0); }

    protected int dateForm() { int f = sys().intv("date-form"); return f < 1 || f > 3 ? 1 : f; }
    /** zz070-Convert-Date: UK 形式（dd/mm/ccyy）→ 設定された日付形式。 */
    protected String fromUk(String uk) {
        if (uk.isBlank()) return " ".repeat(10);
        return switch (dateForm()) {
            case 2 -> uk.substring(3, 5) + uk.substring(2, 3) + uk.substring(0, 2) + uk.substring(5);
            case 3 -> uk.substring(6, 10) + "/" + uk.substring(3, 5) + "/" + uk.substring(0, 2);
            default -> uk;
        };
    }
    /** zz050-Validate-Date の前半: 設定された日付形式の入力 → UK 形式。 */
    protected String toUk(String d) {
        d = pad(d, 10).replace('.', '/').replace(',', '/').replace('-', '/');
        return switch (dateForm()) {
            case 2 -> d.substring(3, 5) + d.substring(2, 3) + d.substring(0, 2) + d.substring(5);
            case 3 -> d.substring(8, 10) + "/" + d.substring(5, 7) + "/" + d.substring(0, 4);
            default -> d;
        };
    }
    /** zz050-Validate-Date: 入力日付（設定形式）→ 通算日。不正は 0。 */
    protected long validateDate(String d) { return Maps04.toBin(toUk(d)); }
    /** 通算日 → 設定形式の日付文字列（zz060 / zz070）。 */
    protected String binToDate(long bin) { return fromUk(Maps04.toDate(bin)); }
    /** 日付入力の案内に使う書式名。 */
    protected String dateFormName() { return switch (dateForm()) { case 2 -> "mm/dd/yyyy"; case 3 -> "yyyy/mm/dd"; default -> "dd/mm/yyyy"; }; }

    protected static String pad(String s, int n) { return s.length() >= n ? s.substring(0, n) : s + " ".repeat(n - s.length()); }
    protected static String z(long v, int digits) { return Num.z9(v, digits); }
    /** wsd-time (hh:mm:ss)。 */
    protected String timeNow() {
        LocalDateTime now = ctx.now();
        return String.format("%02d:%02d:%02d", now.getHour(), now.getMinute(), now.getSecond());
    }
    /** maps-ser を 24 行 74 桁へ表示。 */
    protected void showMapsSer(int fg) {
        show(24, 74, sys().str("maps-ser-xx"), fg);
        show(24, 76, z(sys().intv("maps-ser-nn"), 4), fg);
    }

    // ---- ファイル（wsnames.cob の論理名） ----
    protected static final String F_LEDGER = "ledger.dat", F_POSTING = "posting.dat", F_BATCH = "batch.dat", F_IRS_POST = "postings2irs.dat",
        F_SALES = "salesled.dat", F_VALUE = "value.dat", F_DELIVERY = "delivery.dat", F_ANALYSIS = "analysis.dat", F_INVOICE = "invoice.dat",
        F_DELINV = "delinvno.dat", F_OI2 = "openitm2.dat", F_OI3 = "openitm3.dat", F_OISORT = "oisort.wrk", F_WORK = "work.tmp", F_PAY = "pay.dat",
        F_STOCK = "stockctl.dat", F_STAUDIT = "staudit.dat";
    protected static Rec salesRec() { return fdRec("copybooks/fdsl.cob", "Sales-Record"); }
    protected static Rec deliveryRec() { return fdRec("copybooks/fddel.cob", "delivery-record"); }

    /** FD のレコード領域。FILLER はレガシーと同じく初期値（x"00"）のまま残る。 */
    protected static Rec fdRec(String copybook, String record) {
        Rec r = Layout.of(copybook, record).newRec();
        fillers(r.layout.root, 0, r.bytes(), null);
        return r;
    }
    /** INITIALIZE: FILLER は変更しない（COBOL の規則）。 */
    protected static void initialize(Rec r) {
        byte[] old = r.copyBytes();
        r.initialize();
        fillers(r.layout.root, 0, r.bytes(), old);
    }
    private static void fillers(Layout.Field f, int delta, byte[] data, byte[] from) {
        if (f.redefines != null) return;
        for (int i = 0; i < f.occurs; i++) {
            int d = delta + i * (f.occurs > 1 ? f.size : 0);
            if (f.kind == Layout.Kind.GROUP) { for (Layout.Field c : f.children) fillers(c, d, data, from); }
            else if ("filler".equals(f.name)) {
                for (int k = f.offset + d; k < f.offset + d + f.size; k++) data[k] = from == null ? 0 : from[k];
            }
        }
    }
    protected static Rec analysisRec() { return fdRec("copybooks/fdanal.cob", "analysis-record"); }
    protected static Rec valueRec() { return fdRec("copybooks/fdval.cob", "value-record"); }
    /** sales/wsnames.cob の file-defs（System-File-Names 1〜13）。SL のプログラムはこの並びでスロットを参照する。 */
    public static final String[] SALES_FILE_DEFS = {"system.dat", F_POSTING, F_BATCH, F_SALES, F_VALUE, F_DELIVERY, F_ANALYSIS, F_INVOICE,
        F_DELINV, F_OI2, F_OI3, F_OISORT, F_WORK};
    /** file-13（value-file）と file-15（analysis-file）の sales/wsnames.cob 上のスロット番号。 */
    protected static final int SLOT_VALUE = 5, SLOT_ANALYSIS = 7;
    /** CALL ... USING file-defs で受け取った呼出し元の file-defs。既定は売掛（sales/wsnames.cob）。 */
    protected String[] fileDefs = SALES_FILE_DEFS;

    /**
     * 呼出し元が CALL の引数で渡した file-defs（String[]）を受け取る。他サブシステム（在庫など）の wsnames は
     * 並びも個数も違うため、同じスロット番号が別のファイル名を指す（レガシーの挙動をそのまま再現する）。
     */
    protected void linkFileDefs(Object... args) {
        for (Object a : args) if (a instanceof String[] d) fileDefs = d;
    }
    /** スロットのファイル名。呼出し元 file-defs の範囲外なら null（レガシーでは OPEN が FILE STATUS 31 で失敗しファイルは作られない）。 */
    protected String slotName(int slot) { return slot >= 1 && slot <= fileDefs.length ? fileDefs[slot - 1] : null; }
    private CobFile slotIndexed(int slot, Rec r, String key) {
        String n = slotName(slot);
        return CobFile.indexed(ctx.store, n == null ? "" : ctx.path(n), r, key);
    }
    protected CobFile analysisFile(Rec r) { return slotIndexed(SLOT_ANALYSIS, r, "pa-code"); }
    protected CobFile valueFile(Rec r) { return slotIndexed(SLOT_VALUE, r, "va-code"); }
    protected static Rec oiHeader() { return Layout.of("sales/wsoi.cob", "oi-header").newRec(); }
    protected static Rec oi3Rec() { return fdRec("sales/fdoi3.cob", "open-item-record-3"); }
    protected static Rec invoiceRec() { return fdRec("sales/fdinv2.cob", "invoice-record"); }
    protected static Rec invoiceHeader() { return Layout.of("sales/fdinv2.cob", "invoice-header").newRec(); }
    protected static Rec invoiceLine() { return Layout.of("sales/fdinv2.cob", "invoice-line").newRec(); }
    protected CobFile oi3File(Rec r) { return CobFile.indexed(ctx.store, ctx.path(F_OI3), r, "oi3-key"); }
    protected CobFile invoiceFile(Rec r) { return CobFile.indexed(ctx.store, ctx.path(F_INVOICE), r, "invoice-key"); }
    /** レコード域の共有（同一 FD の別 01、READ ... INTO / WRITE ... FROM）: src の先頭を dst へ複写する。 */
    protected static void move(Rec src, Rec dst) {
        byte[] a = src.bytes(), b = dst.bytes();
        System.arraycopy(a, 0, b, 0, Math.min(a.length, b.length));
        for (int i = a.length; i < b.length; i++) b[i] = ' ';
    }
    /** UNSTRING src DELIMITED BY delim INTO (size 桁) WITH POINTER ptr。戻り値 {取り出した文字列, 新ポインタ}。 */
    protected static Object[] unstring(String src, String delim, int ptr, int size) {
        if (ptr < 1 || ptr > src.length()) return new Object[] {null, ptr};
        int i = src.indexOf(delim, ptr - 1);
        String part = i < 0 ? src.substring(ptr - 1) : src.substring(ptr - 1, i);
        return new Object[] {pad(part, size), i < 0 ? src.length() + 1 : i + delim.length() + 1};
    }
    protected CobFile salesFile(Rec r) { return CobFile.indexed(ctx.store, ctx.path(F_SALES), r, "sales-key"); }
    protected CobFile deliveryFile(Rec r) { return CobFile.indexed(ctx.store, ctx.path(F_DELIVERY), r, "deliv-key"); }
    protected static boolean invalidKey(CobFile f) { return f.status.charAt(0) == '2'; }

    /** print-spool-command.cob の Print-Report（lpr 呼出し）。 */
    protected void spoolReport(String file, String spoolName, boolean landscape) {
        String opts = landscape
            ? "lpr -r -o 'orientation-requested=4 page-left=21 page-top=48 page-right=10 sides=two-sided-long-edge cpi=12 lpi=8' -P "
            : "lpr -r -o 'orientation-requested=3 page-left=36 page-top=24 page-right=24 sides=two-sided-long-edge cpi=12 lpi=8' -P ";
        ctx.spool(file, opts + spoolName.stripTrailing() + " " + file);
    }

    /** maps99: エラーメッセージ表示（error.txt を検索。無ければ番号のみ表示して入力待ち）。 */
    protected void maps99(int errorPass) {
        int lin = 23;
        termCode(0);
        String serv = "T", mess = "Error not in error.txt. Hit return to close", response = "T";
        boolean found = false;
        CobFile ef = CobFile.lineSequential(ctx.store, "error.txt");
        if (ef.exists() && ef.open(CobFile.Mode.INPUT).charAt(0) == '0') {
            String l;
            while ((l = ef.readLine()) != null) {
                l = pad(l, 57);
                if (!l.substring(0, 3).equals(z(errorPass, 3))) continue;
                found = true;
                serv = l.substring(3, 4); response = l.substring(4, 5); mess = l.substring(7, 57);
                int el = (int) Num.parse(l.substring(5, 7)).longValue();
                if (el != 0) lin = el > 19 ? 24 - (24 - el) : el;
                break;
            }
            ef.close();
        }
        show(lin, 1, serv + "-" + z(errorPass, 3) + " ", 4);
        if (found) show(lin, 7, pad(mess, 50), 4); else display(lin, 7, pad(mess, 50), 4);
        if (!found || response.equals("T") || (serv.equals("S") && response.equals("S"))) { accept(24, 79, 1); return; }
        if (serv.equals("T")) termCode(9);
    }

    /** FileStat-Msgs.cpy: FILE STATUS の説明。 */
    protected static String fileStatMsg(String st) {
        return switch (st) {
            case "00" -> "Success"; case "02" -> "Success Duplicate"; case "04" -> "Success Incomplete"; case "05" -> "Success Optional";
            case "07" -> "Success No Unit"; case "10" -> "End Of File"; case "14" -> "Out Of Key Range"; case "21" -> "Key Invalid";
            case "22" -> "Key Exists"; case "23" -> "Key Not Exists"; case "30" -> "Permanent Error"; case "31" -> "Inconsistent Filename";
            case "34" -> "Boundary Violation"; case "35" -> "File Not Found"; case "37" -> "Permission Denied"; case "38" -> "Closed With Lock";
            case "39" -> "Conflict Attribute"; case "41" -> "Already Open"; case "42" -> "Not Open"; case "43" -> "Read Not Done";
            case "44" -> "Record Overflow"; case "46" -> "Read Error"; case "47" -> "Input Denied"; case "48" -> "Output Denied";
            case "49" -> "I/O Denied"; case "51" -> "Record Locked"; case "52" -> "End-Of-Page"; case "57" -> "I/O Linage";
            case "61" -> "File Sharing Failure"; case "91" -> "File Not Available";
            default -> "";
        };
    }

    /** STRING ... INTO target WITH POINTER ptr（1 始まり）。戻り値は更新後のポインタ。範囲外なら何もしない。 */
    protected static int stringInto(StringBuilder target, int ptr, String src) {
        if (ptr < 1 || ptr > target.length()) return ptr;
        for (int i = 0; i < src.length() && ptr <= target.length(); i++, ptr++) target.setCharAt(ptr - 1, src.charAt(i));
        return ptr;
    }
    /** DELIMITED BY "  "（空白 2 個）で切った送出部分。 */
    protected static String delimited(String s, String delim) { int i = s.indexOf(delim); return i < 0 ? s : s.substring(0, i); }

    /** 入力文字列を数値へ（数字以外は無視、空は 0）。 */
    protected static BigDecimal numOf(String s) {
        String t = s.replaceAll("[^0-9.\\-]", "");
        if (t.isEmpty() || t.equals("-") || t.equals(".")) return BigDecimal.ZERO;
        try { return new BigDecimal(t); } catch (NumberFormatException e) { return BigDecimal.ZERO; }
    }
    protected static int intOf(String s) { return numOf(s).intValue(); }

    /** zz030-accept-money: 金額（整数部 digits 桁 + "." + 2 桁）を表示して UPDATE 入力する。 */
    protected BigDecimal acceptMoney(int line, int col, int digits, BigDecimal cur) {
        BigDecimal a = cur.abs();
        String shown = z(a.longValue(), digits) + "." + z(a.remainder(BigDecimal.ONE).movePointLeft(-2).longValue(), 2);
        String r = acceptUpdate(line, col, digits + 3, shown);
        return new BigDecimal(z(intOf(r.substring(0, digits)), digits) + "." + z(intOf(r.substring(digits + 1)), 2));
    }

    /** 数字項目の ACCEPT（UPDATE なし）。GnuCOBOL と同じく入力域はゼロで初期表示される。 */
    protected int acceptNum(int line, int col, int digits, int flags) {
        return intOf(acceptUpdate(line, col, digits, "0".repeat(digits), flags | NUMERIC));
    }

    // ---- SCREEN SECTION ----
    /** SCREEN SECTION の 1 画面（VALUE / FROM / USING 項目の並び）。 */
    protected final class Scr {
        private record Item(int line, int col, String label, int size, boolean alpha, Supplier<String> get, Consumer<String> set) { }
        private final List<Item> items = new ArrayList<>();
        private boolean blank;
        Scr blankScreen() { blank = true; return this; }
        /** VALUE "文言"。 */
        Scr value(int line, int col, String text) { items.add(new Item(line, col, text, text.length(), false, null, null)); return this; }
        /** FROM 項目（表示のみ）。 */
        Scr from(int line, int col, int size, Supplier<String> get) { items.add(new Item(line, col, null, size, false, get, null)); return this; }
        /** USING 英数字項目。 */
        Scr using(int line, int col, int size, Supplier<String> get, Consumer<String> set) { items.add(new Item(line, col, null, size, true, get, set)); return this; }
        /** USING 数字（編集）項目。get は表示形式の文字列を返す。 */
        Scr usingNum(int line, int col, int size, Supplier<String> get, Consumer<String> set) { items.add(new Item(line, col, null, size, false, get, set)); return this; }
        /** DISPLAY screen-name。 */
        void display() {
            if (blank) clearScreen();
            for (Item i : items) {
                if (i.label != null) SlProgram.this.display(i.line, i.col, i.label, 2);
                else show(i.line, i.col, pad(i.get.get(), i.size), 2);
            }
        }
        /** ACCEPT screen-name。英数字項目の空白は GnuCOBOL と同じくプロンプト文字 "_" で表示する。 */
        int accept() {
            List<Terminal.Field> fs = new ArrayList<>();
            List<Item> us = new ArrayList<>();
            for (Item i : items) {
                if (i.set == null) continue;
                String v = pad(i.get.get(), i.size);
                if (i.alpha) v = v.replace(' ', '_');
                fs.add(field(i.line, i.col, i.size, v)); us.add(i);
            }
            int st = acceptScreen(fs);
            for (int k = 0; k < us.size(); k++) {
                String v = fs.get(k).value;
                if (us.get(k).alpha) v = v.replace('_', ' ');
                us.get(k).set.accept(v);
            }
            return st;
        }
    }
}
