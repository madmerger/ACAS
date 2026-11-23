package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Ctx;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.SystemFile;

/** GL 各プログラム共通の補助（LINKAGE で引き回す領域、ファイル定義、日付形式変換）。 */
final class GlCommon {
    private GlCommon() { }

    static Rec sys(Ctx ctx) { return SystemFile.shared(ctx); }
    /** default-record（system.dat rrn 2）。 */
    static Rec dflt(Ctx ctx) {
        return (Rec) ctx.shared.computeIfAbsent("default-record", k -> Layout.of("copybooks/wsdflt.cob", "Default-Record").newRec());
    }
    /** system-record-4（system.dat rrn 4）。 */
    static Rec sys4(Ctx ctx) {
        return (Rec) ctx.shared.computeIfAbsent("system-record-4", k -> Layout.of("copybooks/wssys4.cob", "System-Record-4").newRec());
    }
    static String toDay(Ctx ctx) { return (String) ctx.shared.getOrDefault("to-day", "          "); }
    static void toDay(Ctx ctx, String v) { ctx.shared.put("to-day", v); }
    static int termCode(Ctx ctx) { return (int) ctx.shared.getOrDefault("ws-term-code", 0); }
    static void termCode(Ctx ctx, int v) { ctx.shared.put("ws-term-code", v); }

    static Rec ledgerRec() {
        // FD のレコード領域は初期値 low-values。FILLER は一度も設定されないので x"00" のまま書かれる
        Rec r = Layout.of("general/fdledger.cob", "ledger-record").newRec();
        byte[] b = r.bytes();
        java.util.Arrays.fill(b, 11, 16, (byte) 0);
        java.util.Arrays.fill(b, b.length - 50, b.length, (byte) 0);
        return r;
    }
    static CobFile ledgerFile(Ctx ctx, Rec r) { return CobFile.indexed(ctx.store, ctx.path("ledger.dat"), r, "ledger-key"); }
    static Rec batchRec() { return Layout.of("copybooks/fdbatch.cob", "batch-record").newRec(); }
    static CobFile batchFile(Ctx ctx, Rec r) { return CobFile.indexed(ctx.store, ctx.path("batch.dat"), r, "batch-key"); }
    static Rec postingRec() { return Layout.of("copybooks/fdpost.cob", "posting-record").newRec(); }
    static CobFile postingFile(Ctx ctx) { return CobFile.relative(ctx.store, ctx.path("posting.dat")); }

    /** UK 形式 dd/mm/ccyy → 設定形式（USA: 日月入替、Intl: ccyy/mm/dd）。画面表示・入力前の変換。 */
    static String ukToForm(Rec sys, String uk) {
        int form = sys.intv("date-form");
        String u = pad10(uk);
        if (form == 2) return u.substring(3, 5) + u.charAt(2) + u.substring(0, 2) + u.substring(5);
        if (form == 3) return u.substring(6, 10) + "/" + u.substring(3, 5) + "/" + u.substring(0, 2);
        return u;
    }
    /** 設定形式で入力された日付 → UK 形式。 */
    static String formToUk(Rec sys, String in) {
        int form = sys.intv("date-form");
        String u = pad10(in);
        if (form == 2) return u.substring(3, 5) + u.charAt(2) + u.substring(0, 2) + u.substring(5);
        if (form == 3) return u.substring(8, 10) + "/" + u.substring(5, 7) + "/" + u.substring(0, 4);
        return u;
    }
    static String pad10(String s) { return (s + "          ").substring(0, 10); }
    static String pad(String s, int n) { return s.length() >= n ? s.substring(0, n) : s + " ".repeat(n - s.length()); }
}
