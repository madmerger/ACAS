package jp.co.acas.core;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** COBOL 数値編集・変換の補助。 */
public final class Num {
    private Num() { }

    /** 画面入力文字列などを数値へ（数字・小数点・符号以外は無視。空は 0）。 */
    public static BigDecimal parse(String s) {
        if (s == null) return BigDecimal.ZERO;
        StringBuilder sb = new StringBuilder(); boolean neg = false, dot = false;
        for (char c : s.toCharArray()) {
            if (c >= '0' && c <= '9') sb.append(c);
            else if (c == '.' && !dot) { sb.append(c); dot = true; }
            else if (c == '-') neg = true;
        }
        String t = sb.toString();
        if (t.isEmpty() || t.equals(".")) return BigDecimal.ZERO;
        BigDecimal v = new BigDecimal(t.startsWith(".") ? "0" + t : t);
        return neg ? v.negate() : v;
    }

    /** PIC 9(n) 相当のゼロ埋め表示（上位あふれは切り捨て）。 */
    public static String z9(long v, int digits) {
        String s = Long.toString(Math.abs(v));
        if (s.length() > digits) s = s.substring(s.length() - digits);
        return "0".repeat(digits - s.length()) + s;
    }

    /**
     * COBOL 編集 PICTURE による表示。対応: 9 Z * , . + - CR DB B 0 / と浮動 + - 記号、£/$ は非対応。
     * 例: edit(v, "zzz,zz9.99-"), edit(v, "-(6)9.99"), edit(v, "z(6)9.99cr")
     */
    public static String edit(BigDecimal v, String picture) {
        String p = expand(picture.toLowerCase());
        boolean cr = p.endsWith("cr"), db = p.endsWith("db");
        String body = cr || db ? p.substring(0, p.length() - 2) : p;
        int dot = body.indexOf('.');
        int scale = dot < 0 ? 0 : (int) body.substring(dot + 1).replaceAll("[+-]$", "").chars().filter(c -> "9z*+-".indexOf(c) >= 0).count();
        boolean neg = v.signum() < 0;
        String digits = v.abs().setScale(scale, RoundingMode.DOWN).unscaledValue().toString();
        // 数字位置の数
        long firstFloat = -1; char floatCh = 0;
        int plus = (int) body.chars().filter(c -> c == '+').count(), minus = (int) body.chars().filter(c -> c == '-').count();
        if (plus > 1) floatCh = '+'; else if (minus > 1) floatCh = '-';
        int digitPos = 0;
        boolean firstFloatSeen = false;
        for (char c : body.toCharArray()) {
            if (c == '9' || c == 'z' || c == '*') digitPos++;
            else if (c == floatCh) { if (firstFloatSeen) digitPos++; else firstFloatSeen = true; }
        }
        if (digits.length() > digitPos) digits = digits.substring(digits.length() - digitPos);
        digits = "0".repeat(digitPos - digits.length()) + digits;
        char[] out = new char[body.length()];
        int di = 0; boolean significant = false; firstFloatSeen = false;
        int signPos = -1; // 浮動記号を置く位置
        for (int i = 0; i < body.length(); i++) {
            char c = body.charAt(i);
            switch (c) {
                case '9' -> { out[i] = digits.charAt(di++); significant = true; }
                case 'z', '*' -> {
                    char d = digits.charAt(di++);
                    if (d != '0') significant = true;
                    out[i] = significant ? d : (c == '*' ? '*' : ' ');
                }
                case ',' -> out[i] = significant ? ',' : (body.indexOf('*') >= 0 && body.indexOf('*') < i ? '*' : ' ');
                case '.' -> { out[i] = '.'; }
                case 'b' -> out[i] = ' ';
                case '/' -> out[i] = '/';
                case '0' -> out[i] = '0';
                case '+', '-' -> {
                    if (c == floatCh) {
                        if (!firstFloatSeen) { firstFloatSeen = true; out[i] = ' '; signPos = i; }
                        else {
                            char d = digits.charAt(di++);
                            if (d != '0') significant = true;
                            if (significant) out[i] = d; else { out[i] = ' '; signPos = i; }
                        }
                    } else out[i] = c == '+' ? (neg ? '-' : '+') : (neg ? '-' : ' ');
                }
                default -> out[i] = c;
            }
            if (c == '.' ) significant = true;
        }
        if (floatCh != 0 && signPos >= 0) {
            // 有効数字直前の「,」は空白化済み。記号は最後の抑制位置へ。
            int pos = signPos;
            for (int i = signPos + 1; i < body.length() && out[i] == ' ' && (body.charAt(i) == ',' ); i++) pos = i;
            out[pos] = floatCh == '+' ? (neg ? '-' : '+') : (neg ? '-' : ' ');
        }
        // 値ゼロで全桁抑制（z のみ・小数部も z）の場合は全空白
        String res = new String(out);
        if (v.signum() == 0 && body.indexOf('9') < 0 && floatCh == 0 && body.indexOf('*') < 0) res = " ".repeat(body.length());
        if (cr) res += neg ? "CR" : "  ";
        if (db) res += neg ? "DB" : "  ";
        return res;
    }
    public static String edit(long v, String picture) { return edit(BigDecimal.valueOf(v), picture); }

    private static String expand(String pic) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < pic.length(); i++) {
            char c = pic.charAt(i);
            if (i + 1 < pic.length() && pic.charAt(i + 1) == '(') {
                int e = pic.indexOf(')', i);
                sb.append(String.valueOf(c).repeat(Integer.parseInt(pic.substring(i + 2, e))));
                i = e;
            } else sb.append(c);
        }
        return sb.toString();
    }

    /** COMPUTE x ROUNDED（四捨五入: 0.5 は絶対値の大きい方へ）。 */
    public static BigDecimal rounded(BigDecimal v, int scale) { return v.setScale(scale, RoundingMode.HALF_UP); }
    /** ROUNDED なしの切り捨て。 */
    public static BigDecimal truncated(BigDecimal v, int scale) { return v.setScale(scale, RoundingMode.DOWN); }
}
