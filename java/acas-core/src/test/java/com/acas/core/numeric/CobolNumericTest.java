package com.acas.core.numeric;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class CobolNumericTest {
    @Test void truncation() {
        assertEquals(new BigDecimal("345.67"), CobolNumeric.truncateHigh(new BigDecimal("12345.67"), 3));
        assertEquals(new BigDecimal("-345"), CobolNumeric.truncateHigh(new BigDecimal("-12345"), 3));
        assertEquals(new BigDecimal("-0.67"), CobolNumeric.truncateHigh(new BigDecimal("-123.67"), 0));
        assertEquals(BigDecimal.ZERO, CobolNumeric.truncateHigh(BigDecimal.ZERO, 2));
    }

    @Test void assignment() {
        assertEquals(new BigDecimal("-1.23"), CobolNumeric.store(new BigDecimal("-1.239"), 2, 2, true, false));
        assertEquals(new BigDecimal("-1.24"), CobolNumeric.store(new BigDecimal("-1.235"), 2, 2, true, true));
        assertEquals(new BigDecimal("1.24"), CobolNumeric.store(new BigDecimal("1.235"), 2, 2, true, true));
        assertEquals(new BigDecimal("0.00"), CobolNumeric.store(new BigDecimal("999.995"), 3, 2, true, true));
        assertEquals(new BigDecimal("345.67"), CobolNumeric.store(new BigDecimal("-12345.679"), 3, 2, false, false));
        assertEquals(new BigDecimal("0.00"), CobolNumeric.store(BigDecimal.ZERO, 0, 2, false, true));
    }

    @Test void invalidArguments() {
        assertThrows(IllegalArgumentException.class, () -> CobolNumeric.truncateHigh(BigDecimal.ONE, -1));
        assertThrows(IllegalArgumentException.class, () -> CobolNumeric.store(BigDecimal.ONE, 1, -1, true, false));
        assertThrows(NullPointerException.class, () -> CobolNumeric.truncateHigh(null, 1));
    }
}
