package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** sl115.cbl: 未消込明細（openitm3）を顧客・日付・伝票番号・種別順に整列して oisort.wrk を作る。 */
public class Sl115 extends SlProgram {
    static final String PROG_NAME = "SL115 (3.01.04)";

    @Override
    public void run(Object... args) {
        Rec sys = sys();
        if (sys.str("oi-3-flag").equals("N")) return;
        if (sys.intv("file-status", 19) != 1) {
            sys.set("oi-3-flag", "Y");
            maps99(19); maps99(15);
            return;
        }
        Rec oi3 = oi3Rec(), oi = oiHeader();
        CobFile in = oi3File(oi3), out = CobFile.sequential(ctx.store, ctx.path(F_OISORT));
        record Item(String customer, long date, long invoice, int type, byte[] rec) {}
        List<Item> items = new ArrayList<>();
        in.open(CobFile.Mode.INPUT);
        while (in.readNext(oi3).equals("00")) {
            move(oi3, oi);
            items.add(new Item(oi.str("oi-customer"), oi.longv("oi-date"), oi.longv("oi-invoice"), oi.intv("oi-type"), oi3.bytes().clone()));
        }
        in.close();
        items.sort(Comparator.comparing(Item::customer).thenComparingLong(Item::date).thenComparingLong(Item::invoice).thenComparingInt(Item::type));
        out.open(CobFile.Mode.OUTPUT);
        for (Item i : items) out.write(i.rec());
        out.close();
        sys.set("oi-3-flag", "N");
    }
}
