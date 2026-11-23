package com.acas.isam.codec;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class CobolDateTest {
    @Test void anchorsAndRoundTrips() {
        assertNull(CobolDate.decode(0));
        assertEquals(0, CobolDate.encode(null));
        assertEquals(LocalDate.of(1601,1,1), CobolDate.decode(1));
        assertEquals(1, CobolDate.encode(LocalDate.of(1601,1,1)));
        // 425 years: 425*365 + 103 leap days, then one-based day 1.
        assertEquals(LocalDate.of(2026,1,1), CobolDate.decode(155229));
        assertEquals(155229, CobolDate.encode(LocalDate.of(2026,1,1)));
        for (LocalDate date : new LocalDate[]{LocalDate.of(2000,2,29),LocalDate.of(9999,12,31)}) {
            assertEquals(date, CobolDate.decode(CobolDate.encode(date)));
        }
    }

    @Test void rejectsOutOfRange() {
        assertThrows(CobolDataException.class, () -> CobolDate.decode(-1));
        assertThrows(CobolDataException.class, () -> CobolDate.decode(CobolDate.encode(LocalDate.of(9999,12,31)) + 1));
        assertThrows(CobolDataException.class, () -> CobolDate.encode(LocalDate.of(1600,12,31)));
        assertThrows(CobolDataException.class, () -> CobolDate.encode(LocalDate.of(10000,1,1)));
    }
}
