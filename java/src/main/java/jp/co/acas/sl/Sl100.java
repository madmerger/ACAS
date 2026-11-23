package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;

/** sl100.cbl: 入金転記（顧客残高更新・入金転記帳票・GL/IRS 転記バッチ作成）。 */
public class Sl100 extends SlProgram {
    static final String PROG_NAME = "SL100 (3.01.12)";
    static final String SL002 = "SL002 Note error and hit return";
    static final String SL132 = "SL132 Err on Batch file write : ";
    private static final BigDecimal Z = BigDecimal.ZERO;

    private Rec sys, sys4, sales, oi, oi3, batch, post, irs;
    private CobFile salesFile, oi3File, batchFile, postFile, irsFile;
    private Prt print;
    private int j, lineCnt, pageLines;
    private boolean gl, irsUsed;
    private String uDate = "";

    private static String e(BigDecimal v, String pic) { return Num.edit(v, pic); }

    @Override
    public void run(Object... args) {
        sys = sys(); sys4 = sys4();
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("s-flag-p") != 2) { maps99(11); maps99(15); return; }
        eraseEos(1, 1);
        show(1, 1, PROG_NAME);
        display(1, 36, "Cash Posting");
        show(1, 71, fromUk(toDay()), 2);
        while (true) {
            display(12, 12, "OK to Post Payment Transactions (YES/NO) ? [   ]");
            String r = upper(pad(term().accept(12, 56, 3, "   ", 0, 6), 3));
            if (r.equals("NO ")) return;
            if (r.equals("YES")) break;
        }
        sales = salesRec(); oi = oiHeader(); oi3 = oi3Rec();
        salesFile = salesFile(sales); oi3File = oi3File(oi3);
        oi3File.open(CobFile.Mode.IO); salesFile.open(CobFile.Mode.IO);
        gl = sys.intv("level-1") == 1; irsUsed = sys.str("irs-instead").equals("Y");
        pageLines = sys.intv("page-lines");
        if (gl) blOpen();
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        j = 0;
        headings();
        display(16, 1, "Posting,  Please wait");
        BigDecimal tPaid = Z, tApprop = Z, tDeduct = Z, jPaid = Z, jApprop = Z, jDeduct = Z;
        long nDeduct = 0;
        String type = " ".repeat(11);
        while (oi3File.readNext(oi3).equals("00")) {
            move(oi3, oi);
            int t = oi.intv("oi-type");
            if (t != 2 && t != 5 && t != 6) continue;
            if (t == 2 && oi.longv("oi-b-nos") != 0 && oi.longv("oi-b-item") != 0) {
                computeSalesPay();
                oi.setNum("oi-b-nos", 0); oi.setNum("oi-b-item", 0); oi.setNum("oi-cr", 0);
                move(oi, oi3); oi3File.rewrite(oi3);
                continue;
            }
            if (oi.intv("oi-status") == 1 || t == 2) continue;
            if (oi.longv("oi-b-nos") == 0 && oi.longv("oi-b-item") == 0) continue;
            // cust-update
            sales.set("sales-key", oi.str("oi-customer"));
            salesFile.read(sales);
            String name = invalidKey(salesFile) ? "!! Customer Unknown" : sales.str("sales-name");
            uDate = Maps04.toDate(oi.longv("oi-date"));
            BigDecimal approp = oi.num("oi-net"), paid = oi.num("oi-paid"), ded = oi.num("oi-deduct-amt");
            if (ded.signum() != 0) nDeduct++;
            BigDecimal cur = sales.num("sales-current"), unap = sales.num("sales-unapplied");
            String oldBal = e(cur.subtract(unap), "z(5)9.99cr");
            cur = cur.subtract(approp).subtract(ded);
            if (paid.compareTo(approp) != 0) unap = unap.add(paid.subtract(approp));
            if (cur.signum() < 0) { unap = unap.add(cur.negate()); cur = Z; }
            sales.setNum("sales-current", cur); sales.setNum("sales-unapplied", unap);
            String newBal = e(sales.num("sales-current").subtract(sales.num("sales-unapplied")), "z(5)9.99cr");
            sales.setNum("sales-last-pay", oi.longv("oi-date"));
            if (t == 5) {
                tApprop = tApprop.add(approp); tPaid = tPaid.add(paid); tDeduct = tDeduct.add(ded);
                sys4.setNum("sl-payments", sys4.num("sl-payments").add(paid));
            } else {
                jApprop = jApprop.add(approp); jPaid = jPaid.add(paid); jDeduct = jDeduct.add(ded);
            }
            oi.setNum("oi-paid", approp);
            salesFile.rewrite(sales);
            if (gl) blWrite();
            oi.setNum("oi-status", 1);
            move(oi, oi3); oi3File.rewrite(oi3);
            type = pad(t == 6 ? "Cr Journal" : "Payment", 11);
            print.after(e(BigDecimal.valueOf(oi.longv("oi-b-nos")), "z(4)9") + "/" + z(oi.longv("oi-b-item"), 3) + " " + pad(uDate, 11)
                + pad(oi.str("oi-customer"), 8) + pad(name, 25) + "    " + type + oldBal + "   " + newBal + "  "
                + e(paid.abs(), "z(5)9.99") + "   " + e(ded.abs(), "z(5)9.99") + "     " + e(approp.abs(), "z(5)9.99"), 1);
            lineCnt++;
            if (lineCnt > pageLines) headings();
        }
        salesFile.close(); oi3File.close();
        print.after(total("Payment Totals", tPaid, tDeduct, tApprop), 3);
        print.after(total("Journal Totals", jPaid, jDeduct, jApprop), 2);
        print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
        tDeduct = tDeduct.add(jDeduct);
        if (tDeduct.signum() != 0) analiseDeductions(nDeduct, tDeduct);
        if (gl) blClose();
        sys.set("oi-3-flag", "Y");
        sys.setNum("s-flag-p", 0);
    }

    private static String total(String name, BigDecimal paid, BigDecimal ded, BigDecimal approp) {
        return " ".repeat(29) + pad(name, 25) + " ".repeat(42) + e(paid.abs(), "z(5)9.99") + "   " + e(ded.abs(), "z(5)9.99") + "     " + e(approp.abs(), "z(5)9.99");
    }

    private void headings() {
        j++;
        String l1 = pad(PROG_NAME, 56) + pad("Cash Posting Report", 68) + "Page " + Num.edit(j, "zz9");
        String l2 = pad(sys.str("usera"), 56) + " ".repeat(66) + pad(fromUk(toDay()), 10);
        if (j != 1) { print.afterPage(l1); print.after(l2, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l2, 1); }
        print.after(pad(" Number   ---Date--  <------------Customer------------>  --Type-- ", 67)
            + " Old Balance    New Balance    Payment   Deduction   Apportioned", 1);
        print.after("", 1);
        lineCnt = 5;
    }

    /** compute-sales-pay: レガシーどおり、直前に読んだ顧客レコード領域に対して計算する（顧客の読込はしない）。 */
    private void computeSalesPay() {
        if (oi.longv("oi-date-cleared") == 0) return;
        long a = oi.longv("oi-date-cleared") - oi.longv("oi-date"), b = 0;
        if (sales.longv("sales-pay-activety") != 0) b = sales.longv("sales-pay-activety") * sales.longv("sales-pay-average");
        b += a;
        sales.setNum("sales-pay-activety", sales.longv("sales-pay-activety") + 1);
        sales.setNum("sales-pay-average", b / sales.longv("sales-pay-activety"));
        if (a > sales.longv("sales-pay-worst")) sales.setNum("sales-pay-worst", a);
    }

    private void analiseDeductions(long n, BigDecimal t) {
        Rec val = valueRec();
        CobFile valFile = valueFile(val);
        valFile.open(CobFile.Mode.IO);
        val.set("va-code", "Szd");
        for (int pass = 0; pass < 2; pass++) {
            if (pass == 1) val.set("va-second", " ");
            valFile.read(val);
            if (invalidKey(valFile)) break;
            val.setNum("va-t-this", Math.abs(val.longv("va-t-this") - n)); val.setNum("va-t-year", Math.abs(val.longv("va-t-year") - n));
            val.setNum("va-v-this", val.num("va-v-this").subtract(t)); val.setNum("va-v-year", val.num("va-v-year").subtract(t));
            valFile.rewrite(val);
        }
        valFile.close();
    }

    private void blOpen() {
        if (batch == null) {
            batch = fdRec("copybooks/fdbatch.cob", "batch-record");
            post = fdRec("copybooks/fdpost.cob", "posting-record");
            irs = fdRec("copybooks/fdpost-irs.cob", "irs-posting-record");
            batchFile = CobFile.indexed(ctx.store, ctx.path(F_BATCH), batch, "batch-key");
            postFile = CobFile.relative(ctx.store, ctx.path(F_POSTING));
            irsFile = CobFile.sequential(ctx.store, ctx.path(F_IRS_POST));
        }
        batchFile.open(CobFile.Mode.IO);
        batch.setNum("batch-nos", sys.longv("next-batch"));
        batch.setNum("ledger", 3);
        sys.setNum("next-batch", sys.longv("next-batch") + 1);
        batch.setNum("batch-status", 0); batch.setNum("cleared-status", 0);
        batch.setNum("bcycle", sys.longv("scycle"));
        batch.setNum("entered", sys.longv("run-date"));
        batch.set("description", "Sales-Ledger Payments");
        for (String f : new String[] {"bdefault", "batch-def-ac", "batch-def-pc", "items", "input-gross", "input-vat", "actual-gross", "actual-vat"})
            batch.setNum(f, 0);
        batch.set("convention", "CR"); batch.set("batch-def-code", "SL"); batch.set("batch-def-vat", "O");
        batch.setNum("batch-start", sys.longv("postings") + 1);
        if (irsUsed) {
            irsFile.open(CobFile.Mode.EXTEND);
            if (!irsFile.status.equals("00")) { irsFile.close(); irsFile.open(CobFile.Mode.OUTPUT); }
        } else {
            postFile.open(CobFile.Mode.IO);
            if (!postFile.status.equals("00")) { postFile.close(); postFile.open(CobFile.Mode.OUTPUT); }
        }
        postFile.rrn = batch.longv("batch-start");
    }

    private void blWrite() {
        post.set("post-date", uDate.substring(0, 6) + uDate.substring(8, 10));
        batch.setNum("items", batch.longv("items") + 1);
        post.setNum("post-number", batch.longv("items"));
        post.setNum("post-amount", oi.num("oi-paid"));
        post.set("post-legend", pad(z(oi.longv("oi-b-nos"), 5) + "/" + z(oi.longv("oi-b-item"), 3) + "  :  " + sales.str("sales-name"), 32));
        post.setNum("batch", batch.longv("batch-nos"));
        post.setNum("post-cr", sys.longv("s-debtors"));
        post.setNum("post-dr", sys.longv("sl-pay-ac"));
        for (String f : new String[] {"dr-pc", "cr-pc", "vat-ac", "vat-pc", "vat-amount"}) post.setNum(f, 0);
        BigDecimal amt = post.num("post-amount");
        batch.setNum("input-gross", batch.num("input-gross").add(amt)); batch.setNum("actual-gross", batch.num("actual-gross").add(amt));
        post.set("post-code", "SL");
        post.set("post-vat-side", "CR");
        if (irsUsed) {
            irs.setNum("irs-batch", post.longv("batch"));
            irs.setNum("irs-post-number", post.longv("post-number"));
            irs.set("irs-post-code", "SL");
            irs.set("irs-post-date", post.str("post-date"));
            irs.setNum("irs-post-dr", post.longv("post-dr") % 100000);
            irs.setNum("irs-post-cr", post.longv("post-cr") % 100000);
            irs.setNum("irs-post-amount", amt);
            irs.set("irs-post-legend", post.str("post-legend"));
            irs.setNum("irs-vat-ac-def", 32);
            irs.set("irs-post-vat-side", "CR");
            irs.setNum("irs-vat-amount", 0);
            irsFile.write(irs);
        } else {
            postFile.write(post);
            postFile.rrn++;
        }
        if (batch.intv("items") == 99) { blClose(); blOpen(); }
    }

    private void blClose() {
        batchFile.write(batch);
        if (!batchFile.status.equals("00")) {
            display(23, 1, SL132);
            show(23, 33, batchFile.status);
            show(23, 36, fileStatMsg(batchFile.status));
            display(24, 1, SL002);
            accept(24, 30, 1);
        }
        if (!irsUsed) sys.setNum("postings", postFile.rrn);
        batchFile.close();
        if (irsUsed) irsFile.close(); else postFile.close();
    }
}
