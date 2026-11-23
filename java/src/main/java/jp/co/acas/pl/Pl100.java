package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl100.cbl: 支払転記（Cash Posting）。 */
public class Pl100 extends PlBase {
    static final String PROG_NAME = "PL100 (3.01.04)";
    private static final String CR = "z(6)9.99cr", AMT = "z(6)9.99";
    private Rec purch, oi, batch, post;
    private CobFile purchaseFile, oi5, batchFile, postFile, irsFile;
    private boolean gl, irs;
    private Printer prt;
    private int page, lineCnt;
    private String uDate = "";

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("p-flag-p") != 2) {
            maps99(23);
            maps99(15);
            return;
        }
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 36, "Cash Posting");
        show(1, 71, fromUk(toDay()), 2);
        while (true) {
            display(12, 12, "OK to post payment transactions (YES/NO) ? <   > enter {CR}");
            String r = upper(pad(acceptUpdate(12, 56, 3, "   "), 3));
            if (r.equals("NO ")) return;
            if (r.equals("YES")) break;
        }
        Rec s4 = sys4();
        purch = purchRec(); oi = oiRec();
        purchaseFile = purchaseFile(purch); oi5 = oi5File();
        oi5.open(Mode.IO); purchaseFile.open(Mode.IO);
        gl = sys.intv("level-1") == 1;
        irs = sys.str("irs-instead").equals("Y");
        if (gl) blOpen();
        prt = new Printer("prt-1");
        int pageLines = sys.intv("page-lines");
        headings();
        display(16, 1, "Posting......Please wait");
        BigDecimal[] t = {BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO}, j = {BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO};
        long nDeduct = 0;
        while (oi5.readNext(oi).equals("00")) {
            int type = oi.intv("oi-type");
            if (type != 2 && type != 5 && type != 6) continue;
            if (type == 2 && oi.longv("oi-b-nos") != 0 && oi.longv("oi-b-item") != 0) {
                computePurchPay();
                oi.setNum("oi-b-nos", 0); oi.setNum("oi-b-item", 0); oi.setNum("oi-cr", 0);
                oi5.rewrite(Pl080.oi5Bytes(oi));
                continue;
            }
            if (oi.intv("oi-status") == 1 || type == 2) continue;
            if (oi.longv("oi-b-nos") == 0 && oi.longv("oi-b-item") == 0) continue;
            purch.set("purch-key", oi.str("oi-supplier"));
            String name = invalid(purchaseFile.read(purch)) ? "Supplier Unknown" : purch.str("purch-name");
            uDate = Maps04x(oi.longv("oi-date"));
            BigDecimal approp = oi.num("oi-approp"), paid = oi.num("oi-paid"), deduct = oi.num("oi-deduct-amt");
            if (deduct.signum() != 0) nDeduct++;
            BigDecimal oldBal = purch.num("purch-current").subtract(purch.num("purch-unapplied"));
            purch.sub("purch-current", approp);
            purch.sub("purch-current", deduct);
            if (paid.compareTo(approp) != 0) purch.add("purch-unapplied", paid.subtract(approp));
            if (purch.num("purch-current").signum() < 0) {
                purch.add("purch-unapplied", purch.num("purch-current").negate());
                purch.setNum("purch-current", 0);
            }
            BigDecimal newBal = purch.num("purch-current").subtract(purch.num("purch-unapplied"));
            purch.setNum("purch-last-pay", oi.longv("oi-date"));
            BigDecimal[] a = type == 5 ? t : j;
            a[0] = a[0].add(approp); a[1] = a[1].add(paid); a[2] = a[2].add(deduct);
            if (type == 5) s4.add("pl-payments", paid);
            oi.setNum("oi-paid", approp);
            purchaseFile.rewrite(purch);
            if (gl) blWrite();
            oi.setNum("oi-status", 1);
            oi5.rewrite(Pl080.oi5Bytes(oi));
            prt.after(line5(Num.edit(oi.longv("oi-b-nos"), "z9(4)") + "/" + Num.z9(oi.longv("oi-b-item"), 3) + " "
                    + pad(fromUk(uDate), 11) + pad(oi.str("oi-supplier"), 8) + pad(name, 25) + "    "
                    + pad(type == 6 ? "Cr Journal" : "Payment", 10) + Num.edit(oldBal, CR) + "  " + Num.edit(newBal, CR) + " ",
                    paid, deduct, approp), 1);
            lineCnt++;
            if (lineCnt > pageLines) headings();
        }
        purchaseFile.close(); oi5.close();
        prt.after(line5(pad("", 24) + pad("Payment Totals", 25) + pad("", 40), t[1], t[2], t[0]), 3);
        prt.after(line5(pad("", 24) + pad("Journal Totals", 25) + pad("", 40), j[1], j[2], j[0]), 2);
        prt.close();
        spoolPrt1();
        BigDecimal tDeduct = t[2].add(j[2]);
        if (tDeduct.signum() != 0) analiseDeductions(nDeduct, tDeduct);
        if (gl) blClose();
        sys.set("oi-5-flag", "Y");
        sys.setNum("p-flag-p", 0);
    }

    private String Maps04x(long bin) { return jp.co.acas.sys.Maps04.toDate(bin); }

    private static String line5(String head, BigDecimal paid, BigDecimal deduct, BigDecimal approp) {
        return head + Num.edit(paid.abs(), AMT) + "  " + Num.edit(deduct.abs(), AMT) + "    " + Num.edit(approp.abs(), AMT) + " ";
    }

    private void computePurchPay() {
        if (oi.longv("oi-date-cleared") == 0) return;
        long workA = oi.longv("oi-date-cleared") - oi.longv("oi-date"), workB = 0;
        if (purch.longv("purch-pay-activety") != 0) workB = purch.longv("purch-pay-activety") * purch.longv("purch-pay-average");
        workB += workA;
        purch.setNum("purch-pay-activety", purch.longv("purch-pay-activety") + 1);
        purch.setNum("purch-pay-average", workB / purch.longv("purch-pay-activety"));
        if (workA > purch.longv("purch-pay-worst")) purch.setNum("purch-pay-worst", workA);
    }

    private void analiseDeductions(long n, BigDecimal tDeduct) {
        Rec val = fdRec(Layout.of("copybooks/fdval.cob", "value-record"));
        CobFile vf = CobFile.indexed(ctx.store, ctx.path("value.dat"), val, "va-code");
        vf.open(Mode.IO);
        val.set("va-code", "Pzb");
        for (int pass = 0; pass < 2; pass++) {
            if (invalid(vf.read(val))) break;
            val.setNum("va-t-this", val.longv("va-t-this") - n);
            val.setNum("va-t-year", val.longv("va-t-year") - n);
            val.sub("va-v-this", tDeduct);
            val.sub("va-v-year", tDeduct);
            vf.rewrite(val);
            val.set("va-second", " ");
        }
        vf.close();
    }

    private void headings() {
        page++;
        String line1 = pad(PROG_NAME, 56) + pad("Cash Posting Report", 68) + "Page " + Num.edit(page, "zz9");
        String line2 = pad(sys.str("usera"), 56) + pad("", 66) + fromUk(toDay());
        if (page != 1) {
            prt.afterPage(line1);
            prt.after(line2, 1);
            prt.after("", 1);
        } else {
            prt.before(line1, 1);
            prt.before(line2, 1);
        }
        prt.after(pad(" Number   ---Date--- <-----------Supplier------------>  --Type-- ", 67)
                + " Old Balance    New Balance    Payment   Deduction   Apportioned", 1);
        prt.after("", 1);
        lineCnt = 5;
    }

    private void blOpen() {
        batch = fdRec(Layout.of("copybooks/fdbatch.cob", "batch-record"));
        post = fdRec(Layout.of("copybooks/fdpost.cob", "posting-record"));
        batchFile = CobFile.indexed(ctx.store, ctx.path("batch.dat"), batch, "batch-key");
        if (!batchFile.open(Mode.IO).equals("00")) { batchFile.close(); batchFile.open(Mode.OUTPUT); }
        batch.setNum("batch-nos", sys.longv("bl-next-batch"));
        batch.setNum("ledger", 2);
        sys.setNum("bl-next-batch", sys.longv("bl-next-batch") + 1);
        batch.setNum("batch-status", 0); batch.setNum("cleared-status", 0);
        batch.setNum("bcycle", sys.intv("scycle"));
        batch.setNum("entered", sys.longv("run-date"));
        batch.set("description", "Purchase Ledger Payments");
        for (String f : new String[]{"bdefault", "batch-def-ac", "batch-def-pc", "items", "input-gross", "input-vat", "actual-gross", "actual-vat"})
            batch.setNum(f, 0);
        batch.set("convention", "DR");
        batch.set("batch-def-code", "PL");
        batch.set("batch-def-vat", "I");
        batch.setNum("batch-start", sys.longv("postings") + 1);
        if (irs) {
            irsFile = CobFile.sequential(ctx.store, ctx.path("irs-post.dat"));
            if (!irsFile.open(Mode.EXTEND).equals("00")) { irsFile.close(); irsFile.open(Mode.OUTPUT); }
        } else {
            postFile = CobFile.relative(ctx.store, ctx.path("posting.dat"));
            if (!postFile.open(Mode.IO).equals("00")) { postFile.close(); postFile.open(Mode.OUTPUT); }
            postFile.rrn = batch.longv("batch-start");
        }
    }

    private void blWrite() {
        post.set("post-date", uDate.substring(0, 6) + uDate.substring(8, 10));
        batch.setNum("items", batch.intv("items") + 1);
        post.setNum("post-number", batch.intv("items"));
        post.setNum("post-amount", oi.num("oi-paid"));
        post.setNum("batch", batch.longv("batch-nos"));
        post.set("post-legend", Long.toString(oi.longv("oi-invoice")) + " : " + purch.str("purch-name"));
        post.setNum("post-dr", sys.longv("p-creditors"));
        post.setNum("post-cr", sys.longv("bl-pay-ac"));
        post.setNum("dr-pc", 0); post.setNum("cr-pc", 0); post.setNum("vat-pc", 0);
        post.setNum("vat-ac", 0);
        post.setNum("vat-amount", 0);
        BigDecimal amt = post.num("post-amount");
        batch.add("input-gross", amt); batch.add("actual-gross", amt);
        post.set("post-code", "PL");
        post.set("post-vat-side", "DR");
        if (irs) {
            Rec ir = Layout.of("copybooks/fdpost-irs.cob", "irs-posting-record").newRec();
            ir.set("irs-post-key", post.str("post-key"));
            ir.set("irs-post-code", "PL");
            ir.set("irs-post-date", post.str("post-date"));
            ir.setNum("irs-post-dr", post.longv("post-dr"));
            ir.setNum("irs-post-cr", post.longv("post-cr"));
            ir.setNum("irs-post-amount", amt);
            ir.set("irs-post-legend", post.str("post-legend"));
            ir.setNum("irs-vat-ac-def", 31);
            ir.set("irs-post-vat-side", "DR");
            ir.setNum("irs-vat-amount", 0);
            irsFile.write(ir);
        } else {
            postFile.write(post);
            postFile.rrn++;
        }
        if (batch.intv("items") == 99) { blClose(); blOpen(); }
    }

    private void blClose() {
        String st = batchFile.write(batch);
        if (!st.equals("00")) {
            display(23, 1, "PL132 Err on Batch file write : ");
            show(23, 33, st);
            display(24, 1, "PL002 Note error and hit return");
            accept(24, 30, 1);
        }
        if (!irs) sys.setNum("postings", postFile.rrn);
        batchFile.close();
        if (irs) irsFile.close(); else postFile.close();
    }
}
