package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;

import java.math.BigDecimal;

/** pl060.cbl: 仕入請求書 転記。 */
public class Pl060 extends PlBase {
    static final String PROG_NAME = "PL060 (3.01.07)";
    static final String[] LIT = {"Receipts", "Invoices", "Credit Notes"};
    static final String CR = "z(6)9.99cr", CR8 = "z(7)9.99cr";
    private Printer prt;
    private int page, lineCnt, pageLines;
    private Rec purch, oi, si, batch, post;
    private CobFile purchaseFile, oi4, oi5, batchFile, postFile, irsFile;
    private BigDecimal work1 = BigDecimal.ZERO, workB = BigDecimal.ZERO;
    private boolean gl, irs;
    private String uDate = "";

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 31, "Invoice Posting Report");
        show(1, 71, fromUk(toDay()), 2);
        while (true) {
            display(8, 12, "OK to post Purchase Transactions (YES/NO) ?  [   ]");
            String r = upper(acceptUpdate(8, 58, 3, "   ", 0)).stripTrailing();
            if (r.equals("NO")) return;
            if (r.equals("YES")) break;
        }
        eraseEol(8, 1);
        sys.setNum("p-flag-i", 2);
        sys.setNum("p-flag-a", 1);
        sys.setNum("file-status", 0, 28);
        sys.set("oi-5-flag", "Y");
        purch = purchRec();
        oi = oiRec(); si = Layout.of("purchase/wssoi.cob", "si-header").newRec();
        purchaseFile = purchaseFile(purch);
        oi4 = CobFile.sequential(ctx.store, ctx.path("openitm4.dat"));
        oi5 = oi5File();
        if (sys.intv("file-status", 29) == 0) {
            oi5.open(Mode.OUTPUT); oi5.close();
            sys.setNum("file-status", 1, 29);
        }
        gl = sys.intv("level-1") == 1;
        irs = sys.str("irs-instead").equals("Y");
        pageLines = sys.intv("page-lines");
        if (gl) blOpen();
        purchaseFile.open(Mode.IO);
        prt = new Printer("prt-1");
        eraseEos(12, 1);
        display(12, 1, "Posting......Please Wait");
        display(14, 1, "Phase 1");
        page = 0;
        headings();
        BigDecimal[] totNet = {BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO}, totVat = totNet.clone();
        boolean purchaseMissing = false;
        oi4.open(Mode.INPUT);
        oi5.open(Mode.IO);
        while (true) {
            if (!oi4.readNext(oi).equals("00")) break;
            purch.set("purch-key", oi.str("oi-supplier"));
            boolean unknown = invalid(purchaseFile.read(purch));
            String name;
            if (unknown) {
                purchaseMissing = true;
                initialize(purch);
                purch.set("purch-name", "Supplier Unknown");
                purch.set("purch-key", oi.str("oi-supplier"));
                name = "Supplier Unknown";
            } else name = purch.str("purch-name");
            uDate = Maps04.toDate(oi.longv("oi-date"));
            int type = oi.intv("oi-type");
            String l5type = type == 2 ? "Invoice" : type == 3 ? "Cr. Note" : type == 1 ? "Receipt" : "";
            BigDecimal workVat = oi.num("oi-vat").add(oi.num("oi-c-vat"));
            BigDecimal goods = oi.num("oi-net");
            BigDecimal workNet = oi.num("oi-net").add(oi.num("oi-carriage"));
            int a = Math.max(1, Math.min(3, type)) - 1;
            totVat[a] = totVat[a].add(workVat);
            totNet[a] = totNet[a].add(workNet);
            work1 = workNet.add(workVat);
            if (gl) blWrite(workNet);
            String oldBal = Num.edit(purch.num("purch-current").subtract(purch.num("purch-unapplied")), CR);
            if (type == 1 || type == 2) purchComp(goods);
            int q = sys.intv("current-quarter");
            if (type == 1) {
                purch.add("pturnover-q", goods, q);
                purch.setNum("purch-last-inv", oi.longv("oi-date"));
                purch.setNum("purch-last-pay", oi.longv("oi-date"));
            }
            if (type == 2) {
                purch.add("pturnover-q", goods, q);
                purch.add("purch-current", workVat.add(workNet));
                purch.setNum("purch-last-inv", oi.longv("oi-date"));
            }
            if (type == 3) {
                purch.add("pturnover-q", goods, q);
                purch.add("purch-current", workVat.add(workNet));
                purch.setNum("purch-last-pay", oi.longv("oi-date"));
                crNotes();
                creditComp(goods);
            }
            if (purch.intv("purch-status") == 0) purch.setNum("purch-status", 1);
            if (purch.num("purch-current").signum() < 0) {
                purch.add("purch-unapplied", purch.num("purch-current").negate());
                purch.setNum("purch-current", 0);
            }
            String newBal = Num.edit(purch.num("purch-current").subtract(purch.num("purch-unapplied")), CR);
            if (unknown) { purch.setNum("purch-status", 1); purchaseFile.write(purch); }
            else purchaseFile.rewrite(purch);
            String st = oi5.write(oi5Bytes());
            if (invalid(st)) {
                display(16, 1, "PL130 Open-IT5 = ");
                show(17, 1, oi.str("oi-supplier"));
                show(18, 1, Num.edit(oi.longv("oi-invoice"), "z(7)9") + " ");
                display(19, 1, "fs-reply = ");
                show(19, 12, st);
                display(24, 1, "PL133 PE 060-01", 4);
                display(24, 12, "PL002 Note error and hit return");
                accept(24, 50, 1);
            }
            String line5 = Num.edit(oi.longv("oi-invoice"), "z(7)9") + " " + pad(fromUk(uDate), 11)
                    + pad(oi.str("oi-supplier"), 9) + pad(name, 25) + "  " + pad(l5type, 9)
                    + oldBal + newBal + pad("", 7) + Num.edit(workNet, CR) + Num.edit(workVat, CR) + Num.edit(work1, CR);
            prt.after(line5, 1);
            lineCnt++;
            if (lineCnt > pageLines) headings();
        }
        purchaseFile.close(); oi4.close(); oi5.close();
        if (lineCnt > pageLines - 7) headings();
        for (int a = 0; a < 3; a++)
            prt.after(pad("", 11) + pad("Total  Posted", 14) + pad(LIT[a], 18) + Num.edit(totNet[a], CR8)
                    + Num.edit(totVat[a], CR8) + Num.edit(totNet[a].add(totVat[a]), CR8), a == 0 ? 3 : 2);
        if (gl) blClose();
        oi5.open(Mode.IO);
        workB = BigDecimal.ZERO;
        display(14, 7, "2");
        Rec r5 = oiRec();
        while (oi5.readNext(r5).equals("00")) {
            System.arraycopy(r5.bytes(), 0, oi.bytes(), 0, oi.bytes().length);
            if (oi.intv("oi-status") == 1) continue;
            if (oi.intv("oi-type") == 3) crSwop();
        }
        oi4.open(Mode.OUTPUT);
        oi4.close(); oi5.close();
        boolean unappl = sys.intv("file-status", 28) == 1;
        if (lineCnt > pageLines - 6 && unappl) newHeading();
        if (unappl) prt.after(pad("", 24) + pad("Un-Applied Credits C/F ", 32) + bwz(workB), 3);
        Rec s4 = sys4();
        s4.add("pl-cn-unappl-this-month", workB);
        if (purchaseMissing) prt.after("PL134 Warning Record/s missing in Purchase File", 3);
        prt.close();
        spoolPrt1();
        sys.setNum("file-status", 0, 28);
    }

    /** write/rewrite open-item-record-5 from oi-header（109 バイト、不足分は空白）。 */
    private byte[] oi5Bytes() {
        byte[] b = new byte[109];
        java.util.Arrays.fill(b, (byte) ' ');
        System.arraycopy(oi.bytes(), 0, b, 0, Math.min(109, oi.bytes().length));
        return b;
    }

    private static String bwz(BigDecimal v) { return v.signum() == 0 ? pad("", 11) : Num.edit(v, "z(7)9.99"); }
    private static String bwzInt(long v) { return v == 0 ? pad("", 10) : Num.edit(v, "z(7)9") + "  "; }

    private void crSwop() {
        work1 = oi.num("oi-net").add(oi.num("oi-carriage")).add(oi.num("oi-vat")).add(oi.num("oi-c-vat")).add(oi.num("oi-paid"));
        if (work1.signum() == 0) {
            display(24, 1, "PL131 PE - CR SWOP: Return to continue", 4);
            accept(24, 34, 1);
        }
        if (sys.intv("file-status", 28) == 0) newHeading();
        oi.setNum("oi-status", 1);
        prt.after(pad(oi.str("oi-supplier"), 12) + bwzInt(oi.longv("oi-invoice")) + pad("", 4) + bwz(work1) + pad("", 4)
                + bwz(oi.num("oi-paid")) + pad("", 4) + bwzInt(oi.longv("oi-cr")) + pad("", 4) + pad("Cr. Note", 12), 1);
        lineCnt++;
        if (lineCnt > pageLines) newHeading();
        workB = workB.add(work1);
        work1 = work1.negate();
        oi.add("oi-paid", work1);
        oi5.rewrite(oi5Bytes());
    }

    private String line1() { return pad(PROG_NAME, 54) + pad("Invoice Posting Report", 70) + "Page " + Num.edit(page, "zz9"); }
    private String line2() { return pad(sys.str("usera"), 54) + pad("", 68) + fromUk(toDay()); }

    private void newHeading() {
        if (sys.intv("file-status", 28) == 0) sys.setNum("file-status", 1, 28);
        page++;
        String l1a = pad("", 56) + "Un-Applied Credits";
        if (page != 1) {
            prt.afterPage(line1()); prt.after(line2(), 1); prt.after(l1a, 1); prt.after("", 1);
        } else {
            prt.before(line1(), 1); prt.before(line2(), 1); prt.before(l1a, 1);
        }
        prt.after("--Supplier--   Invoice      Bal C/F        Applied      Cr. Note          Type    ", 1);
        prt.after("", 1);
        lineCnt = 6;
    }

    private void headings() {
        page++;
        if (page != 1) {
            prt.afterPage(line1()); prt.after(line2(), 1); prt.after("", 1);
        } else {
            prt.before(line1(), 1); prt.before(line2(), 1);
        }
        prt.after(" Number     Date    <------------Supplier------------>    Type  "
                + " Old Balance  New Balance            Net         Vat       Gross", 1);
        prt.after("", 1);
        lineCnt = 5;
    }

    private long work2() {
        long act = purch.longv("purch-activety"), avg = purch.longv("purch-average");
        return act != 0 && avg != 0 ? act * avg : 0;
    }
    private void purchComp(BigDecimal goods) {
        BigDecimal w = BigDecimal.valueOf(work2());
        purch.setNum("purch-activety", purch.longv("purch-activety") + 1);
        w = BigDecimal.valueOf(w.add(goods).longValue());
        purch.setNum("purch-average", w.longValue() / purch.longv("purch-activety"));
    }
    private void creditComp(BigDecimal goods) {
        long w = work2();
        if (w == 0) return;
        w = BigDecimal.valueOf(w).add(goods).longValue();
        if (purch.longv("purch-activety") != 0) purch.setNum("purch-average", w / purch.longv("purch-activety"));
    }

    /** cr-notes: 貸方票を元請求書（または同一仕入先の未決済請求書）へ充当する。 */
    private void crNotes() {
        System.arraycopy(oi.bytes(), 0, si.bytes(), 0, oi.bytes().length);
        boolean firstPass = true;
        Rec key = oiRec();
        key.set("oi-supplier", oi.str("oi-supplier"));
        key.setNum("oi-invoice", oi.longv("oi-cr"));
        boolean started = !invalid(oi5.start(key, ">="));
        if (started) {
            workB = BigDecimal.ZERO;
            if (work1.signum() < 0) work1 = work1.negate();
            work1 = work1.subtract(si.num("si-paid"));
        }
        Rec r5 = oiRec();
        while (started) {
            boolean endLoop = false;
            while (true) {
                if (!oi5.readNext(r5).equals("00")) { endLoop = true; break; }
                System.arraycopy(r5.bytes(), 0, oi.bytes(), 0, oi.bytes().length);
                if (oi.intv("oi-type") != 2) continue;
                if (!oi.str("oi-supplier").equals(si.str("si-supplier"))) { endLoop = true; break; }
                if (oi.intv("oi-status") == 1) continue;
                if (si.longv("si-cr") == oi.longv("oi-invoice") || !firstPass) apportion();
                if (work1.signum() != 0) continue;
                break;
            }
            if (work1.signum() == 0 || !firstPass) break;
            firstPass = false;
            key.set("oi-supplier", si.str("si-supplier"));
            key.setNum("oi-invoice", 0);
            started = !invalid(oi5.start(key, ">="));
        }
        System.arraycopy(si.bytes(), 0, oi.bytes(), 0, oi.bytes().length);
    }

    private void apportion() {
        BigDecimal workA = oi.num("oi-net").add(oi.num("oi-carriage")).add(oi.num("oi-vat")).add(oi.num("oi-c-vat")).subtract(oi.num("oi-paid"));
        if (workA.signum() == 0) oi.setNum("oi-status", 1);
        else {
            if (workA.signum() < 0) return;
            int c = workA.compareTo(work1);
            BigDecimal amt = c >= 0 ? work1 : workA;
            oi.add("oi-paid", amt); si.add("si-paid", amt); oi.add("oi-p-c", amt);
            work1 = work1.subtract(amt);
            if (c == 0) { oi.setNum("oi-status", 1); si.setNum("si-status", 1); }
            else if (c > 0) si.setNum("si-status", 1);
            else oi.setNum("oi-status", 1);
            if (work1.signum() == 0) si.setNum("si-status", 1);
        }
        oi5.rewrite(oi5Bytes());
    }

    private void blOpen() {
        batch = fdRec(Layout.of("copybooks/fdbatch.cob", "batch-record"));
        post = fdRec(Layout.of("copybooks/fdpost.cob", "posting-record"));
        batchFile = CobFile.indexed(ctx.store, ctx.path("batch.dat"), batch, "batch-key");
        if (!batchFile.open(Mode.IO).equals("00")) { batchFile.close(); batchFile.open(Mode.OUTPUT); }
        batch.setNum("batch-nos", sys.longv("next-batch"));
        batch.setNum("ledger", 2);
        sys.setNum("next-batch", sys.longv("next-batch") + 1);
        batch.setNum("batch-status", 0); batch.setNum("cleared-status", 0);
        batch.setNum("bcycle", sys.intv("scycle"));
        batch.setNum("entered", sys.longv("run-date"));
        batch.set("description", "Purchase Ledger Invoices");
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

    private void blWrite(BigDecimal workNet) {
        post.set("post-date", uDate.substring(0, 6) + uDate.substring(8, 10));
        post.setNum("batch", batch.longv("batch-nos"));
        batch.setNum("items", batch.intv("items") + 1);
        post.setNum("post-number", batch.intv("items"));
        post.setNum("post-amount", workNet);
        post.set("post-legend", Long.toString(oi.longv("oi-invoice")) + " : " + purch.str("purch-name"));
        post.setNum("post-cr", sys.longv("p-creditors"));
        post.setNum("post-dr", sys.longv("bl-purch-ac"));
        post.setNum("dr-pc", 0); post.setNum("cr-pc", 0); post.setNum("vat-pc", 0);
        post.setNum("vat-ac", sys.longv("vat-ac"));
        BigDecimal vat = oi.num("oi-vat").add(oi.num("oi-c-vat"));
        post.setNum("vat-amount", vat);
        post.set("post-vat-side", "DR");
        post.set("post-code", "PL");
        BigDecimal amt = post.num("post-amount"), va = post.num("vat-amount");
        batch.add("input-gross", amt); batch.add("actual-gross", amt);
        batch.add("input-vat", va); batch.add("actual-vat", va);
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
            ir.setNum("irs-vat-amount", va);
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
