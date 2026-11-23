package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** sl910.cbl: 請求情報入力（一括印刷待ち / 即時印刷）。 */
public class Sl910 extends SlProgram {
    static final String PROG_NAME = "SL910 (3.01.13)";
    static final String SL003 = "SL003 Hit Return To Continue", SL006 = "SL006 Note Details & Hit Return to continue",
        SL180 = "SL180 Err on Invoice file write : ", SL181 = "SL181 Invoice To Credit Does Not Exist On Open Item File",
        SL182 = "SL182 Invoice To Credit Is Paid", SL183 = "SL183 Invoice To Credit Has Query Flag Set",
        SL184 = "SL184 You Can Only Credit Invoices. Not Receipts, Credit Notes Or Proformas",
        SL185 = "SL185 Credit of Prompt Pay/Late Charge will be Automatic", SL186 = "SL186 P.A. Code Does Not Exist",
        SL190 = "SL190 Error on Writing to Audit File", SL191 = "SL191 Error on Stock file Rewrite";
    private static final String[] D_TYPES = {"Receipt <<<", "Account <<<", "Credit Note <<<", "Pro-Forma <<<"};
    private static final String DASH = "-".repeat(80);
    private static final int LINES = 24, L23 = 23, ACCEPT_BODY = 8, ESC = 2005;
    private static final BigDecimal HUNDRED = BigDecimal.valueOf(100);

    private Rec sys, sales, deliv, anal, inv, oi3, oi, sih, bodies, dnos, stock, audit;
    private CobFile salesFile, delivFile, analFile, invFile, oi3File, dnosFile, stockFile, auditFile;
    private int lineSize;
    private int i, j, k, lin, z, newScreen, vatCode;
    private boolean delExists, stockLink, auditUsed, exitProgram;
    private String escapeCode = " ", wsNamed = " ", wsProduct = "", wsDate;
    private BigDecimal wsNet = BigDecimal.ZERO, wsVat = BigDecimal.ZERO, wsUnit = BigDecimal.ZERO;
    private int wsQty;

    @Override
    public void run(Object... args) {
        sys = sys();
        sales = salesRec(); deliv = deliveryRec(); anal = analysisRec(); oi3 = oi3Rec(); oi = oiHeader();
        inv = fdRec("sales/fdinv.cob", "invoice-record");
        sih = Layout.of("sales/wsinv.cob", "sinvoice-header").newRec();
        bodies = Layout.of("sales/wsinv.cob", "sInvoice-Bodies").newRec();
        lineSize = bodies.bytes().length / 40;
        dnos = fdRec("sales/fddnos.cob", "del-inv-nos-record");
        stock = fdRec("copybooks/fdstock.cob", "Stock-Record");
        audit = fdRec("copybooks/fdaudit.cob", "Stock-Audit-Record");
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv); analFile = analysisFile(anal);
        invFile = CobFile.indexed(ctx.store, ctx.path(F_INVOICE), inv, "invoice-key");
        oi3File = oi3File(oi3);
        dnosFile = CobFile.sequential(ctx.store, ctx.path(F_DELINV));
        stockFile = CobFile.indexed(ctx.store, ctx.path(F_STOCK), stock, "stock-key")
            .alt(stock.offset("stock-abrev-key"), stock.size("stock-abrev-key"), false)
            .alt(stock.offset("stock-desc"), stock.size("stock-desc"), true);
        auditFile = CobFile.sequential(ctx.store, ctx.path(F_STAUDIT));
        term().exceptionsEnabled = true; term().escEnabled = true;
        wsDate = fromUk(toDay());
        programStart();
        if (sys.str("sl-own-nos").equals("Y")) delExists = false;
        main:
        while (true) {
            sih.initialize();
            invoiceDetails();
            if (z != 0 || escapeCode.equals("Q")) break;
            eraseEos(16, 1);
            bodies.initialize();
            i = 0;
            if (sys.intv("invoicer") == 1) invLevel1(); else invLevel2();
            if (crtStatus() == ESC) continue;
            if (i != 1) { endTotals(); if (exitProgram) return; }
            while (true) {
                display(LINES, 29, "Enter Further Invoices? (Y/N) [Y] ", 3);
                String r = upper(term().accept(LINES, 60, 1, "Y", 0, 6));
                eraseEol(LINES, 1);
                if (r.equals("Y")) continue main;
                if (r.equals("N")) break main;
            }
        }
        sys.setNum("pass-value", 0);
        closeAll();
    }

    private void closeAll() {
        dnosFile.close(); salesFile.close(); delivFile.close(); analFile.close(); invFile.close(); oi3File.close();
        if (stockLink) { stockFile.close(); auditFile.close(); }
    }

    private static int u99(int v) { return Math.abs(v) % 100; }
    private String d9(BigDecimal v) { return Num.edit(v, "z(6)9.99"); }
    private String d8(BigDecimal v) { return Num.edit(v, "z(5)9.99"); }
    private BigDecimal vatRate(int code) { return sys.num("vat-rate", code); }
    private boolean level1() { return sys.intv("invoicer") == 1; }

    private void runningTotals() {
        BigDecimal n = BigDecimal.ZERO, v = BigDecimal.ZERO;
        for (k = 1; k <= i; k++) { n = n.add(bodies.num("sil-net", k)); v = v.add(bodies.num("sil-vat", k)); }
        sih.setNum("sih-net", n); sih.setNum("sih-vat", v);
        if (level1()) {
            show(12, 37, d9(sih.num("sih-net")));
            show(12, 55, d9(sih.num("sih-vat")));
            show(12, 68, d9(sih.num("sih-net").add(sih.num("sih-vat"))));
        } else show(12, 70, d9(sih.num("sih-net").add(sih.num("sih-vat"))));
    }

    private void writeError(CobFile f) {
        display(L23, 1, SL180, 4); eraseEol(L23, 35);
        show(L23, 36, f.status); show(L23, 39, fileStatMsg(f.status)); show(L23, 64, inv.str("invoice-key"));
        display(LINES, 1, SL006, 3);
        accept(LINES, 30, 1);
        eraseEos(L23, 1);
    }

    private void writeDetails() {
        j++;
        bodies.setNum("sil-invoice", sih.longv("sih-invoice"), j);
        bodies.setNum("sil-line", j, j);
        bodies.set("sil-letter", sih.str("sih-letter"), j);
        bodies.set("sil-type", sih.str("sih-type"), j);
        byte[] b = inv.bytes();
        java.util.Arrays.fill(b, (byte) ' ');
        System.arraycopy(bodies.bytes(), (j - 1) * lineSize, b, 0, lineSize);
        invFile.write(inv);
        if (!invFile.status.equals("00")) writeError(invFile);
        updateStockAndAudit();
    }

    private boolean readStock(String key) {
        if (key.substring(7).isBlank()) { stock.set("stock-abrev-key", key.substring(0, 7)); stockFile.readAlt(stock, 0); }
        else { stock.set("stock-key", key); stockFile.read(stock); }
        return !invalidKey(stockFile);
    }

    private void updateStockAndAudit() {
        if (!stockLink) return;
        audit.initialize();
        audit.setNum("audit-type", 3);
        audit.setNum("audit-invoice-po", sih.longv("sih-invoice"));
        audit.set("audit-process-date", wsDate);
        String key = bodies.str("sil-product", j);
        audit.set("audit-stock-key", key);
        audit.set("audit-desc", bodies.str("sil-description", j));
        audit.setNum("audit-transaction-qty", bodies.longv("sil-qty", j));
        audit.setNum("audit-unit-cost", 0);
        int type = intOf(bodies.str("sil-type", j));
        if (type == 3) {
            audit.setNum("audit-type", 5); audit.setNum("audit-reverse-transaction", 1);
            audit.setNum("audit-cr-for-invoice", sih.longv("sih-cr"));
        } else audit.setNum("audit-reverse-transaction", 0);
        audit.setNum("audit-no", sys.longv("stk-audit-no"));
        if (!readStock(key)) { stock.setNum("stock-cost", 0); stock.set("stock-key", " "); }
        if (!stock.str("stock-key").isBlank()) {
            BigDecimal qty = audit.num("audit-transaction-qty"), cost = stock.num("stock-cost");
            if (type == 1 || type == 2) {
                audit.setNum("audit-stock-value-change", qty.multiply(cost).negate());
                stock.sub("stock-held", qty);
            } else if (type == 3) {
                audit.setNum("audit-stock-value-change", qty.multiply(cost));
                stock.add("stock-held", qty);
            }
            if (stock.num("stock-held").signum() < 0) {
                stock.setNum("stock-held", stock.num("stock-held").negate());
                stock.add("stock-pre-sales", stock.num("stock-held"));
                stock.setNum("stock-held", 0);
            }
            if (stock.num("stock-held").signum() > 0) stock.setNum("stock-value", stock.num("stock-held").multiply(stock.num("stock-cost")));
            else stock.setNum("stock-value", 0);
            stockFile.rewrite(stock);
            if (!stockFile.status.equals("00")) {
                display(L23, 1, SL191, 4); show(L23, 38, stockFile.status, 2);
                display(LINES, 1, SL006);
                accept(LINES, 45, 1);
                eraseEos(L23, 1);
            }
        }
        if (auditUsed) {
            sys.setNum("stk-activity-rep-run", 0);
            auditFile.write(audit);
            if (!auditFile.status.equals("00")) {
                display(L23, 1, SL190, 4); show(L23, 38, auditFile.status, 2); show(L23, 41, fileStatMsg(auditFile.status));
                display(LINES, 1, SL006);
                accept(LINES, 45, 1);
            }
        }
    }

    // ---- level 1 ----
    private void invLevel1() {
        display(11, 1, DASH);
        display(12, 1, "Level 1");
        display(12, 16, "Line - ");
        display(12, 36, "[          ]"); display(12, 54, "[          ]"); display(12, 67, "[          ]");
        display(14, 5, "Code");
        display(14, 36, "<---Net---->  Vat   Vat Amount  Gross Amount");
        while (true) {
            for (lin = 16; lin < L23; lin++) {
                i = u99(i + 1);
                eraseEol(lin, 1);
                show(lin, 1, "(", 2); show(lin, 2, z(i, 2), 2); show(lin, 4, ") [  ]", 2);
                show(lin, 36, "[          ] [ ]   {         } (", 2); show(lin, 78, ")", 2);
            }
            i = u99(i - ACCEPT_BODY);
            j = 1;
            show(12, 23, z(i, 2));
            term().crtStatus = 0;
            getData1();
            if (crtStatus() == ESC) return;
            if (newScreen == 1) continue;
            if (i >= 1 && i <= 40 && !bodies.str("sil-description", i).isBlank() && i != 40) continue;
            return;
        }
    }

    private void getData1() {
        data:
        while (true) {
            lin = j + 15;
            if (lin > L23) { i = u99(i - 1); newScreen = 1; return; }
            newScreen = 0;
            while (true) {
                // get-code
                if (i > 1 && bodies.str("sil-pa", i).isBlank()) bodies.set("sil-pa", bodies.str("sil-pa", i - 1), i);
                String pa = bodies.str("sil-pa", i);
                show(lin, 7, pa);
                pa = acceptUpdate(lin, 7, 2, pa);
                bodies.set("sil-pa", pa, i); anal.set("pa-group", pa);
                bodies.set("sil-description", " ", i);
                if (pa.isBlank()) return;
                if (crtStatus() == ESC) return;
                if (pa.equals("<<")) {
                    if (i == 1) continue;
                    lin--;
                    if (lin > 15) { i--; j--; continue; }
                    i = u99(i - ACCEPT_BODY);
                    continue data;
                }
                anal.set("pa-system", "S");
                analFile.read(anal);
                if (invalidKey(analFile)) { display(L23, 1, SL186, 4); continue; }
                eraseEol(L23, 1);
                show(lin, 11, anal.str("pa-desc"));
                bodies.set("sil-description", anal.str("pa-desc"), i);
                BigDecimal a7 = acceptMoney(lin, 37, 7, BigDecimal.ZERO);
                if (a7.signum() == 0) continue;
                bodies.setNum("sil-net", a7, i); wsNet = a7;
                do { vatCode = intOf(acceptUpdate(lin, 50, 1, z(vatCode, 1), NUMERIC)); } while (vatCode > 3);
                bodies.setNum("sil-vat-code", vatCode, i);
                BigDecimal a6 = vatCode == 0 ? BigDecimal.ZERO : wsNet.multiply(vatRate(vatCode)).divide(HUNDRED, 2, RoundingMode.HALF_UP);
                a6 = acceptMoney(lin, 56, 6, a6);
                bodies.setNum("sil-vat", a6, i); wsVat = a6;
                show(lin, 68, d9(wsVat.add(wsNet)));
                runningTotals();
                j++; i++;
                continue data;
            }
        }
    }

    // ---- level 2 ----
    private void invLevel2() {
        boolean linkN = sys.str("sl-stock-link").equals("N");
        display(11, 1, DASH);
        display(12, 1, stockLink ? "Stock Linked" : "Level 2");
        display(12, 16, "Line - ");
        display(12, 27, "Net <          >");
        display(12, 44, "Vat <          >");
        display(12, 61, "Invoice <          >");
        display(14, 5, linkN ? "Product    Code <---------Description-------->   Qty   Unit Price  Disc. Vat"
            : "Product     <----------Description--------->    Qty   Unit Price  Disc. Vat");
        while (true) {
            for (lin = 16; lin < L23; lin++) {
                i = u99(i + 1);
                eraseEol(lin, 1);
                if (linkN) { show(lin, 1, "[             ][  ][", 2); show(lin, 51, "][     ][          ][     ][ ]", 2); }
                else { show(lin, 1, "[             ][", 2); show(lin, 49, "]  [     ][          ][     ][ ]", 2); }
            }
            i = u99(i - ACCEPT_BODY);
            j = 1;
            show(12, 23, z(i, 2), 2);
            getData2();
            if (crtStatus() == ESC) return;
            if (newScreen == 1) continue;
            if (!wsProduct.isBlank() && i != 40) continue;
            return;
        }
    }

    private enum S { DATA, PRODUCT, PRODTEST, CODE, DESC, QTY, UNIT, RECOMP, DISC, JUMP }

    private void stockMsg(String msg, int fg) { stock.set("stock-desc", msg); show(lin, 17, stock.str("stock-desc"), fg); }

    private void showStockPick(boolean wait) {
        bodies.set("sil-product", stock.str("stock-abrev-key"), i);
        wsProduct = pad(stock.str("stock-abrev-key"), 13);
        show(lin, 17, stock.str("stock-desc"));
        wsQty = (int) (Math.abs(stock.longv("stock-held")) % 100000);
        show(lin, 53, z(wsQty, 5));
        if (wait) accept(24, 10, 1);
        BigDecimal r = stock.num("stock-retail");
        show(lin, 60, z(r.longValue(), 7) + "." + z(r.remainder(BigDecimal.ONE).movePointRight(2).longValue(), 2));
    }

    private void getData2() {
        S s = S.DATA;
        boolean comment = false;
        while (true) {
            switch (s) {
                case DATA -> {
                    lin = j + 15;
                    if (lin > L23 - 1) { i = u99(i - 1); newScreen = 1; return; }
                    newScreen = 0;
                    s = S.PRODUCT;
                }
                case PRODUCT -> {
                    if (i > 1 && bodies.str("sil-product", i).isBlank()) bodies.set("sil-product", bodies.str("sil-product", i - 1), i);
                    show(12, 23, z(i, 2), 2);
                    wsProduct = bodies.str("sil-product", i);
                    show(lin, 2, wsProduct);
                    wsProduct = acceptUpdate(lin, 2, 13, wsProduct);
                    int key = crtStatus();
                    bodies.set("sil-description", " ", i);
                    if (key != 1006) {
                        if (wsProduct.isBlank()) return;
                        if (key == ESC) return;
                    }
                    wsProduct = upper(wsProduct);
                    bodies.set("sil-product", wsProduct, i);
                    comment = wsProduct.startsWith("/");
                    if (comment) { wsNet = BigDecimal.ZERO; wsUnit = BigDecimal.ZERO; wsQty = 0; s = S.DESC; break; }
                    if (wsProduct.equals("<<           ")) { lin--; s = S.PRODTEST; break; }
                    if (!stockLink) { s = S.CODE; break; }
                    if (key == 1003 || key == 1002 || key == 1005) {
                        if (key == 1003) {
                            stock.set("stock-abrev-key", wsProduct.substring(0, 7));
                            stockFile.startAlt(stock, 0, ">=");
                            if (invalidKey(stockFile)) { stockMsg("Not Found", 4); break; }
                        }
                        stockFile.readNext(stock);
                        if (!stockFile.status.equals("00")) { stockMsg("End of File", 4); break; }
                        if (key == 1005) showStockPick(false);
                        else { bodies.set("sil-product", stock.str("stock-abrev-key"), i); show(lin, 17, stock.str("stock-desc")); }
                        break;
                    }
                    if (key == 1006) {
                        String d = acceptUpdate(lin, 17, 32, bodies.str("sil-description", i));
                        stock.set("stock-desc", d);
                        stockFile.startAlt(stock, 1, ">=");
                        if (invalidKey(stockFile)) { stockMsg("Not Found", 4); break; }
                        stockFile.readNext(stock);
                        if (!stockFile.status.equals("00")) { stockMsg("End of File", 4); break; }
                        showStockPick(true);
                        break;
                    }
                    if (!readStock(wsProduct)) { stockMsg("Not on File", 4); break; }
                    // Process-Stock-Record
                    String pa = stock.str("stock-sa-group");
                    anal.set("pa-group", pa); bodies.set("sil-pa", pa, i);
                    show(lin, 17, stock.str("stock-desc"));
                    bodies.set("sil-description", stock.str("stock-desc"), i);
                    wsUnit = stock.num("stock-retail");
                    show(lin, 60, z(wsUnit.longValue(), 7) + "." + z(wsUnit.remainder(BigDecimal.ONE).movePointRight(2).longValue(), 2));
                    wsQty = (int) (Math.abs(stock.longv("stock-held")) % 100000);
                    s = S.QTY;
                }
                case PRODTEST -> {
                    if (i == 1) { lin++; s = S.PRODUCT; }
                    else if (lin > 15) { i--; j--; s = S.PRODUCT; }
                    else { i = u99(i - ACCEPT_BODY); s = S.DATA; }
                }
                case CODE -> {
                    if (i > 1 && bodies.str("sil-pa", i).isBlank()) bodies.set("sil-pa", bodies.str("sil-pa", i - 1), i);
                    String pa = bodies.str("sil-pa", i);
                    show(lin, 17, pa);
                    pa = acceptUpdate(lin, 17, 2, pa);
                    bodies.set("sil-description", " ", i);
                    if (pa.isBlank()) { s = S.PRODUCT; break; }
                    anal.set("pa-group", pa); bodies.set("sil-pa", pa, i);
                    anal.set("pa-system", "S");
                    analFile.read(anal);
                    if (invalidKey(analFile)) { display(lin, 21, SL186, 4); break; }
                    s = S.DESC;
                }
                case DESC -> {
                    if (i > 1 && bodies.str("sil-description", i).isBlank() && !comment)
                        bodies.set("sil-description", bodies.str("sil-description", i - 1), i);
                    int col = stockLink ? 17 : 21;
                    String d = bodies.str("sil-description", i);
                    show(lin, col, d);
                    d = acceptUpdate(lin, col, 32, d);
                    bodies.set("sil-description", d, i);
                    escapeCode = d.isBlank() ? "B" : " ";
                    if (escapeCode.equals("B")) s = comment ? S.PRODUCT : S.CODE;
                    else s = comment ? S.JUMP : S.QTY;
                }
                case QTY -> {
                    if (sys.str("sl-stock-link").equals("N")) wsQty = 0;
                    show(lin, 53, z(wsQty, 5));
                    wsQty = intOf(acceptUpdate(lin, 53, 5, z(wsQty, 5), NUMERIC));
                    if (wsQty == 0) { s = S.DESC; break; }
                    if (stockLink && wsQty > stock.longv("stock-held")) { wsQty = (int) (Math.abs(stock.longv("stock-held")) % 100000); break; }
                    s = stockLink ? S.RECOMP : S.UNIT;
                }
                case UNIT -> {
                    BigDecimal a7 = acceptMoney(lin, 60, 7, BigDecimal.ZERO);
                    if (a7.signum() == 0) { s = S.QTY; break; }
                    wsUnit = a7;
                    s = S.RECOMP;
                }
                case RECOMP -> {
                    BigDecimal n = wsUnit.multiply(BigDecimal.valueOf(wsQty));
                    if (n.compareTo(new BigDecimal("9999999.99")) > 0) { display(lin, 60, "SizEr", 4); s = S.QTY; break; }
                    wsNet = n;
                    bodies.setNum("sil-net", wsNet, i); bodies.setNum("sil-qty", wsQty, i); bodies.setNum("sil-unit", wsUnit, i);
                    show(12, 32, d9(wsNet));
                    s = S.DISC;
                }
                case DISC -> {
                    String d = acceptUpdate(lin, 72, 5, Num.edit(sales.num("sales-discount"), "99.99"));
                    BigDecimal disc = new BigDecimal(z(intOf(d.substring(0, 2)), 2) + "." + z(intOf(d.substring(3, 5)), 2));
                    bodies.setNum("sil-discount", disc, i);
                    BigDecimal w = Num.truncated(Num.truncated(wsNet.multiply(disc), 2).divide(HUNDRED), 2);
                    wsNet = wsNet.subtract(w);
                    bodies.setNum("sil-net", wsNet, i);
                    show(12, 32, d9(wsNet));
                    do {
                        show(lin, 79, z(vatCode, 1));
                        vatCode = intOf(acceptUpdate(lin, 79, 1, z(vatCode, 1), NUMERIC));
                    } while (vatCode > 3);
                    bodies.setNum("sil-vat-code", vatCode, i);
                    wsVat = vatCode == 0 ? BigDecimal.ZERO : wsNet.multiply(vatRate(vatCode)).divide(HUNDRED, 2, RoundingMode.HALF_UP);
                    bodies.setNum("sil-vat", wsVat, i);
                    show(12, 49, d9(wsVat));
                    runningTotals();
                    s = S.JUMP;
                }
                case JUMP -> { j++; i++; s = S.DATA; }
            }
        }
    }

    // ---- totals ----
    private void endTotals() {
        while (true) {
            term().crtStatus = 0;
            totalScreen();
            if (crtStatus() == ESC) return;
            eraseEos(15, 1);
            display(16, 60, "*********************");
            for (int l = 17; l <= 19; l++) { show(l, 60, "*", 2); show(l, 80, "*", 2); }
            display(20, 60, "*********************");
            display(17, 61, "Invoice Ok to");
            display(17, 75, sys.intv("pass-value") == 2 ? "Store" : "Print");
            display(19, 68, "(Y/N) ? [Y]");
            String r;
            do {
                r = upper(term().accept(19, 77, 1, "Y", 0, 6));
                if (crtStatus() == ESC) return;
            } while (!r.equals("N") && !r.equals("Y"));
            if (r.equals("Y")) break;
        }
        sih.set("sih-status", "P"); sih.set("sih-status-p", " ");
        i = u99(i - 1);
        sih.setNum("sih-lines", i);
        move(sih, inv);
        invFile.write(inv);
        if (!invFile.status.equals("00")) writeError(invFile);
        j = 0;
        for (int n = i; n > 0; n--) writeDetails();
        int pass = sys.intv("pass-value");
        if (sys.longv("first-sl-inv") == 0 && pass != 3) sys.setNum("first-sl-inv", sih.longv("sih-invoice"));
        if (!delExists) sys.setNum("next-invoice", sys.longv("next-invoice") + 1);
        if (pass == 3) {
            closeAll();
            call("sl930");
            exitProgram = true;
            return;
        }
        sys.setNum("s-flag-i", 1);
        eraseEos(11, 1);
    }

    private void totalScreen() {
        eraseEos(11, 1);
        display(11, 1, DASH);
        display(12, 1, "Level "); show(12, 7, level1() ? "1" : "2", 2);
        display(12, 25, "<---Net---->   <---Vat--->");
        display(12, 54, "<---Gross-->     Days");
        display(14, 4, "Sub-Totals");
        display(14, 25, "{          }   {         }");
        display(14, 54, "{          }     [  ]");
        show(15, 4, sys.str("extra-desc"), 2);
        display(15, 25, "[          ]   [         ]");
        display(15, 54, "{          }");
        display(16, 4, "Shipping & Handling");
        display(16, 25, "[          ]   [         ]");
        display(16, 54, "{          }");
        display(17, 4, "Late Charge");
        display(17, 25, "[          ]              ");
        display(17, 54, "{          }     [  ]");
        display(18, 25, "------------   -----------");
        display(18, 54, "------------");
        display(19, 4, "Itemised Totals");
        display(19, 25, "{          }   {         }");
        display(19, 54, "{          }");
        BigDecimal net = sih.num("sih-net"), vat = sih.num("sih-vat");
        show(14, 26, d9(net)); show(14, 41, d8(vat)); show(14, 55, d9(net.add(vat)));
        int type = sih.intv("sih-type");
        sih.setNum("sih-days", 0); sih.setNum("sih-carriage", 0);
        if (type == 2) sih.setNum("sih-days", sales.longv("sales-credit"));
        else if (type == 4) sih.setNum("sih-days", sys.longv("pf-retention"));
        int days = u99(sih.intv("sih-days"));
        show(14, 72, z(days, 2));
        if (type == 2) { days = intOf(acceptUpdate(14, 72, 2, z(days, 2), NUMERIC)); sih.setNum("sih-days", days); }
        BigDecimal vat1 = sys.num("vat-rate-1");
        if (sys.str("extra-type").equals(" ")) { sih.setNum("sih-extra", 0); sih.setNum("sih-e-vat", 0); }
        else {
            BigDecimal ex = sys.num("extra-rate").signum() != 0 ? Num.truncated(net.multiply(sys.num("extra-rate")).divide(HUNDRED), 2) : BigDecimal.ZERO;
            ex = acceptMoney(15, 26, 7, ex);
            sih.setNum("sih-extra", ex);
            if (ex.signum() == 0) sih.setNum("sih-e-vat", 0);
            else {
                BigDecimal ev = acceptMoney(15, 41, 6, Num.truncated(ex.multiply(vat1).divide(HUNDRED), 2));
                sih.setNum("sih-e-vat", ev);
                show(15, 55, d9(ex.add(ev)));
                if (sys.str("extra-type").equals("D")) { sih.setNum("sih-extra", ex.negate()); sih.setNum("sih-e-vat", ev.negate()); }
            }
        }
        BigDecimal car = acceptMoney(16, 26, 7, BigDecimal.ZERO);
        sih.setNum("sih-carriage", car);
        BigDecimal cv = acceptMoney(16, 41, 6, car.multiply(vat1).divide(HUNDRED, 2, RoundingMode.HALF_UP));
        sih.setNum("sih-c-vat", cv);
        show(16, 55, d9(car.add(cv)));
        // get-deduct-amt
        if (wsNamed.equals("A") && oi.num("oi-net").compareTo(net) == 0 && oi.num("oi-vat").compareTo(vat) == 0
            && oi.num("oi-carriage").compareTo(car) == 0) wsNamed = "Z";
        if ((type != 2 && type != 3) || sales.intv("sales-late") != 1 || wsNamed.equals("Z")) {
            sih.setNum("sih-deduct-amt", 0); sih.setNum("sih-deduct-vat", 0); sih.setNum("sih-deduct-days", 0);
            return;
        }
        BigDecimal ded = Num.truncated(net.divide(BigDecimal.TEN), 2);
        if (ded.compareTo(BigDecimal.valueOf(4)) < 0) ded = BigDecimal.valueOf(4);
        ded = acceptMoney(17, 26, 7, ded);
        sih.setNum("sih-deduct-amt", ded);
        sih.setNum("sih-deduct-vat", 0);
        BigDecimal tn = net.add(sih.num("sih-extra")).add(car).add(sih.num("sih-deduct-amt"));
        BigDecimal tv = vat.add(sih.num("sih-e-vat")).add(cv).add(sih.num("sih-deduct-vat"));
        show(19, 26, d9(tn)); show(19, 41, d8(tv)); show(19, 55, d9(tn.add(tv)));
        days = u99(sih.intv("sih-days"));
        show(17, 72, z(days, 2));
        sih.setNum("sih-deduct-days", intOf(acceptUpdate(17, 72, 2, z(days, 2), NUMERIC)));
    }

    // ---- header ----
    private void invoiceDetails() {
        details:
        while (true) {
            clearScreen();
            show(1, 1, PROG_NAME);
            display(1, 32, "Invoicing Data Entry");
            wsDate = fromUk(toDay());
            show(1, 71, wsDate, 2);
            display(4, 41, "****************************************");
            display(5, 41, "*Date  [  /  /    ]*                   *");
            display(6, 41, "*A/C Nos  [       ]*Ref    [          ]*");
            display(7, 41, "*Invoice [        ]*Order  [          ]*");
            display(8, 41, "****************************************");
            display(9, 11, "F1 = Setup new Customer; F8 = Only Show delivery details");
            display(10, 1, "Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note; <4> = Pro-Forma");
            while (true) {
                show(5, 49, wsDate);
                wsDate = acceptUpdate(5, 49, 10, wsDate);
                if (crtStatus() == ESC || wsDate.isBlank()) { z = 1; return; }
                long bin = validateDate(wsDate);
                if (bin == 0) continue;
                sih.setNum("sih-date", bin);
                break;
            }
            customer:
            while (true) {
                sih.set("sih-customer", " ");
                term().crtStatus = 0;
                String cust = upper(acceptUpdate(6, 52, 7, " ".repeat(7)));
                sih.set("sih-customer", cust);
                int key = crtStatus();
                boolean showDelivery = key == 1008;
                if (cust.equals("CREATE9")) {
                    display(23, 1, "Creating Invoice File                    ");
                    invFile.close(); invFile.open(CobFile.Mode.OUTPUT); invFile.close();
                    sys.setNum("file-status", 1, 16);
                    invFile.open(CobFile.Mode.IO);
                }
                if (cust.equals("NEW    ") || key == 1001) {
                    dnosFile.close(); salesFile.close(); invFile.close(); delivFile.close(); analFile.close(); oi3File.close();
                    if (stockLink) stockFile.close();
                    if (auditUsed) auditFile.close();
                    call("sl960");
                    programStart();
                    continue details;
                }
                if (cust.isBlank()) { escapeCode = "Q"; return; }
                sales.set("sales-key", cust);
                salesFile.read(sales);
                if (invalidKey(salesFile)) { display(4, 1, "No such Customer", 3); continue; }
                show(9, 11, " ".repeat(23), 2);
                boolean ownNos = sys.str("sl-own-nos").equals("Y");
                if (!ownNos) {
                    if (delExists) getADeletedInvoice(); else sih.setNum("sih-invoice", sys.longv("next-invoice"));
                    show(7, 51, z(sih.longv("sih-invoice"), 8));
                    sih.set("sih-letter", " ");
                } else {
                    boolean back = false;
                    getInv:
                    while (true) {
                        sih.setNum("sih-invoice", intOf(acceptUpdate(7, 51, 8, z(sih.longv("sih-invoice"), 8), NUMERIC)));
                        if (crtStatus() == ESC) { back = true; break; }
                        sih.set("sih-letter", " ");
                        while (true) {
                            sih.setNum("sih-test", 0);
                            inv.setNum("invoice-nos", sih.longv("sih-invoice")); inv.set("invoice-let", sih.str("sih-letter")); inv.setNum("item-nos", 0);
                            invFile.read(inv);
                            if (invalidKey(invFile)) break getInv;
                            display(7, 1, "Confirm Duplicate - [ ]");
                            if (!upper(term().accept(7, 22, 1, " ", 0, 6)).equals("Y")) continue getInv;
                            String l = sih.str("sih-letter");
                            if (l.equals(" ")) sih.set("sih-letter", "A");
                            else if (l.equals("A")) sih.set("sih-letter", "B");
                            else if (l.equals("B")) sih.set("sih-letter", "C");
                        }
                    }
                    if (back) continue customer;
                }
                // jump-1
                String addr;
                if (sales.intv("delivery-tag") == 0 || !showDelivery) addr = sales.str("sales-address");
                else {
                    deliv.set("deliv-key-type", "D"); deliv.set("deliv-sales-key", sales.str("sales-key"));
                    delivFile.read(deliv);
                    if (invalidKey(delivFile)) { sales.setNum("delivery-tag", 0); addr = sales.str("sales-address"); }
                    else addr = deliv.str("deliv-address");
                }
                show(3, 1, sales.intv("delivery-tag") == 0 ? sales.str("sales-name") : deliv.str("deliv-name"));
                String delim = pad(sys.str("sl-delim"), 1);
                int p = 1;
                String line = " ".repeat(36);
                for (int l = 4; l <= 7; l++) {
                    Object[] r = unstring(addr, delim, p, 36);
                    if (r[0] != null) { line = (String) r[0]; p = (int) r[1]; }
                    show(l, 1, line);
                    line = " ".repeat(36);
                }
                if (p >= 1 && p <= addr.length()) line = pad(addr.substring(p - 1, Math.min(addr.length(), p + 35)), 36);
                show(8, 1, line);
                break;
            }
            sih.set("sih-ref", acceptUpdate(6, 69, 10, " ".repeat(10)));
            sih.set("sih-order", acceptUpdate(7, 69, 10, " ".repeat(10)));
            int type;
            do {
                type = intOf(acceptUpdate(10, 7, 1, "0", NUMERIC));
                sih.setNum("sih-type", type);
                wsNamed = " ";
                if (type == 0) continue details;
            } while (type > 4);
            eraseEol(10, 1);
            display(10, 31, ">>> ");
            display(10, 35, D_TYPES[type - 1]);
            sih.setNum("sih-cr", 0);
            if (type == 3) { crNote(); if (escapeCode.equals("Q")) continue; }
            z = 0;
            if (type != 2) return;
            int weError = 0;
            sales.setNum("sales-current", sales.num("sales-current").subtract(sales.num("sales-unapplied")));
            BigDecimal cur = sales.num("sales-current");
            if (cur.signum() > 0 && Math.abs(sys.longv("run-date") - sales.longv("sales-last-inv")) > sales.longv("sales-credit")) {
                display(16, 48, "Overdue Balance <<<"); weError = 999;
            }
            if (cur.compareTo(BigDecimal.valueOf(sales.longv("sales-limit"))) > 0) { display(17, 25, "Balance Exceeds Credit Limit <<<"); weError = 998; }
            if (sales.longv("sales-credit") <= 0 || sales.longv("sales-limit") <= 0) { display(18, 25, "No Longer an Account Customer <<<"); weError = 997; }
            if (weError == 0) return;
            display(16, 35, ">>> Warning! ");
            display(19, 58, "**********************");
            show(20, 58, "*", 2); show(21, 58, "*", 2); show(20, 79, "*", 2); show(21, 79, "*", 2);
            display(22, 58, "**********************");
            display(20, 60, "None Zero To Abort");
            display(21, 60, "Return To Continue");
            z = intOf(term().accept(22, 80, 2, "00", NUMERIC, 6));
            if (crtStatus() == ESC) { z = 1; term().crtStatus = 1; }
            return;
        }
    }

    private void getADeletedInvoice() {
        while (true) {
            dnosFile.readNext(dnos);
            if (!dnosFile.status.equals("00")) break;
            if (dnos.longv("del-inv-nos") == 0) continue;
            sih.setNum("sih-invoice", dnos.longv("del-inv-nos"));
            display(3, 45, "Using Deleted Invoice Numbers");
            return;
        }
        dnosFile.close();
        dnosFile.open(CobFile.Mode.OUTPUT);
        show(3, 45, " ".repeat(29), 2);
        sih.setNum("sih-invoice", sys.longv("next-invoice"));
        delExists = false;
    }

    private void crNote() {
        boolean clear = true;
        while (true) {
            if (clear) for (int l = 12; l <= 16; l++) eraseEol(l, 1);
            clear = true;
            display(12, 1, "Invoice To Credit - [");
            display(12, 30, "] ");
            long cr = intOf(acceptUpdate(12, 22, 8, "00000000", NUMERIC));
            if (crtStatus() == ESC) { escapeCode = "Q"; return; }
            sih.setNum("sih-cr", cr);
            if (cr == 0) { wsNamed = "Z"; break; }
            wsNamed = " ";
            if (cr == 99999999) { escapeCode = "Q"; return; }
            escapeCode = " ";
            oi3.setNum("oi3-invoice", cr); oi3.set("oi3-customer", sih.str("sih-customer"));
            oi3File.read(oi3);
            if (invalidKey(oi3File)) {
                display(L23, 1, SL181);
                String r;
                do {
                    display(14, 1, "Do you wish to use this Invoice No.? {N}");
                    display(15, 1, "..If so, you must ensure that it belonged to the same customer and that it is a ");
                    display(16, 1, "Invoice ie, not a receipt");
                    r = upper(term().accept(14, 39, 1, "N", 0, 6));
                } while (!r.equals("Y") && !r.equals("N"));
                if (r.equals("Y")) break;
                continue;
            }
            move(oi3, oi);
            eraseEol(L23, 1);
            if (oi.intv("oi-type") != 2) { display(L23, 1, SL184); clear = false; continue; }
            if (oi.intv("oi-status") == 1) { display(13, 1, SL182); clear = false; continue; }
            eraseEol(L23, 1);
            if (oi.str("oi-hold-flag").equals("Q")) display(L23, 1, SL183);
            if (oi.longv("oi-date") + 1 + oi.longv("oi-deduct-days") > sih.longv("sih-date")) wsNamed = "A";
            oi.add("oi-deduct-amt", oi.num("oi-deduct-vat"));
            BigDecimal os = oi.num("oi-discount");
            for (String f : new String[] {"oi-extra", "oi-carriage", "oi-deduct-amt", "oi-net", "oi-vat", "oi-c-vat", "oi-e-vat"}) os = os.add(oi.num(f));
            os = os.subtract(oi.num("oi-paid"));
            oi.setNum("oi-discount", os);
            display(14, 1, "Amount O/S on Invoice is ");
            show(14, 26, d9(oi.num("oi-discount")));
            display(14, 37, "of which");
            show(14, 46, d8(oi.num("oi-deduct-amt")));
            display(14, 56, "is Late Charges");
            if (wsNamed.equals("A")) display(15, 10, SL185);
            display(16, 26, SL006);
            accept(16, 61, 1);
            break;
        }
        for (int l = 12; l <= 16; l++) eraseEol(l, 1);
    }

    private void programStart() {
        clearScreen();
        stockLink = sys.str("sl-stock-link").equals("Y");
        auditUsed = sys.intv("stk-audit-used") == 1;
        if (sys.intv("file-status", 15) != 1) {
            ctx.shared.put("ws-process-func", 1); ctx.shared.put("ws-sub-function", 1);
            call("sl070");
            if (sys.intv("file-status", 15) != 1) { maps99(29); maps99(15); }
        }
        salesFile.open(CobFile.Mode.INPUT); delivFile.open(CobFile.Mode.INPUT); analFile.open(CobFile.Mode.INPUT);
        if (sys.intv("file-status", 16) != 1) { invFile.open(CobFile.Mode.OUTPUT); invFile.close(); sys.setNum("file-status", 1, 16); }
        if (sys.intv("file-status", 19) != 1) { oi3File.open(CobFile.Mode.OUTPUT); oi3File.close(); sys.setNum("file-status", 1, 19); }
        invFile.open(CobFile.Mode.IO);
        oi3File.open(CobFile.Mode.INPUT);
        dnosFile.open(CobFile.Mode.INPUT);
        if (!dnosFile.status.equals("00")) delExists = false;
        else { dnosFile.close(); dnosFile.open(CobFile.Mode.IO); delExists = true; }
        if (stockLink) {
            if (sys.intv("file-status", 11) != 1) {
                stockFile.open(CobFile.Mode.OUTPUT); stockFile.close(); stockFile.open(CobFile.Mode.IO);
                sys.setNum("file-status", 1, 11);
            } else stockFile.open(CobFile.Mode.IO);
            if (auditUsed) {
                if (sys.intv("file-status", 10) != 1) { auditFile.open(CobFile.Mode.OUTPUT); sys.setNum("file-status", 1, 10); }
                else auditFile.open(CobFile.Mode.EXTEND);
            }
        }
    }
}
