package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Rec;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** pl090.cbl: 支払検証帳票用の未決済明細ソート。 */
public class Pl090 extends PlBase {
    @Override
    public void run(Object... args) {
        init();
        clearScreen();
        if (sys.intv("p-flag-p") == 0) {
            maps99(30);
            maps99(15);
            return;
        }
        sys.set("oi-5-flag", "Y");
        CobFile oi5 = oi5File();
        CobFile out = CobFile.sequential(ctx.store, ctx.path("poisort.wrk"));
        List<Rec> recs = new ArrayList<>();
        if (oi5.open(Mode.INPUT).equals("00")) {
            while (true) {
                Rec r = oiRec();
                if (!oi5.readNext(r).equals("00")) break;
                int t = r.intv("oi-type");
                if (t == 1 || t == 3) continue;
                if (r.longv("oi-b-nos") == 0 && r.longv("oi-b-item") == 0) continue;
                recs.add(r);
            }
        }
        oi5.close();
        recs.sort(Comparator.<Rec>comparingLong(r -> r.longv("oi-b-nos"))
                .thenComparingLong(r -> r.longv("oi-b-item"))
                .thenComparingLong(r -> -r.longv("oi-type"))
                .thenComparingLong(r -> r.longv("oi-date"))
                .thenComparingLong(r -> r.longv("oi-invoice")));
        out.open(Mode.OUTPUT);
        for (Rec r : recs) out.write(Pl080.oi5Bytes(r));
        out.close();
    }
}
