package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** irs055.cbl: 転記ファイル（post.dat）を指定順に整列して postsort.dat（行順）へ出力する。 */
public class Irs055 extends IrsBase {
    @Override
    public void run(Object... args) {
        Rec sys = (Rec) args[0];
        FileAccess fa = fa();
        fa.fileNames = sys.str("system-files");
        int sequ = sys.intv("save-sequ");
        if (sequ < 1 || sequ > 3) return;
        Rec post = newPostingRecord();
        List<String> recs = new ArrayList<>();
        CobFile in = CobFile.indexed(ctx.store, ctx.irsPath(fa.file(4)), 0, 5);
        if (in.open(CobFile.Mode.INPUT).equals("00")) {
            while (in.readNext(post).equals("00")) recs.add(new String(post.bytes(), StandardCharsets.ISO_8859_1));
            in.close();
        }
        // レコード: key(0,5) code(5,2) date dd/mm/yy(7,8) ...
        Comparator<String> key = Comparator.comparing(r -> r.substring(0, 5));
        Comparator<String> code = Comparator.comparing(r -> r.substring(5, 7));
        Comparator<String> date = Comparator.comparing((String r) -> r.substring(13, 15)).thenComparing(r -> r.substring(10, 12)).thenComparing(r -> r.substring(7, 9));
        recs.sort(sequ == 1 ? code.thenComparing(date).thenComparing(key) : sequ == 2 ? date.thenComparing(code).thenComparing(key) : key);
        CobFile out = CobFile.lineSequential(ctx.store, ctx.irsPath("postsort.dat"));
        out.open(CobFile.Mode.OUTPUT);
        for (String r : recs) out.writeLine(r);
        out.close();
    }
}
