package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** sl090.cbl: 入金検証用に未消込明細（openitm3）をバッチ順へ整列して oisort.wrk を作る。 */
public class Sl090 extends SlProgram {
    static final String PROG_NAME = "SL090 (3.01.02)";

    @Override
    public void run(Object... args) {
        Rec sys = sys();
        eraseEos(1, 1);
        show(1, 1, PROG_NAME);
        // レコード長検査（OTM3 と整列レコードはともに 114 バイトで、レガシーでも不一致にならない）は省略。
        if (sys.intv("s-flag-p") == 0) { maps99(30); maps99(15); return; }
        sys.set("oi-3-flag", "Y");
        Rec oi3 = oi3Rec(), oi = oiHeader();
        CobFile in = oi3File(oi3), out = CobFile.sequential(ctx.store, ctx.path(F_OISORT));
        in.open(CobFile.Mode.INPUT);
        if (!in.status.equals("00")) {
            in.close();
            out.open(CobFile.Mode.OUTPUT); out.close();
            return;
        }
        record Item(long bNos, long bItem, int type, long date, long invoice, byte[] rec) {}
        List<Item> items = new ArrayList<>();
        while (in.readNext(oi3).equals("00")) {
            move(oi3, oi);
            int t = oi.intv("oi-type");
            if (t == 1 || t == 3) continue;
            if (oi.longv("oi-b-nos") == 0 && oi.longv("oi-b-item") == 0) continue;
            items.add(new Item(oi.longv("oi-b-nos"), oi.longv("oi-b-item"), t, oi.longv("oi-date"), oi.longv("oi-invoice"), oi3.bytes().clone()));
        }
        in.close();
        items.sort(Comparator.comparingLong(Item::bNos).thenComparingLong(Item::bItem)
            .thenComparing(Comparator.comparingInt(Item::type).reversed())
            .thenComparingLong(Item::date).thenComparingLong(Item::invoice));
        out.open(CobFile.Mode.OUTPUT);
        for (Item i : items) out.write(i.rec());
        out.close();
    }
}
