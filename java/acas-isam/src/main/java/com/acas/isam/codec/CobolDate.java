package com.acas.isam.codec;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

public final class CobolDate {
    private static final LocalDate EPOCH = LocalDate.of(1600, 12, 31);
    private static final LocalDate MAX = LocalDate.of(9999, 12, 31);
    private static final int MAX_INTEGER = (int) ChronoUnit.DAYS.between(EPOCH, MAX);

    private CobolDate() {}

    public static LocalDate decode(int value) {
        if (value < 0 || value > MAX_INTEGER) {
            throw CodecSupport.error(0, value);
        }
        return value == 0 ? null : EPOCH.plusDays(value);
    }

    public static int encode(LocalDate value) {
        if (value == null) {
            return 0;
        }
        if (!value.isAfter(EPOCH) || value.isAfter(MAX)) {
            throw CodecSupport.error(0, value);
        }
        return (int) ChronoUnit.DAYS.between(EPOCH, value);
    }
}
