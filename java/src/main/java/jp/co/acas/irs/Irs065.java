package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** irs065.cbl: 名目勘定元帳を勘定種別（nl-ac）順に整列して worksort.tmp（順編成）へ出力する。 */
public class Irs065 extends IrsBase {
    @Override
    public void run(Object... args) {
        Rec sys = (Rec) args[0];
        FileAccess fa = fa();
        fa.fileNames = sys.str("system-files");
        Rec nl = newNlRecord();
        CobFile out = CobFile.sequential(ctx.store, ctx.irsPath("worksort.tmp"));
        CobFile in = CobFile.indexed(ctx.store, ctx.irsPath(fa.file(1)), 0, 10);
        if (!in.open(CobFile.Mode.INPUT).equals("00")) {
            display(24, 1, "Failure to open Nominal Ledger!!!");
            accept(24, 41, 1);
            out.open(CobFile.Mode.OUTPUT);
            out.close();
            stopRun();
        }
        List<Rec> recs = new ArrayList<>();
        while (in.readNext(nl).equals("00")) {
            if (nl.str("nl-type").equals("S")) continue;
            recs.add(nl.copy());
        }
        in.close();
        recs.sort(Comparator.comparing(r -> r.str("nl-ac")));
        out.open(CobFile.Mode.OUTPUT);
        for (Rec r : recs) out.write(r);
        out.close();
    }
}
