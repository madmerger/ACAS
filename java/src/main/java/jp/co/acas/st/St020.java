package jp.co.acas.st;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;

/** st020.cbl: 在庫移動（入庫・出庫・バーコード入庫・発注入力・期末監査帳票）。 */
public class St020 extends StProgram {
    static final String PROG_NAME = "ST020 (3.01.29)";
    static final BigDecimal MAX_VALUE = new BigDecimal("99999999.99");
    private static final BigDecimal E8 = BigDecimal.valueOf(100_000_000L);

    private Rec sys, stock, audit;
    private CobFile stockFile, auditFile;
    private St.Printer print;
    private int menuReply, i, lineCnt = 99, pageNos;
    private String wsDate = "", wsProcDate = "", toDay = "";
    private int procMth;
    private BigDecimal newCost = BigDecimal.ZERO, addTotal = BigDecimal.ZERO, dedTotal = BigDecimal.ZERO;
    private String l1Title = "Stock Addition Report", l2Batch = "", l3ProcLit = "Proc. Date", l3PriceLit = "Price",
            l3StockLit = "    Stock Value    ", l3DatesLit = "Order Date    Date Due     Order Status";
    private static final int L23 = 23, L22 = 22;
    private String amt6 = "000000.00";

    // ---------- 再利用可能な計算（CALC の drvavg 相当） ----------

    /** compute ws-Old-Value = (Stock-Held + Stock-Work-in-Progress) * Stock-Cost（s9(8)v99、切捨て）。 */
    public static BigDecimal oldValue(long held, long wip, BigDecimal cost) {
        if (held == 0 && wip == 0) return BigDecimal.ZERO;
        return fit8(cost.multiply(BigDecimal.valueOf(held + wip)));
    }
    /** multiply ws-Qty by ws-Price giving ws-Value（s9(8)v99）。 */
    public static BigDecimal movementValue(long qty, BigDecimal price) { return fit8(price.multiply(BigDecimal.valueOf(qty))); }
    /** add ws-Value ws-Old-Value giving ws-New-Value on size error → 99999999.99。 */
    public static BigDecimal newValue(BigDecimal value, BigDecimal oldValue) {
        BigDecimal v = value.add(oldValue);
        return v.abs().compareTo(MAX_VALUE) > 0 ? MAX_VALUE : v;
    }
    /**
     * 平均原価: divide ws-New-Qty into ws-New-Value giving ws-New-Cost rounded（s9(6)v9999）。
     * 数量 0 は除算不能のため直前値（previous）を保持する。
     */
    public static BigDecimal averageCost(BigDecimal newValue, long newQty, BigDecimal previous) {
        if (newQty == 0) return previous;
        return newValue.setScale(2, RoundingMode.DOWN).divide(BigDecimal.valueOf(newQty), 4, RoundingMode.HALF_UP)
                .remainder(BigDecimal.valueOf(1_000_000));
    }
    private static BigDecimal fit8(BigDecimal v) { return v.setScale(2, RoundingMode.DOWN).remainder(E8); }

    // ---------- 手続き部 ----------

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        sys = SystemFile.shared(ctx);
        toDay = St.x((String) ctx.shared.getOrDefault("to-day", ""), 10);
        if (sys.intv("file-status", 11) != 1) {
            display(L23, 1, "ST219 Stock File not yet created", 4);
            maps99(45);
            return;
        }
        stock = St.fdRec(Layout.of("copybooks/fdstock.cob", "Stock-Record"));
        audit = St.fdRec(Layout.of("copybooks/fdaudit.cob", "Stock-Audit-Record"));
        stockFile = St.stockFile(ctx, stock);
        stockFile.open(CobFile.Mode.IO);
        if (!stockFile.status.equals("00")) {
            stockFile.close();
            display(L23, 1, "ST201 Stock File not found", 4);
            show(L23, 28, stockFile.status, 2);
            maps99(45);
            return;
        }
        auditFile = CobFile.sequential(ctx.store, ctx.path("staudit.dat"));
        menuReply = 0;
        convertToday();
        wsProcDate = wsDate;
        String cur = sys.str("stk-period-cur");
        String period = cur.equals("Q") ? "Quarter" : cur.equals("W") ? "Week" : "Month";
        String auditLit = "(5)  End of " + period + " Audit Reports";
        while (true) {
            displayHeadings();
            // aa020-DH-End
            String pm = wsDate.substring(3, 5);
            if (!pm.matches("\\d\\d") || Integer.parseInt(pm) < 1 || Integer.parseInt(pm) > 12) {
                display(L23, 1, "ST213 Bad month in date", 4);
                show(L23, 25, pm, 2);
                show(L23, 28, wsDate, 2);
                maps99(45);
                return;
            }
            procMth = Integer.parseInt(pm);
            // aa100-Main-Menu
            display(4, 1, "Select one of the following by number :- [ ]");
            display(6, 4, "(1)  Stock Additions Entry");
            display(7, 4, "(2)  Stock Deductons Entry");
            display(8, 4, "(3)  Stock Additions from Barcode Readers");
            display(9, 4, "(4)  Stock Order Entry");
            boolean auditUsed = sys.intv("stk-audit-used") == 1;
            if (auditUsed) display(11, 4, auditLit);
            display(14, 4, "(9)  Return to System Menu");
            while (true) {
                String r = acceptUpdate(4, 43, 1, String.valueOf(menuReply), AUTO);
                menuReply = (int) St.digits(r);
                if (menuReply == 9) { stockFile.close(); return; }
                if (menuReply == 0 || menuReply > 5) continue;
                break;
            }
            String fs = "00";
            if (sys.intv("file-status", 10) != 1 && auditUsed) {
                auditFile.open(CobFile.Mode.OUTPUT);
                auditFile.close();
                sys.setNum("file-status", 1, 10);
            }
            if (auditUsed) fs = auditFile.open(menuReply < 5 ? CobFile.Mode.EXTEND : CobFile.Mode.INPUT, true);
            if (fs.charAt(0) != '0') {
                display(L23, 1, "ST202 Audit File not found", 4);
                show(L23, 28, fs, 2);
                maps99(45);
                stockFile.close();
                return;
            }
            switch (menuReply) {
                case 1 -> {
                    l1Title = "Stock Addition Report"; l3DatesLit = "Order Date    Date Due     Order Status";
                    l3ProcLit = "Proc. Date"; l3PriceLit = "Price"; l3StockLit = "    Stock Value    "; l2Batch = "";
                    print = new St.Printer(ctx, "prt-1");
                    additions(false);
                    closeAndSpool();
                }
                case 2 -> {
                    l1Title = "Stock Deduction Report"; l3DatesLit = ""; l3PriceLit = ""; l2Batch = "";
                    l3ProcLit = "Proc. Date"; l3StockLit = "    Stock Value    ";
                    print = new St.Printer(ctx, "prt-1");
                    deductions();
                    closeAndSpool();
                }
                case 3 -> {
                    l2Batch = "";
                    print = new St.Printer(ctx, "prt-1");
                    additions(true);
                    closeAndSpool();
                }
                case 4 -> {
                    l1Title = "Stock Orders Update"; l3DatesLit = "Order Date    Date Due"; l3PriceLit = "B'Qty";
                    l3StockLit = ""; l3ProcLit = ""; l2Batch = "";
                    print = new St.Printer(ctx, "prt-1");
                    orders();
                    closeAndSpool();
                }
                case 5 -> {
                    if (auditUsed) {
                        l2Batch = "Batch " + Num.edit(sys.intv("stk-audit-no"), "zz9");
                        endOfMonth();
                    }
                }
                default -> { }
            }
            if (auditUsed) auditFile.close();
            menuReply = 0;
        }
    }

    private void closeAndSpool() {
        print.close();
        if (pageNos != 0) ctx.spool("prt-1", St.printCommand(sys.str("print-spool-name")));
    }

    private void convertToday() { wsDate = St.fromUk(toDay, dateForm()); }
    private int dateForm() {
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        return sys.intv("date-form");
    }
    /** zz060-Convert-Date: 通算日 → 設定形式の日付（0 は空白）。 */
    private String convertBin(long bin) {
        if (bin == 0) return St.x("", 10);
        return St.fromUk(Maps04.toDate(bin), dateForm());
    }
    /** zz050-Validate-Date: 設定形式の日付 → 通算日（不正は 0）。 */
    private long validateDate(String d) { return Maps04.toBin(St.toUk(d, dateForm())); }

    /** aa010-Display-Headings。 */
    private void displayHeadings() {
        pageNos = 0; lineCnt = 99;
        String title; int col;
        switch (menuReply) {
            case 1 -> { title = "Stock Additions Entry"; col = 30; }
            case 2 -> { title = "Stock Deductions Entry"; col = 30; }
            case 3 -> { title = "Stock Barcode Additions Entry"; col = 23; }
            case 4 -> { title = "Stock End of Month Processing"; col = 26; }
            case 5 -> { title = "Stock Order Entry"; col = 32; }
            default -> { title = "Stock Movements Menu"; col = 31; }
        }
        eraseEos(1, 1);
        display(1, 1, PROG_NAME);
        display(1, col, title);
        convertToday();
        show(1, 71, wsDate, 2);
    }

    private void err(String msg) { display(L23, 1, msg, 4); }
    private boolean backKey() { int s = crtStatus(); return s == 2005 || s == 2003 || s == 2001; }

    /** 品目キーの読込み。barcode=true は主キーのみ。見つからなければ false。 */
    private boolean readStock(String key, boolean barcode) {
        if (!barcode && key.substring(7).isBlank()) {
            stock.set("stock-abrev-key", key.substring(0, 7));
            if (!stockFile.readAlt(stock, 0).equals("00")) { err("ST203 Abbreviated Stock number not present"); return false; }
        } else {
            stock.set("stock-key", key);
            if (!stockFile.read(stock).equals("00")) { err("ST214 Stock Number not found"); return false; }
        }
        return true;
    }

    private void drawAdditionLines() {
        display(3, 1, " Stock Number    Description         Quantity    Price   Stk Qty   Stk Value");
        for (int lin = 5; lin <= L22; lin++) {
            eraseEol(lin, 1);
            display(lin, 1, "[             ]");
            display(lin, 16, "{                    }");
            display(lin, 38, "[       ]");
            display(lin, 47, "[         ]");
            display(lin, 58, "{      }");
            display(lin, 67, "[           ]");
        }
    }

    /** ba000-Process-Manual-Additions / da000-Process-Barcode-Additions。 */
    private void additions(boolean barcode) {
        displayHeadings();
        drawAdditionLines();
        i = 4;
        boolean auditUsed = sys.intv("stk-audit-used") == 1;
        boolean averaging = sys.intv("stk-averaging") == 1;
        data1:
        while (true) {
            i++;
            if (i > L22) {
                displayHeadings();
                drawAdditionLines();
                i = 5;
            }
            St.initialize(audit);
            String key = upper(acceptUpdate(i, 2, 13, St.x("", 13)));
            if (key.isBlank() || crtStatus() == 2005) return;
            show(i, 2, key);
            if (!readStock(key, barcode)) {
                if (barcode) show(i, 2, "Missing Stock Record"); else i--;
                continue;
            }
            show(i, 17, stock.str("stock-desc").substring(0, 20));
            if (stock.str("stock-services-flag").equals("Y")) {
                display(L23, 1, "ST217 Services only Product");
                show(i, 17, St.x("", 20), 7);
                if (!barcode) i--;
                continue;
            }
            eraseEol(L23, 1);
            long unit6, qty = 0; String sign6;
            BigDecimal price;
            boolean askQty = !barcode;
            if (barcode) {
                qty = 1;
                BigDecimal p = stock.num("stock-last-actual-cost").signum() != 0 ? stock.num("stock-last-actual-cost") : stock.num("stock-cost");
                p = p.setScale(2, RoundingMode.DOWN).remainder(BigDecimal.valueOf(1_000_000));
                amt6 = money(p, 6);
                show(i, 39, "000001 ");
            }
            while (true) {
                if (askQty) {
                    // ba020-Accept-Qty
                    String q = acceptUpdate(i, 39, 7, Num.z9(Math.abs(stock.longv("stock-on-order")), 6) + " ");
                    unit6 = St.digits(q.substring(0, 6)); sign6 = q.substring(6);
                    if (unit6 == 0 || backKey()) {
                        i--;
                        show(i + 1, 17, St.x("", 20), 7);
                        continue data1;
                    }
                    if (unit6 > 999998) { err("ST204 Quantity cannot equal or exceed 999,999"); continue; }
                    if (unit6 + stock.longv("stock-held") > 999999) { err("ST205 Quantity in Stock cannot exceed 999,999"); continue; }
                    if (!sign6.equals("-") && !sign6.equals(" ")) { err("ST207 Quantity can only end with space or -"); continue; }
                    eraseEol(L23, 1);
                    qty = unit6;
                    if (sign6.equals("-")) { audit.setNum("audit-reverse-transaction", 1); qty = -qty; }
                    if (qty + stock.longv("stock-held") < 0) { err("ST206 Quantity in Stock cannot be less than zero"); continue; }
                    if (qty + stock.longv("stock-held") == 0) { err("ST208 CAUTION: Stock quantity will be zero"); maps99(15); }
                }
                // ba030-Accept-Price
                if (barcode) {
                    show(i, 48, amt6);
                } else {
                    amt6 = "000000.00";
                    show(i, 48, amt6);
                    amt6 = acceptUpdate(i, 48, 9, amt6);
                }
                price = amount(amt6, 6);
                if (!barcode && price.signum() == 0) { askQty = true; continue; }
                break;
            }
            if (auditUsed) {
                audit.setNum("audit-type", 1);
                audit.set("audit-stock-key", stock.str("stock-key"));
                audit.set("audit-desc", stock.str("stock-desc"));
                audit.setNum("audit-transaction-qty", qty);
                audit.setNum("audit-unit-cost", price);
            }
            stock.setNum("stock-last-actual-cost", price);
            BigDecimal oldValue = oldValue(stock.longv("stock-held"), stock.longv("stock-work-in-progress"), stock.num("stock-cost"));
            BigDecimal value = movementValue(qty, price);
            if (auditUsed) audit.setNum("audit-stock-value-change", value);
            BigDecimal nv = value.add(oldValue);
            if (nv.abs().compareTo(MAX_VALUE) > 0) { err("ST212 Stock Value set to Maximum. (99,999,999.99)"); nv = MAX_VALUE; }
            long newQty = (qty + stock.longv("stock-held")) % 1_000_000;
            show(i, 59, Num.edit(newQty, "z(6)"));
            if (!averaging) {
                String a8 = money(nv.abs(), 8);
                show(i, 68, a8);
                a8 = acceptUpdate(i, 68, 11, a8);
                BigDecimal ok8 = amount(a8, 8);
                if (ok8.signum() != 0) nv = ok8;
            }
            newCost = averageCost(nv, newQty, newCost);
            if (averaging) {
                display(i, 67, "{           }");
                show(i, 68, money(nv.abs(), 8));
            }
            if (auditUsed) {
                audit.setNum("audit-no", sys.intv("stk-audit-no"));
                sys.setNum("stk-activity-rep-run", 0);
                audit.set("audit-process-date", wsProcDate);
                if (!writeAudit()) return;
            }
            if (qty > 0) stock.setNum("stock-on-order", stock.longv("stock-on-order") - qty);
            else stock.setNum("stock-on-order", stock.longv("stock-on-order") + qty);
            if (stock.longv("stock-on-order") != 0) {
                stock.setNum("stock-back-ordered", stock.longv("stock-back-ordered") + stock.longv("stock-on-order"));
                stock.setNum("stock-on-order", 0);
            }
            if (stock.longv("stock-back-ordered") < 0) stock.setNum("stock-back-ordered", 0);
            stock.setNum("stock-adds", stock.longv("stock-adds") + qty);
            stock.setNum("stock-td-adds", stock.longv("stock-td-adds", procMth) + qty, procMth);
            if (stock.longv("stock-adds") < 1) err("ST215 Current Additions at Zero or < 0");
            if (stock.longv("stock-td-adds", procMth) < 1) display(L23, 41, "ST216 To Date Additions at Zero or < 0", 4);
            // ba040-Setup-Print-Transaction
            String dOrd = convertBin(stock.longv("stock-order-date")), dDue = convertBin(stock.longv("stock-order-due"));
            long uBin = Maps04.toBin(toDay);
            if (uBin == 0) { err("ST005 Invalid Date"); show(L23, 20, toDay, 2); }
            String daysLate = "   ", litLate = "";
            long due = stock.longv("stock-order-due");
            if (due != 0) {
                long late = (uBin - due) % 1000;
                if (late != 0) daysLate = Num.edit(late, "zz9");
                if (late > 0) litLate = " Days Late"; else if (late < 0) litLate = " Days Early";
            }
            if (stock.longv("stock-on-order") == 0 && stock.longv("stock-back-ordered") == 0) {
                stock.setNum("stock-order-date", 0); stock.setNum("stock-order-due", 0);
            }
            String line4 = St.x(wsProcDate, 11) + St.x(stock.str("stock-key"), 14) + stock.str("stock-desc")
                    + Num.edit(qty, "z(6)9-") + Num.edit(price, "z(6)9.99-") + Num.edit(value, "z(5),zz9.99-") + "   "
                    + St.x(dOrd, 13) + St.x(dDue, 13) + daysLate + St.x(litLate, 10);
            printLine(line4);
            stock.setNum("stock-value", nv);
            stock.setNum("stock-held", newQty);
            stock.setNum("stock-cost", newCost);
            if (!rewriteStock()) return;
        }
    }

    private boolean writeAudit() {
        String fs = auditFile.write(audit.copyBytes());
        if (fs.charAt(0) == '0') return true;
        display(L23, 1, "ST002 Error on Writing to Audit File", 4);
        show(L23, 38, fs, 2);
        maps99(45);
        return false;
    }
    private boolean rewriteStock() {
        String fs = stockFile.rewrite(stock);
        if (fs.charAt(0) == '0') return true;
        display(L23, 1, "ST000 Error on Writing to Stock File", 4);
        show(L23, 38, fs, 2);
        maps99(45);
        return false;
    }
    private void printLine(String line) {
        if (lineCnt > sys.intv("page-lines")) printHeads();
        print.after(St.x(line, 132), 1);
        lineCnt++;
    }

    /** 金額の画面表記（整数部 n 桁 + "." + 2 桁）。 */
    private static String money(BigDecimal v, int n) {
        BigDecimal a = v.abs().setScale(2, RoundingMode.DOWN);
        return Num.z9(a.longValue() % (long) Math.pow(10, n), n) + "." + Num.z9(a.remainder(BigDecimal.ONE).movePointRight(2).longValue(), 2);
    }
    /** 画面表記の金額を数値へ。 */
    private static BigDecimal amount(String s, int n) {
        s = St.x(s, n + 3);
        return BigDecimal.valueOf(St.digits(s.substring(0, n)) * 100 + St.digits(s.substring(n + 1)), 2);
    }

    private void drawDeductionLines() {
        displayHeadings();
        display(3, 1, " Stock Number    Description         Quantity    Stk Qty");
        for (int lin = 5; lin <= L22; lin++) {
            eraseEol(lin, 1);
            display(lin, 1, "[             ]");
            display(lin, 16, "{                    }");
            display(lin, 38, "[       ]");
            display(lin, 47, "{      }");
        }
    }

    /** ca000-Process-Manual-Deductions。 */
    private void deductions() {
        drawDeductionLines();
        i = 4;
        boolean auditUsed = sys.intv("stk-audit-used") == 1;
        data1:
        while (true) {
            i++;
            if (i > L22) {
                drawDeductionLines();
                i = 5;
            }
            St.initialize(audit);
            String key = upper(acceptUpdate(i, 2, 13, St.x("", 13)));
            if (key.isBlank() || crtStatus() == 2005) return;
            show(i, 2, key);
            if (!readStock(key, false)) { i--; continue; }
            show(i, 17, stock.str("stock-desc").substring(0, 20));
            show(i, 48, Num.edit(stock.longv("stock-work-in-progress") + stock.longv("stock-held"), "z(6)"));
            eraseEol(L23, 1);
            long qty;
            while (true) {
                // ca020-Accept-Qty
                String q = acceptUpdate(i, 39, 7, "000000 ");
                long unit6 = St.digits(q.substring(0, 6)); String sign6 = q.substring(6);
                if (unit6 == 0 || backKey()) {
                    i--;
                    show(i + 1, 17, St.x("", 20), 7);
                    continue data1;
                }
                if (unit6 > 999998) { err("ST204 Quantity cannot equal or exceed 999,999"); continue; }
                if (!sign6.equals("-") && !sign6.equals(" ")) { err("ST207 Quantity can only end with space or -"); continue; }
                eraseEol(L23, 1);
                qty = unit6;
                if (sign6.equals("-")) {
                    audit.setNum("audit-reverse-transaction", 1);
                    qty = -qty;
                    if (unit6 + stock.longv("stock-held") > 999999) { err("ST205 Quantity in Stock cannot exceed 999,999"); continue; }
                }
                if (stock.longv("stock-held") - qty < 0) { err("ST206 Quantity in Stock cannot be less than zero"); continue; }
                eraseEol(L23, 1);
                break;
            }
            if (stock.str("stock-services-flag").equals("Y")) {
                display(L23, 1, "ST217 Services only Product");
                i--;
                continue;
            }
            if (stock.longv("stock-held") - qty == 0) {
                err("ST208 CAUTION: Stock quantity will be zero");
                maps99(15);
                eraseEos(L23, 1);
            }
            long newQty = stock.longv("stock-held") - qty;
            show(i, 48, Num.edit(newQty, "z(6)"));
            audit.setNum("audit-type", 2);
            audit.set("audit-stock-key", stock.str("stock-key"));
            audit.set("audit-desc", stock.str("stock-desc"));
            audit.setNum("audit-transaction-qty", qty);
            audit.setNum("audit-unit-cost", stock.num("stock-cost"));
            audit.setNum("audit-stock-value-change", stock.num("stock-cost").multiply(BigDecimal.valueOf(-qty)));
            audit.setNum("audit-no", sys.intv("stk-audit-no"));
            if (auditUsed) {
                sys.setNum("stk-activity-rep-run", 0);
                audit.set("audit-process-date", wsProcDate);
                if (!writeAudit()) return;
            }
            stock.setNum("stock-deducts", stock.longv("stock-deducts") + qty);
            stock.setNum("stock-td-deds", stock.longv("stock-td-deds", procMth) + qty, procMth);
            if (stock.longv("stock-deducts") < 1) err("ST210 Current Deductions at Zero or < 0");
            if (stock.longv("stock-td-deds", procMth) < 1) display(L23, 41, "ST211 To Date Deductions at Zero or < 0", 4);
            // ca040-Setup-Print-Transaction
            String line4 = St.x(wsProcDate, 11) + St.x(stock.str("stock-key"), 14) + stock.str("stock-desc")
                    + Num.edit(qty, "z(6)9-") + St.x("", 11) + Num.edit(audit.num("audit-stock-value-change"), "z(5),zz9.99-");
            printLine(line4);
            stock.setNum("stock-held", stock.longv("stock-held") - qty);
            BigDecimal sv = stock.num("stock-cost").multiply(BigDecimal.valueOf(stock.longv("stock-held") + stock.longv("stock-work-in-progress")))
                    .setScale(2, RoundingMode.DOWN);
            if (sv.abs().compareTo(new BigDecimal("999999999.99")) > 0) { err("ST212 Stock Value set to Maximum. (99,999,999.99)"); sv = MAX_VALUE; }
            stock.setNum("stock-value", sv);
            if (!rewriteStock()) return;
        }
    }

    private void drawOrderLines() {
        displayHeadings();
        display(3, 1, " Stock Number   Description          Qty Ord Date Ordered  Date Due  Back Qty");
        for (int lin = 5; lin <= L22; lin++) {
            eraseEol(lin, 1);
            display(lin, 1, "[             ]");
            display(lin, 16, "{                    }");
            display(lin, 38, "[      ]");
            display(lin, 46, "[          ]");
            display(lin, 58, "[          ]");
            display(lin, 70, "[      ]");
        }
    }

    /** fa000-Process-Orders。 */
    private void orders() {
        drawOrderLines();
        i = 4;
        data1:
        while (true) {
            i++;
            if (i > L22) {
                drawOrderLines();
                i = 5;
            }
            String key = upper(acceptUpdate(i, 2, 13, St.x("", 13)));
            if (key.isBlank() || crtStatus() == 2005) return;
            show(i, 2, key);
            if (!readStock(key, false)) { i--; continue; }
            show(i, 17, stock.str("stock-desc").substring(0, 20));
            if (stock.str("stock-services-flag").equals("Y")) {
                display(L23, 1, "ST217 Services only Product");
                show(i, 17, St.x("", 20), 7);
                i--;
                continue;
            }
            eraseEol(L23, 1);
            while (true) {
                // fa020-Accept-Qty
                long unit6 = St.digits(acceptUpdate(i, 39, 6, Num.z9(Math.abs(stock.longv("stock-on-order")), 6), NUMERIC));
                if (backKey()) {
                    i--;
                    show(i + 1, 17, St.x("", 20), 7);
                    continue data1;
                }
                if (unit6 > 999998) { err("ST204 Quantity cannot equal or exceed 999,999"); continue; }
                eraseEol(L23, 1);
                stock.setNum("stock-on-order", unit6);
                break;
            }
            String dOrd = convertBin(stock.longv("stock-order-date")), dDue = convertBin(stock.longv("stock-order-due"));
            while (true) {
                dOrd = acceptUpdate(i, 47, 10, dOrd);
                if (dOrd.isBlank()) { stock.setNum("stock-order-date", 0); break; }
                long b = validateDate(dOrd);
                if (b != 0) { stock.setNum("stock-order-date", b); break; }
                err("ST005 Invalid Date"); display(L23, 19, " (Order Date)", 4);
            }
            while (true) {
                dDue = acceptUpdate(i, 59, 10, dDue);
                if (dDue.isBlank()) { stock.setNum("stock-order-due", 0); break; }
                long b = validateDate(dDue);
                if (b != 0) { stock.setNum("stock-order-due", b); break; }
                err("ST005 Invalid Date"); display(L23, 19, " (Due Date)", 4);
            }
            eraseEol(L23, 1);
            while (true) {
                long unit6 = St.digits(acceptUpdate(i, 71, 6, Num.z9(Math.abs(stock.longv("stock-back-ordered")), 6), NUMERIC));
                if (unit6 > 999998) { err("ST204 Quantity cannot equal or exceed 999,999"); continue; }
                eraseEol(L23, 1);
                stock.setNum("stock-back-ordered", unit6);
                break;
            }
            String line4 = St.x("", 11) + St.x(stock.str("stock-key"), 14) + stock.str("stock-desc")
                    + Num.edit(stock.longv("stock-on-order"), "z(6)9-") + "  " + Num.edit(stock.longv("stock-back-ordered"), "z(5)9") + "   "
                    + St.x("", 16) + St.x(convertBin(stock.longv("stock-order-date")), 13) + St.x(convertBin(stock.longv("stock-order-due")), 13);
            printLine(line4);
            if (!rewriteStock()) return;
        }
    }

    /** ea000-Process-End-of-Month。 */
    private void endOfMonth() {
        eraseEos(13, 37);
        display(13, 37, "Printing");
        print = new St.Printer(ctx, "prt-1");
        auditReport(true);
        closeAndSpool();
        print = new St.Printer(ctx, "prt-1");
        auditReport(false);
        closeAndSpool();
        sys.setNum("stk-activity-rep-run", 1);
        while (true) {
            display(4, 1, "Can I Delete the Audit File Now? [ ]");
            display(6, 1, " Making sure that Sales Invoicing and Purchase Ledger are NOT running", 4);
            display(8, 2, "Check that Reports are complete first, before responding", 4);
            String r = upper(acceptUpdate(4, 35, 1, "N"));
            if (r.equals("N")) return;
            if (!r.equals("Y")) continue;
            auditFile.close();
            auditFile.open(CobFile.Mode.OUTPUT);
            int n = sys.intv("stk-audit-no") + 1;
            sys.setNum("stk-audit-no", n > 255 ? 1 : n);
            return;
        }
    }

    /** ea100-Print-Additions / ea200-Print-Deductions。 */
    private void auditReport(boolean additions) {
        auditFile.close();
        auditFile.open(CobFile.Mode.INPUT, true);
        pageNos = 0; lineCnt = 99;
        if (additions) {
            addTotal = BigDecimal.ZERO; dedTotal = BigDecimal.ZERO;
            l1Title = "Additions Stock Audit Report"; l3PriceLit = "Price"; l3DatesLit = "Source/PO.no.";
        } else {
            l1Title = "Deductions Stock Audit Report"; l3DatesLit = "Source/Inv.no.";
        }
        l3ProcLit = "Proc. Date"; l3StockLit = "    Stock Value    ";
        String cost = St.x("", 11);
        while (auditFile.readNext(audit).equals("00")) {
            int type = audit.intv("audit-type");
            boolean ded = type == 2 || type == 3 || type == 5;
            if (additions) {
                if (ded) dedTotal = dedTotal.add(audit.num("audit-stock-value-change"));
                if (type != 1 && type != 4) continue;
                cost = Num.edit(audit.num("audit-unit-cost"), "z(6)9.99-");
                addTotal = addTotal.add(audit.num("audit-stock-value-change"));
            } else if (!ded) continue;
            String source = "";
            if (type == 4) source = "Purchasing/" + audit.str("audit-invoice-po");
            if (type == 3) source = "Invoicing/" + audit.str("audit-invoice-po");
            if (type == 5) source = "Credit note/" + audit.str("audit-invoice-po") + " for " + audit.str("audit-cr-for-invoice");
            String line4 = St.x(audit.str("audit-process-date"), 11) + St.x(audit.str("audit-stock-key"), 14) + audit.str("audit-desc")
                    + Num.edit(audit.num("audit-transaction-qty"), "z(6)9-") + cost
                    + Num.edit(audit.num("audit-stock-value-change"), "z(5),zz9.99-") + "   " + St.x(source, 39);
            printLine(line4);
        }
        // ea120-Totals / ea220-Totals
        if (lineCnt > sys.intv("page-lines") - 7) printHeads();
        String pad = St.x("", 55);
        print.after(St.x(pad + " Total Additions   " + Num.edit(addTotal, "zzz,zzz,zz9.99"), 132), 3);
        String dedLine = pad + " Total Deductions  " + Num.edit(dedTotal, "zzz,zzz,zz9.99");
        print.after(St.x(dedLine, 132), 1);
        print.after(St.x(pad + St.x("", 19) + "-------------- ", 132), 1);
        print.after(St.x(pad + " Total Changes     " + Num.edit(addTotal.add(dedTotal), "zzz,zzz,zz9.99") + " ", 132), 1);
        print.after(St.x(pad + St.x("", 19) + "============== ", 132), 1);
    }

    /** zz010-Print-Heads。 */
    private void printHeads() {
        if (lineCnt <= sys.intv("page-lines")) return;
        pageNos = (pageNos + 1) % 256;
        convertToday();
        LocalDateTime now = ctx.now();
        String line1 = St.x(PROG_NAME, 16) + St.x("", 39) + St.x(l1Title, 42) + St.x("", 27) + "Page " + Num.edit(pageNos, "zz9");
        String line2 = St.x(sys.str("usera"), 61) + St.x(l2Batch, 55) + St.x(wsDate, 10) + " "
                + String.format("%02d:%02d", now.getHour(), now.getMinute());
        if (pageNos != 1) {
            print.afterPage(line1);
            print.after(line2, 1);
            print.after(St.x("", 132), 1);
        } else {
            print.before(line1, 1);
            print.before(line2, 1);
        }
        lineCnt = 6;
        if (menuReply != 5) print.after(St.x(St.x("", 78) + "Change in", 132), 1);
        else lineCnt--;
        print.after(St.x(St.x(l3ProcLit, 11) + "Stock Number  Description                         Qty    "
                + St.x(l3PriceLit, 5) + St.x(l3StockLit, 19) + St.x(l3DatesLit, 39), 132), 1);
        print.after(St.x("", 132), 1);
    }
}
