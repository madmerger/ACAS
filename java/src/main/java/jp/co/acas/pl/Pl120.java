package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Arrays;

/** pl120.cbl: 買掛金年齢表（Aged Creditors Report）。 */
public class Pl120 extends PlBase {
    static final String PROG_NAME = "PL120 (3.01.08)";
    private static final BigDecimal Z = BigDecimal.ZERO;
    private static final String C13 = "zzzz,zz9.99cr", N11 = "zzzz,zz9.99";
    private Rec purch, oi, s4;
    private CobFile purchaseFile, ois, salesSort;
    private Printer prt;
    private boolean sorted;
    private String customerIn = "", lastRead = pad("", 7), l3Date = "", l3List = "", l1Sorted = "", line4;
    private BigDecimal payValue = Z, invAmount = Z, amountOut = Z;
    private long enteredDate;
    private int pageNos, lineCnt = 66, pageLines;
    private final char[] l5 = new char[132], l8 = new char[90];
    private String l6Lover = "", l6Over = "", l6Credit = "", l6Limit = "", l6Lbalance = "Balance:", l6Balance = "";
    private long inv0, inv30, inv60, inv90, totNoPay, totNoCrBal, totActive, totLive, totNoUnapp, totLostNo;
    private BigDecimal tb0 = Z, tb30 = Z, tb60 = Z, tb90 = Z, totAmtLate = Z, totAmtPay = Z, totAmtCrBal = Z,
            totAmtUnapp = Z, totUnapplCredits = Z, totSalesBal = Z, totLostAmt = Z;
    private BigDecimal bal0 = Z, bal30 = Z, bal60 = Z, bal90 = Z, balPay = Z;

    private static void put(char[] b, int off, String s) { for (int i = 0; i < s.length(); i++) b[off + i] = s.charAt(i); }
    private static void put(char[] b, int off, int len, String s) { put(b, off, pad(s, len)); }
    private static String abs(BigDecimal v, String pic) { return Num.edit(v.abs(), pic); }

    @Override
    public void run(Object... args) {
        init();
        if (sys.intv("p-flag-p") == 1) {
            maps99(24);
            maps99(15);
            return;
        }
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("file-status", 29) != 1) {
            maps99(25);
            maps99(15);
            return;
        }
        s4 = sys4();
        pageLines = sys.intv("page-lines");
        Arrays.fill(l5, ' '); Arrays.fill(l8, ' ');
        line4 = "Supplier              Name                 Telephone "
                + "    Folio      Date       Current         30         60    90 & over   Payments";
        l3List = "Current Period is " + "  ";
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 31, "Aged Creditors Report");
        show(1, 71, fromUk(toDay()), 2);
        trailBalance();
        reportAnalysis();
        prt.close();
        spoolPrt1();
    }

    private void trailBalance() {
        display(4, 41, "****************************************");
        display(5, 41, "*Date  [  /  /    ]*A/C Nos   [       ]*");
        display(6, 41, "***                                  ***");
        display(7, 41, "*Value  [         ]*                   *");
        display(8, 41, "****************************************");
        display(12, 1, "Notes");
        display(13, 1, "*****");
        display(15, 1, " (1)  -  <Date>  :  Appears on listing");
        display(16, 1, " (2)  -  <A/C>   :  A/Cs to match for printing");
        display(17, 1, " (3)  -  <Value> :  Minimum o/s to print");
        display(18, 1, " (4)  -  F1 pressed gives Alphabetic Sort");
        String d = fromUk(toDay());
        while (true) {
            term().crtStatus = 0;
            show(5, 49, d, 3);
            d = pad(acceptUpdate(5, 49, 10, d), 10);
            enteredDate = validateDate(d);
            if (enteredDate != 0) break;
        }
        l3Date = d;
        if (crtStatus() == 1001) sorted = true;
        customerIn = upper(pad(accept(5, 72, 7), 7));
        if (crtStatus() == 1001) sorted = true;
        payValue = acceptMoney(7, 50, 6, Z);
        if (crtStatus() == 1001) sorted = true;
        prt = new Printer("prt-1");
        pageNos = 0;
        if (sorted) {
            l1Sorted = "(Sorted)";
            salesSort = CobFile.sequential(ctx.store, ctx.path("suppsort.inx"));
            salesSort.open(Mode.INPUT);
        }
        headings();
        purch = purchRec(); oi = oiRec();
        purchaseFile = purchaseFile(purch);
        purchaseFile.open(Mode.INPUT);
        ois = CobFile.sequential(ctx.store, ctx.path("poisort.wrk"));
        if (ois.open(Mode.INPUT).equals("00")) {
            if (!customerIn.isBlank()) {
                purch.set("purch-key", customerIn);
                purchaseFile.start(purch, ">=");
                customerIn = customerIn.replace(' ', 'Z');
            }
            boolean eof = false;
            while (readSales()) {
                String key = purch.str("purch-key");
                if (lastRead.equals(key)) roi1();
                while (true) {
                    if (lastRead.compareTo(key) > 0) break;
                    // EOF 後の再 READ も AT END として扱う
                    if (eof || !ois.readNext(oi).equals("00")) { eof = true; endStatement(); break; }
                    lastRead = oi.str("oi-supplier");
                    if (lastRead.compareTo(key) > 0) { endStatement(); break; }
                    if (!lastRead.equals(key)) { bypassAgeing(); continue; }
                    roi1();
                }
            }
        }
        ois.close(); purchaseFile.close();
        if (sorted) salesSort.close();
    }

    private void roi1() {
        int type = oi.intv("oi-type");
        if (type == 1) return;
        if (lineCnt > pageLines - 5) headings();
        boolean pay = type == 5 || type == 6;
        if (pay) oi.setNum("oi-invoice", 0);
        put(l5, 54, Pl095.bwz(oi.longv("oi-invoice"), "z(7)9", 8));
        put(l5, 62, 1, oi.str("oi-hold-flag"));
        put(l5, 64, binToDate(oi.longv("oi-date")));
        BigDecimal paid = oi.num("oi-paid");
        invAmount = oi.num("oi-net").add(oi.num("oi-carriage")).add(oi.num("oi-vat")).add(oi.num("oi-c-vat"));
        if (type == 2) amountOut = invAmount.subtract(paid);
        if (type == 3) {
            invAmount = invAmount.add(paid);
            put(l5, 75, Num.edit(invAmount, "zzzzzz9.99cr"));
            if (invAmount.signum() == 0) { l5[74] = '<'; l5[87] = '>'; put(l5, 75, Num.edit(paid.negate(), "zzzzzz9.99cr")); }
        } else if (pay) {
            balPay = balPay.add(paid);
            if (paid.compareTo(oi.num("oi-approp")) == 0) { l5[120] = '<'; l5[131] = '>'; put(l5, 121, abs(paid, "zzzzzz9.99")); }
            else put(l5, 121, abs(paid.subtract(oi.num("oi-approp")), "zzzzzz9.99"));
        } else {
            long work1 = enteredDate - oi.longv("oi-date");
            BigDecimal ded = oi.num("oi-deduct-amt");
            int dd = oi.intv("oi-deduct-days");
            if (work1 <= dd && ded.signum() != 0) { invAmount = invAmount.subtract(ded); l5[63] = '*'; }
            if (work1 > dd && ded.signum() > 0) { totLostNo++; totLostAmt = totLostAmt.add(ded); }
            int b = amountOut.signum() == 0 ? 0 : 1;
            if (amountOut.signum() < 0) work1 = 1;
            if (work1 < 30) {
                bal0 = bal0.add(amountOut);
                put(l5, 75, Num.edit(amountOut, "zzzzzz9.99cr"));
                if (amountOut.signum() == 0) { l5[74] = '<'; l5[87] = '>'; put(l5, 75, Num.edit(paid, "zzzzzz9.99cr")); }
                tb0 = tb0.add(amountOut); inv0 += b;
            } else if (work1 < 60) {
                bal30 = bal30.add(amountOut); put(l5, 88, abs(amountOut, "zzzzzzz9.99")); tb30 = tb30.add(amountOut); inv30 += b;
            } else if (work1 < 90) {
                bal60 = bal60.add(amountOut); put(l5, 99, abs(amountOut, "zzzzzzz9.99")); tb60 = tb60.add(amountOut); inv60 += b;
            } else {
                put(l5, 110, abs(amountOut, "zzzzzz9.99")); tb90 = tb90.add(amountOut); inv90 += b; bal90 = bal90.add(amountOut);
            }
        }
        bypassAgeing();
        if (type == 3 && invAmount.signum() != 0) totUnapplCredits = totUnapplCredits.add(invAmount);
        amountOut = Z;
        if (!new String(l5, 0, 9).isBlank()) { prt.after("", 1); lineCnt++; }
        prt.after(new String(l5), 1);
        lineCnt++;
        Arrays.fill(l5, ' ');
    }

    private void bypassAgeing() {
        int type = oi.intv("oi-type");
        if (type != 5 && type != 6) return;
        if (oi.num("oi-deduct-amt").signum() != 0) totAmtLate = totAmtLate.add(oi.num("oi-deduct-amt"));
        totAmtPay = totAmtPay.add(oi.num("oi-paid"));
        totNoPay++;
    }

    private void endStatement() {
        if (!l6Lbalance.isBlank()) {
            prt.after(pad(l6Lover, 5) + pad(l6Over, 12) + pad("Terms:", 7) + pad(l6Credit, 4) + "Credit Limit:" + pad(l6Limit, 8)
                    + pad("", 6) + pad(l6Lbalance, 8) + pad(l6Balance, 11) + Num.edit(bal0, C13) + abs(bal30, N11)
                    + abs(bal60, N11) + abs(bal90, N11) + abs(balPay, N11), 1);
            prt.after("", 1);
            l6Lbalance = "";
            lineCnt += 2;
        }
        bal0 = bal30 = bal60 = bal90 = balPay = Z;
    }

    /** read-sales。false = 終了（fs-reply 99）。 */
    private boolean readSales() {
        while (true) {
            if (sorted) {
                Rec kr = Layout.ofSource(" 01 sales-sort-record.\n 03 sales-sort-key pic x(7).\n", "sales-sort-record").newRec();
                if (!salesSort.readNext(kr).equals("00")) return false;
                String key = kr.str("sales-sort-key");
                purch.set("purch-key", key);
                if (invalid(purchaseFile.read(purch))) {
                    display(23, 1, "Not Found - ", 4);
                    show(23, 13, key, 4);
                    continue;
                }
            } else if (!purchaseFile.readNext(purch).equals("00")) return false;
            String pkey = purch.str("purch-key");
            if (!customerIn.isBlank() && pkey.compareTo(customerIn) > 0) return false;
            totLive++;
            BigDecimal un = purch.num("purch-unapplied");
            totSalesBal = totSalesBal.add(purch.num("purch-current"));
            if (un.signum() != 0 && purch.num("purch-current").signum() != 0) { totAmtUnapp = totAmtUnapp.add(un); totNoUnapp++; }
            if (un.signum() != 0) { totSalesBal = totSalesBal.subtract(un); purch.sub("purch-current", un); }
            BigDecimal cur = purch.num("purch-current");
            if (cur.signum() < 0) { totNoCrBal++; totAmtCrBal = totAmtCrBal.add(cur); }
            // read-sales-test
            boolean truth = cur.signum() != 0;
            long lp = purch.longv("purch-last-pay"), li = purch.longv("purch-last-inv");
            if (cur.signum() == 0 && Math.max(lp, li) > sys.longv("s-end-cycle-date")) truth = true;
            if (cur.signum() == 0 && lp != 0 && lp == li) truth = lastRead.equals(pkey);
            if (payValue.signum() != 0 && cur.compareTo(payValue) < 0) truth = false;
            if (!truth) continue;
            put(l5, 9, 32, purch.str("purch-name"));
            totActive++;
            put(l5, 0, 9, pkey);
            put(l5, 41, 13, purch.str("purch-phone"));
            l6Balance = abs(cur, N11);
            l6Lbalance = "Balance:";
            l6Lover = "";
            l6Credit = Num.edit(Math.abs(purch.longv("purch-credit")) % 100, "z9");
            long limit = purch.longv("purch-limit");
            l6Limit = Num.edit(Math.abs(limit), "zzzz,zz9");
            if (cur.compareTo(BigDecimal.valueOf(limit)) > 0) {
                l6Over = Num.edit(cur.subtract(BigDecimal.valueOf(limit)), "zzz,zz9.99");
                l6Lover = "Over:";
            } else l6Over = "";
            if (cur.signum() < 0) l6Lbalance = "Cr Bal:";
            headings();
            if (un.signum() == 0) return true;
            put(l5, 121, abs(un, "zzzzzz9.99"));
            put(l5, 54, 20, "Unapplied Cash");
            balPay = balPay.add(un);
            prt.after(new String(l5), 2);
            Arrays.fill(l5, ' ');
            lineCnt += 2;
            if (!lastRead.equals(pkey)) endStatement();
            return true;
        }
    }

    private void headings() {
        if (lineCnt < pageLines - 5) return;
        pageNos++;
        if (lineCnt != 99) l3List = "Current Period is " + Pl095.bwz(sys.longv("scycle"), "z9", 2);
        String line1 = pad(PROG_NAME, 56) + pad("Aged Creditors Report", 22) + pad(l1Sorted, 8) + pad("", 38) + "Page "
                + Num.edit(pageNos, "zz9");
        if (pageNos != 1) {
            prt.afterPage(line1);
            prt.after("", 1);
        } else prt.before(line1, 1);
        prt.after(pad(sys.str("usera"), 56) + pad(l3List, 20) + pad("", 46) + l3Date, 1);
        prt.after(line4, 2);
        lineCnt = 0;
    }

    private void w8(int n) { prt.after(new String(l8), n); }
    private void w10(int n) { prt.after(new String(l8, 0, 85), n); }
    private void head(String s) { put(l8, 0, 25, s); }
    private void t8(int i, BigDecimal v) { put(l8, 25 + 13 * i, Num.edit(v, C13)); }
    private void t10(int i, long v) { put(l8, 25 + 13 * i, i == 4 ? 8 : 13, Num.edit(Math.abs(v), "zzzz,zz9")); }
    private void clr8() { Arrays.fill(l8, ' '); }
    private void clr10() { Arrays.fill(l8, 0, 85, ' '); }
    private static BigDecimal div(BigDecimal a, BigDecimal b, BigDecimal keep, RoundingMode m) {
        return b.signum() == 0 ? keep : a.divide(b, 2, m);
    }

    private void reportAnalysis() {
        l3List = " Account Statistics ";
        line4 = ""; l1Sorted = "";
        lineCnt = 99;
        headings();
        prt.after(pad("", 29) + "Total       Current         30           60       90 & over", 1);
        prt.after("", 1);
        head("Number of Invoices");
        t10(1, inv0); t10(2, inv30); t10(3, inv60); t10(4, inv90);
        long a = inv0 + inv30 + inv60 + inv90;
        t10(0, a);
        w10(1);
        head("Amount");
        t8(1, tb0); t8(2, tb30); t8(3, tb60); t8(4, tb90);
        BigDecimal totOs = tb0.add(tb30).add(tb60).add(tb90), work2 = totOs, work1 = Z;
        t8(0, totOs);
        w8(1);
        head("% of O/S Invoices");
        t8(0, new BigDecimal("100"));
        BigDecimal[] tbs = {tb0, tb30, tb60, tb90};
        for (int i = 0; i < 4; i++) {
            work1 = div(tbs[i].movePointRight(2), work2, work1, RoundingMode.HALF_UP);
            t8(i + 1, work1);
        }
        w8(1);
        head("Average O/S Amount");
        long[] invs = {inv0, inv30, inv60, inv90};
        for (int i = 0; i < 4; i++) t8(i + 1, invs[i] == 0 ? Z : tbs[i].divide(BigDecimal.valueOf(invs[i]), 2, RoundingMode.DOWN));
        if (a != 0) t8(0, work2.divide(BigDecimal.valueOf(a), 2, RoundingMode.DOWN));
        w8(1);
        prt.after(pad("", 29) + "Number       Amount", 3);
        clr8();
        head("Unapplied Cash"); t8(1, totAmtUnapp); t10(0, totNoUnapp); w8(2);
        head("Payments"); t8(1, s4.num("pl-payments")); t10(0, totNoPay); w8(1);
        head("Credit Balances"); t10(0, totNoCrBal); t8(1, totAmtCrBal); w8(1);
        head("Prompt Payment Disc. lost"); t8(1, totLostAmt); t10(0, totLostNo); w8(1);
        clr8();
        head("Number of Live Accounts"); t10(0, totLive); w10(1);
        head("Number of Active Accounts"); t10(0, totActive); w10(1);
        head("% Active");
        if (totLive != 0) work1 = BigDecimal.valueOf(totActive * 100).divide(BigDecimal.valueOf(totLive), 2, RoundingMode.DOWN);
        t8(0, work1);
        w8(1);
        if (!customerIn.isBlank()) return;
        clr10();
        head("  Reconciliation Data:"); w10(3);
        head(""); w10(1);
        t8(0, s4.num("pl-os-bal-last-month")); head("Balance Brought Forward"); w10(1);
        t8(0, s4.num("pl-invoices-this-month")); head("Plus: Invoices Posted"); w10(1);
        BigDecimal t0 = s4.num("pl-os-bal-last-month").add(s4.num("pl-invoices-this-month"));
        String dash = "-".repeat(13);
        prt.after(pad("", 25) + dash + dash, 1);
        clr10(); t8(1, t0); w10(1);
        clr10(); t8(0, s4.num("pl-credit-notes-this-month")); head("Less: Credit Notes Posted"); w10(2);
        t8(0, s4.num("pl-payments")); head("      Payments Posted"); w10(1);
        t8(0, totAmtLate); head("      Prompt pay taken"); w10(1);
        prt.after(pad("", 25) + dash + dash, 1);
        BigDecimal t30 = totAmtLate.add(s4.num("pl-payments")).add(s4.num("pl-credit-notes-this-month"));
        clr10(); t8(1, t30); w10(1);
        prt.after(pad("", 38) + dash, 2);
        t0 = t0.subtract(t30);
        head("Balance Carried Forward"); t8(1, t0);
        s4.setNum("pl-os-bal-this-month", t0);
        w10(1);
        prt.after(pad("", 38) + "=".repeat(13), 1);
        clr8();
        s4.setNum("pl-variance", totSalesBal.subtract(t0));
        t8(0, s4.num("pl-variance"));
        if (s4.num("pl-variance").signum() != 0) {
            put(l8, 1, 24, "Out of Balance");
            s4.add("pl-os-bal-this-month", s4.num("pl-variance"));
            w10(2);
        }
    }
}
