package jp.co.acas.st;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Ctx;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Store;
import jp.co.acas.sys.SystemFile;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** st020 の在庫金額・平均原価計算（レガシー実測 ST-400 と丸め規則）。 */
class St020Test {
    private static BigDecimal bd(String s) { return new BigDecimal(s); }

    @Test
    void 入力画面が次ページに進んだ直後に終了しても入庫帳票が残る() throws Exception {
        var jdbc = new JdbcTemplate(new DriverManagerDataSource(
                "jdbc:h2:mem:stock-entry-pages;DB_CLOSE_DELAY=-1"));
        Store store = new Store(jdbc);
        var init = Store.class.getDeclaredMethod("init");
        init.setAccessible(true);
        init.invoke(store);
        Ctx ctx = new Ctx(store, LocalDate.of(2026, 11, 23));
        ctx.shared.put("to-day", "23/11/2026");
        var sys = SystemFile.shared(ctx);
        sys.setNum("file-status", 1, 11);
        sys.setNum("stk-averaging", 1);
        sys.setNum("date-form", 1);
        sys.setNum("page-lines", 60);
        var item = St.fdRec(Layout.of("copybooks/fdstock.cob", "Stock-Record"));
        St.initialize(item);
        item.set("stock-key", "ITEM001");
        item.set("stock-abrev-key", "ITM001");
        var stock = St.stockFile(ctx, item);
        assertEquals("00", stock.open(CobFile.Mode.OUTPUT));
        assertEquals("00", stock.write(item));
        stock.close();
        CompletableFuture<Void> entry = CompletableFuture.runAsync(() -> {
            try {
                ctx.call("st020");
            } finally {
                ctx.term.end("");
            }
        });
        ctx.term.awaitIdle(2000);
        ctx.term.feed(List.of("1"), 2000);
        List<String> line = List.of("I", "T", "M", "0", "0", "1", "ENTER",
                "0", "0", "0", "0", "0", "2", " ", "ENTER",
                "0", "0", "0", "0", "0", "5", ".", "0", "0", "ENTER");
        for (int i = 0; i < 18; i++) {
            ctx.term.feed(line, 2000);
        }
        ctx.term.feed(List.of("ESC", "9"), 2000);
        entry.get(3, TimeUnit.SECONDS);
        long details = store.all("spool/0001/prt-1").stream()
                .map(record -> new String(record.getValue(), StandardCharsets.ISO_8859_1))
                .filter(text -> text.contains("ITEM001"))
                .count();
        assertEquals(18, details);
    }

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
