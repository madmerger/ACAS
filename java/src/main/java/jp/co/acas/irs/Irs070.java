package jp.co.acas.irs;

import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** irs070.cbl: 転記訂正（既存転記の取消・修正・削除と転記番号の振り直し）。 */
public class Irs070 extends IrsBase {
    static final String PROG_NAME = "irs070 (3.01.06)";
    private static final BigDecimal Z = BigDecimal.ZERO;
    private Rec sys, nl, def, post;
    private FileAccess fa;
    private int c, d, e;
    private BigDecimal amtOk = Z;

    private void irsub1(int fn) { fa.fileFunction = fn; call("irsub1", nl, fa); }
    private void irsub4(int fn) { fa.fileFunction = fn; call("irsub4", post, fa); }
    private void irsubp(int fn) { fa.fileFunction = fn; call("irsubp", post, fa, sys); }
    private static long toNum(String s) { return Num.parse(s).longValue(); }
    private BigDecimal amt() { return post.num("post-amount"); }
    private BigDecimal vat() { return post.num("vat-amount"); }
    private String side() { return post.str("post-vat-side"); }
    /** 勘定を索引読みする。無ければ false（we-error = 2）。 */
    private boolean readNl(long account) {
        nl.setNum("nl-owning", account);
        nl.setNum("nl-sub-nominal", 0);
        irsub1(4);
        return fa.weError != 2;
    }
    private long vatAccount() { return def.longv("def-acs", post.intv("vat-ac-def")); }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        nl = newNlRecord(); def = newDefaultRecord(); post = newPostingRecord();
        fa = fa();
        term().exceptionsEnabled = true; term().escEnabled = true;
        fa.fileNames = sys.str("system-files");
        sys.setNum("save-sequ", 0);
        fa.fileFunction = 3;
        call("irsub3", def, fa);
        fa.accessType = 2; irsub1(1);
        fa.accessType = 2; irsub4(1);
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 31, "Posting Correction", 7);
        show(1, 73, sys.str("run-date"), 2);
        while (true) {
            display(5, 1, "Number   :  [     ]");
            eraseEol(5, 25);
            display(5, 25, "(Return to quit)");
            display(6, 1, "Code     :  [  ]");
            display(7, 1, "Date     :  [        ]");
            display(8, 1, "Debit    :  [     ]");
            display(9, 1, "Credit   :  [     ]");
            display(10, 1, "Net      :  [          ]");
            eraseEol(11, 1);
            display(11, 1, "Narative :  [");
            display(11, 47, "]");
            display(12, 1, "VAT Type :  [  ]");
            display(13, 1, "(31-Input/32-Output)");
            display(14, 1, "VAT Side :  [  ]");
            display(15, 1, "VAT      :  [          ]");
            display(22, 1, "Enter code of <**> to delete");
            display(23, 1, "Enter number of zero to exit");
            post.setNum("post-key", toNum(acceptUpdate(5, 14, 5, "00000")));
            if (post.longv("post-key") == 0) break;
            fa.weError = 0;
            irsub4(4);
            if (fa.weError == 2) { display(5, 42, "Posting does not exist!"); continue; }
            display(5, 42, "Reversing posting. please wait");
            show(6, 14, post.str("post-code"));
            show(7, 14, post.str("post-date"));
            show(8, 14, post.str("post-dr"));
            show(9, 14, post.str("post-cr"));
            show(10, 14, Num.edit(amt(), "z(6)9.99"));
            show(11, 14, post.str("post-legend"));
            show(12, 14, post.str("vat-ac-def"));
            show(14, 14, side());
            show(15, 14, Num.edit(vat(), "z(6)9.99"));
            reverse();
            if (amend()) irsub4(7); else irsub4(8);
        }
        irsub4(2);
        call("irsub1", nl, fa);
        display(3, 1, "Renumber the postings (Y/N) - [ ]");
        while (true) {
            String r = up(pad(accept(3, 32, 1), 1));
            if (r.equals("N")) return;
            if (r.equals("Y")) break;
        }
        display(13, 31, "Sorting please wait.");
        sys.setNum("pass-value", 2); sys.setNum("save-sequ", 2);
        call("irs055", sys);
        sys.setNum("pass-value", 0);
        fa.accessType = 3; irsub4(1);
        fa.accessType = 1; irsubp(1);
        long counter = 0;
        while (true) {
            irsubp(3);
            if (fa.weError != 0) break;
            counter = (counter + 1) % 100000;
            post.setNum("post-key", counter);
            irsub4(5);
        }
        irsub4(2);
        call("irsubp", post, fa, sys);
        sys.setNum("next-post", post.longv("post-key") + 1);
        fa.fileFunction = 5;
        call("irsub2", sys, fa);
    }

    /** 既存転記を元帳から取り消す（reverse-dr / reverse-cr / reverse-vat）。 */
    private void reverse() {
        BigDecimal a = amt(), v = vat();
        if (readNl(post.longv("post-dr"))) {
            if (a.signum() > 0) nl.add("nl-cr", a); else nl.sub("nl-dr", a);
            if (side().equals("CR") && v.signum() > 0) nl.add("nl-cr", v);
            if (side().equals("CR") && v.signum() < 0) nl.sub("nl-dr", v);
            irsub1(7);
        }
    }

    /** reverse-cr 以降と修正入力。true=書換え、false=削除。 */
    private boolean amend() {
        BigDecimal a = amt(), v = vat();
        if (readNl(post.longv("post-cr"))) {
            if (a.signum() > 0) nl.add("nl-dr", a); else nl.sub("nl-cr", a);
            if (side().equals("DR") && v.signum() > 0) nl.add("nl-dr", v);
            if (side().equals("DR") && v.signum() < 0) nl.sub("nl-cr", v);
            irsub1(7);
        }
        if (post.intv("vat-ac-def") != 0 && readNl(vatAccount())) {   // reverse-vat
            if (side().equals("CR") && v.signum() > 0) nl.add("nl-dr", v);
            if (side().equals("DR") && v.signum() > 0) nl.add("nl-cr", v);
            if (side().equals("CR") && v.signum() < 0) nl.add("nl-cr", v);
            if (side().equals("DR") && v.signum() < 0) nl.add("nl-dr", v);
            irsub1(7);
        }
        while (true) {   // reverse-end
            eraseEol(5, 25);
            display(5, 25, "Correct the transaction       ");
            display(6, 41, "** here will delete transaction", 4);
            post.set("post-code", acceptUpdate(6, 14, 2, post.str("post-code")));
            if (post.str("post-code").equals("**")) return false;
            eraseEol(6, 41);
            while (true) {
                post.set("post-date", acceptUpdate(7, 14, 8, post.str("post-date")));
                Object[] dv = dateValidate(post.str("post-date"));
                if (((Number) dv[1]).longValue() == 0) continue;
                post.set("post-date", (String) dv[0]);
                break;
            }
            post.setNum("post-dr", toNum(acceptUpdate(8, 14, 5, post.str("post-dr"))));
            post.setNum("post-cr", toNum(acceptUpdate(9, 14, 5, post.str("post-cr"))));
            amtOk = amt();
            acceptMoney(10, 14);
            post.setNum("post-amount", amtOk);
            post.set("post-legend", acceptUpdate(11, 14, 32, post.str("post-legend")));
            while (true) {   // get-ac-def
                while (true) {
                    post.setNum("vat-ac-def", toNum(acceptUpdate(12, 14, 2, post.str("vat-ac-def"))));
                    int vd = post.intv("vat-ac-def");
                    if (vd == 0 || vd == 31 || vd == 32) break;
                    display(12, 18, "Error", 4);
                }
                show(12, 18, "     ");
                while (true) {
                    post.set("post-vat-side", up(acceptUpdate(14, 14, 2, side())));
                    if (side().equals("CR") || side().equals("DR")) break;
                    display(14, 18, "Error", 4);
                }
                show(14, 18, "     ");
                amtOk = vat();
                acceptMoney(15, 14);
                if (amtOk.signum() != 0 && post.intv("vat-ac-def") == 0) { display(15, 25, "Inconsistent", 4); continue; }
                break;
            }
            show(15, 25, " ".repeat(12));
            post.setNum("vat-amount", amtOk);
            if (!readNl(post.longv("post-dr"))) continue;
            if (!readNl(post.longv("post-cr"))) continue;
            if (post.intv("vat-ac-def") != 0 && !readNl(vatAccount())) continue;
            break;
        }
        readNl(post.longv("post-dr"));
        nl.add("nl-dr", amt());
        if (side().equals("CR")) nl.add("nl-dr", vat());
        irsub1(7);
        readNl(post.longv("post-cr"));
        nl.add("nl-cr", amt());
        if (side().equals("DR")) nl.add("nl-cr", vat());
        irsub1(7);
        if (post.intv("vat-ac-def") != 0) {
            readNl(vatAccount());
            if (side().equals("CR")) nl.add("nl-cr", vat());
            if (side().equals("DR")) nl.add("nl-dr", vat());
            irsub1(7);
        }
        return true;
    }

    /** accept-money: 9(7).99 の 10 桁（符号は表示されない）を update 入力する。 */
    private void acceptMoney(int line, int col) {
        while (true) {
            BigDecimal abs = amtOk.abs();
            String cur = Num.z9(abs.longValue(), 7) + "." + Num.z9(abs.remainder(BigDecimal.ONE).movePointRight(2).longValue(), 2);
            justify(pad(acceptUpdate(line, col, 10, cur), 10));
            if (c > 1 || d > 1) display(24, 1, "Amount not numeric. Re-Enter", 4);
            else { show(24, 1, " ".repeat(28)); return; }
        }
    }

    /** justify-accept-money（e と数字列 ws-nstrg は呼出し間で保持される）。 */
    private final char[] nstrg = "000000000".toCharArray();
    private void justify(String s) {
        amtOk = Z; c = 0; d = 0;
        int b = 10;
        for (int a = 10; a >= 1; a--) {
            char ch = s.charAt(a - 1);
            boolean num = ch >= '0' && ch <= '9';
            if (ch == '-' && c == 1) { c = 2; break; }
            if (ch == '.' && d == 1) { d = 2; break; }
            if (ch == '-') { c = 1; continue; }
            if (ch == '.') { d = 1; e = 10 - b; continue; }
            if (!num && b != 10) { c = 3; break; }
            if (num) { b--; if (b >= 1) nstrg[b - 1] = ch; }
        }
        if (c < 2 && d < 2) {
            BigDecimal v = new BigDecimal(new String(nstrg));
            if (e == 2) v = v.movePointLeft(2); else if (e == 1) v = v.movePointLeft(1);
            v = v.remainder(BigDecimal.valueOf(10_000_000)).setScale(2, java.math.RoundingMode.DOWN);
            amtOk = c == 1 ? v.negate() : v;
        }
    }
}
