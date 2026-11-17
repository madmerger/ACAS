package com.acas.isam.codec;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class ZonedDecimalTest {
    private byte[] ascii(String s) { return s.getBytes(StandardCharsets.US_ASCII); }

    @Test void vectorsAndOverpunch() {
        byte[] buf = new byte[5];
        ZonedDecimal.encode(new BigDecimal("-123.45"), buf, 0, 5, 2, true);
        assertArrayEquals(ascii("1234u"), buf);
        assertEquals(new BigDecimal("-123.45"), ZonedDecimal.decode(buf, 0, 5, 2, true));
        ZonedDecimal.encode(new BigDecimal("-123.45"), buf, 0, 5, 2, true, ZonedDecimal.SignPosition.LEADING);
        assertArrayEquals(ascii("q2345"), buf);
        assertEquals(new BigDecimal("-123.45"), ZonedDecimal.decode(buf, 0, 5, 2, true, ZonedDecimal.SignPosition.LEADING));
        for (int digit = 0; digit <= 9; digit++) {
            for (char c : new char[]{(char) ('0'+digit), digit == 0 ? '{' : (char) ('A'+digit-1)}) {
                assertEquals(BigDecimal.valueOf(digit), ZonedDecimal.decode(ascii(""+c), 0, 1, 0, true));
            }
            for (char c : new char[]{(char) ('p'+digit), digit == 0 ? '}' : (char) ('J'+digit-1)}) {
                assertEquals(BigDecimal.valueOf(-digit), ZonedDecimal.decode(ascii(""+c), 0, 1, 0, true));
            }
        }
        ZonedDecimal.encode(BigDecimal.ZERO, buf, 0, 5, 2, false);
        assertArrayEquals(ascii("00000"), buf);
        assertEquals(new BigDecimal("0.00"), ZonedDecimal.decode(buf, 0, 5, 2, false));
        assertEquals(5, ZonedDecimal.length(5));
    }

    @Test void strictErrors() {
        for (String raw : new String[]{"  ", "1:", "p1", "1Z"}) {
            assertThrows(CobolDataException.class, () -> ZonedDecimal.decode(ascii(raw), 0, 2, 0, true));
        }
        assertThrows(CobolDataException.class, () -> ZonedDecimal.decode(ascii("1p"), 0, 2, 0, false));
        for (String value : new String[]{"100", "-1", "1.001"}) {
            assertThrows(CobolDataException.class, () -> ZonedDecimal.encode(new BigDecimal(value), new byte[2], 0, 2, 0, false));
        }
        assertThrows(CobolDataException.class, () -> ZonedDecimal.decode(new byte[0], 0, 1, 0, true));
        assertThrows(CobolDataException.class, () -> ZonedDecimal.decode(new byte[1], 0, 1, 0, true, null));
        assertThrows(CobolDataException.class, () -> ZonedDecimal.encode(BigDecimal.ZERO, new byte[1], 0, 1, 0, true, null));
        assertThrows(CobolDataException.class, () -> ZonedDecimal.length(0));
    }
}
