package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** sl060.cbl: 請求書転記（未消込明細 2 → 3、顧客残高更新、GL/IRS 仕訳バッチ作成）と転記帳票。 */
public class Sl060 extends SlProgram {
    static final String PROG_NAME = "SL060 (3.01.14)";
    static final String SL002 = "SL002 Note error and hit return";
    static final String SL130 = "SL130 Open-IT3 = ";
    static final String SL131 = "SL131 PE - CR SWOP: Return to continue";
    static final String SL132 = "SL132 Err on Batch file write : ";
    static final String SL133 = "SL133 PE 060-01";
    static final String SL134 = "SL134 Warning Record/s missing in Sales File";
    static final String SL135 = "SL135 Error On Re/write Sales File";
    private static final String M = "z(6)9.99cr", M8 = "z(7)9.99cr";
    private static final String[] LITS = {"Receipts", "Invoices", "Credit Notes"};
    private static final BigDecimal Z = BigDecimal.ZERO;

    private Rec sys, sales, oi, si, oi3, val, batch, post, irs;
    private CobFile salesFile, oi2File, oi3File, valFile, batchFile, postFile, irsFile;
    private Prt print;
    private int j, lineCnt;
    private long totalMovDed;
    private boolean salesMissing, firstPass, gl, irsUsed;
    private BigDecimal work1 = Z, workA = Z, workB = Z, workNet = Z, workVat = Z, workGoods = Z, wsDeduction = Z, totalDeduct = Z;
    private String l5Type = "";

    private static String bwz(BigDecimal v, String pic) { String s = Num.edit(v, pic); return v.signum() == 0 ? " ".repeat(s.length()) : s; }
    private BigDecimal n(String f) { return oi.num(f); }
    private BigDecimal oiTotal() {
        return n("oi-net").add(n("oi-extra")).add(n("oi-carriage")).add(n("oi-vat")).add(n("oi-discount")).add(n("oi-e-vat")).add(n("oi-c-vat"))
            .add(n("oi-deduct-amt")).add(n("oi-deduct-vat"));
    }

    /** USE AFTER ERROR PROCEDURE ON Sales-File（表示後 goback）。 */
    private static final class SalesFileError extends RuntimeException { }
    private void checkSales() {
        if (salesFile.status.equals("00")) return;
        display(23, 1, SL135);
        show(23, 37, salesFile.status);
        display(23, 40, fileStatMsg(salesFile.status));
        display(24, 1, SL002);
        accept(24, 33, 1);
        throw new SalesFileError();
    }

    @Override
    public void run(Object... args) {
        try { main(); } catch (SalesFileError e) { /* goback */ }
    }

    private void main() {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        clearScreen();
        show(1, 1, PROG_NAME);
        display(1, 31, "Invoice Posting & Report");
        show(1, 71, fromUk(toDay()), 2);
        while (true) {
            display(8, 12, "OK to post Sales transactions (YES/NO) ?  [   ]");
            String r = upper(acceptUpdate(8, 55, 3, "   ")).stripTrailing();
            if (r.equals("NO")) return;
            if (r.equals("YES")) break;
        }
        eraseEol(8, 1);
        sys.setNum("s-flag-i", 2); sys.setNum("s-flag-a", 1); sys.set("oi-3-flag", "Y");
        sales = salesRec(); oi = oiHeader(); si = oiHeader(); oi3 = oi3Rec(); val = valueRec();
        salesFile = salesFile(sales); oi3File = oi3File(oi3); valFile = valueFile(val);
        oi2File = CobFile.sequential(ctx.store, ctx.path(F_OI2));
        if (sys.intv("file-status", 19) != 1) { oi3File.open(CobFile.Mode.OUTPUT); oi3File.close(); sys.setNum("file-status", 1, 19); }
        gl = sys.intv("level-1") == 1; irsUsed = sys.str("irs-instead").equals("Y");
        if (gl) blOpen();
        salesFile.open(CobFile.Mode.IO);
        checkSales();
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        display(12, 1, "Posting......Please Wait"); eraseEol(12, 25);
        display(14, 1, "Phase 1 - Building OTM3 from OTM2"); eraseEol(14, 34);
        j = 0;
        headings();
        BigDecimal[] totNet = {Z, Z, Z}, totVat = {Z, Z, Z};
        oi2File.open(CobFile.Mode.INPUT);
        oi3File.open(CobFile.Mode.IO);
        Rec in2 = fdRec("sales/fdoi2.cob", "open-item-record-2");
        while (oi2File.readNext(in2).equals("00")) {
            System.arraycopy(in2.bytes(), 0, oi.bytes(), 0, Math.min(114, oi.bytes().length));
            String cust = oi.str("oi-customer");
            sales.set("sales-key", cust);
            salesFile.read(sales);
            boolean unknown = invalidKey(salesFile);
            if (!unknown) checkSales();
            String name;
            if (unknown) {
                salesMissing = true;
                initialize(sales);
                name = "*** Customer Unknown ***"; sales.set("sales-name", name);
                sales.set("sales-key", cust);
            } else name = sales.str("sales-name");
            int type = oi.intv("oi-type");
            if (type == 2) l5Type = "Invoice"; else if (type == 3) l5Type = "CR. Note"; else if (type == 1) l5Type = "Receipt";
            workVat = n("oi-vat").add(n("oi-c-vat")).add(n("oi-e-vat")).add(n("oi-deduct-vat"));
            workGoods = n("oi-net").add(n("oi-extra"));
            workNet = n("oi-net").add(n("oi-extra")).add(n("oi-carriage")).add(n("oi-discount")).add(n("oi-deduct-amt"));
            if (type >= 1 && type <= 3) { totVat[type - 1] = totVat[type - 1].add(workVat); totNet[type - 1] = totNet[type - 1].add(workNet); }
            work1 = workNet.add(workVat);
            BigDecimal gross = work1;
            wsDeduction = Z;
            if (gl) blWrite();
            BigDecimal oldBal = sales.num("sales-current").subtract(sales.num("sales-unapplied"));
            int q = Math.max(1, Math.min(4, sys.intv("current-quarter")));
            if (type == 1 || type == 2) salesComp();
            if (type >= 1 && type <= 3) sales.setNum("sturnover-q", sales.num("sturnover-q", q).add(workGoods), q);
            if (type == 1) { sales.setNum("sales-last-inv", oi.longv("oi-date")); sales.setNum("sales-last-pay", oi.longv("oi-date")); }
            if (type == 2) {
                sales.setNum("sales-current", sales.num("sales-current").add(workVat).add(workNet));
                sales.setNum("sales-last-inv", oi.longv("oi-date"));
            }
            if (type == 3) {
                sales.setNum("sales-current", sales.num("sales-current").add(workVat).add(workNet));
                sales.setNum("sales-last-pay", oi.longv("oi-date"));
                crNotes();
                creditComp();
            }
            totalDeduct = totalDeduct.add(wsDeduction);
            if (sales.intv("sales-status") == 0) sales.setNum("sales-status", 1);
            if (sales.num("sales-current").signum() < 0) {
                sales.setNum("sales-unapplied", sales.num("sales-unapplied").add(sales.num("sales-current").negate()));
                sales.setNum("sales-current", 0);
            }
            BigDecimal newBal = sales.num("sales-current").subtract(sales.num("sales-unapplied"));
            if (unknown) { sales.setNum("sales-status", 1); salesFile.write(sales); } else salesFile.rewrite(sales);
            checkSales();
            String nos = Num.edit(oi.longv("oi-invoice"), "z(7)9") + " ";
            move(oi, oi3);
            oi3File.write(oi3);
            if (invalidKey(oi3File)) {
                display(16, 1, SL130);
                show(17, 1, oi3.str("oi3-customer"));
                show(18, 1, nos);
                display(19, 1, "fs-reply = ");
                show(19, 12, oi3File.status);
                display(19, 15, fileStatMsg(oi3File.status));
                display(24, 1, SL133, 4);
                display(24, 12, SL002);
                accept(24, 50, 1);
            }
            print.after(nos + pad(binToDate(oi.longv("oi-date")), 11) + pad(cust, 9) + pad(name, 25) + "  " + pad(l5Type, 9)
                + Num.edit(oldBal, M) + Num.edit(newBal, M) + bwz(wsDeduction, "zzz9.99") + Num.edit(workNet, M) + Num.edit(workVat, M)
                + Num.edit(gross, M), 1);
            lineCnt++;
            if (lineCnt > sys.intv("page-lines")) headings();
        }
        // aa030-Main-End
        salesFile.close(); oi2File.close(); oi3File.close();
        if (lineCnt > sys.intv("page-lines") - 7) headings();
        for (int a = 0; a < 3; a++)
            print.after(" ".repeat(11) + pad("Total  Posted", 14) + pad(LITS[a], 18) + Num.edit(totNet[a], M8) + Num.edit(totVat[a], M8)
                + Num.edit(totNet[a].add(totVat[a]), M8), a == 0 ? 3 : 2);
        print.after(pad("           Total  Amount Late Deductions", 43) + Num.edit(totalDeduct, M8), 2);
        Rec s4 = sys4();
        s4.setNum("sl-credit-deductions", s4.num("sl-credit-deductions").add(totalDeduct));
        if (totalDeduct.signum() != 0) {
            valFile.open(CobFile.Mode.IO);
            analiseDeductions();
            valFile.close();
        }
        if (gl) blClose();
        oi3File.open(CobFile.Mode.IO);
        workB = Z;
        display(14, 7, "2 - Applying Cr. Notes to OTM3"); eraseEol(14, 37);
        while (oi3File.readNext(oi3).equals("00")) {
            move(oi3, oi);
            if (oi.intv("oi-status") == 1) continue;
            if (oi.intv("oi-type") == 3) crSwop();
        }
        oi2File.open(CobFile.Mode.OUTPUT); oi2File.close();
        oi3File.close();
        if (lineCnt > sys.intv("page-lines") - 6 && sys.intv("file-status", 18) == 1) newHeading();
        if (sys.intv("file-status", 18) == 1)
            print.after(" ".repeat(24) + pad("Un-Applied Credits C/F ", 32) + bwz(workB, "z(7)9.99"), 3);
        s4.setNum("sl-cn-unappl-this-month", s4.num("sl-cn-unappl-this-month").add(workB));
        if (salesMissing) print.after(SL134, 3);
        print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
        sys.setNum("file-status", 0, 18);
    }

    private void crSwop() {
        work1 = oiTotal().add(n("oi-paid"));
        if (work1.signum() == 0) { display(24, 1, SL131, 4); accept(24, 34, 1); }
        if (sys.intv("file-status", 18) == 0) newHeading();
        oi.setNum("oi-status", 1);
        print.after(pad(oi.str("oi-customer"), 12) + bwz(BigDecimal.valueOf(oi.longv("oi-invoice")), "z(7)9") + "  " + " ".repeat(4)
            + bwz(work1, "z(7)9.99") + " ".repeat(4) + bwz(n("oi-paid"), "z(7)9.99") + " ".repeat(4)
            + bwz(BigDecimal.valueOf(oi.longv("oi-cr")), "z(7)9") + "  " + " ".repeat(4) + pad("Cr. Note", 12), 1);
        lineCnt++;
        if (lineCnt > sys.intv("page-lines")) newHeading();
        workB = workB.add(work1);
        work1 = work1.negate();
        oi.setNum("oi-paid", n("oi-paid").add(work1));
        move(oi, oi3);
        oi3File.rewrite(oi3);
    }

    private String line1() { return pad(PROG_NAME, 54) + pad("Invoice Posting Report", 70) + "Page " + Num.edit(++j, "zz9"); }
    private String line2() { return pad(sys.str("usera"), 54) + " ".repeat(68) + fromUk(toDay()); }

    private void newHeading() {
        if (sys.intv("file-status", 18) == 0) sys.setNum("file-status", 1, 18);
        String l1 = line1(), l1a = " ".repeat(56) + "Un-Applied Credits";
        if (j != 1) { print.afterPage(l1); print.after(line2(), 1); print.after(l1a, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(line2(), 1); print.before(l1a, 1); }
        print.after("--Customer--   Invoice      Bal C/F        Applied      Cr. Note          Type", 1);
        print.after("", 1);
        lineCnt = 6;
    }

    private void headings() {
        String l1 = line1();
        if (j != 1) { print.afterPage(l1); print.after(line2(), 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(line2(), 1); }
        print.after(pad(" Number     Date    <------------Customer------------>   Type  ", 64)
            + " Old Balance  New Balance   Dedn     Net         Vat       Gross", 1);
        print.after("", 1);
        lineCnt = 5;
    }

    private BigDecimal activityProduct() {
        long act = sales.longv("sales-activety"), avg = sales.longv("sales-average");
        return act != 0 && avg != 0 ? BigDecimal.valueOf(act * avg) : Z;
    }
    private void salesComp() {
        BigDecimal w = activityProduct();
        sales.setNum("sales-activety", sales.longv("sales-activety") + 1);
        w = w.add(workGoods).setScale(0, RoundingMode.DOWN);
        sales.setNum("sales-average", w.divide(BigDecimal.valueOf(sales.longv("sales-activety")), 0, RoundingMode.DOWN));
    }
    private void creditComp() {
        BigDecimal w = activityProduct();
        if (w.signum() != 0) {
            w = w.add(workGoods).setScale(0, RoundingMode.DOWN);
            sales.setNum("sales-average", w.divide(BigDecimal.valueOf(sales.longv("sales-activety")), 0, RoundingMode.DOWN));
        }
    }

    /** ba000-CR-Notes: 赤伝を同一顧客の未決済請求書へ充当する。 */
    private void crNotes() {
        move(oi, si);
        firstPass = true;
        oi3.set("oi3-customer", oi.str("oi-customer"));
        oi3.setNum("oi3-invoice", oi.longv("oi-cr"));
        oi3File.start(oi3, ">=");
        boolean loop = !invalidKey(oi3File);
        if (loop) {
            workB = Z;
            if (work1.signum() < 0) work1 = work1.negate();
            work1 = work1.subtract(si.num("oi-paid"));
        }
        while (true) {
            while (loop) {
                if (!oi3File.readNext(oi3).equals("00")) break;
                move(oi3, oi);
                if (oi.intv("oi-type") != 2) continue;
                if (!oi.str("oi-customer").equals(si.str("oi-customer"))) break;
                if (oi.intv("oi-status") == 1) continue;
                workB = n("oi-deduct-amt").add(n("oi-deduct-vat"));
                if (oi.longv("oi-date") + 1 + oi.longv("oi-deduct-days") <= si.longv("oi-date")) workB = Z;
                if (si.longv("oi-cr") == oi.longv("oi-invoice") || !firstPass) apportion();
                if (work1.signum() == 0) break;
            }
            // ba020-end-loop
            if (work1.signum() == 0 || !firstPass) break;
            firstPass = false;
            oi3.set("oi3-customer", si.str("oi-customer"));
            oi3.setNum("oi3-invoice", 0);
            oi3File.start(oi3, ">=");
            if (invalidKey(oi3File)) break;
            loop = true;
        }
        move(si, oi);
    }

    private void addPaid(BigDecimal v) {
        oi.setNum("oi-paid", n("oi-paid").add(v));
        si.setNum("oi-paid", si.num("oi-paid").add(v));
        oi.setNum("oi-p-c", n("oi-p-c").add(v));
    }

    private void apportion() {
        workA = oiTotal().subtract(n("oi-paid"));
        if (workA.signum() == 0) oi.setNum("oi-status", 1);
        else {
            if (workA.signum() < 0) return;
            workA = workA.subtract(workB);
            int c = workA.compareTo(work1);
            if (c == 0) {
                addPaid(work1); work1 = Z;
                clearInvoiceDeduct();
                oi.setNum("oi-status", 1); si.setNum("oi-status", 1);
            } else if (c > 0) {
                addPaid(work1); work1 = Z;
                si.setNum("oi-status", 1);
            } else {
                addPaid(workA); work1 = work1.subtract(workA);
                clearInvoiceDeduct();
                oi.setNum("oi-status", 1);
            }
            if (work1.signum() == 0) si.setNum("oi-status", 1);
        }
        move(oi, oi3);
        oi3File.rewrite(oi3);
    }

    private void clearInvoiceDeduct() {
        if (workB.signum() > 0) {
            sales.setNum("sales-current", sales.num("sales-current").subtract(workB));
            wsDeduction = wsDeduction.add(workB);
            totalMovDed++;
            oi.setNum("oi-deduct-amt", 0); oi.setNum("oi-deduct-vat", 0);
        }
    }

    private void analiseDeductions() {
        val.set("va-code", "Szd");
        for (int pass = 0; pass < 2; pass++) {
            if (pass == 1) val.set("va-second", " ");
            valFile.read(val);
            if (invalidKey(valFile)) return;
            val.setNum("va-t-this", val.longv("va-t-this") - totalMovDed); val.setNum("va-t-year", val.longv("va-t-year") - totalMovDed);
            val.setNum("va-v-this", val.num("va-v-this").subtract(totalDeduct)); val.setNum("va-v-year", val.num("va-v-year").subtract(totalDeduct));
            valFile.rewrite(val);
        }
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
        if (!batchFile.status.equals("00")) { batchFile.close(); batchFile.open(CobFile.Mode.OUTPUT); }
        batch.setNum("batch-nos", sys.longv("next-batch"));
        batch.setNum("ledger", 3);
        sys.setNum("next-batch", sys.longv("next-batch") + 1);
        batch.setNum("batch-status", 0); batch.setNum("cleared-status", 0);
        batch.setNum("bcycle", sys.longv("scycle"));
        batch.setNum("entered", sys.longv("run-date"));
        batch.set("description", "Sales Ledger Invoices");
        for (String f : new String[] {"bdefault", "batch-def-ac", "batch-def-pc", "items", "input-gross", "input-vat", "actual-gross", "actual-vat"})
            batch.setNum(f, 0);
        batch.set("convention", "CR"); batch.set("batch-def-code", "SL"); batch.set("batch-def-vat", "O");
        batch.setNum("batch-start", sys.longv("postings") + 1);
        if (irsUsed) {
            irsFile.open(CobFile.Mode.EXTEND, true);
            if (!irsFile.ok()) { irsFile.close(); irsFile.open(CobFile.Mode.OUTPUT); }
        } else {
            postFile.open(CobFile.Mode.IO);
            if (!postFile.status.equals("00")) { postFile.close(); postFile.open(CobFile.Mode.OUTPUT); }
        }
        postFile.rrn = batch.longv("batch-start");
    }

    private void blWrite() {
        String u = Maps04.toDate(oi.longv("oi-date"));
        post.set("post-date", u.substring(0, 6) + u.substring(8, 10));
        post.setNum("batch", batch.longv("batch-nos"));
        batch.setNum("items", batch.longv("items") + 1);
        post.setNum("post-number", batch.longv("items"));
        post.setNum("post-amount", workNet);
        post.set("post-legend", pad(oi.longv("oi-invoice") + " : " + sales.str("sales-name"), 32));
        post.setNum("post-dr", sys.longv("s-debtors"));
        post.setNum("post-cr", sys.longv("sl-sales-ac"));
        post.setNum("dr-pc", 0); post.setNum("cr-pc", 0); post.setNum("vat-pc", 0);
        post.setNum("vat-ac", sys.longv("vat-ac"));
        BigDecimal vat = n("oi-vat").add(n("oi-e-vat")).add(n("oi-c-vat"));
        post.setNum("vat-amount", vat);
        post.set("post-vat-side", "CR");
        post.set("post-code", "SL");
        BigDecimal amt = post.num("post-amount");
        batch.setNum("input-gross", batch.num("input-gross").add(amt)); batch.setNum("actual-gross", batch.num("actual-gross").add(amt));
        batch.setNum("input-vat", batch.num("input-vat").add(vat)); batch.setNum("actual-vat", batch.num("actual-vat").add(vat));
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
            irs.setNum("irs-vat-amount", vat);
            irsFile.write(irs);
        } else postFile.write(post);
        postFile.rrn++;
        if (batch.intv("items") == 99) { blClose(); blOpen(); }
    }

    private void blClose() {
        batchFile.write(batch);
        if (!batchFile.status.equals("00")) {
            display(23, 1, SL132);
            show(23, 33, batchFile.status);
            display(23, 36, fileStatMsg(batchFile.status));
            display(24, 1, SL002);
            accept(24, 33, 1);
        }
        sys.setNum("postings", postFile.rrn);
        batchFile.close();
        if (irsUsed) irsFile.close(); else postFile.close();
    }
}
