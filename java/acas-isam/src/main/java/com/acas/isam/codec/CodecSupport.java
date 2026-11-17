package com.acas.isam.codec;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.math.RoundingMode;

final class CodecSupport {
    private CodecSupport() {}

    static CobolDataException error(int offset, Object value) {
        return new CobolDataException("Invalid COBOL data at offset " + offset + ": " + value);
    }

    static void bounds(byte[] buf, int offset, int length) {
        if (buf == null || offset < 0 || length < 0 || offset > buf.length - length) {
            throw error(offset, "buffer length " + (buf == null ? "null" : buf.length));
        }
    }

    static void pic(int digits, int scale) {
        if (digits < 1 || scale < 0 || scale > digits) {
            throw error(0, "PIC digits=" + digits + ", scale=" + scale);
        }
    }

    static BigInteger unscaled(BigDecimal value, int digits, int scale, boolean signed, int offset) {
        pic(digits, scale);
        if (value == null) {
            throw error(offset, "null value");
        }
        try {
            BigInteger n = value.setScale(scale, RoundingMode.UNNECESSARY).unscaledValue();
            if ((!signed && n.signum() < 0) || n.abs().toString().length() > digits) {
                throw error(offset, value);
            }
            return n;
        } catch (ArithmeticException ex) {
            throw error(offset, value);
        }
    }

    static BigDecimal decoded(BigInteger n, int digits, int scale, boolean signed, int offset) {
        BigDecimal value = new BigDecimal(n, scale);
        unscaled(value, digits, scale, signed, offset);
        return value;
    }
}
