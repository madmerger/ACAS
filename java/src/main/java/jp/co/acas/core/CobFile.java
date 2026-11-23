package jp.co.acas.core;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/**
 * COBOL ファイル入出力（索引・相対・順・行順）の意味論を Store 上で再現する。
 * 各操作は FILE STATUS（"00","10","22","23","35" など）を status に設定して返す。
 */
public final class CobFile {
    public enum Org { INDEXED, RELATIVE, SEQUENTIAL, LINE_SEQUENTIAL }
    public enum Mode { INPUT, OUTPUT, IO, EXTEND }

    private final Store store; public final String name; public final Org org;
    private final int keyOff, keyLen;
    private int[][] altKeys = new int[0][];   // {offset, length, duplicates(1/0)}
    public String status = "00";
    private boolean open; private Mode mode;
    private byte[] cursor;          // 直前に読んだ（または START で位置付けた）主キー
    private boolean cursorPending;  // START 直後: 次の READ NEXT は cursor 自身を返す
    private int altInUse = -1; private List<Map.Entry<byte[], byte[]>> altList; private int altPos;
    private long seq;
    /** FD の宣言レコード長（索引ファイルを Rec から定義した場合のみ。0 は不明）。 */
    private int recLen;
    /** 相対ファイルの RELATIVE KEY（rrn）。 */
    public long rrn;

    public CobFile(Store store, String name, Org org, int keyOff, int keyLen) {
        this.store = store; this.name = name; this.org = org; this.keyOff = keyOff; this.keyLen = keyLen;
    }
    public static CobFile indexed(Store s, String name, int keyOff, int keyLen) { return new CobFile(s, name, Org.INDEXED, keyOff, keyLen); }
    public static CobFile indexed(Store s, String name, Rec r, String keyField) {
        CobFile f = indexed(s, name, r.offset(keyField), r.size(keyField));
        f.recLen = r.bytes().length;
        return f;
    }
    public static CobFile relative(Store s, String name) { return new CobFile(s, name, Org.RELATIVE, 0, 0); }
    public static CobFile sequential(Store s, String name) { return new CobFile(s, name, Org.SEQUENTIAL, 0, 0); }
    public static CobFile lineSequential(Store s, String name) { return new CobFile(s, name, Org.LINE_SEQUENTIAL, 0, 0); }
    /** 副キー（ALTERNATE RECORD KEY）を追加。番号は追加順に 0,1,..。 */
    public CobFile alt(int off, int len, boolean duplicates) {
        altKeys = Arrays.copyOf(altKeys, altKeys.length + 1);
        altKeys[altKeys.length - 1] = new int[]{off, len, duplicates ? 1 : 0};
        return this;
    }

    public boolean ok() { return status.charAt(0) == '0'; }
    public boolean isOpen() { return open; }
    public boolean exists() { return store.exists(name); }
    public int count() { return store.count(name); }

    public String open(Mode m) { return open(m, false); }
    /** optional=true は SELECT OPTIONAL 相当（無ければ I-O/EXTEND で作成し "05"）。 */
    public String open(Mode m, boolean optional) {
        if (open) return status = "41";
        // ファイル名が空（呼出し元 file-defs の範囲外スロットなど）: GnuCOBOL は FILE STATUS 31 で失敗し、ファイルを作らない。
        if (name == null || name.isBlank()) return status = "31";
        boolean ex = store.exists(name);
        // GnuCOBOL（BDB）の索引ファイルは、実ファイルのレコードが FD の宣言より長いと OPEN が FILE STATUS 39 になる。
        // 例: 在庫側から呼ばれた sl070 が analysis.dat へ value-record（66 バイト）を書いた後、36 バイト定義で開く場合。
        if (m != Mode.OUTPUT && ex && org == Org.INDEXED && recLen > 0) {
            var first = store.next(name, null, false);
            if (first != null && first.getValue().length > recLen) return status = "39";
        }
        status = "00";
        switch (m) {
            case OUTPUT -> store.create(name);
            case INPUT -> { if (!ex) return status = optional ? "05" : "35"; }
            default -> { if (!ex) { if (!optional) return status = "35"; store.create(name); status = "05"; } }
        }
        open = true; mode = m; cursor = null; cursorPending = false; altInUse = -1;
        seq = m == Mode.EXTEND || m == Mode.IO ? lastSeq() : 0;
        if (m == Mode.INPUT && !ex) open = true;
        return status;
    }
    private long lastSeq() {
        var e = store.prev(name, null, true);
        if (e == null || org == Org.INDEXED) return 0;
        return toLong(e.getKey());
    }
    public String close() { if (!open) return status = "42"; open = false; return status = "00"; }
    public void delete() { store.deleteFile(name); open = false; }

    private byte[] pkey(byte[] rec) { return Arrays.copyOfRange(rec, keyOff, keyOff + keyLen); }
    private static byte[] seqKey(long n) {
        byte[] k = new byte[8];
        for (int i = 7; i >= 0; i--) { k[i] = (byte) n; n >>= 8; }
        return k;
    }
    private static long toLong(byte[] k) { long n = 0; for (byte b : k) n = n << 8 | (b & 0xff); return n; }

    // ---------- 書込み ----------
    public String write(byte[] rec) {
        if (!open) return status = "48";
        switch (org) {
            case INDEXED -> {
                byte[] k = pkey(rec);
                if (store.get(name, k) != null) return status = "22";
                if (dupAlt(rec, k)) return status = "22";
                store.put(name, k, rec);
            }
            case RELATIVE -> {
                if (mode == Mode.OUTPUT || mode == Mode.EXTEND) { if (rrn <= 0 || mode == Mode.EXTEND) rrn = ++seq; else seq = Math.max(seq, rrn); }
                byte[] k = seqKey(rrn);
                if (store.get(name, k) != null) return status = "22";
                store.put(name, k, rec);
            }
            default -> store.put(name, seqKey(++seq), rec);
        }
        return status = "00";
    }
    public String write(Rec r) { return write(r.bytes()); }
    /** 行順ファイルへ 1 行出力（後続空白は除去）。 */
    public String writeLine(String line) { return write(line.stripTrailing().getBytes(StandardCharsets.ISO_8859_1)); }
    private boolean dupAlt(byte[] rec, byte[] self) {
        for (int[] a : altKeys) {
            if (a[2] == 1) continue;
            for (var e : store.all(name))
                if (!Arrays.equals(e.getKey(), self) && Arrays.equals(e.getValue(), a[0], a[0] + a[1], rec, a[0], a[0] + a[1])) return true;
        }
        return false;
    }
    public String rewrite(byte[] rec) {
        if (!open) return status = "49";
        byte[] k = switch (org) { case INDEXED -> pkey(rec); case RELATIVE -> seqKey(rrn); default -> cursor; };
        if (k == null || store.get(name, k) == null) return status = org == Org.SEQUENTIAL ? "43" : "23";
        store.put(name, k, rec);
        return status = "00";
    }
    public String rewrite(Rec r) { return rewrite(r.bytes()); }
    /** DELETE（索引: レコード域のキー、相対: rrn）。 */
    public String delete(byte[] rec) {
        if (!open) return status = "49";
        byte[] k = org == Org.INDEXED ? pkey(rec) : seqKey(rrn);
        return status = store.remove(name, k) ? "00" : "23";
    }
    public String delete(Rec r) { return delete(r.bytes()); }

    // ---------- 読込み ----------
    /** READ ... KEY（主キー: レコード域のキー値で読む。相対: rrn）。成功時 rec へ格納。 */
    public String read(Rec rec) {
        if (!open) return status = "47";
        byte[] k = org == Org.INDEXED ? pkey(rec.bytes()) : seqKey(rrn);
        byte[] d = store.get(name, k);
        if (d == null) return status = "23";
        rec.load(d); cursor = k; cursorPending = false; altInUse = -1;
        return status = "00";
    }
    /** 副キー n（0 始まり）による READ。 */
    public String readAlt(Rec rec, int n) {
        if (!open) return status = "47";
        int[] a = altKeys[n];
        buildAlt(n);
        for (int i = 0; i < altList.size(); i++) {
            byte[] d = altList.get(i).getValue();
            if (Arrays.equals(d, a[0], a[0] + a[1], rec.bytes(), a[0], a[0] + a[1])) {
                rec.load(d); altInUse = n; altPos = i + 1; cursor = altList.get(i).getKey();
                return status = "00";
            }
        }
        return status = "23";
    }
    private void buildAlt(int n) {
        int[] a = altKeys[n];
        altList = store.all(name);
        altList.sort((x, y) -> {
            int c = Arrays.compareUnsigned(x.getValue(), a[0], a[0] + a[1], y.getValue(), a[0], a[0] + a[1]);
            return c != 0 ? c : Arrays.compareUnsigned(x.getKey(), y.getKey());
        });
    }
    /** START: op は "=", ">", ">=", "<", "<="（主キー。キー値はレコード域または rrn）。 */
    public String start(Rec rec, String op) {
        if (!open) return status = "47";
        byte[] k = org == Org.INDEXED ? pkey(rec.bytes()) : seqKey(rrn);
        Map.Entry<byte[], byte[]> e = switch (op) {
            case "=" -> { byte[] d = store.get(name, k); yield d == null ? null : Map.entry(k, d); }
            case ">" -> store.next(name, k, false);
            case ">=" -> store.next(name, k, true);
            case "<" -> store.prev(name, k, false);
            default -> store.prev(name, k, true);
        };
        altInUse = -1;
        if (e == null) return status = "23";
        cursor = e.getKey(); cursorPending = true;
        return status = "00";
    }
    /** 副キー n による START（>= など）。以降の readNext は副キー順。 */
    public String startAlt(Rec rec, int n, String op) {
        if (!open) return status = "47";
        int[] a = altKeys[n];
        buildAlt(n);
        for (int i = 0; i < altList.size(); i++) {
            int c = Arrays.compareUnsigned(altList.get(i).getValue(), a[0], a[0] + a[1], rec.bytes(), a[0], a[0] + a[1]);
            boolean hit = switch (op) { case "=" -> c == 0; case ">" -> c > 0; default -> c >= 0; };
            if (hit) { altInUse = n; altPos = i; return status = "00"; }
        }
        return status = "23";
    }
    /** READ NEXT。ファイル終端は "10"。 */
    public String readNext(Rec rec) {
        if (!open) return status = "47";
        if (altInUse >= 0) {
            if (altPos >= altList.size()) return status = "10";
            var e = altList.get(altPos++);
            byte[] d = store.get(name, e.getKey());
            if (d == null) return readNext(rec);
            rec.load(d); cursor = e.getKey();
            return status = "00";
        }
        Map.Entry<byte[], byte[]> e = cursorPending ? store.next(name, cursor, true) : store.next(name, cursor, false);
        cursorPending = false;
        if (e == null) return status = "10";
        cursor = e.getKey();
        if (org == Org.RELATIVE) rrn = toLong(cursor);
        rec.load(e.getValue());
        return status = "00";
    }
    public String readPrevious(Rec rec) {
        if (!open) return status = "47";
        Map.Entry<byte[], byte[]> e = cursor == null ? store.prev(name, null, true) : store.prev(name, cursor, cursorPending);
        cursorPending = false;
        if (e == null) return status = "10";
        cursor = e.getKey(); rec.load(e.getValue());
        return status = "00";
    }
    /** 行順/順ファイルの READ NEXT を文字列で取得（終端は null、status "10"）。 */
    public String readLine() {
        Map.Entry<byte[], byte[]> e = store.next(name, cursor, false);
        if (e == null) { status = "10"; return null; }
        cursor = e.getKey(); status = "00";
        return new String(e.getValue(), StandardCharsets.ISO_8859_1);
    }
}
