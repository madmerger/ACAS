package jp.co.acas.core;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;

class LayoutTest {
    @Test
    void recordSizesMatchLegacyFiles() {
        assertEquals(1024, Layout.of("copybooks/wssystem.cob", "System-Record").size);
        assertEquals(126, Layout.of("general/fdledger.cob", "ledger-record").size);
        assertEquals(300, Layout.of("copybooks/fdsl.cob", "sales-record").size);
        assertEquals(300, Layout.of("copybooks/fdpl.cob", "purch-record").size);
        assertEquals(400, Layout.of("copybooks/fdstock.cob", "stock-record").size);
        assertEquals(36, Layout.of("copybooks/fdanal.cob", "analysis-record").size);
    }

    @Test
    void packedDecimalAndDisplayRoundTrip() {
        Layout l = Layout.ofSource("""
                 01  r.
                     03  a   pic s9(5)v99 comp-3.
                     03  b   pic 9(4).
                     03  c   pic x(3).
                     03  d   pic s9(3)v9 comp-3 occurs 2.
                """, "r");
        Rec r = l.newRec();
        assertEquals(4 + 4 + 3 + 3 * 2, l.size);
        r.setNum("a", new BigDecimal("-123.45"));
        r.setNum("b", 42);
        r.set("c", "x");
        r.setRounded("d", new BigDecimal("1.25"), 2);
        assertEquals(new BigDecimal("-123.45"), r.num("a"));
        assertArrayEquals(new byte[]{0x00, 0x12, 0x34, 0x5d}, r.raw("a"));
        assertEquals("0042", r.str("b"));
        assertEquals("x  ", r.str("c"));
        assertEquals(new BigDecimal("1.3"), r.num("d", 2));
        r.setNum("b", 123456);
        assertEquals("3456", r.str("b"));
    }
}
