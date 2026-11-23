package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** pl165.cbl: 仕入先名順の索引（suppsort.inx）作成。 */
public class Pl165 extends PlBase {
    @Override
    public void run(Object... args) {
        init();
        Rec purch = purchRec();
        CobFile pf = purchaseFile(purch);
        pf.open(Mode.INPUT);
        CobFile out = CobFile.sequential(ctx.store, ctx.path("suppsort.inx"));
        out.open(Mode.OUTPUT);
        List<String[]> l = new ArrayList<>();
        while (pf.readNext(purch).equals("00")) l.add(new String[]{purch.str("purch-key"), purch.str("purch-name")});
        l.sort(Comparator.comparing(a -> a[1]));
        for (String[] a : l) out.write(pad(a[0], 7).getBytes(StandardCharsets.ISO_8859_1));
        pf.close(); out.close();
    }
}
