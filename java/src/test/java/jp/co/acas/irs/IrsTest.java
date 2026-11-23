package jp.co.acas.irs;

import jp.co.acas.core.Messages;
import org.junit.jupiter.api.Test;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class IrsTest {
    @Test
    void dateValidateFollowsLegacyRules() {
        assertEquals("23/11/26", IrsBase.dateValidate("23.11.26")[0]);
        assertTrue(((Number) IrsBase.dateValidate("23/11/26")[1]).longValue() > 0);
        assertEquals(0, ((Number) IrsBase.dateValidate("31/04/26")[1]).longValue());
        assertEquals(0, ((Number) IrsBase.dateValidate("29/02/26")[1]).longValue());
        assertTrue(((Number) IrsBase.dateValidate("29/02/24")[1]).longValue() > 0);
        assertEquals(0, ((Number) IrsBase.dateValidate("2311/26")[1]).longValue());
        long a = ((Number) IrsBase.dateValidate("31/12/26")[1]).longValue();
        long b = ((Number) IrsBase.dateValidate("01/01/27")[1]).longValue();
        assertEquals(1, b - a);
    }

    /** irs060 ws-unpack はうるう日を補正しない（u-year を加算後に ws-work2 と比較するため）。ソースどおりの結果を固定する。 */
    @Test
    void unpackFollowsLegacySource() {
        assertEquals("31/12/00", Irs060.unpack(365));
        assertEquals("01/01/00", Irs060.unpack(1));
        long bin = ((Number) IrsBase.dateValidate("01/01/26")[1]).longValue();
        assertEquals("08/01/26", Irs060.unpack(bin));
    }

    @Test
    void translationsFitLegacyWidth() throws Exception {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(
                IrsTest.class.getResourceAsStream("/i18n/irs.tsv"), StandardCharsets.UTF_8))) {
            int n = 0;
            for (String line; (line = r.readLine()) != null; ) {
                if (line.startsWith("#") || !line.contains("\t")) continue;
                String[] p = line.split("\t", 2);
                assertFalse(p[1].isBlank(), p[0]);
                assertTrue(Messages.width(p[1]) <= p[0].length(), "訳語が原文より広い: " + p[0]);
                n++;
            }
            assertTrue(n > 300);
        }
    }

    @Test
    void menuIsShownInJapanese() {
        assertEquals("簡易会計システム", Messages.ja("Incomplete Records System").strip());
        assertTrue(Messages.ja("(7)  Accounts Production").contains("決算書作成"));
        assertTrue(Messages.ja("Enter comparative to use (0 to 4) -  [0]").startsWith("使用する比較欄"));
    }
}
