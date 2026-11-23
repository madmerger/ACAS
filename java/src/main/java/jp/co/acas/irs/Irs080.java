package jp.co.acas.irs;

import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

/** irs080.cbl: 名目勘定元帳の修復（残高をゼロにして転記ファイルから再集計する）。 */
public class Irs080 extends IrsBase {
    static final String PROG_NAME = "irs080 (3.01.13)";
    private Rec sys, nl, def, post;
    private FileAccess fa;

    private void irsub1(int fn) { fa.fileFunction = fn; call("irsub1", nl, fa); }
    private void irsub4(int fn) { fa.fileFunction = fn; call("irsub4", post, fa); }
    private boolean readNl(long account) {
        nl.setNum("nl-owning", account);
        nl.setNum("nl-sub-nominal", 0);
        irsub1(4);
        return fa.weError == 0;
    }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        nl = newNlRecord(); def = newDefaultRecord(); post = newPostingRecord();
        fa = fa();
        fa.fileNames = sys.str("system-files");
        sys.setNum("save-sequ", 0);
        long cnt = 0;
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 29, "Fixup Accounts File", 7);
        show(1, 73, sys.str("run-date"), 2);
        display(3, 1, "You have, made a backup of all the data files? If not do it NOW!!", 4);
        display(4, 10, "To quit, just enter an invalid password");
        display(5, 1, "Enter pass word - [****]");
        show(5, 20, "    ");
        String wsPass = pad(accept(5, 20, 4, SECURE), 4);
        if (!wsPass.equals(pad(sys.str("pass-word"), 4))) return;
        clearScreen();
        display(1, 1, "Clearing Nominal Ledger of totals");
        fa.accessType = 2;
        irsub1(1);
        while (true) {
            irsub1(3);
            if (fa.weError == 3) break;
            nl.setNum("nl-dr", 0); nl.setNum("nl-cr", 0);
            irsub1(7);
            cnt = (cnt + 1) % 100000;
        }
        display(2, 1, "Cleared Nominal Ledger of totals");
        show(2, 34, Num.z9(cnt, 5));
        cnt = 0;
        fa.fileFunction = 3;
        call("irsub3", def, fa);
        display(3, 1, "Got Default record");
        Rec[] vatNl = new Rec[2];
        for (int i = 0; i < 2; i++) {
            if (!readNl(def.longv("def-acs", 31 + i))) {
                display(23, 1, "IRSUB1-" + (31 + i) + " returns ", 4);
                show(23, 19, String.valueOf(fa.weError), 4);
                accept(23, 40, 1);
                stopRun();
            }
            vatNl[i] = nl.copy();
        }
        display(4, 1, "Updating Nominal Ledger");
        fa.accessType = 1;
        irsub4(1);
        if (fa.weError != 0) display(23, 1, "No Postings Available");
        else while (true) {
            fa.weError = 0;
            irsub4(3);
            if (fa.weError == 3) break;
            cnt = (cnt + 1) % 100000;
            String side = post.str("post-vat-side");
            if (!keyOk(post.longv("post-dr"), "Invalid key 1 = ", post.str("post-dr"))) continue;
            nl.add("nl-dr", post.num("post-amount"));
            if (side.equals("CR")) nl.add("nl-dr", post.num("vat-amount"));
            irsub1(7);
            if (!keyOk(post.longv("post-cr"), "Invalid key 2 = ", post.str("post-cr"))) continue;
            nl.add("nl-cr", post.num("post-amount"));
            if (side.equals("DR")) nl.add("nl-cr", post.num("vat-amount"));
            irsub1(7);
            int vd = post.intv("vat-ac-def");
            if ((vd == 31 || vd == 32) && (side.equals("CR") || side.equals("DR")))
                vatNl[vd - 31].add(side.equals("CR") ? "nl-cr" : "nl-dr", post.num("vat-amount"));
        }
        for (Rec r : vatNl) { nl.load(r.copyBytes()); irsub1(7); }
        irsub4(2);
        call("irsub1", nl, fa);
        eraseEol(5, 1);
        display(5, 1, "Processing Complete on 12345 records");
        show(5, 24, Num.z9(cnt, 5), 2);
        display(7, 1, "Note counts. messages and Hit return for menu");
        accept(7, 47, 1);
    }

    private boolean keyOk(long account, String msg, String value) {
        nl.setNum("nl-owning", account);
        nl.setNum("nl-sub-nominal", 0);
        irsub1(4);
        if (fa.weError != 2) return true;
        display(23, 1, msg, 4);
        show(23, 17, value, 4);
        accept(23, 40, 1);
        return false;
    }
}
