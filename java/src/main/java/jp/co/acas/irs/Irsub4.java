package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

/** irsub4.cbl: 転記ファイル（post.dat、索引編成）のファイルハンドラー。 */
public class Irsub4 extends IrsBase {
    static final String KEY = "irs.posting-file";

    @Override
    public void run(Object... args) {
        Rec post = (Rec) args[0]; FileAccess fa = (FileAccess) args[1];
        fa.weError = 0;
        CobFile f = sharedFile(KEY);
        if (f == null) { f = CobFile.indexed(ctx.store, ctx.irsPath("post.dat"), 0, 5); ctx.shared.put(KEY, f); }
        Rec rec4 = post.copy();
        switch (fa.fileFunction) {
            case 1 -> {
                switch (fa.accessType) {
                    case 1 -> f.open(CobFile.Mode.INPUT);
                    case 2 -> f.open(CobFile.Mode.IO);
                    case 3 -> f.open(CobFile.Mode.OUTPUT);
                    default -> { }
                }
                if (f.status.charAt(0) != '0') {
                    display(23, 1, "Failure to open posting-file", 4);
                    displayFileError(f.status);
                    fa.weError = 1;
                }
            }
            case 2 -> f.close();
            case 4 -> {
                if (!f.read(rec4).equals("00")) { fa.weError = 2; return; }
                post.load(rec4.bytes());
            }
            case 3 -> readNext(f, rec4, post, fa);
            case 5 -> {
                while (true) {
                    String st = f.write(post);
                    if (st.equals("00")) break;
                    if (st.charAt(0) != '2') break;     // INVALID KEY 以外（未オープン等）は再試行しない
                    post.setNum("post-key", post.longv("post-key") + 1);
                }
            }
            case 8 -> f.delete(post);
            case 7 -> f.rewrite(post);
            default -> {
                String op = switch (fa.accessType) { case 5 -> "="; case 6 -> ">="; case 7 -> ">"; default -> null; };
                if (op != null && !f.start(rec4, op).equals("00")) { fa.weError = 2; return; }
                readNext(f, rec4, post, fa);
            }
        }
    }
    private void readNext(CobFile f, Rec rec4, Rec post, FileAccess fa) {
        if (!f.readNext(rec4).equals("00")) { fa.weError = 3; return; }
        post.load(rec4.bytes());
    }
}
