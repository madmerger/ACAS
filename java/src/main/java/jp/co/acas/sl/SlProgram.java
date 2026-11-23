package jp.co.acas.sl;

import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.time.LocalDateTime;

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
        d = pad(d, 10);
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
}
