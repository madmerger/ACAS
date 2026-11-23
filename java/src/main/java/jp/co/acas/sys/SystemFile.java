package jp.co.acas.sys;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Ctx;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;

/** システムファイル（system.dat、相対編成）: rrn 1=システム, 2=既定値, 3=期末, 4=システム 4。 */
public final class SystemFile {
    public static final String NAME = "system.dat";
    private SystemFile() { }

    public static Layout layout() { return Layout.of("copybooks/wssystem.cob", "System-Record"); }
    public static CobFile file(Ctx ctx) { return CobFile.relative(ctx.store, ctx.path(NAME)); }

    /** 実行単位で共有するシステムレコード（レガシーの LINKAGE system-record）。 */
    public static Rec shared(Ctx ctx) {
        return (Rec) ctx.shared.computeIfAbsent("system-record", k -> layout().newRec());
    }
    /** rrn 1 を読み、共有システムレコードへ格納。戻り値は FILE STATUS。 */
    public static String read(Ctx ctx) {
        CobFile f = file(ctx);
        String st = f.open(CobFile.Mode.IO);
        if (!f.ok()) return st;
        f.rrn = 1;
        st = f.read(shared(ctx));
        f.close();
        return st;
    }
    /** 共有システムレコードを rrn 1 へ書き戻す。 */
    public static String rewrite(Ctx ctx) {
        CobFile f = file(ctx);
        String st = f.open(CobFile.Mode.IO);
        if (!f.ok()) return st;
        f.rrn = 1;
        st = f.rewrite(shared(ctx));
        f.close();
        return st;
    }
}
