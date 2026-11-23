package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.util.Arrays;

/** sl020.cbl: 売掛残高・明細照会。 */
public class Sl020 extends SlProgram {
    static final String PROG_NAME = "SL020 (3.01.08)";
    static final String SL111 = "SL111 Error On Writing Work File. Hit Return To Abort", SL112 = "SL112 Can't open file",
        SL113 = "SL113 Can't find it", SL114 = "SL114 Record not found", SL115 = "SL115 Error On Rewrite",
        SL116 = "SL116 Note: and hit return to continue", SL117 = "SL117 No Work File Created..No Data", SL118 = "SL118 Work file Created";
    private static final int BODY = 13;
    private static final String WORK = """
         01  work-record.
             03  work-key.
                 05  work-customer  pic x(7).
                 05  work-invoice   binary-long.
             03  work-amount        pic s9(8)v99  comp-3.
        """;

    private Rec sys, sales, oi3, oi, inv, ih, work;
    private CobFile salesFile, oi3File, invFile, workFile;
    private int a, b;
    private int screenStart, screenEnd;
    private BigDecimal amountOut = BigDecimal.ZERO, invAmount = BigDecimal.ZERO;
    private BigDecimal bal0 = BigDecimal.ZERO, bal30 = BigDecimal.ZERO, bal60 = BigDecimal.ZERO, bal90 = BigDecimal.ZERO, balT = BigDecimal.ZERO;
    private String customerIn = "", workFileData = "N";
    private final String[] l7 = new String[100];
    private String l1Name = "", l2Address = "", l3Address = "", l4Address = "", l5Address = "", l2Account = "";
    private String l2Balance = "", l3Ytd = "", l3Unapplied = "", l4Credit = "", l4Unposted = "";
    private boolean abort;

    @Override
    public void run(Object... args) {
        sys = sys();
        sales = salesRec(); oi3 = oi3Rec(); oi = oiHeader(); inv = invoiceRec(); ih = invoiceHeader();
        work = Layout.ofSource(WORK, "work-record").newRec();
        salesFile = salesFile(sales); oi3File = oi3File(oi3); invFile = invoiceFile(inv);
        workFile = CobFile.indexed(ctx.store, ctx.path(F_WORK), work, "work-key");
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("file-status", 19) != 1) { maps99(19); maps99(15); return; }
        setUpWorkFile();
        if (abort) return;
        salesFile.open(CobFile.Mode.INPUT); oi3File.open(CobFile.Mode.INPUT); workFile.open(CobFile.Mode.INPUT);
        enquiry();
        salesFile.close(); oi3File.close(); workFile.close();
    }

    private void main001() {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 31, "Sales Ledger Enquiry");
        show(1, 71, fromUk(toDay()), 2);
    }

    private String line20() {
        return pad("Inv #", 7) + pad("Total O/S", 20) + pad("Current", 18) + pad("30", 15) + pad("60", 14) + "90+";
    }
    private String line21() {
        return Num.edit(a, "zz9") + "  " + Num.edit(balT, "zz,zzz,zz9.99") + Num.edit(bal0, "z(6),zzz,zz9.99") + Num.edit(bal30, "zzzz,zzz,zz9.99")
            + Num.edit(bal60, "zzzz,zzz,zz9.99") + Num.edit(bal90, "zzzz,zzz,zz9.99");
    }

    private void enquiry() {
        enquiry:
        while (true) {
            main001();
            display(2, 41, "****************************************");
            display(3, 41, "*A/C Nos [       ]*Balance             *");
            display(4, 41, "*Ytd              *Unapplied           *");
            display(5, 41, "*Credit           *Unposted            *");
            display(6, 41, "****************************************");
            while (true) {
                // main-display-end
                customerIn = accept(3, 51, 7);
                if (customerIn.isBlank()) return;
                if (crtStatus() == 2005) return;
                customerIn = upper(customerIn);
                show(3, 51, customerIn);
                sales.set("sales-key", customerIn); oi3.set("oi3-customer", customerIn); l2Account = customerIn; work.set("work-customer", customerIn);
                oi3.setNum("oi3-invoice", 0); work.setNum("work-invoice", 0); invAmount = BigDecimal.ZERO;
                salesFile.start(sales, ">=");
                oi3File.start(oi3, ">=");
                if (!workFileData.equals("N")) workFile.start(work, ">=");
                salesFile.readNext(sales);
                if (salesFile.status.charAt(0) == '1') continue;
                if (!sales.str("sales-key").equals(customerIn)) continue;
                break;
            }
            Arrays.fill(l7, " ".repeat(80));
            l1Name = sales.str("sales-name");
            String addr = sales.str("sales-address"), delim = pad(sys.str("sl-delim"), 1);
            int p = 1;
            String[] parts = new String[4];
            for (int i = 0; i < 4; i++) {
                Object[] r = unstring(addr, delim, p, 36);
                parts[i] = r[0] == null ? " ".repeat(36) : (String) r[0];
                p = (int) r[1];
            }
            l2Address = parts[0].substring(0, 30); l3Address = parts[1].substring(0, 30);
            l4Address = parts[2].substring(0, 30); l5Address = parts[3].substring(0, 30);
            display(2, 1, "Customer:"); show(2, 11, l1Name, 2);
            display(3, 1, "Address :"); show(3, 11, l2Address, 2);
            show(4, 1, " ".repeat(10) + l3Address, 2);
            show(5, 1, " ".repeat(10) + l4Address, 2);
            show(6, 1, " ".repeat(10) + l5Address, 2);
            l2Balance = Num.edit(sales.num("sales-current"), "z(6)9.99");
            l3Unapplied = Num.edit(sales.num("sales-unapplied"), "z(6)9.99");
            BigDecimal ytd = BigDecimal.ZERO;
            for (int q = 1; q <= 4; q++) ytd = ytd.add(sales.num("sturnover-q", q));
            l3Ytd = Num.edit(Num.truncated(ytd, 0), "z(7)9");
            l4Credit = Num.edit(sales.num("sales-limit"), "z(7)9");
            getUnposted();
            show(3, 70, l2Balance, 2);
            show(4, 51, l3Ytd, 2);
            if (sales.num("sales-unapplied").signum() != 0) show(4, 70, l3Unapplied, 2);
            show(5, 51, l4Credit, 2);
            if (invAmount.signum() != 0) show(5, 70, l4Unposted, 2);
            display(7, 2, "Number"); display(7, 14, "Date"); display(7, 24, "Description");
            display(7, 46, "Invoiced"); display(7, 63, "Paid"); display(7, 73, "Balance");
            a = 0; b = 0;
            int bodyLines = BODY;
            screenStart = 1; screenEnd = BODY * 80;
            readOpenItems();
            while (true) {
                // end-statement
                int rows = (screenEnd - screenStart + 1) / 80, first = (screenStart - 1) / 80;
                for (int i = 0; i < rows && first + i < 100; i++) show(8 + i, 1, l7[first + i], 2);
                b += bodyLines;
                if (a > b) {
                    screenStart += BODY * 80; screenEnd += BODY * 80;
                    if (b > 100) {
                        b -= 100; screenEnd = 8000;
                        int c = bodyLines - b + 1;
                        eraseEos(c + 7, 1);
                    }
                }
                display(21, 1, "Inv #"); display(21, 8, "Total O/S"); display(21, 28, "Current");
                display(21, 46, "30"); display(21, 61, "60"); display(21, 75, "90+");
                show(22, 1, line21(), 2);
                while (true) {
                    // es-disp
                    display(24, 1, "Select: 'P'rint, 'N'ext enquiry, 'T'oggle query flag, ");
                    if (a > b) display(24, 55, "'M'ore or 'E'nd [ ]"); else display(24, 55, "or 'E'nd [ ]");
                    String s1;
                    while (true) {
                        int col = a > b ? 72 : 65;
                        s1 = upper(term().accept(24, col, 1, " ", AUTO, 6));
                        if (crtStatus() == 2005 || s1.equals("E")) return;
                        if ("MPNT".contains(s1) && !s1.isBlank()) break;
                    }
                    if (s1.equals("P")) { printScreen(); continue; }
                    if (s1.equals("T")) { setQueryFlag(); continue; }
                    if (s1.equals("N")) {
                        bal0 = bal30 = bal60 = bal90 = balT = BigDecimal.ZERO;
                        continue enquiry;
                    }
                    break;  // M
                }
            }
        }
    }

    private void set7(int row, int off, String v) {
        String cur = l7[row - 1];
        l7[row - 1] = cur.substring(0, off) + v + cur.substring(off + v.length());
    }

    private void readOpenItems() {
        while (true) {
            oi3File.readNext(oi3);
            if (!oi3File.status.equals("00")) return;
            if (!oi3.str("oi3-customer").equals(sales.str("sales-key"))) return;
            move(oi3, oi);
            a++;
            int type = oi.intv("oi-type");
            boolean overflow = false;
            if (a > 100) { set7(100, 22, pad(">> screen overflow <<", 19)); a = 100; overflow = true; }
            else {
                if (type == 5 || type == 6) oi.setNum("oi-invoice", 0);
                long invNo = oi.longv("oi-invoice");
                set7(a, 0, invNo == 0 ? " ".repeat(8) : Num.edit(invNo, "z(7)9"));
                set7(a, 11, pad(binToDate(oi.longv("oi-date")), 11));
                if (!oi.str("oi-hold-flag").equals(" ")) set7(a, 9, "Q");
                String desc = switch (type) {
                    case 1 -> "Receipt ";
                    case 2 -> "Goods - " + delimited(oi.str("oi-description"), "  ");
                    case 3 -> "CN.Re Inv -" + Num.edit(oi.longv("oi-cr"), "z(7)9");
                    case 5 -> "Payment";
                    case 6 -> "Journal Payment";
                    default -> "";
                };
                set7(a, 22, pad(pad(desc, 20), 19));
            }
            // item-comp-1
            invAmount = BigDecimal.ZERO;
            for (String f : new String[] {"oi-net", "oi-extra", "oi-carriage", "oi-vat", "oi-discount", "oi-e-vat", "oi-deduct-amt", "oi-deduct-vat", "oi-c-vat"})
                invAmount = invAmount.add(oi.num(f));
            if (type == 3) oi.setNum("oi-paid", oi.num("oi-paid").negate());
            if (type == 2 || type == 3) amountOut = invAmount.subtract(oi.num("oi-paid"));
            // 注: レガシーでは a を 100 に戻した後の "a > 100" 判定は成立しない
            {
                if (type == 2 || type == 3) set7(a, 67, Num.edit(amountOut, "zz,zzz,zz9.99"));
                set7(a, 41, Num.edit(invAmount, "zz,zzz,zz9.99"));
                set7(a, 54, Num.edit(oi.num("oi-paid"), "zz,zzz,zz9.99"));
                if (type == 1) {
                    set7(a, 54, Num.edit(invAmount, "zz,zzz,zz9.99"));
                    set7(a, 67, Num.edit(BigDecimal.ZERO, "zz,zzz,zz9.99"));
                    continue;
                }
                if (type == 5 || type == 6) {
                    set7(a, 67, Num.edit(BigDecimal.ZERO, "zz,zzz,zz9.99"));
                    set7(a, 41, Num.edit(BigDecimal.ZERO, "zz,zzz,zz9.99"));
                    continue;
                }
            }
            long age = sys.longv("run-date") - oi.longv("oi-date");
            if (age < 30) bal0 = bal0.add(amountOut);
            else if (age < 60) bal30 = bal30.add(amountOut);
            else if (age < 90) bal60 = bal60.add(amountOut);
            else bal90 = bal90.add(amountOut);
            balT = balT.add(amountOut);
        }
    }

    private void printScreen() {
        Prt print = new Prt(ctx, "prt-1");
        print.openOutput();
        String line0 = pad(PROG_NAME, 30) + pad("Sales Ledger Enquiry", 40) + fromUk(toDay());
        print.after(line0, 1);
        heads1(print);
        for (int l = 1; l <= a; l++) {
            print.after(l7[l - 1], 1);
            if (l == 59) { print.afterPage(line0); heads1(print); }
        }
        print.after(line20(), 2);
        print.after(line21(), 2);
        print.close();
        spoolReport("prt-1", sys.str("print-spool-name"), false);
    }
    private void heads1(Prt print) {
        String stars = "*".repeat(40);
        print.after(pad("Customer:", 10) + pad(l1Name, 30) + stars, 1);
        print.after(pad("Address :", 10) + pad(l2Address, 30) + pad("* A/C Nos", 10) + pad(l2Account, 8) + pad("*Balance", 11) + l2Balance + "*", 1);
        print.after(" ".repeat(10) + pad(l3Address, 30) + pad("* YTD", 10) + l3Ytd + pad("*Unapplied", 11) + l3Unapplied + "*", 1);
        print.after(" ".repeat(10) + pad(l4Address, 30) + pad("* Credit", 10) + l4Credit + pad("*Unposted", 11) + l4Unposted + "*", 1);
        print.after(" ".repeat(10) + pad(l5Address, 30) + stars, 1);
        print.after(" " + pad("Number", 12) + pad("Date", 10) + pad("Description", 23) + pad("Invoiced", 17) + pad("Paid", 10) + "Balance", 1);
    }

    private void setUpWorkFile() {
        main001();
        int lin = 14, col = 0, cnt = 0;
        if (sys.intv("s-flag-i") == 1) {
            workFile.open(CobFile.Mode.OUTPUT);
            invFile.open(CobFile.Mode.INPUT);
            if (!invFile.status.equals("00")) { workFile.close(); invFile.close(); return; }
            while (true) {
                invFile.readNext(inv);
                if (invFile.status.charAt(0) == '1') break;
                move(inv, ih);
                if (ih.intv("ih-test") != 0) continue;
                if (ih.str("ih-status").equals("z")) continue;
                int type = ih.intv("ih-type");
                if (type == 1 || type == 4) continue;
                work.setNum("work-invoice", ih.longv("ih-invoice"));
                work.set("work-customer", ih.str("ih-customer"));
                BigDecimal amt = BigDecimal.ZERO;
                for (String f : new String[] {"ih-net", "ih-extra", "ih-carriage", "ih-discount", "ih-vat", "ih-c-vat", "ih-e-vat", "ih-deduct-amt", "ih-deduct-vat"})
                    amt = amt.add(ih.num(f));
                if (type == 3) amt = amt.negate();
                work.setNum("work-amount", amt);
                workFile.write(work);
                if (!workFile.status.equals("00")) {
                    display(24, 1, SL111, 4);
                    term().accept(24, 53, 1, " ", 0, 6);
                    invFile.close(); workFile.close();
                    abort = true;
                    return;
                }
                cnt++;
                if (cnt > 9) { cnt = 0; col++; show(lin, col, ".", 2); }
                if (col > 79) { lin++; col = 0; }
            }
            invFile.close(); workFile.close();
        }
        if (lin == 14 && col == 0 && cnt == 0) display(18, 1, SL117);
        else { workFileData = "Y"; display(18, 1, SL118); }
    }

    private void getUnposted() {
        if (!workFileData.equals("N")) {
            while (true) {
                workFile.readNext(work);
                if (!workFile.status.equals("00")) break;
                if (!customerIn.equals(work.str("work-customer"))) break;
                invAmount = invAmount.add(work.num("work-amount"));
            }
        }
        l4Unposted = Num.edit(invAmount, "z(6)9.99");
    }

    private void setQueryFlag() {
        display(23, 1, "For Account:        . Give invoice no. to toggle [        ]");
        show(23, 14, customerIn);
        long tinv = acceptNum(23, 51, 8, 0);
        if (tinv == 0) return;
        eraseEol(23, 1);
        oi3File.close();
        oi3File.open(CobFile.Mode.IO);
        String err = null;
        if (!oi3File.status.equals("00")) err = SL112;
        else {
            oi3.set("oi3-customer", customerIn); oi3.setNum("oi3-invoice", tinv);
            oi3File.read(oi3);
            if (invalidKey(oi3File)) err = SL113;
            else if (oi3.longv("oi3-invoice") != tinv || !oi3.str("oi3-customer").equals(customerIn)) err = SL114;
            else {
                move(oi3, oi);
                oi.set("oi-hold-flag", oi.str("oi-hold-flag").equals(" ") ? "Q" : " ");
                move(oi, oi3);
                oi3File.rewrite(oi3);
                if (invalidKey(oi3File)) err = SL115;
            }
        }
        if (err != null) {
            display(23, 1, err, 4);
            eraseEol(24, 1); display(24, 1, SL116);
            accept(24, 34, 1);
            eraseEos(23, 1);
        }
        oi3File.close();
        oi3File.open(CobFile.Mode.INPUT);
    }
}
