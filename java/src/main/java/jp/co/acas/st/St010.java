package jp.co.acas.st;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.Maps09;
import jp.co.acas.sys.SystemFile;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/** st010.cbl: 在庫品目マスター管理（登録・変更・削除・番号変更・照会・一覧印刷）。 */
public class St010 extends StProgram {
    static final String PROG_NAME = "ST010 (3.01.37)";
    private static final int L22 = 22, L23 = 23, L24 = 24;
    private static final String LINE3 =
            "<------ Stock ------> Supplier  Location     Unit      Unit        Value    Number"
            + " <- ReOrder -> <------- Date ------>  Quantity On";
    private static final String LINE4 =
            "Abrev   Number         Number               Price      Cost        in Stk   in Stk"
            + "  Point    Qty   Ordered     Due      Order  B/Ord";

    private Rec sys, stock, purch, anal;
    private CobFile stockFile, purchFile, analFile;
    private int menuReply, errorCode;
    private String escapeCode = " ", orderDate = St.x("", 10), orderDue = St.x("", 10), toDay = "";
    private boolean manu, exitProgram;

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        sys = SystemFile.shared(ctx);
        toDay = St.x((String) ctx.shared.getOrDefault("to-day", ""), 10);
        manu = sys.intv("stk-manu-used") == 1;
        stock = St.fdRec(Layout.of("copybooks/fdstock.cob", "Stock-Record"));
        purch = Layout.of("copybooks/fdpl.cob", "Purch-Record").newRec();
        anal = Layout.of("copybooks/fdanal.cob", "analysis-record").newRec();
        stockFile = St.stockFile(ctx, stock);
        purchFile = CobFile.indexed(ctx.store, ctx.path("purchled.dat"), purch, "purch-key");
        analFile = CobFile.indexed(ctx.store, ctx.path("analysis.dat"), anal, "pa-code");
        while (true) {
            // aa010-Menu-Return
            menuReply = 0;
            displayHeading();
            while (true) {
                // aa020-Menu-Input
                if (sys.intv("file-status", 11) != 1) {
                    setupStock();
                    if (exitProgram) return;
                    break;
                }
                display(7, 1, "Select one of the following by number :- [ ]");
                display(9, 4, "(1)  Set-up Stock records");
                display(11, 4, "(2)  Amend Stock records");
                display(13, 4, "(3)  Delete Stock records");
                display(15, 4, "(4)  Renumber Stock records");
                display(17, 4, "(5)  Display Stock records");
                display(19, 4, "(6)  Print Stock records");
                display(21, 4, "(9)  Return to system menu");
                menuReply = (int) St.digits(acceptUpdate(7, 43, 1, String.valueOf(menuReply), AUTO));
                if (menuReply == 9) return;
                if (menuReply < 1 || menuReply > 6) continue;
                switch (menuReply) {
                    case 1 -> setupStock();
                    case 2 -> amendStock();
                    case 3 -> deleteStock();
                    case 4 -> renumberStock();
                    case 6 -> reportStock();
                    default -> displayStock();
                }
                if (exitProgram) return;
                break;
            }
        }
    }

    // ---------- 共通 ----------

    private String open(CobFile f, CobFile.Mode m) { return f.isOpen() ? "41" : f.open(m); }
    private void clearErrorLine() { eraseEol(L23, 1); }
    private boolean esc() { return crtStatus() == 2005; }
    private boolean back() { int s = crtStatus(); return s == 2001 || s == 2003; }
    private int dateForm() {
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        return sys.intv("date-form");
    }
    private String convertBin(long bin) { return bin == 0 ? St.x("", 10) : St.fromUk(Maps04.toDate(bin), dateForm()); }
    private static String n6(long v) { return Num.z9(Math.abs(v) % 1_000_000, 6); }
    private static String money(BigDecimal v, int ints, int decs) {
        BigDecimal a = v.abs().setScale(decs, RoundingMode.DOWN);
        String frac = a.remainder(BigDecimal.ONE).movePointRight(decs).toBigInteger().toString();
        return Num.z9(a.longValue() % (long) Math.pow(10, ints), ints) + "." + "0".repeat(decs - frac.length()) + frac;
    }
    private static BigDecimal amount(String s, int ints, int decs) {
        s = St.x(s, ints + 1 + decs);
        return new BigDecimal(java.math.BigInteger.valueOf(St.digits(s.substring(0, ints)))
                .multiply(java.math.BigInteger.TEN.pow(decs)).add(java.math.BigInteger.valueOf(St.digits(s.substring(ints + 1)))), decs);
    }
    private void loadDates() {
        orderDate = convertBin(stock.longv("stock-order-date"));
        orderDue = convertBin(stock.longv("stock-order-due"));
    }
    private void showKeys() {
        show(4, 21, stock.str("stock-key"));
        show(4, 57, stock.str("stock-abrev-key"));
    }

    /** zz010-Display-Heading。 */
    private void displayHeading() {
        if (menuReply != 4) {
            eraseEos(1, 1);
            display(1, 1, PROG_NAME);
            show(3, 1, sys.str("usera"));
            show(1, 71, St.fromUk(toDay, sys.intv("date-form")), 2);
        }
        switch (menuReply) {
            case 0 -> { display(1, 24, "Stock File Set-Up & Maintenance"); display(4, 34, "Function  Menu"); }
            case 1 -> display(1, 29, "Stock Record Creation");
            case 2 -> display(1, 29, "Stock Record Amendment");
            case 3 -> display(1, 29, "Stock Record Deletion");
            case 5 -> display(1, 29, "Stock Record Display");
            default -> { }
        }
    }

    /** zz020-Display-Outline。 */
    private void displayOutline() {
        displayHeading();
        St.initialize(stock);
        orderDate = orderDue = St.x("", 10);
        display01(null);
    }

    /** Display-01: fields が null なら DISPLAY、そうでなければ ACCEPT 用に入力項目を集める。 */
    private void display01(List<Terminal.Field> fields) {
        display(4, 1, "Stock Number     - [");
        display(4, 34, "]");
        display(4, 41, "PL Fast key  - [");
        display(4, 64, "]");
        display(5, 1, "Desc [");
        item(fields, 5, 7, stock.str("stock-desc"));
        display(5, 39, "]");
        display(5, 41, "Stock Location [");
        item(fields, 5, 57, stock.str("stock-location"));
        display(5, 67, "]");
        display(6, 1, "Supplier: 1 - [");
        item(fields, 6, 16, stock.str("stock-supplier-p1"));
        display(6, 23, "] : 2 - [");
        item(fields, 6, 32, stock.str("stock-supplier-p2"));
        display(6, 39, "]");
        display(6, 50, ": 3 - [");
        item(fields, 6, 57, stock.str("stock-supplier-p3"));
        display(6, 64, "]");
        display(7, 1, "Stock Qty        - [");
        item(fields, 7, 21, n6(stock.longv("stock-held")));
        display(7, 27, "]");
        display(7, 41, "Qty Ordered      - [");
        item(fields, 7, 61, n6(stock.longv("stock-on-order")));
        display(7, 67, "]");
        display(8, 1, "Re-Order Point   - [");
        item(fields, 8, 21, n6(stock.longv("stock-reorder-pnt")));
        display(8, 27, "]");
        display(8, 41, "Back Ordered     - [");
        item(fields, 8, 61, n6(stock.longv("stock-back-ordered")));
        display(8, 67, "]");
        display(9, 1, "Re-Order Qty     - [");
        item(fields, 9, 21, n6(stock.longv("stock-std-reorder")));
        display(9, 27, "]");
        display(9, 41, "Sales Orders O/S - [");
        item(fields, 9, 61, n6(stock.longv("stock-pre-sales")));
        display(9, 67, "]");
        display(10, 1, "Sales Anal. Code - [");
        item(fields, 10, 21, stock.str("stock-sa-group"));
        display(10, 23, "]");
        display(10, 41, "Purch Anal.Code[");
        item(fields, 10, 57, stock.str("stock-pa-group"));
        display(10, 59, "]");
        display(11, 1, "Services only Flag [");
        item(fields, 11, 21, stock.str("stock-services-flag"));
        display(11, 22, "] (Y/N)");
        display(12, 1, "Date Ordered - [");
        item(fields, 12, 17, orderDate);
        display(12, 27, "]");
        display(12, 41, "Date Due     - [");
        item(fields, 12, 57, orderDue);
        display(12, 67, "]");
        String[] box = {"*******************", "* Escape Code [ ] *", "* <B> = Back      *", "* <S> = Save      *",
            "* <Q> = Quit      *", "*******************"};
        for (int i = 0; i < 6; i++) { eraseEol(18 + i, 61); display(18 + i, 61, box[i]); }
    }
    private void item(List<Terminal.Field> fields, int line, int col, String value) {
        if (fields == null) show(line, col, value);
        else fields.add(field(line, col, value.length(), value));
    }

    /** ACCEPT Display-01 の結果をレコードへ戻す。 */
    private int accept01() {
        List<Terminal.Field> f = new ArrayList<>();
        display01(f);
        int st = acceptScreen(f);
        String[] alpha = {"stock-desc", "stock-location", "stock-supplier-p1", "stock-supplier-p2", "stock-supplier-p3"};
        for (int i = 0; i < 5; i++) stock.set(alpha[i], f.get(i).value);
        String[] nums = {"stock-held", "stock-on-order", "stock-reorder-pnt", "stock-back-ordered", "stock-std-reorder", "stock-pre-sales"};
        for (int i = 0; i < 6; i++) stock.setNum(nums[i], number(f.get(5 + i).value));
        stock.set("stock-sa-group", f.get(11).value);
        stock.set("stock-pa-group", f.get(12).value);
        stock.set("stock-services-flag", f.get(13).value);
        orderDate = f.get(14).value;
        orderDue = f.get(15).value;
        return st;
    }
    private static long number(String s) {
        String d = s.replaceAll("[^0-9]", "");
        return d.isEmpty() ? 0 : Long.parseLong(d);
    }

    /** Display-01C: 金額項目（表示のみ）。 */
    private void display01C() {
        display(13, 1, "Retail Price - [");
        show(13, 17, money(stock.num("stock-retail"), 7, 2));
        display(13, 27, "]");
        display(13, 41, "Cost   Price - [");
        show(13, 57, money(stock.num("stock-cost"), 7, 4));
        display(13, 69, "]");
        display(14, 1, "Stock Value  - [");
        show(14, 17, money(stock.num("stock-value"), 9, 2));
        display(14, 29, "]");
    }

    /** Display-02: 仕掛（BOMP）項目。 */
    private void display02(List<Terminal.Field> fields) {
        display(15, 21, "Optional - Work In Progress (BOMP) Data");
        display(16, 1, "Construct Bundle - [");
        item(fields, 16, 21, n6(stock.longv("stock-construct-bundle")));
        display(16, 27, "]");
        display(16, 41, "Construction   - [");
        item(fields, 16, 59, n6(stock.longv("stock-under-construction")));
        display(16, 65, "]");
        display(17, 1, "Work In Progress - [");
        item(fields, 17, 21, n6(stock.longv("stock-work-in-progress")));
        display(17, 27, "]");
        display(17, 41, "Construct Item - [");
        item(fields, 17, 59, stock.str("stock-construct-item"));
        display(17, 72, "]");
    }
    private void accept02() {
        List<Terminal.Field> f = new ArrayList<>();
        display02(f);
        acceptScreen(f);
        stock.setNum("stock-construct-bundle", number(f.get(0).value));
        stock.setNum("stock-under-construction", number(f.get(1).value));
        stock.setNum("stock-work-in-progress", number(f.get(2).value));
        stock.set("stock-construct-item", f.get(3).value);
    }

    /** zz100-test-escape。 */
    private void testEscape(String initial) {
        escapeCode = initial;
        show(19, 76, escapeCode, 6);
        do {
            escapeCode = upper(acceptUpdate(19, 76, 1, escapeCode));
        } while ("BSQKDRCN".indexOf(escapeCode) < 0 || escapeCode.isEmpty());
    }

    /** zz040-Check-for-Supplier: 戻り値は（補正後の）仕入先コード。errorCode を設定する。 */
    private String checkSupplier(String supplier) {
        errorCode = 0;
        if (supplier.isBlank()) return supplier;
        if (supplier.charAt(6) == ' ') {
            int cd = Maps09.checkDigit(supplier.substring(0, 6));
            if (cd < 0) {
                errorCode = 2;
                display(L23, 1, "ST103 Abbreviated Stock number Invalid", 4);
                return supplier;
            }
            supplier = supplier.substring(0, 6) + cd;
        }
        purch.set("purch-key", supplier);
        if (purchFile.read(purch).equals("00")) return supplier;
        errorCode = 1;
        display(L23, 1, "ST101 Supplier not found", 4);
        return supplier;
    }

    /**
     * ba040 / ca040-Accept-Block 以降の共通部（ESC エスケープ入力まで）。
     * 戻り値: 0 = エスケープ入力済み, 1 = 品目番号入力へ戻る（ESC）。
     */
    private int acceptBlock(boolean amend) {
        while (true) {
            int st = accept01();
            if (st == 2005) return 1;
            if (st == 1003) {
                ctx.shared.put("ws-term-code", 0);
                call("pl010");
                displayHeading();
                display01(null);
                showKeys();
                continue;
            }
            boolean c = false;
            for (int b = 1; b <= 3; b++) {
                String name = "stock-supplier-p" + b;
                if (stock.str(name).isBlank()) continue;
                String s = checkSupplier(upper(stock.str(name)));
                if (errorCode != 0) {
                    if (!c) { c = true; display(L23, 1, "Supplier not found : ", 4); }
                    show(L23, b * 2 + 20, String.valueOf(b), 4);
                }
                stock.set(name, s);
            }
            if (c) continue;
            clearErrorLine();
            stock.set("stock-pa-group", stock.str("stock-pa-group").toLowerCase(java.util.Locale.ROOT));
            show(10, 57, stock.str("stock-pa-group"));
            if (!stock.str("stock-pa-group").isBlank()) {
                stock.set("stock-pa-system", "P");
                anal.set("pa-code", stock.str("stock-pa-code"));
                if (analFile.start(anal, "=").charAt(0) == '2') { display(L23, 1, "ST111 Cannot find Purchase Ledger Analysis Code", 4); continue; }
            }
            stock.set("stock-sa-group", stock.str("stock-sa-group").toLowerCase(java.util.Locale.ROOT));
            show(10, 21, stock.str("stock-sa-group"));
            if (!stock.str("stock-sa-group").isBlank()) {
                stock.set("stock-sa-system", "S");
                anal.set("pa-code", stock.str("stock-sa-code"));
                if (analFile.start(anal, "=").charAt(0) == '2') { display(L23, 1, "ST110 Cannot find Sales Ledger Analysis Code", 4); continue; }
            }
            display01C();
            // 金額項目
            String m = money(stock.num("stock-retail"), 7, 2);
            show(13, 17, m);
            stock.setNum("stock-retail", amount(acceptUpdate(13, 17, 10, m), 7, 2));
            m = money(stock.num("stock-cost"), 7, 4);
            show(13, 57, m);
            stock.setNum("stock-cost", amount(acceptUpdate(13, 57, 12, m), 7, 4));
            m = money(stock.num("stock-value"), 9, 2);
            show(14, 17, m);
            stock.setNum("stock-value", amount(acceptUpdate(14, 17, 12, m), 9, 2));
            if (manu) accept02();
            boolean avg = sys.intv("stk-averaging") == 1 && stock.num("stock-value").signum() == 0
                    && stock.num("stock-cost").signum() != 0 && stock.longv("stock-held") != 0;
            if (avg) stock.setNum("stock-value", stock.num("stock-cost").multiply(BigDecimal.valueOf(stock.longv("stock-held"))));
            // 変更（ca046）は原文のピリオド位置により、仕掛分の加算が平均法の条件に関係なく行われる
            if (manu && (amend || avg))
                stock.setNum("stock-value", stock.num("stock-value")
                        .add(stock.num("stock-cost").multiply(BigDecimal.valueOf(stock.longv("stock-work-in-progress")))));
            if (!orderDate.isBlank()) {
                long bin = Maps04.toBin(St.toUk(orderDate, dateForm()));
                if (bin == 0) { display(L23, 1, "ST005 Invalid Date", 4); show(12, 28, "*", 4); continue; }
                stock.setNum("stock-order-date", bin);
                show(12, 28, " ");
            }
            if (!orderDue.isBlank()) {
                long bin = Maps04.toBin(St.toUk(orderDue, dateForm()));
                if (bin == 0) { display(L23, 1, "ST005 Invalid Date", 4); show(12, 68, "*", 4); continue; }
                stock.setNum("stock-order-due", bin);
                show(12, 68, " ");
            }
            show(12, 28, " ");
            show(12, 68, " ");
            clearErrorLine();
            if (!stock.str("stock-construct-item").isBlank()) {
                stock.set("stock-construct-item", upper(stock.str("stock-construct-item")));
                show(16, 59, stock.str("stock-construct-item"));
                byte[] saved = stock.copyBytes();
                stock.set("stock-key", stock.str("stock-construct-item"));
                boolean found = stockFile.start(stock, "=").equals("00");
                stock.load(saved);
                if (!found) { display(L23, 1, "ST115 Construct Stock Number not found", 4); continue; }
            }
            if (!stock.str("stock-services-flag").equals(" "))
                stock.set("stock-services-flag", upper(stock.str("stock-services-flag")));
            if (stock.str("stock-services-flag").equals("Y")) {
                stock.set("stock-construct-item", "");
                orderDue = orderDate = St.x("", 10);
                for (String n : new String[] {"stock-construct-bundle", "stock-under-construction", "stock-work-in-progress",
                    "stock-reorder-pnt", "stock-std-reorder", "stock-back-ordered", "stock-on-order", "stock-pre-sales",
                    "stock-value", "stock-order-due", "stock-order-date"}) stock.setNum(n, 0);
                display01(null);
                display01C();
                if (manu) display02(null);
                display(L23, 1, "ST118 Service Flag is set, so unused values cleared", 2);
            }
            testEscape("S");
            return 0;
        }
    }

    private void fileError(String fs) {
        display(L23, 1, "ST000 Error on Writing to Stock File", 4);
        show(L23, 38, fs, 4);
        maps99(45);
    }

    // ---------- (1) 登録 ----------

    /** ba000-Setup-Stock。 */
    private void setupStock() {
        if (!open(purchFile, CobFile.Mode.INPUT).equals("00")) {
            display(L23, 1, "ST104 Purchase Ledger not yet set up, Aborting", 4);
            maps99(45);
            exitProgram = true;
            return;
        }
        if (!open(stockFile, CobFile.Mode.IO).equals("00")) {
            stockFile.close();
            stockFile.open(CobFile.Mode.OUTPUT);
            stockFile.close();
            stockFile.open(CobFile.Mode.IO);
            sys.set("stock-control", "Y");
            sys.setNum("file-status", 1, 11);
        }
        if (sys.intv("file-status", 15) != 1) {
            ctx.shared.put("ws-process-func", 1);
            ctx.shared.put("ws-sub-function", 1);
            call("sl070");
            if (sys.intv("file-status", 15) != 1) {
                display(L23, 1, "ST112 Analysis File not found, Aborting", 4);
                stockFile.close(); purchFile.close();
                maps99(45);
                return;
            }
        }
        open(analFile, CobFile.Mode.INPUT);   // 原文は結果を検査しない（開けない場合、分析コードの START は INVALID KEY にならない）
        boolean outline = true;
        while (true) {
            if (outline) {
                // ba010-Display-Stock-Headings
                displayOutline();
                St.initialize(stock);
                stock.set("stock-services-flag", "N");
            }
            outline = true;
            // ba020-Stock-Item-Accept
            show(4, 67, " ", 2);
            String key = accept(4, 21, 13);
            stock.set("stock-key", key);
            if (key.isBlank() || esc()) break;
            key = upper(key);
            stock.set("stock-key", key);
            show(4, 21, key);
            // ba030-Stock-Abrev-Item-Accept
            String abrev;
            boolean again = false;
            while (true) {
                abrev = accept(4, 57, 7);
                stock.set("stock-abrev-key", abrev);
                if (esc() || back()) { again = true; break; }
                if (!abrev.isBlank()) {
                    abrev = upper(abrev);
                    stock.set("stock-abrev-key", abrev);
                    show(4, 57, abrev);
                    clearErrorLine();
                    break;
                }
                display(L23, 1, "ST102 Abbreviated Stock number Must be present", 4);
            }
            if (again) { outline = false; continue; }
            if (stockFile.read(stock).equals("00")) {
                display(L23, 1, "ST113 Abbreviated Stock Number is already on file", 4);
                outline = false; continue;
            }
            stock.set("stock-abrev-key", abrev);
            if (stockFile.readAlt(stock, 0).equals("00")) {
                display(L23, 1, "ST116 Stock Number is already on file", 4);
                outline = false; continue;
            }
            clearErrorLine();
            stock.set("stock-abrev-key", abrev);
            stock.set("stock-key", key);
            if (acceptBlock(false) == 1) { outline = false; continue; }
            // ba050-Main-Output
            if (escapeCode.equals("Q") || esc()) break;
            if (escapeCode.equals("B") || back()) { outline = false; continue; }
            String fs = stockFile.write(stock);
            if (!fs.equals("00")) { fileError(fs); break; }
            St.initialize(stock);
            orderDate = orderDue = St.x("", 10);
        }
        stockFile.close(); analFile.close(); purchFile.close();
    }

    // ---------- (2) 変更 ----------

    /** ca000-Amend-Stock。 */
    private void amendStock() {
        if (!open(purchFile, CobFile.Mode.INPUT).equals("00")) {
            display(L23, 1, "ST105 Purchase Ledger File not found, Aborting", 4);
            maps99(45);
            return;
        }
        if (!open(stockFile, CobFile.Mode.IO).equals("00")) {
            stockFile.close();
            stockFile.open(CobFile.Mode.OUTPUT);
            stockFile.close();
            stockFile.open(CobFile.Mode.IO);
            sys.set("stock-control", "Y");
            sys.setNum("file-status", 1, 11);
            display(L23, 1, "ST106 Stock File not found, nothing to do", 4);
            stockFile.close(); analFile.close(); purchFile.close();
            return;
        }
        if (!open(analFile, CobFile.Mode.INPUT).equals("00")) {
            display(L23, 1, "ST112 Analysis File not found, Aborting", 4);
            stockFile.close(); purchFile.close();
            maps99(45);
            return;
        }
        boolean outline = true;
        while (true) {
            if (outline) displayOutline();
            outline = true;
            // ca020-Stock-Item-Accept
            St.initialize(stock);
            orderDate = orderDue = St.x("", 10);
            show(4, 67, " ", 2);
            String key = accept(4, 21, 13);
            stock.set("stock-key", key);
            if (key.isBlank() || esc()) break;
            stock.set("stock-key", upper(key));
            if (!stockFile.read(stock).equals("00")) {
                display(L23, 1, "ST114 Stock Number not found", 4);
                outline = false; continue;
            }
            showKeys();
            clearErrorLine();
            loadDates();
            display01(null);
            showKeys();
            if (acceptBlock(true) == 1) { outline = false; continue; }
            if (escapeCode.equals("Q") || esc()) break;
            if (escapeCode.equals("B") || back()) { outline = false; continue; }
            String fs = stockFile.rewrite(stock);
            if (!fs.equals("00")) { fileError(fs); break; }
            St.initialize(stock);
            orderDate = orderDue = St.x("", 10);
        }
        stockFile.close(); analFile.close(); purchFile.close();
    }

    // ---------- (3) 削除 ----------

    /** da000-Delete-Stock。 */
    private void deleteStock() {
        if (!open(stockFile, CobFile.Mode.IO).equals("00")) {
            stockFile.close();
            display(L23, 1, "ST106 Stock File not found, nothing to do", 4);
            return;
        }
        boolean outline = true;
        while (true) {
            if (outline) displayOutline();
            outline = true;
            // da020-Stock-Item-Accept
            stock.set("stock-key", ""); stock.set("stock-abrev-key", "");
            eraseEol(23, 61);
            display01(null);
            if (manu) display02(null);
            String key = accept(4, 21, 13);
            stock.set("stock-key", key);
            if (key.isBlank() || esc()) { stockFile.close(); return; }
            stock.set("stock-key", upper(key));
            eraseEos(L23, 1);
            if (!stockFile.read(stock).equals("00")) {
                display(L23, 1, "ST114 Stock Number not found", 4);
                outline = false; continue;
            }
            showKeys();
            clearErrorLine();
            loadDates();
            display01(null);
            if (manu) display02(null);
            display(22, 61, "* <D> = Delete    *");
            display(23, 61, "*******************");
            showKeys();
            if (stock.longv("stock-on-order") != 0 || stock.longv("stock-held") != 0 || stock.longv("stock-back-ordered") != 0) {
                display(L23, 1, "ST107 Cannot Delete record as non zero values exist", 4);
                outline = false; continue;
            }
            testEscape("D");
            if (escapeCode.equals("Q") || esc()) return;
            if (escapeCode.equals("B") || escapeCode.equals("S") || back()) { outline = false; continue; }
            if (!escapeCode.equals("D")) continue;
            // da040-Accept-Delete
            String reply;
            do {
                display(L22, 1, "Deleting Stock Item record, are you sure? [ ]");
                reply = upper(accept(L22, 44, 1));
            } while (!reply.equals("Y") && !reply.equals("N"));
            if (reply.equals("N")) continue;
            eraseEol(L22, 1);
            String fs = stockFile.delete(stock);
            if (!fs.equals("00")) {
                display(L23, 1, "ST108 Delete failed on Stock File = ", 4);
                show(L23, 37, fs, 4);
                maps99(15);
            }
        }
    }

    // ---------- (4) 番号変更 ----------

    /** ga000-Renumber-Stock。 */
    private void renumberStock() {
        if (!open(stockFile, CobFile.Mode.IO).equals("00")) {
            stockFile.close();
            display(L23, 1, "ST106 Stock File not found, nothing to do", 4);
            return;
        }
        boolean outline = true;
        while (true) {
            if (outline) displayOutline();
            outline = true;
            // ga020-Stock-Item-Accept
            stock.set("stock-key", ""); stock.set("stock-abrev-key", "");
            eraseEol(23, 61);
            display01(null);
            display01C();
            if (manu) display02(null);
            String key = accept(4, 21, 13);
            stock.set("stock-key", key);
            if (key.isBlank() || esc()) { stockFile.close(); return; }
            stock.set("stock-key", upper(key));
            eraseEos(L23, 1);
            if (!stockFile.read(stock).equals("00")) {
                display(L23, 1, "ST114 Stock Number not found", 4);
                outline = false; continue;
            }
            showKeys();
            clearErrorLine();
            loadDates();
            display01(null);
            display01C();
            if (manu) display02(null);
            eraseEol(16, 1);
            display(16, 1, "Stock Number     - [");
            display(16, 34, "]");
            display(16, 41, "PL Fast key  - [");
            display(16, 64, "]");
            display(22, 61, "* <R> = Renumber  *");
            display(23, 61, "*******************");
            showKeys();
            if (stock.longv("stock-on-order") != 0 || stock.longv("stock-back-ordered") != 0) {
                display(L23, 1, "ST109 Cannot Renumber record as Order values exist", 4);
                outline = false; continue;
            }
            String saveKey = stock.str("stock-key"), saveAbrev = stock.str("stock-abrev-key");
            String newKey = saveKey, newAbrev = saveAbrev;
            int next;   // 0 = 見出しから, 1 = 品目入力から, 2 = 終了
            while (true) {
                // ga040-Accept-New-Stock-No
                newKey = acceptUpdate(16, 21, 13, newKey);
                if (newKey.isBlank() || esc()) { next = 0; break; }
                newKey = upper(newKey);
                show(16, 21, stock.str("stock-key"));
                newAbrev = accept(16, 57, 7);
                if (esc() || back()) continue;
                if (newAbrev.isBlank()) { display(L23, 1, "ST102 Abbreviated Stock number Must be present", 4); continue; }
                newAbrev = upper(newAbrev);
                clearErrorLine();
                testEscape("R");
                if (escapeCode.equals("Q") || esc()) { next = 2; break; }
                if (escapeCode.equals("B") || escapeCode.equals("S") || back()) { next = 1; break; }
                if (!escapeCode.equals("R")) { next = 0; break; }
                // ga050-Accept-Renumber
                String reply;
                do {
                    display(L22, 1, "Renumbering Stock Item record, are you sure? [ ]");
                    reply = upper(accept(L22, 47, 1));
                } while (!reply.equals("Y") && !reply.equals("N"));
                if (reply.equals("N")) { next = 0; break; }
                eraseEol(L22, 1);
                stock.set("stock-key", newKey);
                stock.set("stock-abrev-key", newAbrev);
                String fs = stockFile.write(stock);
                if (fs.equals("22")) { display(L23, 1, "ST117 Stock Number/Abrev No. is already on file", 4); continue; }
                if (!fs.equals("00")) {
                    fileError(fs);
                    stockFile.close();
                    return;
                }
                stock.set("stock-key", saveKey);
                stock.set("stock-abrev-key", saveAbrev);
                fs = stockFile.delete(stock);
                if (!fs.equals("00")) {
                    display(L23, 1, "ST108 Delete failed on Stock File = ", 4);
                    show(L23, 37, fs, 4);
                    maps99(15);
                }
                next = 0;
                break;
            }
            if (next == 2) return;
            if (next == 1) outline = false;
        }
    }

    // ---------- (5) 照会 ----------

    /** fa000-Display-Stock。 */
    private void displayStock() {
        if (!open(stockFile, CobFile.Mode.INPUT).equals("00")) {
            stockFile.close();
            display(L23, 1, "ST106 Stock File not found, nothing to do", 4);
            display(L24, 1, "ST003 Hit return for Menu", 4);
            return;
        }
        boolean outline = true;
        while (true) {
            if (outline) displayOutline();
            outline = true;
            // fa020-Stock-Item-Accept
            stock.set("stock-key", ""); stock.set("stock-abrev-key", "");
            display01(null);
            display01C();
            if (manu) display02(null);
            String key = accept(4, 21, 13);
            stock.set("stock-key", key);
            if (key.isBlank() || esc()) { stockFile.close(); return; }
            String wsKey = upper(key);
            stock.set("stock-key", wsKey);
            boolean redo = false;
            while (true) {
                // fa030-Get-Record
                if (wsKey.charAt(0) == '*') {
                    if (!stockFile.readNext(stock).equals("00")) {
                        display(L23, 1, "ST119 No more records to display", 4);
                        display(L24, 1, "ST003 Hit return for Menu", 4);
                        redo = true; break;
                    }
                } else if (!stockFile.read(stock).equals("00")) {
                    display(L23, 1, "ST114 Stock Number not found", 4);
                    display(L24, 1, "ST003 Hit return for Menu", 4);
                    redo = true; break;
                }
                showKeys();
                clearErrorLine();
                loadDates();
                display01(null);
                display01C();
                if (manu) display02(null);
                showKeys();
                if (wsKey.stripTrailing().equals("*")) {
                    display(20, 64, "N> = Next  ");
                    testEscape("N");
                } else testEscape("S");
                if (escapeCode.equals("N") || crtStatus() == 1001) continue;
                break;
            }
            if (redo) { outline = false; continue; }
            if (escapeCode.equals("Q") || esc()) { stockFile.close(); return; }
        }
    }

    // ---------- (6) 一覧印刷 ----------

    /** ea000-Report-Stock。 */
    private void reportStock() {
        St.Printer print = new St.Printer(ctx, "prt-1");
        if (!open(stockFile, CobFile.Mode.INPUT).equals("00")) {
            stockFile.close(); print.close();
            display(L23, 1, "ST106 Stock File not found, nothing to do", 4);
            return;
        }
        // ea200-Produce-Report
        int lineCnt = 99, pageNos = 0; long recCnt = 0;
        int pageLines = sys.intv("page-lines");
        String hh = "  ", mm = "  ";
        LocalDateTime now = ctx.now();
        if (now.getHour() != 0 || now.getMinute() != 0 || now.getSecond() != 0 || now.getNano() >= 10_000_000) {
            hh = String.format("%02d", now.getHour()); mm = String.format("%02d", now.getMinute());
        }
        String line2 = St.x(sys.str("usera"), 40) + St.x("", 76) + St.fromUk(toDay, sys.intv("date-form")) + " " + hh + ":" + mm;
        while (stockFile.readNext(stock).equals("00")) {
            if (lineCnt > pageLines) { heads(print, ++pageNos, line2); lineCnt = 5; }
            recCnt++;
            boolean service = stock.str("stock-services-flag").equals("Y");
            String cost = Num.edit(stock.num("stock-cost"), "z(6)9.9999");
            if (cost.endsWith("00")) cost = cost.substring(0, 10) + "  ";
            String l5 = St.x(stock.str("stock-abrev-key"), 8) + St.x(stock.str("stock-key"), 14) + St.x(stock.str("stock-supplier-p1"), 8)
                    + St.x(stock.str("stock-location"), 11) + Num.edit(stock.num("stock-retail"), "z(6)9.99") + cost;
            if (!service)
                l5 += Num.edit(stock.num("stock-value"), "zzzzz,zz9.99") + Num.edit(stock.longv("stock-held"), "z(6)9")
                        + Num.edit(stock.longv("stock-reorder-pnt"), "z(6)9") + Num.edit(stock.longv("stock-std-reorder"), "z(6)9") + " ";
            else l5 += St.x("", 34);
            l5 += St.x(convertBin(stock.longv("stock-order-date")), 11) + convertBin(stock.longv("stock-order-due"));
            if (!service) l5 += Num.edit(stock.longv("stock-on-order"), "z(6)9") + Num.edit(stock.longv("stock-back-ordered"), "z(6)9");
            StringBuilder vars = new StringBuilder();
            String p2 = stock.str("stock-supplier-p2"), p3 = stock.str("stock-supplier-p3");
            if (!p2.isBlank() || !p3.isBlank()) {
                vars.append("Secondary Suppliers");
                if (!p2.isBlank()) vars.append(" 1: ").append(p2);
                if (!p3.isBlank()) vars.append(" 2: ").append(p3);
                vars.append("  ");
            }
            if (!stock.str("stock-sa-code").isBlank()) vars.append("SA Code: ").append(stock.str("stock-sa-group")).append("  ");
            if (!stock.str("stock-pa-code").isBlank()) vars.append("PA Code: ").append(stock.str("stock-pa-group"));
            if (stock.longv("stock-pre-sales") != 0) vars.append("  Pre Sales :").append(Num.edit(stock.longv("stock-pre-sales"), "z(6)"));
            if (lineCnt > 5) {
                print.after("-".repeat(132), 1);
                print.after(St.x(l5, 132), 1);
            } else print.after(St.x(l5, 132), 2);
            print.after(St.x(St.x("", 5) + "Description: " + St.x(stock.str("stock-desc"), 32) + St.x("", 5) + vars, 132), 1);
            lineCnt += 3;
            if (!service && (stock.longv("stock-construct-bundle") != 0 || stock.longv("stock-under-construction") != 0
                    || stock.longv("stock-work-in-progress") != 0 || !stock.str("stock-construct-item").isBlank())) {
                print.after(St.x("Construction Bundle :" + Num.edit(stock.longv("stock-construct-bundle"), "z(6)") + "  WIP :"
                        + Num.edit(stock.longv("stock-work-in-progress"), "z(6)") + "  Under Construction :"
                        + Num.edit(stock.longv("stock-under-construction"), "z(6)") + " For Constructed Item : "
                        + stock.str("stock-construct-item"), 132), 1);
                lineCnt++;
            }
            if (service) { print.after(St.x("Services only Product", 132), 1); lineCnt++; }
        }
        // ea230-Totals
        if (lineCnt > pageLines - 3) heads(print, ++pageNos, line2);
        print.after(St.x(" Total Stock Records " + Num.edit(recCnt, "zzz,zzz,zz9").strip(), 132), 3);
        stockFile.close();
        print.close();
        ctx.spool("prt-1", St.printCommand(sys.str("print-spool-name")));
    }

    /** ea220-Heads。 */
    private void heads(St.Printer print, int pageNos, String line2) {
        String line1 = St.x(PROG_NAME, 16) + St.x("", 41) + "Stock File Report" + St.x("", 50) + "Page " + Num.edit(pageNos, "zz9");
        if (pageNos != 1) {
            print.afterPage(line1);
            print.after(line2, 1);
            print.after(St.x("", 132), 1);
        } else {
            print.before(line1, 1);
            print.before(line2, 1);
        }
        print.after(LINE3, 1);
        print.after(LINE4, 1);
    }
}
