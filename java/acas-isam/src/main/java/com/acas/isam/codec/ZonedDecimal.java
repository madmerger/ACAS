package com.acas.isam.codec;

import java.math.BigDecimal;
import java.math.BigInteger;

public final class ZonedDecimal {
    public enum SignPosition { TRAILING, LEADING }

    private ZonedDecimal() {}

    public static int length(int digits) {
        CodecSupport.pic(digits, 0);
        return digits;
    }

    public static BigDecimal decode(byte[] buf, int offset, int digits, int scale, boolean signed) {
        return decode(buf, offset, digits, scale, signed, SignPosition.TRAILING);
    }

    public static BigDecimal decode(byte[] buf, int offset, int digits, int scale, boolean signed,
                                    SignPosition position) {
        CodecSupport.pic(digits, scale);
        CodecSupport.bounds(buf, offset, digits);
        if (position == null) {
            throw CodecSupport.error(offset, "null sign position");
        }
        int signIndex = position == SignPosition.LEADING ? 0 : digits - 1;
        boolean negative = false;
        StringBuilder number = new StringBuilder();
        for (int i = 0; i < digits; i++) {
            int c = buf[offset + i] & 255;
            int digit = c - '0';
            if (signed && i == signIndex && (digit < 0 || digit > 9)) {
                if (c >= 'p' && c <= 'y') {
                    digit = c - 'p';
                    negative = true;
                } else if (c == '{' || (c >= 'A' && c <= 'I')) {
                    digit = c == '{' ? 0 : c - 'A' + 1;
                } else if (c == '}' || (c >= 'J' && c <= 'R')) {
                    digit = c == '}' ? 0 : c - 'J' + 1;
                    negative = true;
                }
            }
            if (digit < 0 || digit > 9) {
                throw CodecSupport.error(offset + i, "display byte " + c);
            }
            number.append(digit);
        }
        BigInteger n = new BigInteger(number.toString());
        return new BigDecimal(negative ? n.negate() : n, scale);
    }

    public static void encode(BigDecimal value, byte[] buf, int offset, int digits, int scale, boolean signed) {
        encode(value, buf, offset, digits, scale, signed, SignPosition.TRAILING);
    }

    public static void encode(BigDecimal value, byte[] buf, int offset, int digits, int scale, boolean signed,
                              SignPosition position) {
        BigInteger n = CodecSupport.unscaled(value, digits, scale, signed, offset);
        CodecSupport.bounds(buf, offset, digits);
        if (position == null) {
            throw CodecSupport.error(offset, "null sign position");
        }
        String raw = n.abs().toString();
        String number = "0".repeat(digits - raw.length()) + raw;
        int signIndex = position == SignPosition.LEADING ? 0 : digits - 1;
        for (int i = 0; i < digits; i++) {
            int digit = number.charAt(i) - '0';
            buf[offset + i] = (byte) ((signed && n.signum() < 0 && i == signIndex ? 'p' : '0') + digit);
        }
    }
}
