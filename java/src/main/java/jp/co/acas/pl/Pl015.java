package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl015.cbl: 買掛元帳照会。 */
public class Pl015 extends PlBase {
    static final String PROG_NAME = "PL015 (3.01.07)";
    static final String L6 = " Number       Date       Description          Invoiced        Paid     Balance";
    static final String L20 = "Total Outstanding          Current           30             60            90+";
    private static final Layout WORK = Layout.ofSource("""
             01  work-record.
                 03  work-key.
                     05  work-supplier  pic x(7).
                     05  work-invoice   binary-long.
                 03  work-amount        pic s9(8)v99  comp-3.
            """, "work-record");
    private Rec purch, oi, work;
    private CobFile purchaseFile, oi5, workFile;
    private String workFileData = "N", customerIn = "";
    private BigDecimal invAmount = BigDecimal.ZERO, amountOut = BigDecimal.ZERO;
    private BigDecimal bal0 = BigDecimal.ZERO, bal30 = BigDecimal.ZERO, bal60 = BigDecimal.ZERO, bal90 = BigDecimal.ZERO, balT = BigDecimal.ZERO;
    private final String[] l7 = new String[100];
    private int a, b;
    private String l1name = "", l2addr = "", l3addr = "", l4addr = "", l5addr = "";
    private String l2balance = "", l3ytd = "", l3unapplied = "", l4limit = "", l4unposted = "";
    private String line21 = "";

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        if (sys.intv("file-status", 29) != 1) {
            maps99(25);
            maps99(15);
            return;
        }
        purch = purchRec(); oi = oiRec(); work = WORK.newRec();
        purchaseFile = purchaseFile(purch); oi5 = oi5File();
        workFile = CobFile.indexed(ctx.store, ctx.path("work.tmp"), work, "work-key");
        if (!setUpWorkFile()) return;
        purchaseFile.open(Mode.INPUT); oi5.open(Mode.INPUT); workFile.open(Mode.INPUT);
        enquiry();
        purchaseFile.close(); oi5.close(); workFile.close();
    }

    private void main001() {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 29, "Purchase Ledger Enquiry");
        show(1, 71, fromUk(toDay()), 2);
        display(2, 41, "****************************************");
        display(3, 41, "*A/C Nos [       ]*Balance [          ]*");
        display(4, 41, "*Ytd    [        ]*Unapplied[         ]*");
        display(5, 41, "*Credit [        ]*Unposted[          ]*");
        display(6, 41, "****************************************");
    }

    private String l7(String inv, String prompt, String hold, String date, String desc, String amount, String paid, String balance) {
        return pad(inv, 8) + pad(prompt, 1) + pad(hold, 1) + " " + pad(date, 11) + pad(desc, 22) + pad(amount, 12) + pad(paid, 12) + pad(balance, 12);
    }

    private void enquiry() {
        enquiry:
        while (true) {
            main001();
            customer:
            while (true) {
                customerIn = accept(3, 51, 7);
                if (customerIn.isBlank()) return;
                if (crtStatus() == 2005) return;
                customerIn = upper(customerIn);
                show(3, 51, customerIn);
                purch.set("purch-key", customerIn);
                oi.set("oi-supplier", customerIn); oi.setNum("oi-invoice", 0);
                work.set("work-supplier", customerIn); work.setNum("work-invoice", 0);
                invAmount = BigDecimal.ZERO;
                purchaseFile.start(purch, ">=");
                oi5.start(oi, ">=");
                if (!workFileData.equals("N")) workFile.start(work, ">=");
                if (!purchaseFile.readNext(purch).equals("00")) continue;
                if (!purch.str("purch-key").equals(pad(customerIn, 7))) continue;
                break;
            }
            for (int i = 0; i < 100; i++) l7[i] = pad("", 80);
            l1name = purch.str("purch-name");
            String[] ad = purch.str("purch-address").split(java.util.regex.Pattern.quote(sys.str("pl-delim")), -1);
            l2addr = pad(ad.length > 0 ? ad[0] : "", 30);
            l3addr = pad(ad.length > 1 ? ad[1] : "", 30);
            l4addr = pad(ad.length > 2 ? ad[2] : "", 30);
            l5addr = pad(ad.length > 3 ? ad[3] : "", 30);
            display(2, 1, "Supplier:"); show(2, 10, " " + l1name, 2);
            display(3, 1, "Address :"); show(3, 10, " " + l2addr, 2);
            show(4, 1, pad("", 10) + l3addr, 2);
            show(5, 1, pad("", 10) + l4addr, 2);
            show(6, 1, pad("", 10) + l5addr, 2);
            l2balance = Num.edit(purch.num("purch-current"), "z(6)9.99");
            l3unapplied = Num.edit(purch.num("purch-unapplied"), "z(5)9.99");
            BigDecimal ytd = purch.num("pturnover-q", 1).add(purch.num("pturnover-q", 2)).add(purch.num("pturnover-q", 3)).add(purch.num("pturnover-q", 4));
            l3ytd = Num.edit(ytd, "z(6)9");
            l4limit = Num.edit(purch.longv("purch-limit"), "z(6)9");
            a = 0;
            getUnposted();
            show(3, 69, l2balance);
            show(4, 51, l3ytd);
            if (purch.num("purch-unapplied").signum() != 0) show(4, 70, l3unapplied);
            show(5, 51, l4limit);
            if (invAmount.signum() != 0) show(5, 69, l4unposted);
            display(7, 1, L6);
            a = 0; b = 0;
            int bodyLines = 13, screenSize = bodyLines * 80, screenStart = 1, screenEnd = screenSize;
            long runDate = sys.longv("run-date");
            while (true) {
                if (!oi5.readNext(oi).equals("00")) break;
                if (!oi.str("oi-supplier").equals(purch.str("purch-key"))) break;
                a++;
                int type = oi.intv("oi-type");
                String inv = "", prompt = "", hold = "", date = "", desc = "", amount = "", paid = "", balance = "";
                boolean overflow = a > 100;
                if (overflow) {
                    l7[99] = l7[99].substring(0, 22) + pad(">> Screen Overflow <<", 22) + l7[99].substring(44);
                    a = 100;
                } else {
                    if (type == 5 || type == 6) oi.setNum("oi-invoice", 0);
                    inv = Num.edit(oi.longv("oi-invoice"), "z(7)9");
                    if (oi.longv("oi-invoice") == 0) inv = "";
                    date = binToDate(oi.longv("oi-date"));
                    if (!oi.str("oi-hold-flag").equals(" ")) hold = "H";
                    switch (type) {
                        case 1 -> desc = "Receipt ";
                        case 2 -> { String r = oi.str("oi-ref"); int sp = r.indexOf(' '); desc = "Goods - " + (sp < 0 ? r : r.substring(0, sp)); }
                        case 3 -> desc = "CN.Re Inv -" + Num.edit(oi.longv("oi-cr"), "z(7)9");
                        case 5 -> desc = "Payment";
                        case 6 -> desc = "Journal Payment";
                        default -> { }
                    }
                    desc = pad(desc, 20);
                }
                // item-comp-1
                invAmount = oi.num("oi-net").add(oi.num("oi-carriage")).add(oi.num("oi-vat")).add(oi.num("oi-c-vat"));
                if (type == 2 && oi.num("oi-deduct-amt").signum() != 0) {
                    prompt = "P";
                    if (oi.longv("oi-date") + oi.intv("oi-deduct-days") >= runDate) invAmount = invAmount.subtract(oi.num("oi-deduct-amt"));
                }
                if (type == 3) oi.setNum("oi-paid", oi.num("oi-paid").negate());
                if (type == 2 || type == 3) amountOut = invAmount.subtract(oi.num("oi-paid"));
                // 原文: a > 100 は到達しない（上で 100 に丸める）ため常に明細行を更新する
                if (type == 2 || type == 3) balance = Num.edit(amountOut, "zzzzz,zz9.99");
                amount = Num.edit(invAmount, "zzzzz,zz9.99");
                paid = Num.edit(oi.num("oi-paid"), "zzzzz,zz9.99");
                boolean age = true;
                if (type == 1) { paid = amount; balance = Num.edit(BigDecimal.ZERO, "zzzzz,zz9.99"); age = false; }
                else if (type == 5 || type == 6) { balance = amount = Num.edit(BigDecimal.ZERO, "zzzzz,zz9.99"); age = false; }
                if (overflow) {
                    String cur = l7[99];
                    l7[99] = cur.substring(0, 9) + (prompt.isEmpty() ? cur.substring(9, 10) : prompt) + cur.substring(10, 44) + pad(amount, 12) + pad(paid, 12) + pad(balance, 12);
                    if (type == 2 || type == 3) { /* balance set above */ } else l7[99] = l7[99].substring(0, 68) + cur.substring(68);
                } else l7[a - 1] = l7(inv, prompt, hold, date, desc, amount, paid, balance);
                if (age) {
                    long days = runDate - oi.longv("oi-date");
                    if (days < 30) bal0 = bal0.add(amountOut);
                    else if (days < 60) bal30 = bal30.add(amountOut);
                    else if (days < 90) bal60 = bal60.add(amountOut);
                    else bal90 = bal90.add(amountOut);
                    balT = balT.add(amountOut);
                }
            }
            StringBuilder all = new StringBuilder();
            for (String s : l7) all.append(s);
            while (true) {
                // end-statement: display line-7-19 (Screen-Start:Screen-End) at 0801
                int from = screenStart - 1, to = Math.min(8000, from + screenEnd);
                int line = 8;
                for (int p = from; p < to && line <= 24; p += 80, line++) show(line, 1, all.substring(p, Math.min(to, p + 80)), 2);
                b += bodyLines;
                if (a > b) {
                    screenStart += screenSize;
                    screenEnd += screenSize;
                    if (b > 100) {
                        b -= 100;
                        screenEnd = 8000;
                        int c = bodyLines - b + 1;
                        eraseEos(c + 7, 1);
                    }
                }
                display(21, 1, L20);
                line21 = pad("", 5) + Num.edit(balT, "zz,zzz,zz9.99") + Num.edit(bal0, "z(6),zzz,zz9.99")
                        + Num.edit(bal30, "zzzz,zzz,zz9.99") + Num.edit(bal60, "zzzz,zzz,zz9.99") + Num.edit(bal90, "zzzz,zzz,zz9.99");
                show(22, 1, line21, 2);
                String s1;
                esdisp:
                while (true) {
                    display(24, 1, "Select: 'P'rint, 'N'ext enquiry, 'T'oggle query flag, ");
                    if (a > b) display(24, 55, "'M'ore or 'E'nd [ ]");
                    else display(24, 55, "or 'E'nd [ ]");
                    while (true) {
                        int col = a > b ? 72 : 65;
                        s1 = upper(acceptUpdate(24, col, 1, " ", AUTO));
                        if (crtStatus() == 2005) return;
                        if (s1.equals("E")) return;
                        if (s1.equals("M")) break esdisp;
                        if (s1.equals("P")) { printScreen(); continue esdisp; }
                        if (s1.equals("N")) {
                            bal0 = bal30 = bal60 = bal90 = balT = BigDecimal.ZERO;
                            continue enquiry;
                        }
                        if (s1.equals("T")) { setQueryFlag(); continue esdisp; }
                    }
                }
            }
        }
    }

    private void printScreen() {
        Printer p = new Printer("prt-1");
        String stars = "*".repeat(40);
        String line0 = pad(PROG_NAME, 16) + pad("", 13) + "Purchase Ledger Enquiry" + pad("", 18) + fromUk(toDay());
        String[] heads = {
                pad("Supplier:", 10) + pad(l1name, 30) + stars,
                pad("Address :", 10) + l2addr + "* A/C No [" + pad(customerIn, 7) + "]" + "*Balance [" + l2balance + "]*",
                pad("", 10) + l3addr + "* Ytd    [" + l3ytd + "]*Unapplied[" + l3unapplied + "]*",
                pad("", 10) + l4addr + "* Credit [" + l4limit + "]*Unposted[" + l4unposted + "]*",
                pad("", 10) + l5addr + stars,
                L6};
        p.after(line0, 1);
        for (String h : heads) p.after(h, 1);
        for (int l = 1; l <= a; l++) {
            p.after(l7[l - 1], 1);
            if (l == 59) {
                p.afterPage(line0);
                for (String h : heads) p.after(h, 1);
            }
        }
        p.after(L20, 2);
        p.after(line21, 2);
        p.close();
        spoolPrt1Portrait();
    }

    /** set-up-work-file。false: 異常終了（menu-exit）。 */
    private boolean setUpWorkFile() {
        main001();
        display(12, 1, "Creating Invoice Work File, Please Wait");
        int lin = 14, cole = 0;
        a = 0;
        if (sys.intv("p-flag-i") == 1) {
            workFile.open(Mode.OUTPUT);
            CobFile inv = invoiceFile();
            Rec ih = invHeaderRec();
            if (!inv.open(Mode.INPUT).equals("00")) {
                workFile.close(); inv.close();
                return true;
            }
            while (inv.readNext(ih).equals("00")) {
                if (ih.intv("ih-test") != 0) continue;
                if (ih.str("ih-status").equals("z")) continue;
                int type = ih.intv("ih-type");
                if (type == 1 || type == 4) continue;
                work.setNum("work-invoice", ih.longv("ih-invoice"));
                work.set("work-supplier", ih.str("ih-supplier"));
                BigDecimal amt = ih.num("ih-net").add(ih.num("ih-carriage")).add(ih.num("ih-vat")).add(ih.num("ih-c-vat"));
                if (type == 3) amt = amt.negate();
                work.setNum("work-amount", amt);
                if (!workFile.write(work).equals("00")) {
                    display(24, 1, "PL111 Error On Writing Work File. Hit Return To Abort", 4);
                    accept(24, 53, 1);
                    inv.close(); workFile.close();
                    return false;
                }
                a++;
                if (a > 9) {
                    a = 0;
                    cole++;
                    display(lin, cole, ".", 3);
                }
                if (cole > 79) { lin++; cole = 0; }
            }
            inv.close(); workFile.close();
        }
        if (lin == 14 && cole == 0 && a == 0) display(18, 1, "PL117 No Work File Created..No Data");
        else {
            workFileData = "Y";
            display(18, 1, "PL118 Work file Created");
        }
        return true;
    }

    private void getUnposted() {
        if (!workFileData.equals("N")) {
            while (workFile.readNext(work).equals("00")) {
                if (!pad(customerIn, 7).equals(work.str("work-supplier"))) break;
                invAmount = invAmount.add(work.num("work-amount"));
            }
        }
        l4unposted = Num.edit(invAmount, "z(6)9.99");
    }

    private void setQueryFlag() {
        long tinv = 0;
        display(23, 1, "For Account:        . Give invoice no. to toggle [        ]");
        show(23, 14, customerIn);
        tinv = Pl010.digits(acceptUpdate(23, 51, 8, Num.z9(tinv, 8)));
        if (tinv == 0) return;
        eraseEol(23, 1);
        oi5.close();
        boolean err = true;
        Rec r = oiRec();
        if (!oi5.open(Mode.IO).equals("00")) display(23, 1, "PL112 Can't open file", 4);
        else {
            r.set("oi-supplier", customerIn);
            r.setNum("oi-invoice", tinv);
            if (!oi5.read(r).equals("00")) display(23, 1, "PL113 Can't find it", 4);
            else if (r.intv("oi-type") != 2) display(23, 1, "PL119 Only on invoices");
            else {
                r.set("oi-hold-flag", r.str("oi-hold-flag").equals(" ") ? "H" : " ");
                if (!oi5.rewrite(r).equals("00")) display(23, 1, "PL115 Error On Rewrite", 4);
                else err = false;
            }
        }
        if (err) {
            display(24, 1, "PL116 Note: and hit return to continue");
            accept(24, 34, 1);
            eraseEol(23, 1);
        }
        oi5.close();
        oi5.open(Mode.INPUT);
    }
}
