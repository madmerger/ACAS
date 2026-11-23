package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Rec;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** pl115.cbl: 買掛金年齢表用の未決済明細ソート。 */
public class Pl115 extends PlBase {
    @Override
    public void run(Object... args) {
        init();
        if (sys.str("oi-5-flag").equals("N")) return;
        if (sys.intv("file-status", 29) != 1) {
            sys.set("oi-5-flag", "Y");
            maps99(25);
            maps99(15);
            ctx.shared.put("pl-error-code", 25);
            return;
        }
        CobFile oi5 = oi5File();
        List<Rec> recs = new ArrayList<>();
        oi5.open(Mode.INPUT);
        while (true) {
            Rec r = oiRec();
            if (!oi5.readNext(r).equals("00")) break;
            recs.add(r);
        }
        oi5.close();
        recs.sort(Comparator.<Rec, String>comparing(r -> r.str("oi-supplier"))
                .thenComparingLong(r -> r.longv("oi-date"))
                .thenComparingLong(r -> r.longv("oi-invoice"))
                .thenComparingLong(r -> r.longv("oi-type")));
        CobFile out = CobFile.sequential(ctx.store, ctx.path("poisort.wrk"));
        out.open(Mode.OUTPUT);
        for (Rec r : recs) out.write(Pl080.oi5Bytes(r));
        out.close();
        sys.set("oi-5-flag", "N");
    }
}
