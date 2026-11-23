package jp.co.acas.sl;

import org.junit.jupiter.api.Test;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** SL 売掛: 顧客帳票の抽出条件判定（test-num）と訳語表 sl.tsv の整合。 */
class SlTest {
    @Test
    void 演算子LGEは入力値に対する実値の大小で判定する() {
        assertTrue(CustReport.testNum("L", 30, 29));
        assertFalse(CustReport.testNum("L", 30, 30));
        assertTrue(CustReport.testNum("G", 30, 31));
        assertFalse(CustReport.testNum("G", 30, 30));
        assertTrue(CustReport.testNum("E", 30, 30));
        assertFalse(CustReport.testNum("E", 30, 31));
        assertTrue(CustReport.testNum(" ", 30, 99));
    }

    @Test
    void 訳語表は英語原文が重複せず全行に訳語がある() throws Exception {
        var in = SlTest.class.getResourceAsStream("/i18n/sl.tsv");
        assertNotNull(in);
        Set<String> keys = new HashSet<>();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.isBlank() || line.startsWith("#")) continue;
                int t = line.indexOf('\t');
                assertTrue(t > 0, "タブ区切りでない行: " + line);
                assertFalse(line.substring(t + 1).isBlank(), "訳語が空: " + line);
                assertTrue(keys.add(line.substring(0, t)), "英語原文が重複: " + line);
            }
        }
    }
}
