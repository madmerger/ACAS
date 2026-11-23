package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;

/** gl070.cbl: 仕訳転記 フェーズ 1（バッチ確認）・フェーズ 2（仕訳前処理 → pretrans.tmp）。 */
public class Gl070 extends GlProgram {
    static final String PROG_NAME = "gl070 (3.00.02)";
    static final String TRANS_LAYOUT = """
             01  trans-record.
                 03  t-batch         pic 9(5).
                 03  t-post          pic 9(5).
                 03  t-code          pic xx.
                 03  t-date          pic x(8).
                 03  t-ac            pic 9(6).
                 03  t-pc            pic 99.
                 03  t-amount        pic s9(8)v99.
                 03  t-legend        pic x(32).
            """;
    static Rec transRec() { return Layout.ofSource(TRANS_LAYOUT, "trans-record").newRec(); }

    private Rec bat, post, pre; private CobFile batchFile, postingFile, preTrans;
    private int a, lin;
    private String wsDate = sp(10), l6Ledger = sp(8), l6Status = sp(11);

    @Override
    public void run(Object... args) {
        init();
        bat = GlCommon.batchRec(); batchFile = GlCommon.batchFile(ctx, bat);
        bat.load(new byte[bat.bytes().length]);
        post = GlCommon.postingRec(); postingFile = GlCommon.postingFile(ctx);
        pre = transRec(); preTrans = CobFile.lineSequential(ctx.store, ctx.path("pretrans.tmp"));
        wsDate = wsDate();
        menuInput();
        a = 0;
        display(8, 1, "Phase - 1.  Batch Check");
        gl071a();
        if (a == 1) {
            gl060a();
            GlCommon.termCode(ctx, 5);
            return;
        }
        display(8, 1, "Phase - 2.  Transaction Pre-process");
        gl071b();
    }

    private void menuInput() {
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 32, "Transaction Posting");
        show(1, 71, wsDate, 2);
    }

    private boolean nextBatch() {
        String st = batchFile.readNext(bat);
        if (st.equals("10")) return false;
        if (!st.equals("00")) runaway();
        return true;
    }

    private void gl071a() {
        batchFile.open(CobFile.Mode.INPUT);
        while (nextBatch()) {
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            if (bat.intv("batch-status") == 0) a = 1;
        }
        batchFile.close();
    }

    private static String money(BigDecimal v, boolean blankZero) {
        if (blankZero && v.signum() == 0) return sp(12);
        return Num.edit(v, "zzzzzzzz9.99");
    }

    private void gl060a() {
        menuInput();
        wsDate = wsDate();
        // line-1（l1-prog・l1-page は未設定のまま表示される）
        show(3, 1, sp(31) + pad("Batch Status Report", 41) + " Page " + "  ", 2);
        display(3, 1, "Cycle - ");
        show(3, 9, Num.edit(sys.intv("scycle"), "z9"), 2);
        show(5, 1, pad("Ledger  Batch  Status       Last", 48) + "---------Batch Controls---------", 2);
        show(6, 1, pad("------  -----  ------     Activity", 48) + "Items  ---Gross---- -----VAT----", 2);
        lin = 7;
        batchFile.open(CobFile.Mode.INPUT);
        while (nextBatch()) {
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            int ledger = bat.intv("ledger");
            if (ledger == 1) l6Ledger = pad(" G/L", 8);
            if (ledger == 2) l6Ledger = pad(" P/L", 8);
            if (ledger == 3) l6Ledger = pad(" S/L", 8);
            for (String f : new String[]{"stored", "posted", "proofed", "entered"}) {
                long bin = bat.num(f).longValue();
                if (bin != 0) {
                    if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
                    wsDate = GlCommon.ukToForm(sys, Maps04.toDate(bin));
                    break;
                }
            }
            int bs = bat.intv("batch-status"), cs = bat.intv("cleared-status");
            if (bs == 0) l6Status = pad("Open", 11);
            if (bs == 1 && cs == 0) l6Status = pad("Waiting", 11);
            if (bs == 1 && cs == 1) l6Status = pad("Processed", 11);
            if (bs == 1 && cs == 2) l6Status = pad("Archived", 11);
            String items = Num.edit(bat.intv("items"), "z9") + sp(4);
            show(lin + 1, 1, l6Ledger + Num.edit(bat.intv("batch-nos"), "zzzz9") + "  " + l6Status + pad(wsDate, 14) + "Header   " + items
                    + money(bat.num("input-gross"), false) + " " + money(bat.num("input-vat"), true), 2);
            show(lin + 2, 1, sp(40) + "Actual   " + items + money(bat.num("actual-gross"), false) + " " + money(bat.num("actual-vat"), true), 2);
            lin += 3;
            if (lin < 21) continue;
            display(22, 1, "Enter <N> for next screen or <X> to exit :- [ ]");
            String r = pad(accept(22, 46, 1), 1);
            if (r.equals("X") || r.equals("x")) break;
            lin = 7; eraseEos(7, 1);
        }
        display(22, 1, "Type return to exit.");
        accept(22, 22, 1);
        batchFile.close();
    }

    private void gl071b() {
        preTrans.open(CobFile.Mode.OUTPUT);
        batchFile.open(CobFile.Mode.INPUT);
        while (nextBatch()) {
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            if (bat.intv("batch-status") == 0 || bat.intv("cleared-status") != 0 || bat.intv("ledger") != 1) continue;
            preProcess();
            postingFile.close();
        }
        batchFile.close(); preTrans.close();
    }

    private void writePre(long ac, int pc, BigDecimal amount) {
        pre.setNum("t-ac", ac); pre.setNum("t-pc", pc); pre.setNum("t-amount", amount);
        preTrans.writeLine(latin(pre.bytes()));
    }

    private void preProcess() {
        pre.setNum("t-batch", bat.intv("batch-nos"));
        postingFile.open(CobFile.Mode.INPUT);
        while (postingFile.readNext(post).equals("00")) {
            if (post.intv("batch") == 0 && post.intv("post-number") == 0) continue;
            if (post.intv("batch") != bat.intv("batch-nos")) continue;
            pre.setNum("t-batch", post.intv("batch"));
            pre.setNum("t-post", post.intv("post-number"));
            pre.set("t-code", post.str("post-code"));
            pre.set("t-date", post.str("post-date"));
            pre.set("t-legend", post.str("post-legend"));
            String side = post.str("post-vat-side");
            BigDecimal amt = post.num("post-amount"), vat = post.num("vat-amount");
            writePre(post.intv("post-dr"), post.intv("dr-pc"), side.equals("CR") ? amt.add(vat) : amt);
            writePre(post.intv("post-cr"), post.intv("cr-pc"), (side.equals("DR") ? amt.add(vat) : amt).negate());
            if (post.intv("vat-ac") == 0 || vat.signum() == 0) continue;
            writePre(post.intv("vat-ac"), post.intv("vat-pc"), side.equals("CR") ? vat.negate() : vat);
        }
    }
}
