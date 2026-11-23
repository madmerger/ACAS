package jp.co.acas.pl;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** pl940: 小切手金額の英語表記（データ出力）。 */
class Pl940Test {
    @Test
    void 一から九十九の表記() {
        assertEquals("One", Pl940.wordn(1));
        assertEquals("Nineteen", Pl940.wordn(19));
        assertEquals("Twenty", Pl940.wordn(20));
        assertEquals("Forty-Two", Pl940.wordn(42));
    }

    @Test
    void 金額文言は二行に分かれる() {
        String[] w = Pl940.words(new BigDecimal("1234.56"));
        assertEquals(2, w.length);
        assertTrue(w[0].startsWith("One Thousand "), w[0]);
        assertTrue(w[1].startsWith("Two Hundred and Thirty-Four Pounds Fifty-Six Pence "), w[1]);
    }
}
