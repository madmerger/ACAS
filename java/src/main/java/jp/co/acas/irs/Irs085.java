package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** irs085.cbl: 転記を勘定・月順に整列して workpost.tmp（順編成）へ出力する（分析表用）。 */
public class Irs085 extends IrsBase {
    static final String OUT = """
         01  output-record.
             03  output-date     pic 99.
             03  output-account  pic 9(5)      comp.
             03  output-amount   pic s9(7)v99  comp.
        """;
    public static Rec newOutputRecord() { return Layout.ofSource(OUT, "output-record").newRec(); }

    @Override
    public void run(Object... args) {
        Rec sys = (Rec) args[0];
        FileAccess fa = fa();
        fa.fileNames = sys.str("system-files");
        Rec def = newDefaultRecord(), post = newPostingRecord();
        fa.fileFunction = 3;
        call("irsub3", def, fa);
        List<Rec> recs = new ArrayList<>();
        CobFile in = CobFile.indexed(ctx.store, ctx.irsPath(fa.file(4)), 0, 5);
        if (!in.open(CobFile.Mode.INPUT).equals("00")) {
            display(24, 1, "Error opening postings = ", 4);
            show(24, 26, in.status, 4);
            accept(24, 78, 1);
        } else {
            while (in.readNext(post).equals("00")) {
                String d = post.str("post-date");
                long mm = numeric(d.substring(3, 5)) ? Long.parseLong(d.substring(3, 5)) : 0;
                BigDecimal amt = post.num("post-amount");
                recs.add(rec(mm, post.longv("post-cr"), amt));
                recs.add(rec(mm, post.longv("post-dr"), amt.negate()));
                int vd = post.intv("vat-ac-def");
                if (vd == 0) continue;
                recs.add(rec(mm, def.longv("def-acs", vd), post.num("vat-amount")));
            }
            in.close();
        }
        recs.sort(Comparator.comparingLong((Rec r) -> r.longv("output-account")).thenComparingLong(r -> r.longv("output-date")));
        CobFile out = CobFile.sequential(ctx.store, ctx.irsPath("workpost.tmp"));
        out.open(CobFile.Mode.OUTPUT);
        for (Rec r : recs) out.write(r);
        out.close();
    }
    private static Rec rec(long mm, long account, BigDecimal amount) {
        Rec r = newOutputRecord();
        r.setNum("output-date", mm); r.setNum("output-account", account); r.setNum("output-amount", amount);
        return r;
    }
}
