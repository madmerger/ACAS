package jp.co.acas.pl;

import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

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

    private static Rec purch(PlSession s) {
        return s.records("purchled.dat", PlBase::purchRec).stream().filter(r -> r.str("purch-key").equals("SUPP018")).findFirst().orElseThrow();
    }

    /** 画面から請求（税込 120.00）と、それを指定した貸方票（税込 36.00）を入力し、メニュー H で転記する。 */
    @Test
    void 貸方票の転記で元請求と貸方票の両方に充当額が反映される() throws Exception {
        PlSession s = new PlSession("pl060cr", "sl-ready");
        BigDecimal before = purch(s).num("purch-current");
        s.keys("D").keys("\rSUPP018\rPL-ORDER\rPL-REF\r2\r").keys("a1\r0000100.00\r1\r000020.00\r  \r").keys("\r\r\r\rY\rY\rN\r");
        s.assertMenu();
        s.keys("D").keys("\rSUPP018\rCN-ORDER\rCN-REF\r3\r").keys("00000001\r").keys("a1\r0000030.00\r1\r000006.00\r  \r").keys("\r\rY\rY\rN\r");
        s.assertMenu();
        s.keys("H");
        assertTrue(s.screen().contains("OK to post Purchase Transactions"), s::screen);
        s.keys("YES\r");
        s.assertMenu();

        List<Rec> items = s.records("openitm5.dat", PlBase::oiRec);
        assertEquals(2, items.size());
        Rec inv = items.stream().filter(r -> r.longv("oi-invoice") == 1).findFirst().orElseThrow();
        Rec cr = items.stream().filter(r -> r.longv("oi-invoice") == 2).findFirst().orElseThrow();
        assertEquals(2, inv.intv("oi-type"));
        assertEquals(new BigDecimal("36.00"), inv.num("oi-paid"));
        assertEquals(new BigDecimal("36.00"), inv.num("oi-p-c"));
        assertEquals(0, inv.intv("oi-status"));
        assertEquals(3, cr.intv("oi-type"));
        assertEquals(1, cr.longv("oi-cr"));
        assertEquals(new BigDecimal("-30.00"), cr.num("oi-net"));
        assertEquals(new BigDecimal("-6.00"), cr.num("oi-vat"));
        assertEquals(new BigDecimal("36.00"), cr.num("oi-paid"));
        assertEquals(1, cr.intv("oi-status"));
        assertEquals(before.add(new BigDecimal("84.00")), purch(s).num("purch-current"));
        assertEquals(0, s.ctx.store.count(s.ctx.path("openitm4.dat")));
    }
}
