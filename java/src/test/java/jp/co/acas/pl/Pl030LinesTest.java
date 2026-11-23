package jp.co.acas.pl;

import org.junit.jupiter.api.Test;

import static jp.co.acas.pl.Pl020LinesTest.assertSaved;
import static jp.co.acas.pl.Pl020LinesTest.entered;
import static jp.co.acas.pl.Pl020LinesTest.line;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** 請求修正（pl030）: 画面から登録した 39 行／40 行の請求を修正画面で開き、保存する。 */
class Pl030LinesTest {
    /** 既存の明細は全項目 Enter で確定する。 */
    private static String keep(int count) { return "\r\r\r\r".repeat(count); }
    private static final String AMEND = "E" + "00000001\r" + "\r\r\r\r\r";
    private static final String AMEND_TOTALS = "\r\r\r\rY\rY\rN\r";

    @Test
    void 修正で39行のまま保存する() throws Exception {
        PlSession s = entered("pl030a39", 39);
        s.keys(AMEND).keys(keep(38)).keys(line(49)).keys("\r").keys(AMEND_TOTALS);
        s.assertMenu();
        assertSaved(s, 39, 49, 790);
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
        s.keys(AMEND).keys(keep(39)).keys(line(50)).keys(AMEND_TOTALS);
        s.assertMenu();
        assertSaved(s, 40, 50, 830);
    }

    @Test
    void レガシー未転記請求の明細を復元して金額変更を保存する() throws Exception {
        PlSession s = new PlSession("pl030legacy", "pl-invoice");
        s.keys(AMEND);
        s.keys("\r");
        assertTrue(s.screen().contains("0000100.00"), s::screen);
        s.keys("0000060.00\r1\r\r").keys("\r").keys(AMEND_TOTALS);
        s.assertMenu();
        assertSaved(s, 1, 60, 60);
    }
}
