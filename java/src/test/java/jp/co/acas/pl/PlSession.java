package jp.co.acas.pl;

import jp.co.acas.core.Ctx;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Store;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** 業務メニュー（acas → 買掛元帳）を画面キー入力だけで操作する試験用セッション。 */
final class PlSession {
    final Ctx ctx;
    private final AtomicReference<Throwable> error = new AtomicReference<>();

    PlSession(String db, String baseline) throws Exception {
        Store store = new Store(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + db + ";DB_CLOSE_DELAY=-1")));
        Method init = Store.class.getDeclaredMethod("init");
        init.setAccessible(true);
        init.invoke(store);
        store.loadBaseline(baseline);
        ctx = new Ctx(store, java.time.LocalDate.of(2026, 11, 23));
        Thread t = new Thread(() -> {
            try { ctx.call("acas"); } catch (Throwable e) { error.set(e); } finally { ctx.term.end(""); }
        });
        t.setDaemon(true);
        t.start();
        ctx.term.awaitIdle(10000);
        keys("C\r");
        assertMenu();
    }

    /** 画面への打鍵（\r は Enter）。 */
    PlSession keys(String s) {
        List<String> ks = new ArrayList<>();
        for (char ch : s.toCharArray()) ks.add(ch == '\r' ? "ENTER" : String.valueOf(ch));
        ctx.term.feed(ks, 10000);
        assertNull(error.get(), () -> "業務処理が異常終了: " + error.get());
        return this;
    }

    String screen() { return ctx.term.text(false); }

    void assertMenu() {
        assertNull(error.get(), () -> "業務処理が異常終了: " + error.get());
        assertTrue(screen().contains("Purchase Ledger System Menu"), this::screen);
    }

    List<Rec> records(String file, Supplier<Rec> rec) {
        List<Rec> out = new ArrayList<>();
        for (Map.Entry<byte[], byte[]> e : ctx.store.all(ctx.path(file))) {
            Rec r = rec.get();
            System.arraycopy(e.getValue(), 0, r.bytes(), 0, Math.min(e.getValue().length, r.bytes().length));
            out.add(r);
        }
        return out;
    }

    static String key(Map.Entry<byte[], byte[]> e) { return new String(e.getKey(), StandardCharsets.ISO_8859_1); }
}
