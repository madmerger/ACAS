package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** 小切手サブシステム（pl910〜pl960）共通: pay.dat と支払予定帳票の行編集。 */
abstract class PlPay extends PlBase {
    protected static final BigDecimal MOD7 = BigDecimal.valueOf(10_000_000);
    protected Printer prt;
    protected int p, lineCnt;
    protected BigDecimal bal0 = BigDecimal.ZERO, bal30 = BigDecimal.ZERO, bal60 = BigDecimal.ZERO,
            bal90 = BigDecimal.ZERO, balT = BigDecimal.ZERO, tot0 = BigDecimal.ZERO, tot30 = BigDecimal.ZERO,
            tot60 = BigDecimal.ZERO, tot90 = BigDecimal.ZERO, totT = BigDecimal.ZERO;
    protected String l5Key = "", l5Supplier = "", l5Folio = "", l5Method = " ", l5Date = "", l5Invoice = "";

    protected static Rec payRec() { return fdRec(Layout.of("purchase/fdpay.cob", "pay-record")); }
    protected CobFile payFile(Rec r) { return CobFile.indexed(ctx.store, ctx.path("pay.dat"), r, "pay-key"); }

    /** 符号なし 9(7)v99 への格納。 */
    protected static BigDecimal u9(BigDecimal v) { return v.abs().remainder(MOD7); }

    protected String line5(int keyWidth) {
        return pad(l5Key, keyWidth) + pad(l5Supplier, 35 - keyWidth) + pad(l5Folio, 8) + " " + pad(l5Method, 1) + " "
                + pad(l5Date, 12) + pad(l5Invoice, 11) + cr(bal0) + cr(bal30) + cr(bal60) + cr(bal90) + "    "
                + Pl095.bwz(balT, "z(6)9.99", 10);
    }

    protected String line6(BigDecimal pay) {
        return pad("    Total", 69) + cr(tot0) + cr(tot30) + cr(tot60) + cr(tot90) + "    " + Pl095.bwz(pay, "z(6)9.99", 10);
    }

    protected static String line7() {
        return pad("", 69) + "  --------  ".repeat(4) + "    " + "  ========";
    }

    private static String cr(BigDecimal v) { return Pl095.bwz(v, "z(6)9.99cr", 12); }

    protected void headings(String line1, String line2, String line4) {
        p = (p + 1) % 100;
        String l1 = line1 + Num.edit(p, "zz9");
        if (p != 1) {
            prt.afterPage(l1);
            prt.after(line2, 1);
            prt.after("", 1);
        } else {
            prt.before(l1, 1);
            prt.before(line2, 1);
        }
        prt.after(line4, 1);
        prt.after("", 1);
        lineCnt = 5;
    }
}
