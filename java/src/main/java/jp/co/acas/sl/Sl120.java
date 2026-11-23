package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** sl120.cbl: 売掛金年齢調べ（Aged Debtors Report）。sl115 が作る oisort.wrk を読む。 */
public class Sl120 extends SlProgram {
    static final String PROG_NAME = "SL120 (3.01.07)";
    private static final BigDecimal Z = BigDecimal.ZERO, HUNDRED = new BigDecimal(100);

    /** 帳票行の作業領域（COBOL の 01 レベル。項目単位で上書きし、書かれない桁は前の内容が残る）。 */
    private static final class Buf {
        final StringBuilder s;
        Buf(int len) { s = new StringBuilder(" ".repeat(len)); }
        void put(int off, int len, String v) { s.replace(off, off + len, pad(v, len)); }
        void spaces() { int n = s.length(); s.setLength(0); s.append(" ".repeat(n)); }
        String get(int off, int len) { return s.substring(off, off + len); }
        @Override public String toString() { return s.toString(); }
    }

    private Rec sys, sys4, sales, oi, in;
    private CobFile salesFile, sFile;
    private Prt print;
    private final Buf l5 = new Buf(132), l6 = new Buf(131), l8 = new Buf(90);
    private String l3List = "Current Period is " + "  ", l3Date = "", line4 = pad("Customer  Name                           Telephone  "
        + "   Invoice     Date       Current         30         60    90 & Over   Payments", 132);
    private String customerIn = " ".repeat(7), lastRead = " ".repeat(7), key = "";
    private int pageNos, lineCnt = 66, pageLines, fsReply, fsReply2;
    private long entered;
    private BigDecimal payValue = Z, work1 = Z, invAmount = Z, amountOut = Z;
    private long inv0, inv30, inv60, inv90, totNoPay, totNoCrBal, totAcctActive, totAcctLive, totNoLate, totNoUnappPay;
    private BigDecimal totBal0 = Z, totBal30 = Z, totBal60 = Z, totBal90 = Z, totAmtLate = Z, totAmtPay = Z, totAmtCrBal = Z,
        totAmtUnappPay = Z, totUnapplCredits = Z, totSalesBal = Z;
    private BigDecimal bal0 = Z, bal30 = Z, bal60 = Z, bal90 = Z, balT = Z, balPay = Z;

    private static int d(char c) { return c & 0x0F; }

    /** 編集項目への転記（整数部は intDigits 桁に切り詰め、小数部は切捨て）。 */
    private static String ed(BigDecimal v, String pic, int intDigits) {
        return Num.edit(v.setScale(2, RoundingMode.DOWN).remainder(BigDecimal.TEN.pow(intDigits)), pic);
    }
    private static String ed(long v, String pic, int intDigits) { return ed(BigDecimal.valueOf(v), pic, intDigits); }
    private static String cr13(BigDecimal v) { return ed(v, "zzzz,zz9.99cr", 7); }
    private static String n13(long v) { return ed(v, "zzzz,zz9", 7) + " ".repeat(5); }
    private static String u11(BigDecimal v) { return ed(v.abs(), "zzzz,zz9.99", 7); }

    // line-8 / line-10 の桁位置
    private void l8Head(String v) { l8.put(0, 25, v); }
    private void l8Tot(BigDecimal v) { l8.put(25, 13, cr13(v)); }
    private void l8Col(int i, BigDecimal v) { l8.put(38 + 13 * i, 13, cr13(v)); }
    private void l10Tot(long v) { l8.put(25, 13, n13(v)); }

    @Override
    public void run(Object... args) {
        sys = sys(); sys4 = sys4();
        eraseEos(1, 1);
        if (sys.intv("s-flag-p") == 1) { maps99(24); maps99(15); return; }
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("file-status", 19) != 1) { maps99(19); maps99(15); return; }
        eraseEos(2, 2);
        show(2, 2, PROG_NAME, 2);
        display(2, 31, "Aged Debtors Report", 2);
        show(2, 71, fromUk(toDay()), 2);
        pageLines = sys.intv("page-lines");
        // 編集数字項目の初期値はゼロの編集結果。
        l8.put(25, 13, cr13(Z));
        for (int i = 0; i < 4; i++) l8Col(i, Z);
        l6.put(17, 7, "Terms:"); l6.put(28, 13, "Credit Limit:"); l6.put(55, 8, "Balance:");
        trailBalance();
        reportAnalysis();
        print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private void trailBalance() {
        display(4, 41, "****************************************", 2);
        display(5, 41, "*Date    [  /  /    ]                  *", 2);
        display(6, 41, "*A/C Nos [       ]                   ***", 2);
        display(7, 41, "*Value  [         ]*                   *", 2);
        display(8, 41, "****************************************", 2);
        display(12, 1, "Notes", 2);
        display(13, 1, "*****", 2);
        display(15, 1, " (1)  -  <Date>  :  Appears on listing", 2);
        display(16, 1, " (2)  -  <A/C>   :  A/c's to match for printing", 2);
        display(17, 1, " (3)  -  <Value> :  Minimum o/s to print", 2);
        String wsDate = pad(fromUk(toDay()), 10);
        while (true) {
            show(5, 51, wsDate, 3);
            wsDate = pad(acceptUpdate(5, 51, 10, wsDate), 10);
            entered = validateDate(wsDate);
            if (entered != 0) break;
        }
        l3Date = wsDate;
        customerIn = upper(pad(accept(6, 51, 7), 7));
        show(7, 50, "000000.00");
        long v = 0;
        for (char c : pad(accept(7, 50, 8), 8).toCharArray()) v = v * 10 + d(c);
        payValue = BigDecimal.valueOf(v, 2);
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        pageNos = 0;
        headings1();
        sales = salesRec(); oi = oiHeader(); in = oi3Rec();
        salesFile = salesFile(sales);
        sFile = CobFile.sequential(ctx.store, ctx.path(F_OISORT));
        salesFile.open(CobFile.Mode.INPUT);
        sFile.open(CobFile.Mode.INPUT);
        if (!sFile.status.equals("00")) {
            sFile.close();
            sFile.open(CobFile.Mode.OUTPUT); sFile.close();
            sFile.open(CobFile.Mode.INPUT);
            display(24, 50, "No Open invoice records present");
        }
        if (!customerIn.isBlank()) {
            sales.set("sales-key", customerIn);
            salesFile.start(sales, ">=");
            customerIn = customerIn.replace(' ', 'Z');
        }
        boolean roi1;
        perform:
        while (true) {
            readSales();
            if (fsReply == 99) break;
            roi1 = lastRead.equals(key);
            while (true) {
                if (!roi1) {
                    // read-open-item
                    if (lastRead.compareTo(key) > 0) continue perform;
                    if (fsReply2 == 99) break;
                    if (!sFile.readNext(in).equals("00")) { fsReply2 = 99; break; }
                    move(in, oi);
                    lastRead = pad(oi.str("oi-customer"), 7);
                    if (lastRead.compareTo(key) > 0) break;
                    if (!lastRead.equals(key)) { bypassAgeing(); continue; }
                }
                roi1 = false;
                roi1();
            }
            endStatement();
        }
        sFile.close(); salesFile.close();
    }

    private void roi1() {
        int type = oi.intv("oi-type");
        if (type == 1 || type == 4) return;
        if (lineCnt > pageLines) headings1();
        if (type == 5 || type == 6) oi.setNum("oi-invoice", 0);
        long invoice = oi.longv("oi-invoice");
        l5.put(54, 8, invoice == 0 ? "" : Num.edit(invoice, "z(7)9"));
        l5.put(62, 1, oi.str("oi-hold-flag"));
        l5.put(64, 10, binToDate(oi.longv("oi-date")));
        invAmount = oi.num("oi-net").add(oi.num("oi-extra")).add(oi.num("oi-carriage")).add(oi.num("oi-vat")).add(oi.num("oi-discount"))
            .add(oi.num("oi-e-vat")).add(oi.num("oi-deduct-amt")).add(oi.num("oi-deduct-vat")).add(oi.num("oi-c-vat"));
        BigDecimal paid = oi.num("oi-paid");
        if (type == 2) amountOut = invAmount.subtract(paid);
        if (type == 3) {
            invAmount = invAmount.add(paid);
            l5Bal0(invAmount);
            checkZero(type);
        } else if (type == 5 || type == 6) {
            balPay = balPay.add(paid);
            checkZero(type);
        } else {
            work1 = BigDecimal.valueOf(entered - oi.longv("oi-date"));
            int b = amountOut.signum() == 0 ? 0 : 1;
            if (amountOut.signum() < 0) work1 = BigDecimal.ONE;
            int w = work1.intValue();
            if (w < 30) {
                bal0 = bal0.add(amountOut); l5Bal0(amountOut); checkZero(type);
                totBal0 = totBal0.add(amountOut); inv0 += b;
            } else if (w < 60) {
                bal30 = bal30.add(amountOut); l5.put(88, 11, ed(amountOut.abs(), "zzzzzzz9.99", 8));
                totBal30 = totBal30.add(amountOut); inv30 += b;
            } else if (w < 90) {
                bal60 = bal60.add(amountOut); l5.put(99, 11, ed(amountOut.abs(), "zzzzzzz9.99", 8));
                totBal60 = totBal60.add(amountOut); inv60 += b;
            } else {
                l5.put(110, 10, ed(amountOut.abs(), "zzzzzz9.99", 7));
                totBal90 = totBal90.add(amountOut); inv90 += b;
                bal90 = bal90.add(amountOut);
            }
            balT = balT.add(amountOut);
        }
        bypassAgeing();
        // bypass-age-go
        if (type == 3 && invAmount.signum() != 0) totUnapplCredits = totUnapplCredits.add(invAmount);
        l5.put(63, 1, type == 2 && amountOut.compareTo(oi.num("oi-deduct-amt")) == 0 && amountOut.signum() != 0 ? "L" : " ");
        amountOut = Z;
        if (!l5.get(0, 9).isBlank()) { print.after("", 1); lineCnt++; }
        print.after(l5.toString(), 1);
        lineCnt++;
        l5.spaces();
    }

    private void l5Bal0(BigDecimal v) { l5.put(75, 12, ed(v, "zzzzzz9.99cr", 7)); }
    private void l5Payments(BigDecimal v) { l5.put(121, 10, ed(v.abs(), "zzzzzz9.99", 7)); }

    private void bypassAgeing() {
        int type = oi.intv("oi-type");
        if (type != 5 && type != 6) return;
        if (oi.num("oi-deduct-amt").signum() != 0) { totAmtLate = totAmtLate.add(oi.num("oi-deduct-amt")); totNoLate++; }
        totAmtPay = totAmtPay.add(oi.num("oi-paid"));
        totNoPay++;
    }

    private void checkZero(int type) {
        BigDecimal paid = oi.num("oi-paid");
        if (type == 3) {
            if (invAmount.signum() == 0) { l5.put(74, 1, "<"); l5.put(87, 1, ">"); l5Bal0(paid.negate()); }
        } else if (type == 5 || type == 6) {
            if (paid.compareTo(oi.num("oi-approp")) == 0) { l5.put(120, 1, "<"); l5.put(131, 1, ">"); l5Payments(paid); }
            else l5Payments(paid.subtract(oi.num("oi-approp")));
        } else if (amountOut.signum() == 0) { l5.put(74, 1, "<"); l5.put(87, 1, ">"); l5Bal0(paid); }
    }

    private void endStatement() {
        l6.put(74, 13, cr13(bal0));
        l6.put(87, 11, u11(bal30));
        l6.put(98, 11, u11(bal60));
        l6.put(109, 11, u11(bal90));
        l6.put(120, 11, u11(balPay));
        if (!l6.get(55, 8).isBlank()) {
            print.after(l6.toString(), 1);
            print.after("", 1);
            l6.put(55, 8, "");
            lineCnt += 2;
        }
        bal0 = bal30 = bal60 = bal90 = balPay = balT = Z;
    }

    private void headings1() {
        if (lineCnt < pageLines) return;
        pageNos++;
        if (lineCnt != 99) {
            int scycle = sys.intv("scycle");
            l3List = l3List.substring(0, 18) + (scycle == 0 ? "  " : Num.edit(scycle % 100, "z9"));
        }
        String l1 = pad(PROG_NAME, 56) + pad("Aged Debtors Report", 68) + "Page " + Num.edit(pageNos % 100, "zz9");
        if (pageNos != 1) { print.afterPage(l1); print.after("", 1); }
        else print.before(l1, 1);
        print.after(pad(sys.str("usera"), 56) + pad(l3List, 20) + " ".repeat(46) + pad(l3Date, 10), 1);
        print.after(line4, 2);
        lineCnt = 0;
    }

    private void readSales() {
        while (true) {
            if (!salesFile.readNext(sales).equals("00")) { fsReply = 99; return; }
            key = pad(sales.str("sales-key"), 7);
            if (!customerIn.isBlank() && key.compareTo(customerIn) > 0) { fsReply = 99; return; }
            fsReply = 0;
            totAcctLive++;
            BigDecimal current = sales.num("sales-current"), unapplied = sales.num("sales-unapplied");
            totSalesBal = totSalesBal.add(current);
            if (unapplied.signum() != 0 && current.signum() != 0) { totAmtUnappPay = totAmtUnappPay.add(unapplied); totNoUnappPay++; }
            if (unapplied.signum() != 0) { totSalesBal = totSalesBal.subtract(unapplied); current = current.subtract(unapplied); }
            if (current.signum() < 0) { totNoCrBal++; totAmtCrBal = totAmtCrBal.add(current); }
            // read-sales-test
            boolean truth = current.signum() != 0;
            long lastPay = sales.longv("sales-last-pay"), lastInv = sales.longv("sales-last-inv");
            long payDate = Math.max(lastPay, lastInv);
            if (current.signum() == 0 && payDate > sys.longv("s-end-cycle-date")) truth = true;
            if (current.signum() == 0 && lastPay != 0 && lastPay == lastInv)
                truth = lastRead.equals(key) && oi.intv("oi-type") != 1;
            if (payValue.signum() != 0 && current.compareTo(payValue) < 0) truth = false;
            if (!truth) continue;
            totAcctActive++;
            l5.put(9, 32, sales.str("sales-name"));
            l5.put(0, 9, key);
            l5.put(41, 13, sales.str("sales-phone"));
            l6.put(63, 11, u11(current));
            l6.put(55, 8, "Balance:");
            l6.put(0, 5, "");
            l6.put(24, 4, Num.edit(sales.longv("sales-credit") % 100, "z9") + "  ");
            BigDecimal limit = BigDecimal.valueOf(sales.longv("sales-limit"));
            l6.put(41, 8, ed(limit.abs(), "zzzz,zz9", 7));
            if (current.compareTo(limit) > 0) {
                l6.put(5, 12, ed(current.subtract(limit), "zzz,zz9.99", 6) + "  ");
                l6.put(0, 5, "Over:");
            } else l6.put(5, 12, "");
            if (current.signum() < 0) l6.put(55, 8, "Cr Bal:");
            headings1();
            if (unapplied.signum() == 0) return;
            l5Payments(unapplied);
            l5.put(54, 20, "Unapplied Cash");
            balPay = balPay.add(unapplied);
            print.after(l5.toString(), 2);
            l5.spaces();
            lineCnt += 2;
            if (!lastRead.equals(key)) endStatement();
            return;
        }
    }

    private BigDecimal pct(BigDecimal num, BigDecimal den, RoundingMode rm) {
        if (den.signum() != 0) {
            BigDecimal q = num.multiply(HUNDRED).divide(den, 2, rm);
            if (q.abs().compareTo(new BigDecimal(10000000)) < 0) work1 = q;
        }
        return work1;
    }

    private void reportAnalysis() {
        l3List = "Account Statistics  ";
        line4 = "";
        lineCnt = 99;
        headings1();
        print.after(" ".repeat(29) + "Total       Current         30           60       90 & Over", 1);
        print.after("", 1);
        l8Head("Number Of Invoices");
        l8.put(38, 13, n13(inv0)); l8.put(51, 13, n13(inv30)); l8.put(64, 13, n13(inv60)); l8.put(77, 8, ed(inv90, "zzzz,zz9", 7));
        long a = inv0 + inv30 + inv60 + inv90;
        l10Tot(a);
        print.after(l8.toString(), 1);
        l8Head("Amount");
        l8Col(0, totBal0); l8Col(1, totBal30); l8Col(2, totBal60); l8Col(3, totBal90);
        BigDecimal totOsBal = totBal0.add(totBal30).add(totBal60).add(totBal90);
        BigDecimal work2 = totOsBal.remainder(new BigDecimal(10000000));
        l8Tot(totOsBal);
        print.after(l8.toString(), 1);
        l8Head("% of O/S Invoices");
        l8Tot(HUNDRED);
        l8Col(0, pct(totBal0, work2, RoundingMode.HALF_UP));
        l8Col(1, pct(totBal30, work2, RoundingMode.HALF_UP));
        l8Col(2, pct(totBal60, work2, RoundingMode.HALF_UP));
        l8Col(3, pct(totBal90, work2, RoundingMode.HALF_UP));
        print.after(l8.toString(), 1);
        l8Head("Average O/S Amount");
        for (int i = 0; i < 4; i++) l8Col(i, Z);
        if (inv0 != 0) l8Col(0, totBal0.divide(BigDecimal.valueOf(inv0), 2, RoundingMode.DOWN));
        if (inv30 != 0) l8Col(1, totBal30.divide(BigDecimal.valueOf(inv30), 2, RoundingMode.DOWN));
        if (inv60 != 0) l8Col(2, totBal60.divide(BigDecimal.valueOf(inv60), 2, RoundingMode.DOWN));
        if (inv90 != 0) l8Col(3, totBal90.divide(BigDecimal.valueOf(inv90), 2, RoundingMode.DOWN));
        if (a != 0) l8Tot(work2.divide(BigDecimal.valueOf(a), 2, RoundingMode.DOWN));
        print.after(l8.toString(), 1);
        print.after(" ".repeat(29) + "Number       Amount", 3);
        l8.spaces();
        l8Head("Unapplied Cash"); l8Col(0, totAmtUnappPay); l10Tot(totNoUnappPay);
        print.after(l8.toString(), 2);
        l8Head("Payments"); l8Col(0, sys4.num("sl-payments")); l10Tot(totNoPay);
        print.after(l8.toString(), 1);
        l8Head("Credit Balances"); l10Tot(totNoCrBal); l8Col(0, totAmtCrBal);
        print.after(l8.toString(), 1);
        l8Head("Late Charges"); l8Col(0, totAmtLate); l10Tot(totNoLate);
        print.after(l8.toString(), 1);
        l8.spaces();
        l8Head("Number of Live Accounts"); l10Tot(totAcctLive);
        print.after(l8.toString(), 1);
        l8Head("Number of Active Accounts"); l10Tot(totAcctActive);
        print.after(l8.toString(), 1);
        l8Head("% Active");
        l8Tot(pct(BigDecimal.valueOf(totAcctActive), BigDecimal.valueOf(totAcctLive), RoundingMode.DOWN));
        print.after(l8.toString(), 1);
        if (!customerIn.isBlank()) return;
        l8.spaces();
        l8Head("  Reconciliation Data");
        print.after(l8.toString(), 3);
        l8Head("");
        print.after(l8.toString(), 1);
        l8Tot(sys4.num("sl-os-bal-last-month")); l8Head("Balance Brought Forward");
        print.after(l8.toString(), 1);
        l8Tot(sys4.num("sl-invoices-this-month")); l8Head("Plus: Invoices Posted");
        print.after(l8.toString(), 1);
        BigDecimal t0 = sys4.num("sl-os-bal-last-month").add(sys4.num("sl-invoices-this-month"));
        String dash = "-".repeat(13);
        print.after(" ".repeat(25) + dash + dash, 1);
        l8.spaces(); l8Col(0, t0);
        print.after(l8.toString(), 1);
        l8.spaces();
        l8Tot(sys4.num("sl-credit-notes-this-month")); l8Head("Less: Credit Notes Posted");
        print.after(l8.toString(), 2);
        l8Tot(sys4.num("sl-payments")); l8Head("      Payments Posted");
        print.after(l8.toString(), 1);
        l8Tot(totAmtLate); l8Head("      Pay Late Chgs Taken");
        print.after(l8.toString(), 1);
        l8Head("      CN Late Chgs Taken"); l8Tot(sys4.num("sl-credit-deductions"));
        print.after(l8.toString(), 1);
        print.after(" ".repeat(25) + dash + dash, 1);
        BigDecimal t30 = totAmtLate.add(sys4.num("sl-payments")).add(sys4.num("sl-credit-notes-this-month")).add(sys4.num("sl-credit-deductions"));
        l8.spaces(); l8Col(0, t30);
        print.after(l8.toString(), 1);
        print.after(" ".repeat(38) + dash, 2);
        t0 = t0.subtract(t30);
        l8Head("Balance Carried Forward");
        l8Col(0, t0);
        sys4.setNum("sl-os-bal-this-month", t0);
        print.after(l8.toString(), 1);
        print.after(" ".repeat(38) + "=".repeat(13), 1);
        l8.spaces();
        BigDecimal variance = totSalesBal.subtract(t0);
        sys4.setNum("sl-variance", variance);
        l8Tot(variance);
        if (variance.signum() != 0) {
            l8.put(1, 24, "Out Of Balance");
            sys4.setNum("sl-os-bal-this-month", sys4.num("sl-os-bal-this-month").add(variance));
            print.after(l8.toString(), 2);
        }
    }
}
