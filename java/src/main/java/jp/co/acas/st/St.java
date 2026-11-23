package jp.co.acas.st;

/** 在庫管理プログラム共通の補助（日付形式の入替など、各プログラムに重複する段落）。 */
final class St {
    private St() { }

    /**
     * stock/wsnames.cob の file-defs（System-File-Names 1〜6）。在庫から CALL する他サブシステムのプログラム（sl070）へ
     * USING file-defs として渡す。売掛の wsnames とは並びが違い、sl070 側のスロット解決はこの並びで行われる。
     */
    static final String[] FILE_DEFS = {"system.dat", "tmp-stock.dat", "staudit.dat", "stockctl.dat", "analysis.dat", "purchled.dat"};

    /** UK 形式 dd/mm/ccyy → 設定形式（1=UK, 2=USA, 3=Intl）。 */
    static String fromUk(String d, int form) {
        d = String.format("%-10s", d);
        if (form == 2) return d.substring(3, 5) + d.substring(2, 3) + d.substring(0, 2) + d.substring(5);
        if (form == 3) return d.substring(6, 10) + "/" + d.substring(3, 5) + "/" + d.substring(0, 2);
        return d;
    }
    /** 設定形式 → UK 形式 dd/mm/ccyy。 */
    static String toUk(String d, int form) {
        d = String.format("%-10s", d);
        if (form == 2) return d.substring(3, 5) + d.substring(2, 3) + d.substring(0, 2) + d.substring(5);
        if (form == 3) return d.substring(8, 10) + "/" + d.substring(5, 7) + "/" + d.substring(0, 4);
        return d;
    }

    /** 在庫ファイル（stockctl.dat、主キー Stock-Key、副キー Stock-Abrev-Key / Stock-Desc（重複可））。 */
    static jp.co.acas.core.CobFile stockFile(jp.co.acas.core.Ctx ctx, jp.co.acas.core.Rec r) {
        return jp.co.acas.core.CobFile.indexed(ctx.store, ctx.path("stockctl.dat"), r, "stock-key")
                .alt(r.offset("stock-abrev-key"), r.size("stock-abrev-key"), false)
                .alt(r.offset("stock-desc"), r.size("stock-desc"), true);
    }

    /** FileStat-Msgs.cpy: FILE STATUS の説明（該当なしは直前値のまま＝空白）。 */
    static String evalStatus(String fs) {
        return switch (fs) {
            case "00" -> "Success"; case "02" -> "Success Duplicate"; case "04" -> "Success Incomplete";
            case "05" -> "Success Optional"; case "07" -> "Success No Unit"; case "10" -> "End Of File";
            case "14" -> "Out Of Key Range"; case "21" -> "Key Invalid"; case "22" -> "Key Exists";
            case "23" -> "Key Not Exists"; case "30" -> "Permanent Error"; case "31" -> "Inconsistent Filename";
            case "34" -> "Boundary Violation"; case "35" -> "File Not Found"; case "37" -> "Permission Denied";
            case "38" -> "Closed With Lock"; case "39" -> "Conflict Attribute"; case "41" -> "Already Open";
            case "42" -> "Not Open"; case "43" -> "Read Not Done"; case "44" -> "Record Overflow";
            case "46" -> "Read Error"; case "47" -> "Input Denied"; case "48" -> "Output Denied";
            case "49" -> "I/O Denied"; case "51" -> "Record Locked"; case "52" -> "End-Of-Page";
            case "57" -> "I/O Linage"; case "61" -> "File Sharing Failure"; case "91" -> "File Not Available";
            default -> "";
        };
    }

    /** FD のレコード領域の初期状態: FILLER は LOW-VALUES（INITIALIZE は FILLER を初期化しない）。 */
    static jp.co.acas.core.Rec fdRec(jp.co.acas.core.Layout layout) {
        jp.co.acas.core.Rec r = layout.newRec();
        fillers(layout.root, r.bytes(), null);
        return r;
    }
    /** INITIALIZE: 英数字 = 空白、数字 = ゼロ。FILLER は直前の内容を保つ。 */
    static void initialize(jp.co.acas.core.Rec r) {
        byte[] saved = r.copyBytes();
        r.initialize();
        fillers(r.layout.root, r.bytes(), saved);
    }
    /** FILLER 項目の領域を from の内容（null なら LOW-VALUES）にする。 */
    private static void fillers(jp.co.acas.core.Layout.Field f, byte[] data, byte[] from) {
        if (f.redefines != null) return;
        if (f.kind == jp.co.acas.core.Layout.Kind.GROUP) { for (jp.co.acas.core.Layout.Field c : f.children) fillers(c, data, from); return; }
        if (!"filler".equals(f.name)) return;
        int end = f.offset + f.size * f.occurs;
        if (from == null) java.util.Arrays.fill(data, f.offset, end, (byte) 0);
        else System.arraycopy(from, f.offset, data, f.offset, end - f.offset);
    }

    /** PIC X(n) への MOVE（左詰め・空白埋め・切捨て）。 */
    static String x(String s, int n) { return s.length() >= n ? s.substring(0, n) : s + " ".repeat(n - s.length()); }

    /** 表示数字項目として文字列を評価（空白などは下位 4 ビットを数字とみなす）。 */
    static long digits(String s) {
        long v = 0;
        for (char c : s.toCharArray()) v = v * 10 + (c & 0x0f) % 10;
        return v;
    }

    /** Print-Report（lpr 呼出し）のコマンド文字列。 */
    static String printCommand(String psn) {
        return "lpr -r -o 'orientation-requested=4 page-left=21 page-top=48 page-right=10 sides=two-sided-long-edge cpi=12 lpi=8' -P "
                + psn.stripTrailing() + " prt-1";
    }

    /** 印刷ファイル（行順）: WRITE ... BEFORE / AFTER ADVANCING を文字ストリームとして再現する。 */
    static final class Printer {
        private final jp.co.acas.core.CobFile file;
        private final StringBuilder sb = new StringBuilder();
        Printer(jp.co.acas.core.Ctx ctx, String name) {
            file = jp.co.acas.core.CobFile.lineSequential(ctx.store, ctx.path(name));
            file.open(jp.co.acas.core.CobFile.Mode.OUTPUT);
        }
        void before(String rec, int lines) { sb.append(rec).append("\n".repeat(lines)); }
        void after(String rec, int lines) { sb.append("\n".repeat(lines)).append(rec); }
        void afterPage(String rec) { sb.append("\f").append(rec); }
        void close() {
            if (sb.length() > 0) {
                String all = sb.toString();
                if (all.endsWith("\n")) all = all.substring(0, all.length() - 1);
                for (String l : all.split("\n", -1)) file.write(l.getBytes(java.nio.charset.StandardCharsets.ISO_8859_1));
            }
            file.close();
        }
    }
}
