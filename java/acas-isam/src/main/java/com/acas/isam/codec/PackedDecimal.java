package com.acas.isam.codec;

import java.math.BigDecimal;
import java.math.BigInteger;

public final class PackedDecimal {
    private PackedDecimal() {}

    public static int length(int digits) {
        CodecSupport.pic(digits, 0);
        return digits / 2 + 1;
    }

    public static BigDecimal decode(byte[] buf, int offset, int digits, int scale, boolean signed) {
        CodecSupport.pic(digits, scale);
        int size = length(digits);
        CodecSupport.bounds(buf, offset, size);
        int sign = buf[offset + size - 1] & 15;
        boolean negative = sign == 0xD || sign == 0xB;
        if (signed ? !(negative || sign == 0xC || sign == 0xA || sign == 0xE || sign == 0xF)
                : !(sign == 0xF || sign == 0xC)) {
            throw CodecSupport.error(offset, "sign nibble " + sign);
        }
        StringBuilder number = new StringBuilder();
        int padding = size * 2 - 1 - digits;
        for (int i = 0; i < size * 2 - 1; i++) {
            int digit = (buf[offset + i / 2] >> (i % 2 == 0 ? 4 : 0)) & 15;
            if (digit > 9 || (i < padding && digit != 0)) {
                throw CodecSupport.error(offset, "digit nibble " + digit);
            }
            number.append(digit);
        }
        BigInteger n = new BigInteger(number.toString());
        return CodecSupport.decoded(negative ? n.negate() : n, digits, scale, signed, offset);
    }

    public static void encode(BigDecimal value, byte[] buf, int offset, int digits, int scale, boolean signed) {
        BigInteger n = CodecSupport.unscaled(value, digits, scale, signed, offset);
        int size = length(digits);
        CodecSupport.bounds(buf, offset, size);
        String raw = n.abs().toString();
        String packed = "0".repeat(size * 2 - 1 - raw.length()) + raw
                + (signed ? (n.signum() < 0 ? "D" : "C") : "F");
        for (int i = 0; i < size; i++) {
            buf[offset + i] = (byte) Integer.parseInt(packed.substring(i * 2, i * 2 + 2), 16);
        }
    }
}
