package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Arrays;

/** sl920.cbl: 請求書修正。 */
public class Sl920 extends SlProgram {
    static final String PROG_NAME = "SL920 (3.01.08)";
    static final String SL006 = "SL006 Note Details & Hit Return to continue", SL180 = "SL180 Err on Invoice file write : ",
        SL184 = "SL184 You Can Only Credit Invoices. Not Receipts, Credit Notes Or Proformas", SL186 = "SL186 P.A. Code Does Not Exist",
        SL190 = "SL190 Error on Writing to Audit File", SL191 = "SL191 Error on Stock file Rewrite",
        SL192 = "SL192 Err on Invoice file rewrite : ", SL193 = "SL193 Invoice To Credit Does Not Exist On Invoice File",
        SL194 = "SL194 Invoice Not Found!!!!", SL195 = "SL195 Invoice Details Already Passed To Sales Ledger!",
        SL196 = "SL196 You Can Only Credit An Invoice With The Same Account Number";
    private static final String DASH = "-".repeat(80);
    private static final int LINES = 24, L23 = 23, ACCEPT_BODY = 8, ESC = 2005;
    private static final BigDecimal HUNDRED = BigDecimal.valueOf(100);

    private Rec sys, sales, deliv, anal, inv, sih, bodies, stock, audit;
    private CobFile salesFile, delivFile, analFile, invFile, stockFile, auditFile;
    private int lineSize;
    private int i, j, k, lin, z, newScreen, vatCode;
    private boolean stockLink, auditUsed;
    private String escapeCode = " ", wsNamed = " ", wsProduct = "", wsDate;
    private BigDecimal wsNet = BigDecimal.ZERO, wsVat = BigDecimal.ZERO, wsUnit = BigDecimal.ZERO;
    private int wsQty;
    // Change-Item-Tables
    private int citNewProduct, citA, citD;
    private final String[] citAKey = new String[41], citADesc = new String[41], citDKey = new String[41], citDDesc = new String[41];
    private final long[] citAQty = new long[41], citDQty = new long[41];

    @Override
    public void run(Object... args) {
        sys = sys();
        sales = salesRec(); deliv = deliveryRec(); anal = analysisRec();
        inv = fdRec("sales/fdinv.cob", "invoice-record");
        sih = Layout.of("sales/wsinv.cob", "sinvoice-header").newRec();
        bodies = Layout.of("sales/wsinv.cob", "sInvoice-Bodies").newRec();
        lineSize = bodies.bytes().length / 40;
        stock = fdRec("copybooks/fdstock.cob", "Stock-Record");
        audit = fdRec("copybooks/fdaudit.cob", "Stock-Audit-Record");
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv); analFile = analysisFile(anal);
        invFile = CobFile.indexed(ctx.store, ctx.path(F_INVOICE), inv, "invoice-key");
        stockFile = CobFile.indexed(ctx.store, ctx.path(F_STOCK), stock, "stock-key")
            .alt(stock.offset("stock-abrev-key"), stock.size("stock-abrev-key"), false)
            .alt(stock.offset("stock-desc"), stock.size("stock-desc"), true);
        auditFile = CobFile.sequential(ctx.store, ctx.path(F_STAUDIT));
        term().exceptionsEnabled = true; term().escEnabled = true;
        wsDate = fromUk(toDay());
        programStart();
        main:
        while (true) {
            bodies.initialize();
            citNewProduct = 0; citA = 0; citD = 0;
            Arrays.fill(citAKey, " ".repeat(13)); Arrays.fill(citADesc, " ".repeat(32)); Arrays.fill(citAQty, 0);
            Arrays.fill(citDKey, " ".repeat(13)); Arrays.fill(citDDesc, " ".repeat(32)); Arrays.fill(citDQty, 0);
            invoiceDetails();
            if (crtStatus() == ESC || z != 0 || escapeCode.equals("Q")) break;
            eraseEos(16, 1);
            sih.setNum("sih-p-c", 0); sih.setNum("sih-net", 0); sih.setNum("sih-vat", 0);
            i = 0;
            if (level1()) invLevel1(); else invLevel2();
            if (crtStatus() == ESC) continue;
            if (i != 1) endTotals();
            while (true) {
                display(16, 29, "Amend Further Invoices? (Y/N)  [Y]");
                String r = upper(term().accept(16, 61, 1, "Y", 0, 6));
                eraseEol(16, 1);
                if (r.equals("Y")) continue main;
                if (r.equals("N")) break main;
            }
        }
        sys.setNum("pass-value", 0);
        salesFile.close(); delivFile.close(); analFile.close(); invFile.close();
        if (stockLink) { stockFile.close(); auditFile.close(); }
    }

    private static int u99(int v) { return Math.abs(v) % 100; }
    private String d9(BigDecimal v) { return Num.edit(v, "z(6)9.99"); }
    private String d8(BigDecimal v) { return Num.edit(v, "z(5)9.99"); }
    private BigDecimal vatRate(int code) { return sys.num("vat-rate", code); }
    private boolean level1() { return sys.intv("invoicer") == 1; }
    private static String money(BigDecimal v, int digits) {
        BigDecimal a = v.abs();
        return z(a.longValue(), digits) + "." + z(a.remainder(BigDecimal.ONE).movePointRight(2).longValue(), 2);
    }
    private void lineBytes(int from, int to) {
        System.arraycopy(bodies.bytes(), (from - 1) * lineSize, bodies.bytes(), (to - 1) * lineSize, lineSize);
    }

    private void runningTotals() {
        BigDecimal n = BigDecimal.ZERO, v = BigDecimal.ZERO;
        for (k = 1; k <= i; k++) {
            if (bodies.str("sil-type", k).equals("D")) continue;
            n = n.add(bodies.num("sil-net", k)); v = v.add(bodies.num("sil-vat", k));
        }
        sih.setNum("sih-net", n); sih.setNum("sih-vat", v);
        if (level1()) {
            show(12, 37, d9(sih.num("sih-net")));
            show(12, 55, d9(sih.num("sih-vat")));
            show(12, 68, d9(sih.num("sih-net").add(sih.num("sih-vat"))));
        } else show(12, 70, d9(sih.num("sih-net").add(sih.num("sih-vat"))));
    }

    private void writeError(String msg) {
        display(L23, 1, msg, 4); eraseEol(L23, 37);
        show(L23, 36, invFile.status); show(L23, 39, fileStatMsg(invFile.status)); show(L23, 64, inv.str("invoice-key"));
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
        Arrays.fill(b, (byte) ' ');
        System.arraycopy(bodies.bytes(), (j - 1) * lineSize, b, 0, lineSize);
        invFile.rewrite(inv);
        if (invalidKey(invFile)) invFile.write(inv);
        if (!invFile.status.equals("00")) writeError(SL180);
    }

    private void readDetails() {
        j = 0;
        for (int n = sih.intv("sih-lines"); n > 0; n--) {
            j++;
            inv.setNum("invoice-nos", sih.longv("sih-invoice")); inv.setNum("item-nos", j); inv.set("invoice-let", sih.str("sih-letter"));
            invFile.read(inv);
            System.arraycopy(inv.bytes(), 0, bodies.bytes(), (j - 1) * lineSize, lineSize);
        }
    }

    private boolean readStock(String key) {
        if (key.substring(7).isBlank()) { stock.set("stock-abrev-key", key.substring(0, 7)); stockFile.readAlt(stock, 0); }
        else { stock.set("stock-key", key); stockFile.read(stock); }
        return !invalidKey(stockFile);
    }

    private void stockTail() {
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

    private void auditTail() {
        if (!auditUsed) return;
        sys.setNum("stk-activity-rep-run", 0);
        auditFile.write(audit);
        if (!auditFile.status.equals("00")) {
            display(L23, 1, SL190, 4); show(L23, 38, auditFile.status, 2); show(L23, 41, fileStatMsg(auditFile.status));
            display(LINES, 1, SL006);
            accept(LINES, 45, 1);
        }
    }

    private void auditHead(String key, String desc, boolean cn) {
        audit.setNum("audit-type", 3);
        audit.setNum("audit-invoice-po", sih.longv("sih-invoice"));
        audit.set("audit-process-date", wsDate);
        audit.set("audit-stock-key", key);
        audit.set("audit-desc", desc);
    }

    private void auditReverse(boolean cn) {
        if (cn) {
            if (audit.intv("audit-reverse-transaction") == 0) {
                audit.setNum("audit-reverse-transaction", 1); audit.setNum("audit-type", 5);
                audit.setNum("audit-cr-for-invoice", sih.longv("sih-cr"));
            } else audit.setNum("audit-reverse-transaction", 0);
        }
        audit.setNum("audit-no", sys.longv("stk-audit-no"));
    }

    private void updateStockAndAudit() {
        if (!stockLink || (citA == 0 && citD == 0)) return;
        audit.initialize();
        boolean cn = j >= 1 && j <= 40 && bodies.str("sil-type", j).equals("3");
        for (int t = 1; t <= citA; t++) {
            auditHead(citAKey[t], citADesc[t], cn);
            long q = citAQty[t];
            if (q > 0) { audit.setNum("audit-transaction-qty", q); audit.setNum("audit-reverse-transaction", 1); }
            else if (q < 0) audit.setNum("audit-transaction-qty", -q);
            auditReverse(cn);
            if (!readStock(citAKey[t])) { stock.setNum("stock-cost", 0); stock.set("stock-key", " "); }
            if (!stock.str("stock-key").isBlank()) {
                BigDecimal tq = audit.num("audit-transaction-qty"), cost = stock.num("stock-cost"), bq = BigDecimal.valueOf(q);
                boolean plus = cn ? q < 0 : q > 0;
                if (q != 0) {
                    if (plus) { stock.add("stock-held", bq); audit.setNum("audit-stock-value-change", tq.multiply(cost)); }
                    else { stock.sub("stock-held", bq); audit.setNum("audit-stock-value-change", tq.multiply(cost).negate()); }
                }
                stockTail();
            }
            auditTail();
        }
        for (int t = 1; t <= citD; t++) {
            auditHead(citDKey[t], citDDesc[t], cn);
            long q = citDQty[t];
            if (q > 0) audit.setNum("audit-transaction-qty", q);
            auditReverse(cn);
            if (!readStock(citDKey[t])) { stock.setNum("stock-cost", 0); stock.set("stock-key", " "); }
            if (!stock.str("stock-key").isBlank()) {
                BigDecimal tq = audit.num("audit-transaction-qty"), cost = stock.num("stock-cost"), bq = BigDecimal.valueOf(q);
                if (!cn) { stock.add("stock-held", bq); audit.setNum("audit-stock-value-change", tq.multiply(cost)); }
                else { stock.sub("stock-held", bq); audit.setNum("audit-stock-value-change", tq.multiply(cost).negate()); }
                stockTail();
            }
            auditTail();
        }
    }

    private void outline1() {
        i = u99(i + 1);
        eraseEol(lin, 1);
        show(lin, 1, "(", 2); show(lin, 2, z(i, 2), 2); show(lin, 4, ") [  ]", 2);
        show(lin, 36, "[          ] [ ]   {         } (", 2); show(lin, 78, ")", 2);
    }

    private void outline2() {
        i = u99(i + 1);
        eraseEol(lin, 1);
        if (sys.str("sl-stock-link").equals("N")) { show(lin, 1, "[             ][  ][", 2); show(lin, 51, "][     ][          ][     ][ ]", 2); }
        else { show(lin, 1, "[             ][", 2); show(lin, 49, "]  [     ][          ][     ][ ]", 2); }
    }

    private void clearDownLine() {
        for (z = i; z <= 39; z++) { lineBytes(z + 1, z); bodies.setNum("sil-line", z, z); }
        z = 0;
        if (i <= sih.intv("sih-lines")) {
            inv.setNum("invoice-nos", sih.longv("sih-invoice")); inv.set("invoice-let", sih.str("sih-letter"));
            inv.setNum("item-nos", sih.longv("sih-lines"));
            invFile.delete(inv);
            sih.setNum("sih-lines", sih.longv("sih-lines") - 1);
        }
    }

    // ---- level 1 ----
    private void invLevel1() {
        display(11, 1, DASH);
        display(12, 1, "Level 1");
        display(12, 16, "Line - ");
        display(12, 36, "<          >"); display(12, 54, "<          >"); display(12, 67, "<          >");
        display(14, 5, "Code");
        display(14, 36, "<---Net---->  Vat   Vat Amount  Gross Amount");
        while (true) {
            for (lin = 16; lin < L23; lin++) outline1();
            i = u99(i - ACCEPT_BODY);
            j = 1;
            show(12, 23, z(i, 2), 2);
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
                String pa = bodies.str("sil-pa", i);
                show(lin, 7, pa);
                pa = acceptUpdate(lin, 7, 2, pa);
                if (pa.isBlank()) return;
                if (crtStatus() == ESC) return;
                if (pa.equals("<<")) {
                    if (i == 1) continue;
                    lin--;
                    if (lin > 15) { i--; j--; continue; }
                    i = u99(i - ACCEPT_BODY);
                    continue data;
                }
                if (pa.equals("**")) { clearDownLine(); i = u99(i - 1); outline1(); continue; }
                bodies.set("sil-pa", pa, i); anal.set("pa-group", pa);
                anal.set("pa-system", "S");
                analFile.read(anal);
                if (invalidKey(analFile)) { display(L23, 1, SL186, 4); continue; }
                eraseEol(L23, 1);
                show(lin, 11, anal.str("pa-desc"));
                bodies.set("sil-description", anal.str("pa-desc"), i);
                BigDecimal a7 = acceptMoney(lin, 37, 7, bodies.num("sil-net", i));
                if (a7.signum() == 0) continue;
                bodies.setNum("sil-net", a7, i); wsNet = a7;
                do {
                    vatCode = bodies.intv("sil-vat-code", i);
                    show(lin, 50, z(vatCode, 1));
                    vatCode = intOf(acceptUpdate(lin, 50, 1, z(vatCode, 1), NUMERIC));
                } while (vatCode > 3);
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
            for (lin = 16; lin < L23; lin++) outline2();
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

    private enum S { DATA, PRODUCT, PRODTEST, CODE, DESC, QTY, UNIT, RECOMP, JUMP }

    private void stockMsg(String msg, int fg) { stock.set("stock-desc", msg); show(lin, 17, stock.str("stock-desc"), fg); }
    private int held() { return (int) (Math.abs(stock.longv("stock-held")) % 100000); }

    private void showStockPick(boolean wait) {
        bodies.set("sil-product", stock.str("stock-abrev-key"), i);
        wsProduct = pad(stock.str("stock-abrev-key"), 13);
        show(lin, 17, stock.str("stock-desc"));
        wsQty = held();
        show(lin, 53, z(wsQty, 5));
        if (wait) accept(24, 10, 1);
        show(lin, 60, money(stock.num("stock-retail"), 7));
    }

    private void getData2() {
        S s = S.DATA;
        boolean comment = false;
        int col = 53;
        while (true) {
            switch (s) {
                case DATA -> {
                    lin = j + 15;
                    if (lin > L23 - 1) { i = u99(i - 1); newScreen = 1; return; }
                    newScreen = 0;
                    s = S.PRODUCT;
                }
                case PRODUCT -> {
                    wsProduct = bodies.str("sil-product", i);
                    show(lin, 2, wsProduct);
                    wsProduct = acceptUpdate(lin, 2, 13, wsProduct);
                    int key = crtStatus();
                    if (wsProduct.isBlank()) return;
                    if (key == ESC) return;
                    wsProduct = upper(wsProduct);
                    comment = wsProduct.startsWith("/");
                    citA++;
                    if (wsProduct.equals(bodies.str("sil-product", i))) {
                        if (sys.str("sl-stock-link").equals("N")) { citA--; s = S.CODE; break; }
                        citNewProduct = 0;
                        citAKey[citA] = wsProduct; citADesc[citA] = bodies.str("sil-description", i); citAQty[citA] = bodies.longv("sil-qty", i);
                        s = S.QTY;
                        break;
                    }
                    if (comment) {
                        bodies.set("sil-product", wsProduct, i);
                        bodies.setNum("sil-net", 0, i); bodies.setNum("sil-qty", 0, i); bodies.setNum("sil-vat", 0, i);
                        s = S.DESC;
                        break;
                    }
                    if (wsProduct.equals("<<           ")) { lin--; s = S.PRODTEST; break; }
                    if (stockLink) {
                        citAKey[citA] = bodies.str("sil-product", i); citADesc[citA] = bodies.str("sil-description", i);
                        citAQty[citA] = bodies.longv("sil-qty", i);
                        citD++;
                        citNewProduct = 1;
                        citDKey[citD] = wsProduct;
                    }
                    bodies.set("sil-product", wsProduct, i);
                    if (wsProduct.startsWith("**")) { citD--; citNewProduct = 0; s = S.CODE; break; }
                    if (sys.str("sl-stock-link").equals("N")) { s = S.CODE; break; }
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
                    String pa = stock.str("stock-sa-group");
                    anal.set("pa-group", pa); bodies.set("sil-pa", pa, i);
                    show(lin, 17, stock.str("stock-desc"));
                    bodies.set("sil-description", stock.str("stock-desc"), i);
                    citDDesc[citD] = stock.str("stock-desc");
                    wsUnit = Num.truncated(stock.num("stock-retail"), 2).remainder(BigDecimal.valueOf(1000000));
                    show(lin, 60, money(stock.num("stock-retail"), 7));
                    wsQty = held();
                    s = S.QTY;
                }
                case PRODTEST -> {
                    if (i == 1) { lin++; s = S.PRODUCT; }
                    else if (lin > 15) { i--; j--; s = S.PRODUCT; }
                    else { i = u99(i - ACCEPT_BODY); s = S.DATA; }
                }
                case CODE -> {
                    if (bodies.str("sil-product", i).startsWith("**")) { clearDownLine(); i = u99(i - 1); outline2(); s = S.PRODUCT; break; }
                    String pa = bodies.str("sil-pa", i);
                    show(lin, 17, pa);
                    pa = acceptUpdate(lin, 17, 2, pa);
                    if (pa.isBlank()) { s = S.PRODUCT; break; }
                    anal.set("pa-system", "S");
                    anal.set("pa-group", pa); bodies.set("sil-pa", pa, i);
                    analFile.read(anal);
                    if (invalidKey(analFile)) { display(lin, 21, SL186, 4); break; }
                    s = S.DESC;
                }
                case DESC -> {
                    int c = stockLink ? 17 : 21;
                    String d = bodies.str("sil-description", i);
                    show(lin, c, d);
                    d = acceptUpdate(lin, c, 32, d);
                    escapeCode = d.isBlank() ? "B" : " ";
                    if (escapeCode.equals("B")) { s = comment ? S.PRODUCT : S.CODE; break; }
                    bodies.set("sil-description", d, i);
                    s = comment ? S.JUMP : S.QTY;
                }
                case QTY -> {
                    col = 53;
                    wsQty = (int) (Math.abs(bodies.longv("sil-qty", i)) % 100000);
                    show(lin, 53, z(wsQty, 5));
                    wsQty = intOf(acceptUpdate(lin, 53, 5, z(wsQty, 5), NUMERIC));
                    if (wsQty == 0) { s = stockLink ? S.RECOMP : S.DESC; break; }
                    if (stockLink) {
                        if (wsQty > stock.longv("stock-held")) { wsQty = held(); break; }
                        if (citNewProduct == 1) { citDQty[citD] = wsQty; s = S.RECOMP; break; }
                        if (wsQty == bodies.longv("sil-qty", i)) {
                            citAKey[citA] = " ".repeat(13); citADesc[citA] = " ".repeat(32); citAQty[citA] = 0;
                            citA--;
                            s = S.RECOMP;
                            break;
                        }
                        citAQty[citA] = bodies.longv("sil-qty", i) - wsQty;
                    }
                    s = S.UNIT;
                }
                case UNIT -> {
                    col = 60;
                    BigDecimal a6 = acceptMoney(lin, 60, 6, bodies.num("sil-unit", i));
                    if (a6.signum() == 0) { s = S.QTY; break; }
                    wsUnit = a6;
                    s = S.RECOMP;
                }
                case RECOMP -> {
                    // レガシーは SizEr 表示文の直後にピリオドがあり、乗算後は常に get-qty へ戻る（get-disc 以降は到達しない）。
                    BigDecimal n = wsUnit.multiply(BigDecimal.valueOf(wsQty));
                    if (n.compareTo(new BigDecimal("9999999.99")) > 0) display(lin, col, "SizEr", 4);
                    else wsNet = n;
                    s = S.QTY;
                }
                case JUMP -> { j++; i++; s = S.DATA; }
            }
        }
    }

    // ---- totals ----
    private void endTotals() {
        while (true) {
            totalScreen();
            eraseEos(15, 1);
            display(16, 60, "*********************");
            show(17, 60, "*", 2); show(18, 60, "*", 2); show(18, 80, "*", 2); show(19, 60, "*", 2); show(19, 80, "*", 2);
            display(20, 60, "*********************");
            display(17, 61, "Invoice Ok To Store?");
            display(19, 67, "(Y/N)  [Y]");
            String r;
            do { r = upper(term().accept(19, 75, 1, "Y", 0, 6)); } while (!r.equals("N") && !r.equals("Y"));
            if (r.equals("Y")) break;
        }
        sih.set("sih-status", "P"); sih.set("sih-status-p", " ");
        i = u99(i - 1);
        sih.setNum("sih-lines", i);
        move(sih, inv);
        invFile.rewrite(inv);
        if (!invFile.status.equals("00")) writeError(SL192);
        j = 0;
        for (int n = i; n > 0; n--) writeDetails();
        updateStockAndAudit();
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
        BigDecimal car = acceptMoney(16, 26, 7, sih.num("sih-carriage"));
        sih.setNum("sih-carriage", car);
        BigDecimal cv = acceptMoney(16, 41, 6, car.multiply(vat1).divide(HUNDRED, 2, RoundingMode.HALF_UP));
        sih.setNum("sih-c-vat", cv);
        show(16, 55, d9(car.add(cv)));
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
        clearScreen();
        show(1, 1, PROG_NAME);
        display(1, 32, "Invoicing Data Amend");
        wsDate = fromUk(toDay());
        show(1, 71, wsDate, 2);
        display(4, 41, "****************************************");
        display(5, 41, "*Date   [  /  /    ]*                  *");
        display(6, 41, "*A/C Nos   [       ]*Ref   [          ]*");
        display(7, 41, "*Invoice [         ]*Order [          ]*");
        display(8, 41, "****************************************");
        display(9, 11, "F8 = Only Show delivery details on 'A/C nos' entry");
        display(10, 1, "Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note; <4> = Pro-Forma");
        boolean ownNos = sys.str("sl-own-nos").equals("Y");
        while (true) {
            sih.setNum("sih-invoice", 0);
            show(7, 51, "00000000");
            if (!ownNos) display(7, 59, "] ");
            long n = intOf(acceptUpdate(7, 51, 8, "00000000", NUMERIC));
            sih.setNum("sih-invoice", n);
            if (n == 0 || crtStatus() == ESC) { z = 1; return; }
            inv.set("invoice-let", " "); sih.set("sih-letter", " ");
            inv.setNum("item-nos", 0);
            inv.setNum("invoice-nos", n);
            if (ownNos) {
                sih.set("sih-letter", term().accept(7, 59, 1, " ", 0, 6));
                inv.set("invoice-let", sih.str("sih-letter"));
            }
            invFile.read(inv);
            if (invalidKey(invFile)) { display(16, 40, SL194, 4); continue; }
            move(inv, sih);
            eraseEol(16, 40);
            if (sih.str("sih-status").equals("z")) { eraseEol(16, 1); display(16, 1, SL195, 4); continue; }
            eraseEol(16, 1);
            wsDate = binToDate(sih.longv("sih-date"));
            readDetails();
            break;
        }
        while (true) {
            show(5, 50, wsDate);
            wsDate = acceptUpdate(5, 50, 10, wsDate);
            if (crtStatus() == ESC || wsDate.isBlank()) { z = 1; return; }
            long bin = validateDate(wsDate);
            if (bin == 0) continue;
            sih.setNum("sih-date", bin);
            break;
        }
        boolean showDelivery;
        while (true) {
            show(6, 53, sih.str("sih-customer"));
            String cust = upper(acceptUpdate(6, 53, 7, sih.str("sih-customer")));
            sih.set("sih-customer", cust);
            if (crtStatus() == ESC || cust.isBlank()) { escapeCode = "Q"; return; }
            showDelivery = crtStatus() == 1008;
            sales.set("sales-key", cust);
            salesFile.read(sales);
            if (!invalidKey(salesFile)) break;
        }
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
        z = p;  // レガシーは z を UNSTRING の POINTER に流用する
        show(6, 69, sih.str("sih-ref"));
        sih.set("sih-ref", acceptUpdate(6, 69, 10, sih.str("sih-ref")));
        show(7, 69, sih.str("sih-order"));
        sih.set("sih-order", acceptUpdate(7, 69, 10, sih.str("sih-order")));
        int type;
        while (true) {
            show(10, 7, sih.str("sih-type"));
            type = intOf(acceptUpdate(10, 7, 1, sih.str("sih-type"), NUMERIC));
            sih.setNum("sih-type", type);
            if (type == 0) return;
            if (type > 4) continue;
            if (type == 3) { crNote(); if (escapeCode.equals("Q")) continue; }
            break;
        }
        z = 0;
        if (type > 2) return;
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
        z = intOf(acceptUpdate(22, 80, 2, "00", NUMERIC));
        if (crtStatus() == ESC) { z = 1; term().crtStatus = 1; }
    }

    private void crNote() {
        boolean ownNos = sys.str("sl-own-nos").equals("Y");
        boolean clear = true;
        while (true) {
            if (clear) for (int l = 10; l <= 14; l++) eraseEol(l, 1);
            clear = false;
            display(10, 1, "Invoice To Credit - [         ]");
            if (!ownNos) display(10, 30, "] ");
            String cur = z(sih.longv("sih-cr"), 8);
            show(10, 22, cur);
            long cr = intOf(acceptUpdate(10, 22, 8, cur, NUMERIC));
            sih.setNum("sih-cr", cr);
            if (cr == 0) { wsNamed = "Z"; break; }
            wsNamed = " ";
            if (cr == 99999999) { escapeCode = "Q"; return; }
            escapeCode = " ";
            inv.setNum("invoice-nos", cr); inv.setNum("item-nos", 0); inv.set("invoice-let", " ");
            if (ownNos) inv.set("invoice-let", acceptUpdate(10, 30, 1, " "));
            invFile.read(inv);
            if (invalidKey(invFile)) {
                display(11, 32, SL193, 4);
                String r;
                do {
                    display(12, 1, "Do You Wish To Use This Invoice No.? {N}");
                    display(13, 1, "..If So, You must ensure that it Belongs to the same Customer and that it is a ");
                    display(14, 1, "Invoice ie, not a Receipt");
                    r = upper(term().accept(12, 39, 1, "N", 0, 6));
                } while (!r.equals("Y") && !r.equals("N"));
                if (r.equals("Y")) break;
                clear = true;
                continue;
            }
            eraseEol(11, 1);
            if (inv.intv("invoice-type") != 2) { display(11, 1, SL184, 4); continue; }
            if (!inv.str("invoice-customer").equals(sales.str("sales-key"))) { display(11, 1, SL196, 4); continue; }
            break;
        }
        for (int l = 11; l <= 14; l++) eraseEol(l, 1);
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
        invFile.open(CobFile.Mode.IO);
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
