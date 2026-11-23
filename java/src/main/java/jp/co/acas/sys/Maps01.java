package jp.co.acas.sys;

import jp.co.acas.core.Ctx;

/** COBOL maps01: パスワード（4 桁）／利用者名（32 桁）の符号化。作業域は実行単位内で保持される。 */
public final class Maps01 {
    private static final String ALPHA = "CKQUAELSMWYIZJRPBXFVGNODTH";
    private Maps01() { }

    private static char[] area(Ctx ctx, String key, int size) {
        return (char[]) ctx.shared.computeIfAbsent(key, k -> " ".repeat(size).toCharArray());
    }
    private static int index(char c) {
        int a = ALPHA.indexOf(c);
        if (a < 0) a = ALPHA.toLowerCase().indexOf(c);
        return a + 1;
    }
    private static String fit(String s, int n) { return (s + " ".repeat(n)).substring(0, n); }

    /** encode = "P"。 */
    public static String password(Ctx ctx, String password) {
        String in = fit(password, 4);
        char[] out = area(ctx, "maps01.pass-word-output", 4);
        for (int y = 1; y < 5; y++) {
            int a = index(in.charAt(y - 1));
            if (a == 0) continue;
            int z = a + y * y + 3 - 26;
            if (z < 1) z = -z;
            out[5 - y - 1] = z != 0 ? ALPHA.charAt(z - 1) : ' ';
        }
        return new String(out);
    }

    /** encode = "N"。 */
    public static String name(Ctx ctx, String name) {
        String in = fit(name, 32);
        char[] out = area(ctx, "maps01.pass-name-output", 32);
        for (int y = 1; y < 32; y++) {
            int a = index(in.charAt(y - 1));
            if (a == 0) continue;
            int base = (int) Math.floor((y + 51) / (double) y + 0.5);
            if (base > 25) base -= 26;
            int z = a + base - 27;
            if (z < 1) z = -z;
            if (z > 26) z -= 26;
            out[y - 1] = z != 0 ? ALPHA.charAt(z - 1) : ' ';
        }
        return new String(out);
    }
}
