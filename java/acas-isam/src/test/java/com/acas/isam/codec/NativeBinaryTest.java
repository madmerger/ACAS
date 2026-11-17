package com.acas.isam.codec;

import java.nio.ByteOrder;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class NativeBinaryTest {
    @Test void vectorsAndRoundTrips() {
        byte[] bytes = new byte[6];
        NativeBinary.encode(0x12345678, bytes, 1, 4, true);
        assertArrayEquals(new byte[]{0,0x78,0x56,0x34,0x12,0}, bytes);
        assertEquals(0x12345678, NativeBinary.decode(bytes, 1, 4, true));
        NativeBinary.encode(0x12345678, bytes, 1, 4, true, ByteOrder.BIG_ENDIAN);
        assertArrayEquals(new byte[]{0,0x12,0x34,0x56,0x78,0}, bytes);
        for (ByteOrder order : new ByteOrder[]{ByteOrder.LITTLE_ENDIAN, ByteOrder.BIG_ENDIAN}) {
            for (int size : new int[]{1,2,4,8}) {
                for (boolean signed : new boolean[]{true,false}) {
                    if (size == 8 && !signed) continue;
                    long max = size == 8 ? Long.MAX_VALUE : (1L << (size * 8 - (signed ? 1 : 0))) - 1;
                    long min = !signed ? 0 : size == 8 ? Long.MIN_VALUE : -(1L << (size * 8 - 1));
                    for (long value : new long[]{min,0,max}) {
                        byte[] buf = new byte[size];
                        NativeBinary.encode(value, buf, 0, size, signed, order);
                        assertEquals(value, NativeBinary.decode(buf, 0, size, signed, order));
                    }
                }
            }
        }
    }

    @Test void errors() {
        for (long value : new long[]{-129,128}) {
            assertThrows(CobolDataException.class, () -> NativeBinary.encode(value, new byte[1], 0, 1, true));
        }
        for (long value : new long[]{-1,256}) {
            assertThrows(CobolDataException.class, () -> NativeBinary.encode(value, new byte[1], 0, 1, false));
        }
        assertThrows(CobolDataException.class, () -> NativeBinary.decode(new byte[8], 0, 8, false));
        assertThrows(CobolDataException.class, () -> NativeBinary.decode(new byte[8], 0, 3, true));
        assertThrows(CobolDataException.class, () -> NativeBinary.decode(new byte[8], 0, 4, true, null));
        assertThrows(CobolDataException.class, () -> NativeBinary.decode(new byte[0], 0, 1, true));
        assertThrows(CobolDataException.class, () -> NativeBinary.encode(1, new byte[1], -1, 1, true));
    }
}
