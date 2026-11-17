package com.acas.isam.codec;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.util.Arrays;

public final class BigEndianBinary {
    private BigEndianBinary() {}

    public static int length(int digits) {
        if (digits < 1 || digits > 18) {
            throw CodecSupport.error(0, "binary PIC digits " + digits);
        }
        return digits <= 2 ? 1 : digits <= 4 ? 2 : digits <= 9 ? 4 : 8;
    }

    public static BigDecimal decode(byte[] buf, int offset, int digits, int scale, boolean signed) {
        CodecSupport.pic(digits, scale);
        int size = length(digits);
        CodecSupport.bounds(buf, offset, size);
        byte[] bytes = Arrays.copyOfRange(buf, offset, offset + size);
        BigInteger n = signed ? new BigInteger(bytes) : new BigInteger(1, bytes);
        return CodecSupport.decoded(n, digits, scale, signed, offset);
    }

    public static long decode(byte[] buf, int offset, int digits, boolean signed) {
        return decode(buf, offset, digits, 0, signed).longValueExact();
    }

    public static void encode(BigDecimal value, byte[] buf, int offset, int digits, int scale, boolean signed) {
        BigInteger n = CodecSupport.unscaled(value, digits, scale, signed, offset);
        int size = length(digits);
        CodecSupport.bounds(buf, offset, size);
        for (int i = size - 1; i >= 0; i--) {
            buf[offset + i] = n.byteValue();
            n = n.shiftRight(8);
        }
    }

    public static void encode(long value, byte[] buf, int offset, int digits, boolean signed) {
        encode(BigDecimal.valueOf(value), buf, offset, digits, 0, signed);
    }
}
