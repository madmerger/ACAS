package jp.co.acas.st;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** st020 の在庫金額・平均原価計算（レガシー実測 ST-400 と丸め規則）。 */
class St020Test {
    private static BigDecimal bd(String s) { return new BigDecimal(s); }

    @Test
    void 入庫1件はレガシー実測ST400と同じ金額と平均原価になる() {
        // ITEM001: 在庫 10・原価 5.0000 に 数量 2・単価 5.00 を入庫 → 在庫金額 60.00・平均原価 5.0000
        BigDecimal old = St020.oldValue(10, 0, bd("5.0000"));
        BigDecimal value = St020.movementValue(2, bd("5.00"));
        BigDecimal nv = St020.newValue(value, old);
        assertEquals(bd("50.00"), old);
        assertEquals(bd("10.00"), value);
        assertEquals(bd("60.00"), nv);
        assertEquals(bd("5.0000"), St020.averageCost(nv, 12, BigDecimal.ZERO));
    }

    @Test
    void 平均原価は小数4桁へ四捨五入する() {
        assertEquals(bd("3.3333"), St020.averageCost(bd("10.00"), 3, BigDecimal.ZERO));
        assertEquals(bd("6.6667"), St020.averageCost(bd("20.00"), 3, BigDecimal.ZERO));
        assertEquals(bd("-6.6667"), St020.averageCost(bd("-20.00"), 3, BigDecimal.ZERO));
    }

    @Test
    void 数量0は除算せず直前の原価を保持する() {
        assertEquals(bd("7.5000"), St020.averageCost(bd("10.00"), 0, bd("7.5000")));
    }

    @Test
    void 旧在庫金額は仕掛数量を含み小数2桁へ切り捨てる() {
        assertEquals(bd("37.03"), St020.oldValue(2, 1, bd("12.3456")));
        assertEquals(BigDecimal.ZERO, St020.oldValue(0, 0, bd("12.3456")));
    }

    @Test
    void 在庫金額の桁あふれは上限値になる() {
        assertEquals(St020.MAX_VALUE, St020.newValue(bd("99999999.99"), bd("0.01")));
        assertEquals(bd("-10.00"), St020.movementValue(-2, bd("5.00")));
    }
}
