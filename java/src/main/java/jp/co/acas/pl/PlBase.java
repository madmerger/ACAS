package jp.co.acas.pl;

import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.SystemFile;

import java.time.LocalDateTime;

/** PL 買掛プログラム共通の補助（システムレコード・日付変換・maps99 エラー表示など）。 */
abstract class PlBase extends Program {
    protected Rec sys;

    protected void init() { sys = SystemFile.shared(ctx); }

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
        show(23, 3, Num.z9(code, 3), 4);
        display(23, 7, "Error not in error.txt. Hit return to close", 4);
        accept(24, 79, 1);
    }
}
