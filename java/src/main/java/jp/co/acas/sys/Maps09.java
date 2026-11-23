package jp.co.acas.sys;

/** maps09: 顧客／仕入先コード（6 桁）のチェックディジット（モジュラス 11）計算・検証。 */
public final class Maps09 {
    private static final String ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-";
    private Maps09() { }

    /** レガシーの a（計算結果、PIC s9(5) comp）。コード不正（suma=0）は -1。 */
    public static int compute(String nos) {
        String w = (nos + "      ").substring(0, 6);
        int suma = 0;
        for (int a = 1; a <= 6; a++) {
            int q = ALPHA.indexOf(w.charAt(a - 1)) + 1;
            if (q == 0) { suma = 0; break; }
            suma += q * (8 - a);
        }
        if (suma == 0) return -1;
        return 11 - (suma % 11);
    }
    /** "C"（計算）: check-digit（PIC 9）へ格納される値。不正コードは -1。 */
    public static int checkDigit(String nos) {
        int a = compute(nos);
        return a < 0 ? -1 : a % 10;
    }
    /** "V"（検証）: 7 桁コード（6 桁 + チェックディジット）が正しければ true。 */
    public static boolean verify(String code7) {
        if (code7 == null || code7.length() < 7 || !Character.isDigit(code7.charAt(6))) return false;
        int a = compute(code7.substring(0, 6));
        return a >= 0 && a == code7.charAt(6) - '0';
    }
}
