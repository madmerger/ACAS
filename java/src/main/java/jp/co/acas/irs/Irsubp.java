package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;

/** irsubp.cbl: 整列済み転記ファイル（postsort.dat、行順編成）のファイルハンドラー。 */
public class Irsubp extends IrsBase {
    private static final String KEY = "irs.postsort";

    @Override
    public void run(Object... args) {
        Rec post = (Rec) args[0]; FileAccess fa = (FileAccess) args[1];
        fa.weError = 0;
        CobFile f = sharedFile(KEY);
        switch (fa.fileFunction) {
            case 1 -> {
                f = CobFile.lineSequential(ctx.store, ctx.irsPath("postsort.dat"));
                String st = fa.accessType == 3 ? f.open(CobFile.Mode.OUTPUT) : fa.accessType == 1 ? f.open(CobFile.Mode.INPUT) : "00";
                if (!st.startsWith("0")) { fa.weError = 99; ctx.shared.remove(KEY); }
                else ctx.shared.put(KEY, f);
            }
            case 2 -> { if (f != null) { f.close(); ctx.shared.remove(KEY); } }
            case 3 -> {
                // 未オープンでの READ は終端として扱う（レガシーは状態 47 のまま前レコードを返し続ける）
                String line = f == null ? null : f.readLine();
                if (line == null) { fa.weError = 3; return; }
                post.load(pad(line, post.layout.size).getBytes(StandardCharsets.ISO_8859_1));
            }
            case 5 -> {
                if (f != null) f.writeLine(new String(post.bytes(), StandardCharsets.ISO_8859_1));
            }
            default -> { }
        }
    }
}
