package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.SystemFile;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** 請求入力（pl020）・修正（pl030）で明細 39 行／40 行（occurs 40 の上限）を保存する。 */
class Pl020LinesTest {
    private static final String HEADER = "\rSUPP018\rPL-ORDER\rPL-REF\r2\r";
    private static final String TOTALS = "\r\r\r\rY\rY\rN\r";

    /** n 行目は税抜 n.00・VAT コード 1（税額は既定の計算値）。1 行目だけ分析コード a1 を入力し、以降は前行の値を引き継ぐ。 */
    static String line(int n) {
        return (n == 1 ? "a1" : "") + "\r" + String.format("%07d.00", n) + "\r1\r\r";
    }

    static String newLines(int count) {
        StringBuilder sb = new StringBuilder();
        for (int n = 1; n <= count; n++) sb.append(line(n));
        if (count < 40) sb.append("  \r");
        return sb.toString();
    }

    static PlSession entered(String db, int count) throws Exception {
        PlSession s = new PlSession(db, "sl-ready");
        s.keys("D").keys(HEADER).keys(newLines(count)).keys(TOTALS);
        s.assertMenu();
        return s;
    }

    static void assertSaved(PlSession s, int count) {
        assertSaved(s, count, count, count * (count + 1) / 2);
    }

    static void assertSaved(PlSession s, int count, int lastNet, int totalNet) {
        List<Rec> heads = s.records("pinvoice.dat", PlBase::invHeaderRec).stream().filter(r -> r.intv("ih-test") == 0).toList();
        assertEquals(1, heads.size());
        assertEquals(count, heads.get(0).intv("ih-lines"));
        assertEquals(new BigDecimal(totalNet + ".00"), heads.get(0).num("ih-net"));
        assertEquals(BigDecimal.valueOf(totalNet).multiply(new BigDecimal("0.20")), heads.get(0).num("ih-vat"));
        // 明細レコードは wspinv の invoice-line 形式で書かれる（pl020.cbl: move invoice-line (j) to invoice-record）
        List<Rec> lines = s.records("pinvoice.dat", () -> Layout.of("purchase/wspinv.cob", "Pinvoice-lines").newRec())
                .stream().filter(r -> r.intv("il-line", 1) != 0).toList();
        assertEquals(count, lines.size());
        Rec last = lines.get(lines.size() - 1);
        assertEquals(count, last.intv("il-line", 1));
        assertEquals("a1", last.str("il-pa", 1));
        assertEquals(new BigDecimal(lastNet + ".00"), last.num("il-net", 1));
        assertEquals(new BigDecimal(lastNet).multiply(new BigDecimal("0.20")).setScale(2), last.num("il-vat", 1));
    }

    @Test
    void 登録で39行を保存する() throws Exception {
        assertSaved(entered("pl020e39", 39), 39);
    }

    @Test
    void 登録で40行を保存する() throws Exception {
        assertSaved(entered("pl020e40", 40), 40);
    }

    @Test
    void 削除済みの伝票番号は正常な再登録で消費する() throws Exception {
        PlSession s = new PlSession("pl020-reused", "sl-ready");
        var deleted = addDeletedFolio(s, 7);

        s.keys("D").keys(HEADER).keys(newLines(1)).keys(TOTALS);
        s.assertMenu();
        assertSaved(s, 1);
        assertEquals(7, s.records("pinvoice.dat", PlBase::invHeaderRec).getFirst().longv("ih-invoice"));
        assertEquals(0, deleted.count());
    }

    private static CobFile addDeletedFolio(PlSession s, int number) {
        var deleted = CobFile.sequential(s.ctx.store, s.ctx.path("delfolio.dat"));
        deleted.open(CobFile.Mode.EXTEND, true);
        assertTrue(deleted.ok());
        var folio = Layout.of("purchase/fdpdnos.cob", "del-inv-nos-record").newRec();
        folio.setNum("del-inv-nos", number);
        assertEquals("00", deleted.write(folio));
        deleted.close();
        return deleted;
    }

    @Test
    void 種別を再入力しても削除済み番号を引き継ぐ() throws Exception {
        PlSession s = new PlSession("pl020-retry", "sl-ready");
        var sys = SystemFile.shared(s.ctx);
        sys.setNum("next-folio", 12);
        sys.setNum("next-invoice", 0);
        var deleted = addDeletedFolio(s, 7);

        s.keys("D\rSUPP018\rPL-ORDER\rPL-REF\r\r")
                .keys(HEADER).keys(newLines(1)).keys(TOTALS);
        s.assertMenu();
        assertSaved(s, 1);
        assertEquals(7, s.records("pinvoice.dat", PlBase::invHeaderRec).getFirst().longv("ih-invoice"));
        assertEquals(0, deleted.count());
        assertEquals(12, sys.longv("next-folio"));
    }

    @Test
    void 明細保存に失敗したときは今回の請求を取り消す() throws Exception {
        PlSession s = new PlSession("pl020-rollback", "sl-ready");
        var deleted = addDeletedFolio(s, 7);
        s.keys("D").keys(HEADER).keys(newLines(2));
        addOldLine(s, 7);
        var before = s.ctx.store.snapshot().get(s.ctx.path("pinvoice.dat"));

        s.keys("\r\r\r\rY\rY\r\rN\r");
        s.assertMenu();
        assertEquals(before, s.ctx.store.snapshot().get(s.ctx.path("pinvoice.dat")));
        assertEquals(1, deleted.count());
    }

    @Test
    void 旧明細だけが残る番号を飛ばして次の候補で保存する() throws Exception {
        PlSession s = new PlSession("pl020-orphan", "sl-ready");
        var deleted = addDeletedFolio(s, 7);
        addDeletedFolio(s, 8);
        addOldLine(s, 7);

        s.keys("D").keys(HEADER).keys(newLines(2)).keys(TOTALS);
        s.assertMenu();
        var headers = s.records("pinvoice.dat", PlBase::invHeaderRec)
                .stream().filter(r -> r.intv("ih-test") == 0).toList();
        assertEquals(1, headers.size());
        assertEquals(8, headers.getFirst().longv("ih-invoice"));
        assertEquals(1, deleted.count());
    }

    @Test
    void 通常採番でも旧明細だけが残る番号を飛ばす() throws Exception {
        PlSession s = new PlSession("pl020-orphan-next", "sl-ready");
        var sys = SystemFile.shared(s.ctx);
        sys.setNum("next-folio", 7);
        sys.setNum("next-invoice", 0);
        var deleted = addDeletedFolio(s, 7);
        addOldLine(s, 7);

        s.keys("D").keys(HEADER).keys(newLines(2)).keys(TOTALS);
        s.assertMenu();
        var headers = s.records("pinvoice.dat", PlBase::invHeaderRec)
                .stream().filter(r -> r.intv("ih-test") == 0).toList();
        assertEquals(1, headers.size());
        assertEquals(8, headers.getFirst().longv("ih-invoice"));
        assertEquals(9, sys.longv("next-folio"));
        assertEquals(1, deleted.count());
    }

    @Test
    void 最大の伝票番号を保存した後は先頭の空きから採番する() throws Exception {
        PlSession s = new PlSession("pl020-last-folio", "sl-ready");
        var sys = SystemFile.shared(s.ctx);
        sys.setNum("next-folio", 99_999_999);
        addOldLine(s, 1);

        s.keys("D").keys(HEADER).keys(newLines(1)).keys(TOTALS);
        s.assertMenu();
        assertEquals(1, sys.longv("next-folio"));
        s.keys("D").keys(HEADER).keys(newLines(1)).keys(TOTALS);
        s.assertMenu();

        assertEquals(List.of(2L, 99_999_999L), savedFolios(s));
        assertEquals(3, sys.longv("next-folio"));
    }

    @Test
    void 上限まで空きがなければ先頭に戻って探索する() throws Exception {
        PlSession s = new PlSession("pl020-wrap-search", "sl-ready");
        var sys = SystemFile.shared(s.ctx);
        sys.setNum("next-folio", 99_999_999);
        addOldLine(s, 99_999_999);
        addOldLine(s, 1);

        s.keys("D").keys(HEADER).keys(newLines(1)).keys(TOTALS);
        s.assertMenu();

        assertEquals(List.of(2L), savedFolios(s));
        assertEquals(3, sys.longv("next-folio"));
    }

    @Test
    void 保存済みの次番号が範囲外でも先頭から採番する() throws Exception {
        PlSession s = new PlSession("pl020-overflow-folio", "sl-ready");
        var sys = SystemFile.shared(s.ctx);
        sys.setNum("next-folio", 100_000_000);

        s.keys("D").keys(HEADER).keys(newLines(1)).keys(TOTALS);
        s.assertMenu();

        assertEquals(List.of(1L), savedFolios(s));
        assertEquals(2, sys.longv("next-folio"));
    }

    private static List<Long> savedFolios(PlSession s) {
        return s.records("pinvoice.dat", PlBase::invHeaderRec).stream()
                .filter(r -> r.intv("ih-test") == 0)
                .map(r -> r.longv("ih-invoice"))
                .toList();
    }

    private static void addOldLine(PlSession s, long folio) {
        var invoice = CobFile.indexed(s.ctx.store, s.ctx.path("pinvoice.dat"), 0, 9);
        invoice.open(CobFile.Mode.IO, true);
        var priorLine = PlBase.invLineRec();
        priorLine.setNum("il-invoice", folio);
        priorLine.setNum("il-line", 2);
        assertEquals("00", invoice.write(priorLine));
        invoice.close();
    }

    @Test
    void ファイル状態フラグを復旧しても既存の請求書は保持する() throws Exception {
        PlSession s = new PlSession("pl020-existing", "pl-invoice");
        SystemFile.shared(s.ctx).setNum("file-status", 0, 26);
        s.keys("D\r\r");
        s.assertMenu();
        assertEquals(2, s.records("pinvoice.dat", PlBase::invHeaderRec).size());
        assertEquals(1, SystemFile.shared(s.ctx).intv("file-status", 26));
    }
}
