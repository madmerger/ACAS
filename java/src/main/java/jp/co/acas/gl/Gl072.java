package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** gl072.cbl: 仕訳転記 フェーズ 4（元帳残高更新・転記帳票・バッチを処理済みへ）。 */
public class Gl072 extends GlProgram {
    static final String PROG_NAME = "gl072 (3.00.04)";
    private static final BigDecimal MOD = new BigDecimal("100000000");
    private static final String LINE7 = sp(54) + "=".repeat(11) + sp(4) + "=".repeat(11);

    private Rec led, bat, pt; private CobFile ledger, batchFile, postTrans; private Printer print;
    private int saveBatch, lineCnt, y; private String saveLedger = "00000000", readLedger = " ";
    private BigDecimal totDr = BigDecimal.ZERO, totCr = BigDecimal.ZERO;
    // line-6 の各項目（明細間で値が残る）
    private BigDecimal l6Account = BigDecimal.ZERO, l6Balance = BigDecimal.ZERO, l6Debit = BigDecimal.ZERO, l6Credit = BigDecimal.ZERO;
    private int l6Pc, l6Tran; private String l6Date = sp(12), l6Legend = sp(32), l3Desc = sp(32);

    @Override
    public void run(Object... args) {
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        bat = GlCommon.batchRec(); batchFile = GlCommon.batchFile(ctx, bat);
        pt = Gl070.transRec(); postTrans = CobFile.lineSequential(ctx.store, ctx.path("postrans.tmp"));
        print = new Printer("prt-1", 132);
        display(8, 1, "Phase - 4.  Transaction Update");
        batchFile.open(CobFile.Mode.IO); ledger.open(CobFile.Mode.IO);
        postTrans.open(CobFile.Mode.INPUT);
        print.open();
        saveBatch = 0; saveLedger = "00000000";
        while (true) {
            String l = postTrans.isOpen() ? postTrans.readLine() : null;
            if (l == null) { endAccount(); endBatch(); break; }
            pt.load(latin(pad(l, 70)));
            if (!pt.str("t-batch").matches("[0-9]{5}")) continue;
            int pb = pt.intv("t-batch");
            if (pb != saveBatch && saveBatch != 0 && weError != 999) {
                endAccount(); endBatch();
                saveLedger = "00000000";
                headings();
            }
            if (saveBatch == 0) { saveBatch = pb; headings(); }
            if (weError == 999) continue;
            String pl = pt.str("t-ac") + pt.str("t-pc");
            if (!pl.equals(saveLedger) && !saveLedger.equals("00000000")) { endAccount(); newAccount(); }
            if (saveLedger.equals("00000000")) newAccount();
            saveLedger = pl;
            l6Tran = pt.intv("t-post");
            l6Date = pad(pt.str("t-date"), 12);
            BigDecimal amt = pt.num("t-amount");
            if (amt.signum() > 0) { l6Debit = amt; totDr = u8(totDr.add(amt)); l6Credit = BigDecimal.ZERO; }
            else { l6Credit = amt.abs(); totCr = u8(totCr.subtract(amt)); l6Debit = BigDecimal.ZERO; }
            l6Legend = pt.str("t-legend");
            led.setNum("ledger-balance", led.num("ledger-balance").add(amt));
            print.after(line6(), 1);
            lineCnt++;
            if (lineCnt > sys.intv("page-lines")) { endAccount(); headings(); readLedger = "R"; newAccount(); }
        }
        postTrans.close(); print.close(); batchFile.close(); ledger.close();
        ctx.spool("prt-1", printReport());
    }

    /** 符号なし 9(8)v99 への格納（絶対値・上位桁あふれ切捨て）。 */
    private static BigDecimal u8(BigDecimal v) { return v.abs().remainder(MOD); }
    private static String bwz(BigDecimal v, String pic, int n) { return v.signum() == 0 ? sp(n) : Num.edit(v, pic); }

    private String line6() {
        return (l6Account.signum() == 0 ? sp(7) : Num.z9(l6Account.longValue(), 4) + "." + Num.z9(l6Account.movePointRight(2).longValue() % 100, 2))
                + sp(6) + (l6Pc == 0 ? "  " : Num.z9(l6Pc, 2)) + sp(5)
                + (l6Balance.signum() == 0 ? sp(13) : Num.edit(l6Balance.abs(), "zzzzzzz9.99") + (l6Balance.signum() < 0 ? "CR" : "  "))
                + (l6Tran == 0 ? sp(5) : sp(3) + Num.edit(l6Tran % 100, "z9")) + sp(4) + pad(l6Date, 12)
                + bwz(l6Debit, "zzzzzzz9.99", 11) + sp(4) + bwz(l6Credit, "zzzzzzz9.99", 11) + sp(6) + pad(l6Legend, 32);
    }

    private void getBatch() {
        bat.set("ledger", "1");
        saveBatch = pt.intv("t-batch");
        bat.setNum("batch-nos", saveBatch);
        batchFile.read(bat);
        l3Desc = pad(bat.str("description"), 32);
        if (bat.intv("cleared-status") != 0) { weError = 999; saveBatch = 0; }
        else weError = 0;
    }

    private void headings() {
        getBatch();
        if (weError == 999) return;
        y++;
        String l1 = pad(PROG_NAME, 50) + pad("Transaction  Posting", 63) + "Page " + Num.edit(y % 100, "z9");
        String l3 = "Cycle - " + Num.edit(sys.intv("scycle"), "z9") + "          Batch - " + Num.edit(pt.intv("t-batch"), "zzzz9")
                + sp(10) + pad("General", 12) + l3Desc + sp(23) + wsDate();
        if (y != 1) { print.afterPage(l1); print.after(l3, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l3, 1); }
        print.after("Account   Br/P C    --Balance--   Trans  --Date--    ---"
                + "Debit---    ---Credit--       -------------Legend------------", 1);
        print.after(pad("-------", 34) + "-----", 1);
        lineCnt = 5;
    }

    private void endBatch() {
        bat.setNum("cleared-status", 1);
        bat.setNum("posted", sys.num("run-date"));
        batchFile.rewrite(bat);
    }

    private void setAccount() {
        l6Account = BigDecimal.valueOf(led.intv("ledger-nos"), 2);
        l6Pc = led.intv("ledger-pc");
        l6Balance = led.num("ledger-balance");
    }

    private void endAccount() {
        ledger.rewrite(led);
        print.after(LINE7, 1);
        lineCnt++;
        setAccount();
        l6Debit = totDr; l6Credit = totCr;
        l6Date = pad(toDay(), 12);
        l6Legend = led.str("ledger-name");
        l6Tran = 0;
        print.after(line6(), 1);
        print.after(LINE7, 1);
        print.after("", 1);
        lineCnt += 3;
    }

    private void newAccount() {
        led.set("ledger-nos", pt.str("t-ac")); led.set("ledger-pc", pt.str("t-pc"));
        boolean reread = !readLedger.equals("R");
        if (reread) { ledger.read(led); totDr = BigDecimal.ZERO; totCr = BigDecimal.ZERO; }
        setAccount();
        l6Debit = BigDecimal.ZERO; l6Credit = BigDecimal.ZERO;
        l6Date = pad(wsDate(), 12);
        if (reread) {
            BigDecimal bal = led.num("ledger-balance");
            if (bal.signum() > 0) { l6Debit = bal; totDr = u8(totDr.add(bal)); }
            else { l6Credit = bal.abs(); totCr = u8(totCr.add(bal)); }
        }
        l6Legend = "brought forward";
        l6Tran = 0;
        readLedger = " ";
        print.after(line6(), 2);
        lineCnt += 2;
        l6Balance = BigDecimal.ZERO;
    }
}
