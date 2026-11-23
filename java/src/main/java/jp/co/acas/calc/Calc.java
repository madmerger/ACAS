package jp.co.acas.calc;

import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.Maps09;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 計算ロジック（同一性確認 CALC ケースの対象）。
 * レガシーの maps09 / maps04 モジュール呼出しと、sl910（VAT）・sl110（年齢区分）・st020（平均原価）の計算文に対応する。
 */
public final class Calc {
    private Calc() { }

    /** maps09 "C": チェックディジット。code は 6 桁に切詰め／空白埋め。 */
    public static Map<String, Object> checkDigit(String code) {
        String c = (code + "      ").substring(0, 6);
        int cd = Maps09.checkDigit(c);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("check", Math.max(cd, 0));
        m.put("valid", cd >= 0);
        return m;
    }

    /** maps04: 日付 → 通算日。入力は 10 桁に切詰め／空白埋め。 */
    public static Map<String, Object> date(String date) {
        String a = (date + "          ").substring(0, 10);
        long bin = Maps04.toBin(a);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("valid", bin != 0);
        m.put("integer", bin);
        m.put("normalized", bin == 0 ? null : a.replace('.', '/').replace(',', '/').replace('-', '/').strip());
        return m;
    }

    /**
     * sl910: compute amt-ok6 rounded = (ws-net * ws-vat-rate) / 100。
     * ws-net pic 9(7)v99、ws-vat-rate pic 99v99、amt-ok6 pic 9(6)v99 はいずれも符号なし（負の入力は絶対値として扱われる）。
     */
    public static BigDecimal vat(BigDecimal net, BigDecimal rate) {
        BigDecimal n = net.abs().setScale(2, RoundingMode.DOWN).remainder(BigDecimal.valueOf(10_000_000));
        BigDecimal r = rate.abs().setScale(2, RoundingMode.DOWN).remainder(BigDecimal.valueOf(100));
        return n.multiply(r).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP).remainder(BigDecimal.valueOf(1_000_000));
    }

    /** sl110: 経過日数 → 年齢区分（0 / 30 / 60 / 90）。 */
    public static int ageBucket(int days) {
        return days < 30 ? 0 : days < 60 ? 30 : days < 90 ? 60 : 90;
    }

    /** st020: divide ws-New-Qty into ws-New-Value giving ws-New-Cost rounded（s9(6)v9999）。数量 0 は null（ON SIZE ERROR なしのため結果不定）。 */
    public static BigDecimal averageCost(BigDecimal value, long qty) {
        if (qty == 0) return null;
        return value.setScale(2, RoundingMode.DOWN).divide(BigDecimal.valueOf(qty), 4, RoundingMode.HALF_UP).remainder(BigDecimal.valueOf(1_000_000));
    }
}
