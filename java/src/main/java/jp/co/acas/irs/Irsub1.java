package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;

/** irsub1.cbl: 名目勘定元帳（acnts.dat、索引編成）のファイルハンドラー。 */
public class Irsub1 extends IrsBase {
    static final String KEY = "irs.nominal-ledger", REC = "irs.nominal-ledger.record";

    @Override
    public void run(Object... args) {
        Rec nl = (Rec) args[0]; FileAccess fa = (FileAccess) args[1];
        fa.weError = 0;
        String nlFile = fa.file(1);
        Rec rec1 = (Rec) ctx.shared.computeIfAbsent(REC, k -> Layout.of(CB + "fdwsnl.cob", "record-1").newRec());
        CobFile f = sharedFile(KEY);
        int fn = fa.fileFunction;
        if (fn == 1) {
            f = CobFile.indexed(ctx.store, ctx.irsPath(nlFile), 0, 10);
            ctx.shared.put(KEY, f);
            switch (fa.accessType) {
                case 1 -> f.open(CobFile.Mode.INPUT);
                case 2 -> f.open(CobFile.Mode.IO);
                case 3 -> f.open(CobFile.Mode.OUTPUT);
                default -> { }
            }
            if (!f.status.equals("00")) {
                display(24, 1, "Failure to Open Nominal-Ledger", 4);
                displayFileError(f.status);
                fa.weError = 1;
            }
            return;
        }
        if (f == null) { f = CobFile.indexed(ctx.store, ctx.irsPath(nlFile), 0, 10); ctx.shared.put(KEY, f); }
        if (fn == 2) { f.close(); return; }
        if (fn == 4) {
            // retry-1
            while (true) {
                rec1.setRaw("key-1", nl.raw("nl-key"));
                if (!f.read(rec1).equals("00")) { fa.weError = 2; return; }
                nl.load(rec1.bytes());
                if (!nl.str("nl-type").equals("S")) return;
                nl.setNum("nl-sub-nominal", nl.longv("nl-owning"));
                nl.setNum("nl-owning", nl.longv("nl-pointer"));
            }
        }
        if (fn == 3) { readNext(f, rec1, nl, fa); return; }
        if (fn == 5) {
            rec1.load(nl.bytes());
            if (!f.write(rec1).equals("00")) {
                display(24, 1, "Link/record exists on owning write", 4);
                accept(24, 38, 1);
            }
            if (nl.str("nl-type").equals("O")) return;
            nl.set("nl-type", "O");
            rec1.load(nl.bytes());
            if (!f.rewrite(rec1).equals("00")) {
                display(24, 1, "Link/record exists on rewrite", 4);
                accept(24, 32, 1);
            }
            nl.setNum("nl-pointer", nl.longv("nl-owning"));
            nl.setNum("nl-owning", nl.longv("nl-sub-nominal"));
            nl.setNum("nl-sub-nominal", 0);
            nl.set("nl-type", "S");
            rec1.load(nl.bytes());
            if (!f.write(rec1).equals("00")) {
                display(24, 1, "link/record exists on sub write", 4);
                accept(24, 35, 1);
            }
            nl.setNum("nl-sub-nominal", nl.longv("nl-owning"));
            nl.setNum("nl-owning", nl.longv("nl-pointer"));
            return;
        }
        if (fn == 8) {
            f.delete(rec1);
            if (nl.str("nl-type").equals("O")) return;
            nl.setNum("nl-owning", nl.longv("nl-sub-nominal"));
            nl.setNum("nl-sub-nominal", 0);
            rec1.setRaw("key-1", nl.raw("nl-key"));
            f.delete(rec1);
            return;
        }
        if (fn == 7) {
            rec1.load(nl.bytes());
            f.rewrite(rec1);
            return;
        }
        // next-6: START
        rec1.setRaw("key-1", nl.raw("nl-key"));
        rec1.setNum("sub-nominal", 0);
        String op = switch (fa.accessType) { case 5 -> "="; case 6 -> ">="; case 7 -> ">"; default -> null; };
        if (op != null && !f.start(rec1, op).equals("00")) { fa.weError = 2; return; }
        readNext(f, rec1, nl, fa);
    }

    /** retry-2: READ NEXT（ポインタレコード type S は読み飛ばす）。 */
    private void readNext(CobFile f, Rec rec1, Rec nl, FileAccess fa) {
        while (true) {
            if (!f.readNext(rec1).equals("00")) { fa.weError = 3; return; }
            nl.load(rec1.bytes());
            if (!nl.str("nl-type").equals("S")) return;
        }
    }
}
