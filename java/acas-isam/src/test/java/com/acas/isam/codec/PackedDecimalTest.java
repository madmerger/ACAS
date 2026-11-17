package com.acas.isam.codec;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class PackedDecimalTest {
    @Test void vectorsAndSigns() {
        byte[] buf = new byte[6];
        PackedDecimal.encode(new BigDecimal("-123.45"), buf, 1, 7, 2, true);
        assertArrayEquals(new byte[]{0, 0, 0x12, 0x34, 0x5D, 0}, buf);
        assertEquals(new BigDecimal("-123.45"), PackedDecimal.decode(buf, 1, 7, 2, true));
        for (int sign : new int[]{0xA, 0xC, 0xE, 0xF, 0xB, 0xD}) {
            assertEquals(new BigDecimal(sign == 0xB || sign == 0xD ? "-1" : "1"),
                    PackedDecimal.decode(new byte[]{(byte) (0x10 | sign)}, 0, 1, 0, true));
        }
        byte[] even = new byte[2];
        PackedDecimal.encode(new BigDecimal("99"), even, 0, 2, 0, false);
        assertArrayEquals(new byte[]{9, (byte) 0x9F}, even);
        assertEquals(new BigDecimal("99"), PackedDecimal.decode(even, 0, 2, 0, false));
        assertEquals(BigDecimal.ONE, PackedDecimal.decode(new byte[]{0x1C}, 0, 1, 0, false));
        PackedDecimal.encode(BigDecimal.ZERO, even, 0, 2, 0, true);
        assertArrayEquals(new byte[]{0, 0x0C}, even);
    }

    @Test void rejectsInvalidData() {
        for (byte b : new byte[]{0x10, (byte) 0xAC}) {
            assertThrows(CobolDataException.class, () -> PackedDecimal.decode(new byte[]{b}, 0, 1, 0, true));
        }
        assertThrows(CobolDataException.class, () -> PackedDecimal.decode(new byte[]{0x1D}, 0, 1, 0, false));
        assertThrows(CobolDataException.class, () -> PackedDecimal.decode(new byte[]{0x10, 0x1C}, 0, 2, 0, true));
        for (String value : new String[]{"100", "1.001", "-1"}) {
            assertThrows(CobolDataException.class, () -> PackedDecimal.encode(new BigDecimal(value), new byte[2], 0, 2, 0, false));
        }
        assertThrows(CobolDataException.class, () -> PackedDecimal.decode(new byte[0], 0, 1, 0, true));
        assertThrows(CobolDataException.class, () -> PackedDecimal.decode(null, 0, 1, 0, true));
        assertThrows(CobolDataException.class, () -> PackedDecimal.decode(new byte[2], -1, 1, 0, true));
        assertThrows(CobolDataException.class, () -> PackedDecimal.length(0));
        assertThrows(CobolDataException.class, () -> PackedDecimal.decode(new byte[2], 0, 1, 2, true));
        assertThrows(CobolDataException.class, () -> PackedDecimal.encode(null, new byte[2], 0, 1, 0, true));
    }
}
