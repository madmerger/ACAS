package jp.co.acas.st;

/** 在庫管理プログラム共通の補助（日付形式の入替など、各プログラムに重複する段落）。 */
final class St {
    private St() { }

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
