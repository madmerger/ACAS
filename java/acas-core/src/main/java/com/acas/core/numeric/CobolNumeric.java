package com.acas.core.numeric;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Objects;

public final class CobolNumeric {
    private CobolNumeric() {}

    public static BigDecimal truncateHigh(BigDecimal value, int intDigits) {
        Objects.requireNonNull(value, "value");
        if (intDigits < 0) {
            throw new IllegalArgumentException("Invalid integer digits: " + intDigits);
        }
        return value.remainder(BigDecimal.TEN.pow(intDigits));
    }

    public static BigDecimal store(BigDecimal value, int intDigits, int scale, boolean signed, boolean rounded) {
        if (scale < 0) {
            throw new IllegalArgumentException("Invalid scale: " + scale);
        }
        BigDecimal result = truncateHigh(value.setScale(scale,
                rounded ? RoundingMode.HALF_UP : RoundingMode.DOWN), intDigits);
        return signed ? result : result.abs();
    }
}
