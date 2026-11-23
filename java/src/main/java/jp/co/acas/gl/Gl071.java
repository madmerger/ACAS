package jp.co.acas.gl;

import jp.co.acas.core.CobFile;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** gl071.cbl: 仕訳転記 フェーズ 3（pretrans.tmp を バッチ・勘定・P/C・仕訳番号 順に整列 → postrans.tmp）。 */
public class Gl071 extends GlProgram {
    @Override
    public void run(Object... args) {
        init();
        display(8, 1, "Sorting.......Please wait            ");
        CobFile in = CobFile.lineSequential(ctx.store, ctx.path("pretrans.tmp"));
        CobFile out = CobFile.lineSequential(ctx.store, ctx.path("postrans.tmp"));
        List<String> recs = new ArrayList<>();
        if (in.open(CobFile.Mode.INPUT).equals("00")) {
            for (String l = in.readLine(); l != null; l = in.readLine()) recs.add(pad(l, 70));
            in.close();
        }
        // キー: sort-batch(1-5) sort-ac(21-26) sort-pc(27-28) sort-post(6-10)
        recs.sort(Comparator.comparing((String r) -> r.substring(0, 5) + r.substring(20, 28) + r.substring(5, 10)));
        out.open(CobFile.Mode.OUTPUT);
        for (String r : recs) out.writeLine(r);
        out.close();
    }
}
