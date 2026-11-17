package com.acas.isam.codec;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class BigEndianBinaryTest {
    @Test void vectorsAndSizes() {
        assertArrayEquals(new int[]{1,1,2,2,4,4,8,8},
                java.util.stream.IntStream.of(1,2,3,4,5,9,10,18).map(BigEndianBinary::length).toArray());
        byte[] buf = new byte[4];
        BigEndianBinary.encode(new BigDecimal("-12.34"), buf, 1, 4, 2, true);
        assertArrayEquals(new byte[]{0, (byte) 0xFB, (byte) 0x2E, 0}, buf);
        assertEquals(new BigDecimal("-12.34"), BigEndianBinary.decode(buf, 1, 4, 2, true));
        for (int digits : new int[]{2,4,9,18}) {
            for (boolean signed : new boolean[]{false,true}) {
                long max = java.math.BigInteger.TEN.pow(digits).longValueExact() - 1;
                for (long value : new long[]{0, max, signed ? -max : 1}) {
                    byte[] bytes = new byte[BigEndianBinary.length(digits)];
                    BigEndianBinary.encode(value, bytes, 0, digits, signed);
                    assertEquals(value, BigEndianBinary.decode(bytes, 0, digits, signed));
                }
            }
        }
    }

    @Test void strictErrors() {
        assertThrows(CobolDataException.class, () -> BigEndianBinary.decode(new byte[]{100}, 0, 2, true));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.decode(new byte[]{(byte) 255}, 0, 2, false));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.encode(-1, new byte[1], 0, 2, false));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.encode(new BigDecimal("1.001"), new byte[2], 0, 4, 2, true));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.encode(100, new byte[1], 0, 2, true));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.length(19));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.length(0));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.decode(new byte[0], 0, 2, true));
        assertThrows(CobolDataException.class, () -> BigEndianBinary.encode(1, new byte[1], Integer.MAX_VALUE, 2, true));
    }
}
