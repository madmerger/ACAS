package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.Maps09;

import java.math.BigDecimal;

/** sl010.cbl: 顧客マスター登録・保守。 */
public class Sl010 extends SlProgram {
    static final String PROG_NAME = "SL010 (3.01.20)";
    static final String SL004 = "hit return", SL005 = "SL005 Invalid Date", SL101 = "SL101 Addr Err", SL102 = "Error",
        SL103 = "SL103 Sales Ledger files have not been set up yet", SL104 = "SL104 Do you wish to create them (Y/N) ? [ ]",
        SL105 = "SL105 Creating Sales & Delivery Files", SL106 = "SL106 Opening Sales files gives ",
        SL107 = "SL107 Opening Delivery files gives ", SL109 = "SL109 <<<Can not Delete currently active account>>>";

    private Rec sys, sales, deliv;
    private CobFile salesFile, delivFile;
    private Prt print;
    private int menuReply, errorFlag, errorCode, y, a, lineCnt, z;
    private boolean truth;
    private long saveTag, saveNotesTag, wsEnterDate;
    private String escapeCode = " ", printOut = " ", d2402 = " ", d2403 = " ", d24Digit = " ";
    private boolean d24CheckShown;
    private String lateCharg = " ", dunLetter = " ", emailLet = " ", emailStat = " ", emailInv = " ";
    private String notes1 = "", notes2 = "", delivName = "", delivAddr1 = "", delivAddr2 = "";
    private String custIn = "", statusIn = " ", creditOp = " ", invoiceOp = " ", averageOp = " ", overdueOp = " ", enterDateIn = "", enterDateOp = " ";
    private int creditIn, invoiceIn, averageIn, overdueIn;
    private String customerIn = "", customerNos = "", customerCode = "";
    private int checkDigit;
    private String wsLocalDate = "", l3Report = "", l3Date = "", l3User = "";
    private Scr display02, display03;

    @Override
    public void run(Object... args) {
        sys = sys();
        sales = salesRec(); deliv = deliveryRec();
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv);
        print = new Prt(ctx, "prt-1");
        buildScreens();
        term().exceptionsEnabled = true; term().escEnabled = true;
        printOut = " ";
        if (!sys.str("sales-ledger").equals("Y") && !slcreate()) return;
        while (true) {
            menuReply = 0;
            displayHeading();
            while (true) {
                display(7, 1, "Select one of the following by number :- [ ]");
                display(10, 4, "(1)  Set-up customer records");
                display(12, 4, "(2)  Amend Customer records");
                display(14, 4, "(3)  Delete Customer records");
                display(16, 4, "(4)  Print Customer records");
                display(18, 4, "(5)  Display Customer records");
                display(21, 4, "(9)  Return to system menu");
                menuReply = acceptNum(7, 43, 1, AUTO);
                if (menuReply == 9) return;
                if (menuReply >= 1 && menuReply <= 5) break;
            }
            switch (menuReply) {
                case 1 -> setupCustomers();
                case 2 -> amendCustomer();
                case 3 -> deleteCustomer();
                case 4 -> { reportSelection(); reportHeadingSetup(); produceReport(); salesFile.close(); delivFile.close(); }
                default -> displayCustomers();
            }
        }
    }

    private String s(String f) { return sales.str(f); }
    private String address() { return pad(delivAddr1, 48) + pad(delivAddr2, 48); }
    private String notes() { return pad(notes1, 48) + pad(notes2, 48); }
    private String d24Check() { return d24CheckShown ? "Check Digit {" + d24Digit + "}" : " ".repeat(15); }

    private void buildScreens() {
        display02 = new Scr()
            .value(4, 1, "Customer Nos : [").from(4, 23, 1, () -> d2402).from(4, 24, 1, () -> d2403)
            .value(6, 1, "Customer Name: [").using(6, 17, 30, () -> s("sales-name"), v -> sales.set("sales-name", v)).value(6, 47, "]")
            .value(7, 10, "Addr: [").using(7, 17, 48, () -> s("sales-addr1"), v -> sales.set("sales-addr1", v)).value(7, 65, "]")
            .value(8, 16, "[").using(8, 17, 48, () -> s("sales-addr2"), v -> sales.set("sales-addr2", v)).value(8, 65, "]")
            .value(9, 1, "Delivery name: [").using(9, 17, 30, () -> delivName, v -> delivName = v).value(9, 47, "]")
            .value(10, 10, "Addr: [").using(10, 17, 48, () -> delivAddr1, v -> delivAddr1 = v).value(10, 65, "]")
            .value(11, 16, "[").using(11, 17, 48, () -> delivAddr2, v -> delivAddr2 = v).value(11, 65, "]")
            .value(12, 1, "Customer Note: [").using(12, 17, 48, () -> notes1, v -> notes1 = v).value(12, 65, "]")
            .value(13, 16, "[").using(13, 17, 48, () -> notes2, v -> notes2 = v).value(13, 65, "]")
            .value(14, 1, "Telephone    : [").using(14, 17, 13, () -> s("sales-phone"), v -> sales.set("sales-phone", v)).value(14, 30, "]")
            .value(14, 32, "Ext: [").using(14, 38, 4, () -> s("sales-ext"), v -> sales.set("sales-ext", v)).value(14, 42, "]")
            .value(14, 45, "Fax : [").using(14, 52, 13, () -> s("sales-fax"), v -> sales.set("sales-fax", v)).value(14, 65, "]")
            .value(15, 1, "Email Sales  : [").using(15, 17, 30, () -> s("sales-email"), v -> sales.set("sales-email", v)).value(15, 47, "]")
            .value(16, 1, "Late charges : [").using(16, 17, 1, () -> lateCharg, v -> lateCharg = v).value(16, 18, "]")
            .value(16, 26, "Minimum balance before late charge : [")
            .usingNum(16, 64, 4, () -> z(sales.longv("sales-late-min"), 4), v -> sales.setNum("sales-late-min", intOf(v))).value(16, 68, "]")
            .value(17, 1, "Late letters : [").using(17, 17, 1, () -> dunLetter, v -> dunLetter = v).value(17, 18, "]")
            .value(17, 26, "Maximum late charge").value(17, 61, ": [")
            .usingNum(17, 64, 4, () -> z(sales.longv("sales-late-max"), 4), v -> sales.setNum("sales-late-max", intOf(v))).value(17, 68, "]")
            .value(18, 1, "Credit period: [").usingNum(18, 17, 2, () -> z(sales.longv("sales-credit"), 2), v -> sales.setNum("sales-credit", intOf(v))).value(18, 19, "]")
            .value(18, 26, "EMail-Inv:[").using(18, 37, 1, () -> emailInv, v -> emailInv = v).value(18, 38, "]")
            .value(18, 40, "Stat: [").using(18, 47, 1, () -> emailStat, v -> emailStat = v).value(18, 48, "]")
            .value(18, 50, "Dun : [").using(18, 57, 1, () -> emailLet, v -> emailLet = v).value(18, 58, "]")
            .value(19, 1, "Credit limit : [").usingNum(19, 17, 7, () -> z(sales.longv("sales-limit"), 7), v -> sales.setNum("sales-limit", intOf(v)))
            .value(19, 24, "] Discount : [")
            .usingNum(19, 38, 5, () -> Num.edit(sales.num("sales-discount"), "99.99"), v -> sales.setNum("sales-discount", Num.truncated(numOf(v), 2)))
            .value(19, 43, "]")
            .value(19, 56, "*******************")
            .value(20, 1, "Unapplied Bal: {").value(20, 29, "}").value(20, 56, "* Escape Code [").value(20, 72, "] *")
            .value(21, 1, "Current Bal  : {").value(21, 29, "}").value(21, 56, "* <B> = Back      *")
            .value(22, 1, "Last invoice : {").value(22, 27, "}").value(22, 56, "* <S> = Save      *")
            .value(23, 1, "Last payment : {").value(23, 27, "}").value(23, 56, "* <Q> = Quit      *")
            .value(24, 56, "*******************");
        display03 = new Scr().blankScreen()
            .from(1, 1, 15, () -> PROG_NAME).value(1, 34, "Customer File").from(1, 71, 10, () -> wsLocalDate)
            .value(3, 32, "Report Attributes")
            .value(8, 3, "Customer Number - [").using(8, 22, 6, () -> custIn, v -> custIn = v).value(8, 28, "]")
            .value(8, 33, "Enter characters in positions to match")
            .value(10, 3, "Status          - [").using(10, 22, 1, () -> statusIn, v -> statusIn = v).value(10, 23, "]")
            .value(10, 33, "<L> Live;<D> Dormant;< > All")
            .value(12, 3, "Credit Period   - [").usingNum(12, 22, 2, () -> z(creditIn, 2), v -> creditIn = intOf(v)).value(12, 24, "]  [")
            .using(12, 28, 1, () -> creditOp, v -> creditOp = v).value(12, 29, "]")
            .value(12, 33, "Enter number of days & operator")
            .value(13, 37, "<L>  for credit periods < than")
            .value(14, 37, "<G>  for credit periods > than")
            .value(15, 37, "<E>  for credit periods = to")
            .value(17, 3, "Invoice Activity  [").usingNum(17, 22, 5, () -> z(invoiceIn, 5), v -> invoiceIn = intOf(v)).value(17, 27, "] [")
            .using(17, 30, 1, () -> invoiceOp, v -> invoiceOp = v).value(17, 31, "]")
            .value(17, 33, "Enter number of invoices & operator")
            .value(19, 3, "Average Value   - [").usingNum(19, 22, 5, () -> z(averageIn, 5), v -> averageIn = intOf(v)).value(19, 27, "] [")
            .using(19, 30, 1, () -> averageOp, v -> averageOp = v).value(19, 31, "]")
            .value(19, 33, "Enter invoice value & operator")
            .value(21, 3, "Overdue A/Cs    - [").usingNum(21, 22, 5, () -> z(overdueIn, 5), v -> overdueIn = intOf(v)).value(21, 27, "] [")
            .using(21, 30, 1, () -> overdueOp, v -> overdueOp = v).value(21, 31, "]")
            .value(21, 33, "Enter number of days & operator")
            .value(23, 3, "Date Entered-[").using(23, 17, 10, () -> enterDateIn, v -> enterDateIn = v).value(23, 27, "] [")
            .using(23, 30, 1, () -> enterDateOp, v -> enterDateOp = v).value(23, 31, "]")
            .value(23, 33, "Enter date & operator");
    }

    private void clearErrorLine() { eraseEol(23, 1); }
    private void clearErrorLine24() { eraseEol(24, 1); }

    /** test-escape。 */
    private void testEscape() {
        show(20, 71, escapeCode, 6);
        do { escapeCode = upper(term().accept(20, 71, 1, escapeCode, 0, 6)); }
        while (!"BSQKDT".contains(escapeCode) || escapeCode.isBlank());
    }

    private void displayHeading() {
        clearScreen();
        d2402 = " "; d24CheckShown = false; d24Digit = " ";
        d2403 = "]";
        if (menuReply != 4) {
            display(1, 1, PROG_NAME);
            wsLocalDate = fromUk(toDay());
            show(1, 71, wsLocalDate, 2);
        }
        switch (menuReply) {
            case 0 -> { display(1, 24, "Customer File Set-Up & Maintenance"); display(4, 34, "Function  Menu"); }
            case 1 -> { display(1, 29, "Customer Record Creation"); d24CheckShown = true; d2402 = "]"; d2403 = " "; }
            case 2 -> display(1, 29, "Customer Record Amendment");
            case 3 -> display(1, 29, "Customer Record Deletion");
            case 5 -> display(1, 29, "Customer Record Display");
            default -> { }
        }
    }

    private void showDisplay02() {
        display02.display();
        if (d24CheckShown) { display(4, 26, "Check Digit {"); show(4, 39, d24Digit + "}", 2); }
        else show(4, 26, " ".repeat(15), 2);
    }

    private void customerDisplay() {
        lateCharg = sales.intv("sales-late") == 1 ? "Y" : "N";
        dunLetter = sales.intv("sales-dunning") == 1 ? "Y" : "N";
        emailInv = sales.intv("email-invoice") == 1 ? "Y" : "N";
        emailStat = sales.intv("email-statement") == 1 ? "Y" : "N";
        emailLet = sales.intv("email-letters") == 1 ? "Y" : "N";
        if (menuReply == 1) d24Digit = s("sales-key").substring(6, 7); else d2402 = s("sales-key").substring(6, 7);
        showDisplay02();
        if (menuReply == 1 || menuReply == 2) return;
        show(20, 17, Num.edit(sales.num("sales-unapplied"), "-(8)9.99"), 2);
        show(21, 17, Num.edit(sales.num("sales-current"), "-(8)9.99"), 2);
        if (sales.longv("sales-last-inv") != 0) show(22, 17, binToDate(sales.longv("sales-last-inv")), 2);
        if (sales.longv("sales-last-pay") != 0) show(23, 17, binToDate(sales.longv("sales-last-pay")), 2);
    }

    private void displayOutline() {
        displayHeading();
        initialize(sales); initialize(deliv);
        lateCharg = dunLetter = emailLet = emailStat = emailInv = " ";
        delivName = ""; delivAddr1 = ""; delivAddr2 = ""; notes1 = ""; notes2 = "";
        showDisplay02();
    }

    private void deleteDeliv(String type) {
        deliv.set("deliv-sales-key", s("sales-key")); deliv.set("deliv-key-type", type);
        delivFile.delete(deliv);
    }

    private void customerData() {
        do {
            errorFlag = 0;
            showDisplay02();
            display02.accept();
            validateAddress(s("sales-address"));
            if (!truth) { display(7, 66, SL101, 4); errorFlag = 1; } else eraseEol(7, 66);
            boolean delivBlank = delivName.isBlank() && address().isBlank();
            if (delivBlank && sales.intv("delivery-tag") != 0) {
                deleteDeliv("D");
                if (invalidKey(delivFile)) sales.setNum("delivery-tag", 0);
            }
            if (delivBlank) sales.setNum("delivery-tag", 0);
            else {
                validateAddress(address());
                if (!truth) { display(10, 66, SL101, 4); errorFlag = 1; } else eraseEol(10, 66);
                if (!address().isBlank()) sales.setNum("delivery-tag", 1);
            }
            if (notes().isBlank() && sales.intv("notes-tag") != 0) {
                deleteDeliv("N");
                if (invalidKey(delivFile)) sales.setNum("notes-tag", 0);
            }
            sales.setNum("notes-tag", notes().isBlank() ? 0 : 1);
            if (validateResponse(lateCharg)) { sales.setNum("sales-late", z); show(16, 19, " ".repeat(7)); }
            else { errorFlag = 1; display(16, 19, SL102, 4); }
            if (validateResponse(dunLetter)) { show(17, 19, " ".repeat(7)); sales.setNum("sales-dunning", z); }
            else { errorFlag = 1; display(17, 19, SL102, 4); }
            if (validateResponse(emailInv)) { show(18, 39, " "); sales.setNum("email-invoice", z); }
            else { errorFlag = 1; show(18, 39, "*", 4); }
            if (validateResponse(emailStat)) { show(18, 49, " "); sales.setNum("email-statement", z); }
            else { errorFlag = 1; show(18, 49, "*", 4); }
            if (validateResponse(emailLet)) { show(18, 59, " "); sales.setNum("email-letters", z); }
            else { errorFlag = 1; show(18, 59, "*", 4); }
        } while (errorFlag != 0);
    }

    private void validateAddress(String test) {
        test = pad(test, 96);
        char delim = pad(sys.str("sl-delim"), 1).charAt(0);
        int cnt = 0;
        for (int i = 0; i < 96; i++) if (test.charAt(i) == delim) cnt++;
        truth = !(cnt > 4 || cnt < 1);
        int before = test.indexOf(delim);
        if (before < 0) before = 96;
        if (before > 30) truth = false;
    }

    /** validate-response: Y/N 判定。z に 1/0 を返す。 */
    private boolean validateResponse(String reply) {
        reply = upper(reply);
        boolean ok = true;
        if (reply.equals("Y")) z = 1; else if (reply.equals("N")) z = 0; else ok = false;
        if (!ok) { maps99(18); maps99(15); accept(24, 79, 1); return false; }
        clearErrorLine24();
        return true;
    }

    /** accept-key。errorCode: 999 = 空入力、3 = 該当なし。 */
    private void acceptKey() {
        sales.set("sales-key", upper(accept(4, 17, 7)));
        errorCode = 0;
        if (s("sales-key").isBlank()) { errorCode = 999; return; }
        saveTag = 0; saveNotesTag = 0;
        salesFile.read(sales);
        if (invalidKey(salesFile)) { errorCode = 3; maps99(3); customerCode = " ".repeat(7); return; }
        clearErrorLine();
        customerCode = s("sales-key");
        if (sales.intv("delivery-tag") != 0) {
            deliv.set("deliv-sales-key", s("sales-key")); deliv.set("deliv-key-type", "D");
            delivFile.read(deliv);
            if (invalidKey(delivFile)) { sales.setNum("delivery-tag", 0); delivName = "record not found"; delivAddr1 = ""; delivAddr2 = ""; }
            else {
                delivName = deliv.str("deliv-name"); delivAddr1 = deliv.str("deliv-addr1"); delivAddr2 = deliv.str("deliv-addr2");
                saveTag = 1; sales.setNum("delivery-tag", 1);
            }
        }
        if (sales.intv("notes-tag") != 0) {
            deliv.set("deliv-sales-key", s("sales-key")); deliv.set("deliv-key-type", "N");
            delivFile.read(deliv);
            if (invalidKey(delivFile)) { sales.setNum("notes-tag", 0); notes1 = "Record Not Found"; notes2 = ""; }
            else { notes1 = deliv.str("deliv-addr1"); notes2 = deliv.str("deliv-addr2"); saveNotesTag = 1; sales.setNum("notes-tag", 1); }
        }
    }

    private void openIo() {
        salesFile.open(CobFile.Mode.IO);
        delivFile.open(CobFile.Mode.IO);
        if (!delivFile.status.equals("00")) {
            delivFile.close(); delivFile.open(CobFile.Mode.OUTPUT); delivFile.close(); delivFile.open(CobFile.Mode.IO);
        }
    }
    private void closeFiles() { salesFile.close(); delivFile.close(); }

    private void setDeliv(String type) {
        deliv.set("deliv-sales-key", s("sales-key")); deliv.set("deliv-key-type", type);
        if (type.equals("D")) { deliv.set("deliv-name", delivName); deliv.set("deliv-address", address()); }
        else { deliv.set("deliv-name", ""); deliv.set("deliv-address", notes()); }
    }

    private void setupCustomers() {
        openIo();
        while (true) {
            // customer-input
            notes1 = ""; notes2 = "";
            displayOutline();
            while (true) {
                // customer-accept
                customerNos = accept(4, 17, 6);
                if (customerNos.isBlank()) { closeFiles(); return; }
                customerNos = upper(customerNos);
                show(4, 17, customerNos);
                clearErrorLine();
                checkDigit = Maps09.checkDigit(customerNos);
                if (checkDigit < 0) continue;
                customerCode = customerNos + checkDigit;
                sales.set("sales-key", customerCode);
                salesFile.read(sales);
                if (!invalidKey(salesFile)) { maps99(5); customerDisplay(); continue; }
                break;
            }
            // customer-details
            if (menuReply == 1) show(4, 39, String.valueOf(checkDigit));
            show(21, 1, " ".repeat(30)); show(22, 1, " ".repeat(30)); show(23, 1, " ".repeat(30));
            initialize(sales); initialize(deliv);
            sales.set("sales-key", customerCode);
            sales.setNum("sales-late", sys.num("sl-charges"));
            sales.setNum("sales-dunning", sys.num("sl-dunning"));
            sales.setNum("sales-credit", sys.num("sl-credit"));
            sales.setNum("sales-discount", sys.num("sl-disc"));
            sales.setNum("sales-late-min", sys.num("sl-min"));
            sales.setNum("sales-late-max", sys.num("sl-max"));
            sales.setNum("sales-limit", sys.num("sl-limit"));
            sales.setNum("sales-create-date", sys.num("run-date"));
            sales.setNum("sales-status", 1);
            do {
                customerDisplay();
                customerData();
                escapeCode = "S";
                testEscape();
            } while (escapeCode.equals("B"));
            if (escapeCode.equals("Q")) { closeFiles(); return; }
            salesFile.write(sales);
            if (sales.intv("delivery-tag") != 0) { setDeliv("D"); delivFile.write(deliv); }
            if (sales.intv("notes-tag") != 0) { setDeliv("N"); delivFile.write(deliv); }
            initialize(sales); initialize(deliv);
        }
    }

    /** I/O エラー時のデバッグ表示（レガシーの invalid key 節）。 */
    private void ioDebug(String label, CobFile f) {
        display(23, 1, label);
        show(23, 20, f.status);
        show(23, 23, pad(fileStatMsg(f.status), 25));
        display(24, 1, "Note and hit return");
        accept(24, 20, 1);
        eraseEos(23, 1);
    }

    private void amendCustomer() {
        openIo();
        while (true) {
            displayOutline();
            do {
                acceptKey();
                if (errorCode == 999) { closeFiles(); return; }
            } while (customerCode.isBlank());
            saveTag = sales.intv("delivery-tag");
            saveNotesTag = sales.intv("notes-tag");
            int ei = sales.intv("email-invoice");
            if (ei != 0 && ei != 1) { sales.setNum("email-invoice", 0); sales.setNum("email-statement", 0); sales.setNum("email-letters", 0); }
            do {
                customerDisplay();
                customerData();
                escapeCode = "S";
                testEscape();
            } while (escapeCode.equals("B"));
            if (escapeCode.equals("Q")) continue;
            setDeliv("D");
            if (sales.intv("delivery-tag") != 0 && saveTag == 0) {
                delivFile.write(deliv);
                if (invalidKey(delivFile)) { ioDebug("write deliverytag ", delivFile); delivFile.rewrite(deliv); }
            } else if (sales.intv("delivery-tag") != 0) {
                delivFile.rewrite(deliv);
                if (invalidKey(delivFile)) ioDebug("rewrite deliverytag ", delivFile);
            }
            if (sales.intv("delivery-tag") == 0 && saveTag != 0) {
                delivFile.delete(deliv);
                if (invalidKey(delivFile)) ioDebug("Delete deliverytag ", delivFile);
            }
            setDeliv("N");
            if (sales.intv("notes-tag") != 0 && saveNotesTag == 0) {
                delivFile.write(deliv);
                if (invalidKey(delivFile)) ioDebug("write notes tag ", delivFile);
            } else if (sales.intv("notes-tag") != 0) {
                delivFile.rewrite(deliv);
                if (invalidKey(delivFile)) ioDebug("Rewrite notes tag ", delivFile);
            }
            if (sales.intv("notes-tag") == 0 && saveNotesTag != 0) {
                delivFile.delete(deliv);
                if (invalidKey(delivFile)) ioDebug("Delete notes tag ", delivFile);
            }
            salesFile.rewrite(sales);
            if (invalidKey(salesFile)) ioDebug("Rewrite Sales Rec ", salesFile);
        }
    }

    private void deleteCustomer() {
        salesFile.open(CobFile.Mode.IO); delivFile.open(CobFile.Mode.IO);
        input:
        while (true) {
            displayOutline();
            display(21, 59, "D> = Dormant");
            display(22, 59, "K> = Kill ");
            while (true) {
                acceptKey();
                if (errorCode == 999) break input;
                if (customerCode.isBlank()) continue;
                customerDisplay();
                escapeCode = "K";
                testEscape();
                if (escapeCode.equals("Q")) break input;
                if (sales.num("sales-current").signum() != 0 || sales.num("sales-unapplied").signum() != 0) { display(5, 1, SL109, 4); continue; }
                eraseEol(5, 1);
                if (escapeCode.equals("D")) { sales.setNum("sales-status", 0); salesFile.rewrite(sales); }
                if (!escapeCode.equals("K")) continue input;
                deleteDeliv("D");
                deleteDeliv("N");
                salesFile.delete(sales);
                break input;
            }
        }
        closeFiles();
    }

    private void displayCustomers() {
        delivFile.open(CobFile.Mode.INPUT);
        salesFile.open(CobFile.Mode.IO);
        do {
            displayOutline();
            do {
                acceptKey();
                if (errorCode == 999) { closeFiles(); return; }
            } while (customerCode.isBlank());
            customerDisplay();
            escapeCode = "S";
            testEscape();
            if (escapeCode.equals("T")) {
                // テスト用: 未消込残高・現在残高を直接修正（符号なし 9(9)v99）
                sales.setNum("sales-unapplied", acceptMoney(20, 17, 9, sales.num("sales-unapplied")));
                sales.setNum("sales-current", acceptMoney(21, 17, 9, sales.num("sales-current")));
                salesFile.rewrite(sales);
            }
        } while (!escapeCode.equals("Q"));
        closeFiles();
    }

    private static boolean opBad(String op) { return !(op.equals("L") || op.equals("G") || op.equals("E") || op.equals(" ")); }

    private void reportSelection() {
        salesFile.open(CobFile.Mode.INPUT); delivFile.open(CobFile.Mode.INPUT);
        custIn = ""; statusIn = creditOp = invoiceOp = averageOp = overdueOp = enterDateOp = " "; enterDateIn = ""; printOut = " ";
        creditIn = invoiceIn = averageIn = overdueIn = 0; wsEnterDate = 0;
        display03.display();
        while (true) {
            display03.accept();
            custIn = upper(custIn);
            customerIn = pad(custIn, 7);
            statusIn = upper(statusIn);
            if (!(statusIn.equals("L") || statusIn.equals("D") || statusIn.equals(" "))) continue;
            creditOp = upper(creditOp); if (opBad(creditOp)) continue;
            invoiceOp = upper(invoiceOp); if (opBad(invoiceOp)) continue;
            averageOp = upper(averageOp); if (opBad(averageOp)) continue;
            overdueOp = upper(overdueOp); if (opBad(overdueOp)) continue;
            enterDateOp = upper(enterDateOp); if (opBad(enterDateOp)) continue;
            if (enterDateIn.isBlank()) return;
            long bin = validateDate(enterDateIn);
            if (bin == 0) { display(23, 62, SL005, 4); continue; }
            eraseEol(23, 62);
            wsEnterDate = bin;
            return;
        }
    }

    private boolean testNum(long test1, long test2, String op) {
        boolean t = op.equals(" ");
        if (op.equals("L") && test2 < test1) t = true;
        if (op.equals("G") && test2 > test1) t = true;
        if (op.equals("E") && test2 == test1) t = true;
        return t;
    }

    private String line1() { return pad(PROG_NAME, 57) + pad("Customer Listing", 67) + "Page " + Num.edit(a, "zz9"); }
    private String line3() { return pad(l3User, 40) + "Report On : " + pad(l3Report, 70) + pad(l3Date, 10); }
    private static final String LINE4 = pad("Customer  Status    <---------------Name & Address-------------->     ----Telephone"
        + "---- -----Fax-----     Late       Credit", 127) + " Disc";
    private static final String LINE5 = " " + pad("Number   ------", 103) + pad("Chg  Let   Limit/Days    %", 28);

    private void headings() {
        a = (a + 1) % 1000;
        if (a != 1) { print.afterPage(line1()); print.after(line3(), 1); print.after("", 1); }
        else { print.before(line1(), 1); print.before(line3(), 1); }
        print.after(LINE4, 1);
        print.after(LINE5, 1);
        print.after("", 1);
        lineCnt = 6;
    }

    private String line6(String key, String status, String name, String phone, String fax, String charges, String letter,
                         long limit, long credit, BigDecimal discount) {
        return pad(key, 10) + pad(status, 10) + pad(name, 50) + pad(phone, 18) + pad(fax, 13) + "    " + pad(charges, 5) + pad(letter, 3)
            + (limit == 0 ? " ".repeat(7) : Num.edit(limit, "z(6)9"))
            + (credit == 0 ? " ".repeat(7) : Num.edit(credit, "zzz9") + "   ")
            + (discount.signum() == 0 ? " ".repeat(5) : Num.edit(discount, "z9.99"));
    }

    private void listing() {
        int pageLines = sys.intv("page-lines");
        if (lineCnt > pageLines) headings();
        String delim = pad(sys.str("sl-delim"), 1);
        String l7 = pad(s("sales-address"), 112).replace(delim, ",");
        String phone;
        if (s("sales-ext").isBlank()) phone = s("sales-phone");
        else {
            StringBuilder sb = new StringBuilder(" ".repeat(18));
            y = stringInto(sb, 1, delimited(s("sales-phone"), "  "));
            y = y - 1;
            y = stringInto(sb, y, "x" + s("sales-ext"));
            phone = sb.toString();
        }
        if (lineCnt > pageLines - 5) headings();
        print.after(line6(s("sales-key"), sales.intv("sales-status") == 1 ? "Active" : "Dormant", s("sales-name"), phone, s("sales-fax"),
            sales.intv("sales-late") == 1 ? "Y" : " ", sales.intv("sales-dunning") == 1 ? "Y" : " ",
            sales.longv("sales-limit"), sales.longv("sales-credit"), sales.num("sales-discount")), 1);
        print.after(" ".repeat(20) + l7, 1);
        if (sales.intv("delivery-tag") > 0) {
            deliv.set("deliv-key-type", "D"); deliv.set("deliv-sales-key", s("sales-key"));
            delivFile.read(deliv);
            if (invalidKey(delivFile)) deliv.set("deliv-name", "Record Not Found");
            String l7d = pad(deliv.str("deliv-address"), 112);
            if (!deliv.str("deliv-name").stripTrailing().equals("Record Not Found")) l7d = l7d.replace(delim, ",");
            print.after(line6("   Deliver", "y Address", deliv.str("deliv-name"), "", "", "", "", 0, 0, BigDecimal.ZERO), 1);
            print.after(" ".repeat(20) + l7d, 1);
            lineCnt += 2;
        }
        if (sales.intv("notes-tag") > 0) {
            deliv.set("deliv-key-type", "N"); deliv.set("deliv-sales-key", s("sales-key"));
            delivFile.read(deliv);
            if (invalidKey(delivFile)) deliv.set("deliv-address", "Record Not Found");
            print.after(" ".repeat(20) + pad("Notes: " + delimited(deliv.str("deliv-address"), "  "), 112), 1);
            lineCnt += 1;
        }
        print.after("", 1);
        lineCnt += 3;
        printOut = "Y";
    }

    private void produceReport() {
        print.openOutput();
        a = 0;
        headings();
        boolean end = false;
        if (!customerIn.isBlank()) {
            sales.set("sales-key", customerIn);
            salesFile.start(sales, ">=");
            if (invalidKey(salesFile)) { a = 1; end = true; }
            customerIn = customerIn.replace(' ', 'Z');
        }
        while (!end) {
            salesFile.readNext(sales);
            if (!salesFile.status.equals("00")) break;
            int status = sales.intv("sales-status");
            if (statusIn.equals("L") && status == 0) continue;
            if (statusIn.equals("D") && status == 1) continue;
            if (!customerIn.isBlank() && s("sales-key").compareTo(customerIn) > 0) break;
            if (!creditOp.equals(" ") && !testNum(creditIn, sales.longv("sales-credit"), creditOp)) continue;
            if (!invoiceOp.equals(" ") && !testNum(invoiceIn, sales.longv("sales-activety"), invoiceOp)) continue;
            if (!averageOp.equals(" ") && !testNum(averageIn, sales.longv("sales-average"), averageOp)) continue;
            if (!overdueOp.equals(" ") && sales.num("sales-current").signum() > 0
                && !testNum(overdueIn, sys.longv("run-date") - sales.longv("sales-last-inv"), overdueOp)) continue;
            if (!enterDateOp.equals(" ") && !testNum(wsEnterDate, sales.longv("sales-create-date"), enterDateOp)) continue;
            listing();
        }
        print.close();
        if (printOut.equals("Y")) spoolReport("prt-1", sys.str("print-spool-name"), true);
    }

    private static String opSign(String op, String cur) { return switch (op) { case "L" -> "< "; case "G" -> "> "; case "E" -> "= "; default -> cur; }; }
    private String crOperand = "  ", actOperand = "  ", avOperand = "  ", ovOperand = "  ", edOperand = "  ";

    private void reportHeadingSetup() {
        l3Date = fromUk(toDay());
        l3User = sys.str("usera");
        StringBuilder r = new StringBuilder(" ".repeat(70));
        y = (y + 1) % 100;
        boolean all = statusIn.isBlank() && creditOp.isBlank() && invoiceOp.isBlank() && averageOp.isBlank() && overdueOp.isBlank() && customerIn.isBlank();
        y = stringInto(r, y, all ? "All" : "Matched");
        y++;
        if (statusIn.equals("L")) y = stringInto(r, y, "Live");
        if (statusIn.equals("D")) y = stringInto(r, y, "Dormant");
        y++;
        crOperand = opSign(creditOp, crOperand);
        if (!creditOp.equals(" ")) y = stringInto(r, y, crOperand + Num.edit(creditIn, "z9") + " Days Credit");
        y++;
        actOperand = opSign(invoiceOp, actOperand);
        if (!invoiceOp.equals(" ")) y = stringInto(r, y, actOperand + Num.edit(invoiceIn, "zzzz9") + " Invoices");
        y++;
        avOperand = opSign(averageOp, avOperand);
        if (!averageOp.equals(" ")) y = stringInto(r, y, avOperand + Num.edit(averageIn, "zzzz9") + " Av. Value");
        y++;
        ovOperand = opSign(overdueOp, ovOperand);
        if (!overdueOp.equals(" ")) y = stringInto(r, y, ovOperand + Num.edit(overdueIn, "zzzz9") + " Days Overdue");
        y++;
        edOperand = opSign(enterDateOp, edOperand);
        if (!enterDateOp.equals(" ")) y = stringInto(r, y, edOperand + pad(enterDateIn, 10) + " Entry Date");
        y++;
        if (!customerIn.isBlank()) y = stringInto(r, y, " Keys Matching - " + customerIn);
        y %= 100;
        l3Report = r.toString();
    }

    /** slcreate: 売掛ファイルの初期作成。false は中止（exit program）。 */
    private boolean slcreate() {
        String reply;
        do {
            displayHeading();
            display(12, 1, SL103, 4);
            display(13, 1, SL104);
            reply = upper(term().accept(13, 43, 1, " ", 0, 6));
            if (reply.equals("N")) return false;
        } while (!reply.equals("Y"));
        display(15, 6, SL105);
        salesFile.open(CobFile.Mode.OUTPUT);
        if (!salesFile.status.equals("00")) {
            eraseEol(12, 1); display(12, 1, SL106); show(12, 34, salesFile.status); display(12, 37, SL004);
            salesFile.close(); return true;
        }
        delivFile.open(CobFile.Mode.OUTPUT);
        if (!delivFile.status.equals("00")) {
            eraseEol(12, 1); display(12, 1, SL107); show(12, 37, delivFile.status); display(12, 40, SL004);
            delivFile.close(); return true;
        }
        closeFiles();
        sys.setNum("file-status", 1, 12); sys.setNum("file-status", 1, 14);
        sys.set("sales-ledger", "Y");
        return true;
    }
}
