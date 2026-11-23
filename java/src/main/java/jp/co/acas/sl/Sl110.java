package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl110.cbl: 取引明細書（Statement）作成。sl115 が作る oisort.wrk を読む。 */
public class Sl110 extends SlProgram {
    static final String PROG_NAME = "SL110 (3.01.08)";
    static final String SL003 = "SL003 Hit Return To Continue";
    static final String SL150 = "SL150 Re-align statement to top of form";
    private static final BigDecimal Z = BigDecimal.ZERO;
    private static final BigDecimal M7 = new BigDecimal(10000000), M8 = new BigDecimal(100000000);

    private Rec sys;
    private Prt print;
    private boolean firstTime = true;
    private String[] head = new String[11];
    private String wsDate = "";

    private static int d(char c) { return c & 0x0F; }

    /** accept-money: 9(6).99 表示で受け、9(6)v99 として解釈する。 */
    private BigDecimal acceptMoney(int line, int col) {
        show(line, col, "000000.00", 3);
        String r = pad(term().accept(line, col, 8, "000000.0", 0, 3), 8);
        long v = 0;
        for (char c : r.toCharArray()) v = v * 10 + d(c);
        return BigDecimal.valueOf(v, 2);
    }

    @Override
    public void run(Object... args) {
        sys = sys();
        if (sys.intv("file-status", 19) != 1) { maps99(19); maps99(15); return; }
        term().exceptionsEnabled = true; term().escEnabled = true;
        eraseEos(2, 2);
        show(2, 2, PROG_NAME, 2);
        display(2, 32, "Statement Production", 2);
        wsDate = pad(fromUk(toDay()), 10);
        show(2, 71, wsDate, 2);
        statements();
        ctx.spool("prt-2", "lpr -r -o 'orientation-requested=4 page-left=21 page-top=48 page-right=10 cpi=12 lpi=8' -P "
            + sys.str("print-spool-name2").stripTrailing() + " prt-2");
    }

    private static String e7(BigDecimal v) { return Num.edit(v.remainder(M7), "z(6)9.99cr"); }
    private static String inv8(long v) { return v == 0 ? " ".repeat(8) : Num.edit(v, "z(7)9"); }
    private static String line12(long sInv, String date, String desc, BigDecimal sAmt, long rInv, BigDecimal rAmt) {
        return "  " + inv8(sInv) + "   " + pad(date, 11) + pad(desc, 31) + e7(sAmt) + "   " + inv8(rInv) + Num.edit(rAmt.remainder(M8), "z(7)9.99cr");
    }

    private void statements() {
        display(4, 41, "****************************************", 2);
        display(5, 41, "*Date    [  /  /    ]*                 *", 2);
        display(6, 41, "*A/C Nos    [       ]*               ***", 2);
        display(7, 41, "*Value    [         ]*                 *", 2);
        display(8, 41, "****************************************", 2);
        display(11, 1, "Notes", 2);
        display(12, 1, "*****", 2);
        display(14, 1, " (1)  -   <Date>  :  Appears on statement", 2);
        display(15, 1, " (2)  -   <A/C>   :  A/C's to match for printing", 2);
        display(16, 1, " (3)  -   <Value> :  Minimum O/S to print", 2);
        long payDate;
        String testDate;
        while (true) {
            show(5, 51, wsDate, 3);
            wsDate = pad(acceptUpdate(5, 51, 10, wsDate), 10);
            if (wsDate.isBlank()) return;
            testDate = wsDate;
            payDate = validateDate(wsDate);
            if (payDate != 0) break;
        }
        String customerIn = upper(pad(term().accept(6, 54, 7, " ".repeat(7), 0, 2), 7));
        BigDecimal payValue = acceptMoney(7, 52);
        String flavour1 = " ".repeat(64), flavour2 = " ".repeat(64);
        do {
            display(18, 1, "Msg Line 1 - [", 2);
            display(18, 79, "]", 2);
            display(19, 1, "Msg Line 2 - [", 2);
            display(19, 79, "]", 2);
            flavour1 = pad(acceptUpdate(18, 15, 64, flavour1), 64);
            flavour2 = pad(acceptUpdate(19, 15, 64, flavour2), 64);
        } while (flavour2.startsWith("<"));

        Rec sales = salesRec(), oi = oiHeader(), in = oi3Rec();
        CobFile salesFile = salesFile(sales);
        CobFile sFile = CobFile.sequential(ctx.store, ctx.path(F_OISORT));
        salesFile.open(CobFile.Mode.INPUT); sFile.open(CobFile.Mode.INPUT);
        print = new Prt(ctx, "prt-2");
        print.openOutput();
        boolean sel = !customerIn.isBlank();
        if (sel) {
            sales.set("sales-key", customerIn);
            salesFile.start(sales, ">=");
            customerIn = customerIn.replace(' ', 'Z');
        }
        String delim = pad(sys.str("sl-delim"), 1);
        BigDecimal bal0 = Z, bal30 = Z, bal60 = Z, bal90 = Z, balT = Z;
        int lp = 0;
        String lastRead = " ".repeat(7);
        BigDecimal amountOut = Z;
        boolean eof = false;
        sales:
        while (salesFile.readNext(sales).equals("00")) {
            BigDecimal unapplied = sales.num("sales-unapplied");
            BigDecimal current = sales.num("sales-current").subtract(unapplied);
            if (current.signum() == 0) continue;
            if (payValue.signum() != 0 && current.compareTo(payValue) < 0) continue;
            String key = pad(sales.str("sales-key"), 7);
            if (sel && key.compareTo(customerIn) > 0) break;
            String addr = pad(sales.str("sales-address"), 96);
            String[] al = new String[5];
            int a = 1;
            for (int i = 0; i < 5; i++) {
                Object[] u = unstring(addr, delim, a, 36);
                al[i] = u[0] == null ? " ".repeat(36) : (String) u[0];
                a = (Integer) u[1];
            }
            String usera = sys.str("usera");
            String b24 = " ".repeat(24), b21 = " ".repeat(21), b9 = " ".repeat(9);
            head[0] = b24 + pad(usera, 32);
            head[1] = b24 + pad(sys.str("address-1"), 24) + b21 + pad(usera, 23);
            head[2] = b24 + pad(sys.str("address-2"), 24) + b21 + pad(sys.str("address-1"), 23);
            head[3] = b24 + pad(sys.str("address-3"), 24) + b21 + pad(sys.str("address-2"), 23);
            head[4] = b24 + pad(sys.str("address-4"), 24) + b21 + pad(sys.str("address-3"), 23);
            head[5] = b9 + pad(sales.str("sales-name"), 32);
            head[6] = b9 + pad(al[0], 32) + " ".repeat(15) + testDate + "   " + testDate + " ".repeat(5) + key;
            head[7] = b9 + pad(al[1], 32);
            head[8] = b9 + pad(al[2], 32);
            head[9] = b9 + pad(al[3], 32);
            head[10] = b9 + pad(al[4], 32) + " ".repeat(18) + key;
            headings1();
            if (unapplied.signum() != 0) {
                BigDecimal u = unapplied.negate();
                bal0 = bal0.add(u); balT = balT.add(u);
                lp++;
                print.after(line12(0, testDate, "Unapplied Credit Balance", u, 0, u), 1);
            }
            while (true) {
                if (lastRead.isBlank()) {
                    if (!sFile.readNext(in).equals("00")) { eof = true; }
                }
                if (eof) {
                    lp = endStatement(lp, flavour1, flavour2, bal0, bal30, bal60, bal90, balT);
                    break sales;
                }
                move(in, oi);
                lastRead = pad(oi.str("oi-customer"), 7);
                if (lastRead.compareTo(key) > 0) break;
                int type = oi.intv("oi-type");
                if (!lastRead.equals(key) || type == 1 || type == 4) { lastRead = " ".repeat(7); continue; }
                long invoice = type == 5 || type == 6 ? 0 : oi.longv("oi-invoice");
                String date = pad(binToDate(oi.longv("oi-date")), 10);
                String desc;
                if (type == 2) {
                    StringBuilder sb = new StringBuilder(" ".repeat(31));
                    int z = stringInto(sb, 1, "Goods As Per - ");
                    stringInto(sb, z, delimited(pad(oi.str("oi-description"), 32), "  "));
                    desc = oi.str("oi-description").isBlank() ? "Goods" : sb.toString();
                } else if (type == 3) desc = "Credit Note Re. Inv - " + Num.edit(oi.longv("oi-cr"), "z(7)9");
                else if (type == 6) desc = "Unapplied Credit Allocated";
                else desc = "Payment. Received With Thanks";
                BigDecimal invAmount = oi.num("oi-net").add(oi.num("oi-extra")).add(oi.num("oi-carriage")).add(oi.num("oi-vat"))
                    .add(oi.num("oi-discount")).add(oi.num("oi-e-vat")).add(oi.num("oi-deduct-amt")).add(oi.num("oi-deduct-vat")).add(oi.num("oi-c-vat"));
                BigDecimal paid = oi.num("oi-paid"), approp = oi.num("oi-approp");
                // l12 の金額欄は書き換えない種別では直前行の値が残る（type 2/3/5/6 は必ず設定）。
                BigDecimal sAmt = Z, rAmt = Z;
                if (type == 2) {
                    amountOut = invAmount.subtract(paid);
                    sAmt = amountOut.add(oi.num("oi-p-c"));
                    rAmt = amountOut;
                    if (amountOut.signum() == 0 && oi.num("oi-p-c").signum() == 0) sAmt = invAmount;
                } else if (type == 3) {
                    sAmt = invAmount;
                    rAmt = invAmount.add(paid);
                } else if (type == 5 || type == 6) {
                    if (paid.signum() >= 0) paid = paid.negate();
                    if (approp.signum() >= 0) approp = approp.negate();
                    amountOut = paid.subtract(approp);
                    rAmt = amountOut; sAmt = paid;
                }
                long work1 = payDate - oi.longv("oi-date");
                if (work1 < 30) bal0 = bal0.add(amountOut);
                else if (work1 < 60) bal30 = bal30.add(amountOut);
                else if (work1 < 90) bal60 = bal60.add(amountOut);
                else bal90 = bal90.add(amountOut);
                balT = balT.add(amountOut);
                amountOut = Z;
                lp++;
                if (lp > 28) {
                    print.after("", 8);
                    headings1();
                    lp = 1;
                }
                print.after(line12(invoice, date, desc, sAmt, invoice, rAmt), 1);
                lastRead = " ".repeat(7);
            }
            endStatement(lp, flavour1, flavour2, bal0, bal30, bal60, bal90, balT);
            bal0 = bal30 = bal60 = bal90 = balT = Z; lp = 0;
        }
        sFile.close(); salesFile.close(); print.close();
        sFile.open(CobFile.Mode.OUTPUT); sFile.close();
    }

    private int endStatement(int lp, String f1, String f2, BigDecimal b0, BigDecimal b30, BigDecimal b60, BigDecimal b90, BigDecimal bt) {
        lp = 32 - lp;
        if (lp >= 6) {
            lp -= 4;
            print.after(f1, lp);
            print.after(f2, 1);
            lp = 3;
        }
        print.after(e7(b0) + "  " + e7(b30) + " " + e7(b60) + " " + e7(b90) + " " + e7(bt) + " ".repeat(12) + e7(bt), lp);
        print.after("", 4);
        return 0;
    }

    private void headings1() {
        while (true) {
            for (int i = 0; i < 11; i++) print.after(head[i], i == 5 ? 2 : 1);
            if (!firstTime) break;
            display(20, 1, "Statement correctly aligned.... (Y/N) ? - [ ]", 2);
            String reply = upper(acceptUpdate(20, 44, 1, "Y"));
            if (reply.equals("Y")) break;
            display(21, 1, SL150, 2);
            display(22, 1, SL003, 2);
            accept(20, 44, 1);
            eraseEol(21, 1);
            eraseEol(22, 1);
        }
        if (firstTime) show(20, 1, " ".repeat(80));
        firstTime = false;
        print.after("", 3);
    }
}
