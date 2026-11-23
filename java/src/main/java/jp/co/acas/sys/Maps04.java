package jp.co.acas.sys;

import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

/** maps04: 日付（dd/mm/ccyy）⇔ 通算日（COBOL integer-of-date: 1601-01-01 = 1）変換。 */
public final class Maps04 {
    private static final LocalDate EPOCH = LocalDate.of(1600, 12, 31);
    private Maps04() { }

    /** 通算日 → "dd/mm/ccyy"。 */
    public static String toDate(long bin) {
        LocalDate d = EPOCH.plusDays(bin);
        return String.format("%02d/%02d/%04d", d.getDayOfMonth(), d.getMonthValue(), d.getYear());
    }
    public static long toBin(LocalDate d) { return ChronoUnit.DAYS.between(EPOCH, d); }
    /**
     * "dd/mm/ccyy"（区切りは . , - も可）→ 通算日。不正な日付は 0（レガシーは u-bin を変更せず 0 のまま返す）。
     */
    public static long toBin(String date) {
        if (date == null || date.length() < 10) return 0;
        String a = date.substring(0, 10).replace('.', '/').replace(',', '/').replace('-', '/');
        if (a.chars().filter(c -> c == '/').count() != 2) return 0;
        String dd = a.substring(0, 2), mm = a.substring(3, 5), cc = a.substring(6, 8), yy = a.substring(8, 10);
        if (!dd.matches("\\d\\d") || !mm.matches("\\d\\d") || !cc.matches("\\d\\d")) return 0;
        int d = Integer.parseInt(dd), m = Integer.parseInt(mm);
        if (d < 1 || d > 31 || m < 1 || m > 12) return 0;
        if (!yy.matches("\\d\\d")) return 0;
        int y = Integer.parseInt(cc + yy);
        if (y < 1601) return 0;
        try { return toBin(LocalDate.of(y, m, d)); } catch (DateTimeException e) { return 0; }
    }
}
