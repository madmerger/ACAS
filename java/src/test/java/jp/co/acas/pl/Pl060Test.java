package jp.co.acas.pl;

import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** pl060 cr-notes: move oi-header to si-header と同じく、退避領域は wssoi の項目名で参照する。 */
class Pl060Test {
    @Test
    void 退避レコードは旧si_headerの項目で読める() {
        Rec oi = Layout.of("purchase/wsoi.cob", "oi-header").newRec();
        Rec si = Layout.of("purchase/wssoi.cob", "si-header").newRec();
        assertEquals(oi.bytes().length, si.bytes().length);
        oi.set("oi-supplier", "ALPHA01");
        oi.setNum("oi-cr", 1234);
        System.arraycopy(oi.bytes(), 0, si.bytes(), 0, oi.bytes().length);
        assertEquals("ALPHA01", si.str("si-supplier"));
        assertEquals(1234, si.longv("si-cr"));
        si.add("si-paid", new BigDecimal("1.50"));
        assertEquals(new BigDecimal("1.50"), si.num("si-paid"));
    }
}
