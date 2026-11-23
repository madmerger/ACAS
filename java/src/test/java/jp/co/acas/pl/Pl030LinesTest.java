package jp.co.acas.pl;

import org.junit.jupiter.api.Test;

import static jp.co.acas.pl.Pl020LinesTest.assertSaved;
import static jp.co.acas.pl.Pl020LinesTest.entered;
import static jp.co.acas.pl.Pl020LinesTest.line;

/** 請求修正（pl030）: 画面から登録した 39 行／40 行の請求を修正画面で開き、保存する。 */
class Pl030LinesTest {
    /** 既存の明細は全項目 Enter で確定する。 */
    private static String keep(int count) { return "\r\r\r\r".repeat(count); }
    private static final String AMEND = "E" + "00000001\r" + "\r\r\r\r\r";
    private static final String AMEND_TOTALS = "\r\r\r\rY\rY\rN\r";

    @Test
    void 修正で39行のまま保存する() throws Exception {
        PlSession s = entered("pl030a39", 39);
        s.keys(AMEND).keys(keep(39)).keys("\r").keys(AMEND_TOTALS);
        s.assertMenu();
        assertSaved(s, 39);
    }

    @Test
    void 修正で39行に40行目を追加して保存する() throws Exception {
        PlSession s = entered("pl030a3940", 39);
        s.keys(AMEND).keys(keep(39)).keys(line(40).replaceFirst("^\r", "a1\r")).keys(AMEND_TOTALS);
        s.assertMenu();
        assertSaved(s, 40);
    }

    @Test
    void 修正で40行のまま保存する() throws Exception {
        PlSession s = entered("pl030a40", 40);
        s.keys(AMEND).keys(keep(40)).keys(AMEND_TOTALS);
        s.assertMenu();
        assertSaved(s, 40);
    }
}
