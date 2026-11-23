package jp.co.acas.gl;

import static org.junit.jupiter.api.Assertions.*;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import jp.co.acas.core.CobFile;
import jp.co.acas.core.Ctx;
import jp.co.acas.core.StopRun;
import jp.co.acas.core.Store;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

class Gl100Test {
    private static Ctx ctx(String db) throws Exception {
        Store store = new Store(new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:" + db + ";DB_CLOSE_DELAY=-1")));
        Method init = Store.class.getDeclaredMethod("init");
        init.setAccessible(true);
        init.invoke(store);
        return new Ctx(store, java.time.LocalDate.of(2026, 11, 23));
    }

    private static String rec(int batch, int post, int ac, int pc) {
        return String.format("%05d%05dDR23/11/26%06d%02d0000001000%-32s%06d%02d", batch, post, ac, pc, "legend", 0, 0);
    }

    private static AtomicReference<Throwable> start(Gl100 p, Ctx c) {
        AtomicReference<Throwable> err = new AtomicReference<>();
        Thread t = new Thread(() -> {
            try { p.run(); } catch (Throwable e) { err.set(e); } finally { c.term.end(""); }
        });
        t.setDaemon(true);
        t.start();
        return err;
    }

    @Test
    void 区切り文字が渡されれば保管仕訳を勘定_PC_バッチ_仕訳番号順に整列する() throws Exception {
        Ctx c = ctx("gl100a");
        CobFile arc = CobFile.lineSequential(c.store, c.path("archives/archive.dat"));
        arc.open(CobFile.Mode.OUTPUT);
        List<String> in = List.of(rec(2, 1, 200000, 0), rec(1, 2, 100000, 1), rec(1, 1, 100000, 1), rec(3, 1, 100000, 0));
        for (String r : in) arc.writeLine(r);
        arc.close();
        Gl100 p = new Gl100() {{ ctx = c; fileDefsOsDelimiter = "/"; }};
        AtomicReference<Throwable> err = start(p, c);
        c.term.awaitIdle(5000);
        assertTrue(c.term.text(false).contains("GL115 Ensure Archive USB Memory Stick is in path"));
        c.term.feed(List.of("0", "ENTER"), 5000);
        assertTrue(c.term.text(false).contains("archives/archive.dat"));
        c.term.feed(List.of("ENTER"), 5000);
        assertNull(err.get());
        assertTrue(c.term.isEnded());
        CobFile out = CobFile.lineSequential(c.store, c.path("archives/workarc.tmp"));
        assertEquals("00", out.open(CobFile.Mode.INPUT));
        List<String> got = new ArrayList<>();
        for (String l = out.readLine(); l != null; l = out.readLine()) got.add(l.substring(0, 10) + l.substring(20, 28));
        assertEquals(List.of("000030000110000000", "000010000110000001", "000010000210000001", "000020000120000000"), got);
    }

    @Test
    void 保管ファイルが無ければ終了コード4() throws Exception {
        Ctx c = ctx("gl100b");
        Gl100 p = new Gl100() {{ ctx = c; fileDefsOsDelimiter = "/"; }};
        AtomicReference<Throwable> err = start(p, c);
        c.term.awaitIdle(5000);
        c.term.feed(List.of("0", "ENTER"), 5000);
        c.term.feed(List.of("ENTER"), 5000);
        assertNull(err.get());
        assertEquals(4, GlCommon.termCode(c));
    }

    @Test
    void 中止9で終了コード5() throws Exception {
        Ctx c = ctx("gl100c");
        Gl100 p = new Gl100() {{ ctx = c; fileDefsOsDelimiter = "/"; }};
        AtomicReference<Throwable> err = start(p, c);
        c.term.awaitIdle(5000);
        c.term.feed(List.of("9", "ENTER"), 5000);
        assertNull(err.get());
        assertEquals(5, GlCommon.termCode(c));
    }

    @Test
    void レガシー同様に区切り文字がNULLなら見出し直後に異常終了する() throws Exception {
        Ctx c = ctx("gl100d");
        Gl100 p = new Gl100() {{ ctx = c; }};
        AtomicReference<Throwable> err = start(p, c);
        c.term.awaitIdle(5000);
        String s = c.term.text(false);
        assertTrue(s.contains("Ledger Print - Sort") && s.contains("end of program, please press a key to exit"));
        assertFalse(s.contains("GL115"));
        c.term.feed(List.of("ENTER"), 5000);
        assertInstanceOf(StopRun.class, err.get());
    }
}
