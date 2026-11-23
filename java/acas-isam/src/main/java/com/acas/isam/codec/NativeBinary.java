package com.acas.isam.codec;

import java.nio.ByteOrder;

public final class NativeBinary {
    private NativeBinary() {}

    private static void validate(byte[] buf, int offset, int size, boolean signed, ByteOrder order) {
        if ((size != 1 && size != 2 && size != 4 && size != 8) || (size == 8 && !signed) || order == null) {
            throw CodecSupport.error(offset, "native size/sign/order " + size + "/" + signed + "/" + order);
        }
        CodecSupport.bounds(buf, offset, size);
    }

    public static long decode(byte[] buf, int offset, int size, boolean signed, ByteOrder order) {
        validate(buf, offset, size, signed, order);
        long n = 0;
        for (int i = 0; i < size; i++) {
            int index = order == ByteOrder.BIG_ENDIAN ? i : size - 1 - i;
            n = (n << 8) | (buf[offset + index] & 255L);
        }
        return signed && size < 8 ? (n << (64 - size * 8)) >> (64 - size * 8) : n;
    }

    public static long decode(byte[] buf, int offset, int size, boolean signed) {
        return decode(buf, offset, size, signed, ByteOrder.LITTLE_ENDIAN);
    }

    public static void encode(long value, byte[] buf, int offset, int size, boolean signed, ByteOrder order) {
        validate(buf, offset, size, signed, order);
        if (size < 8) {
            long min = signed ? -(1L << (size * 8 - 1)) : 0;
            long max = (1L << (size * 8 - (signed ? 1 : 0))) - 1;
            if (value < min || value > max) {
                throw CodecSupport.error(offset, value);
            }
        }
        for (int i = 0; i < size; i++) {
            int index = order == ByteOrder.LITTLE_ENDIAN ? i : size - 1 - i;
            buf[offset + index] = (byte) (value >> (8 * i));
        }
    }

    public static void encode(long value, byte[] buf, int offset, int size, boolean signed) {
        encode(value, buf, offset, size, signed, ByteOrder.LITTLE_ENDIAN);
    }
}
