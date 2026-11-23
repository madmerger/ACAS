package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;
import jp.co.acas.sys.Maps09;

import java.math.BigDecimal;
import java.util.List;

/** pl010.cbl: 仕入先ファイルの登録・保守。 */
public class Pl010 extends PlBase {
    static final String PROG_NAME = "PL010 (3.01.13)";
    private int menuReply;
    private Rec purch, deliv;
    private CobFile purchaseFile, deliveryFile;
    private String notes1 = "", notes2 = "";
    private String d2402 = " ", d2403 = " ", d24check = "";
    private String escapeCode = " ", customerCode = "";
    private int errorCode, saveNotesTag;
    private String printOut = " ";
    // 帳票条件
    private String custIn, statusIn, creditOp, invoiceOp, averageOp, overdueOp, enterDateOp, enterDateIn, customerIn;
    private int creditIn, invoiceIn, averageIn, overdueIn;
    private long wsEnterDate;
    private String l3report = "";
    private Printer prt;
    private int page, lineCnt;

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        purch = purchRec(); deliv = delivRec();
        purchaseFile = purchaseFile(purch); deliveryFile = deliveryFile(deliv);
        printOut = " ";
        if (!sys.str("purchase-ledger").equals("Y")) {
            if (!plcreate()) return;
        }
        while (true) {
            menuReply = 0;
            displayHeading();
            while (true) {
                display(7, 1, "Select one of the following by number :- [ ]");
                display(10, 4, "(1)  Set-up Supplier records");
                display(12, 4, "(2)  Amend Supplier records");
                display(14, 4, "(3)  Delete Supplier records");
                display(16, 4, "(4)  Print Supplier records");
                display(18, 4, "(5)  Display Supplier records");
                display(21, 4, "(9)  Return to system menu");
                menuReply = digit(acceptUpdate(7, 43, 1, "0", AUTO));
                if (menuReply == 9) return;
                if (menuReply >= 1 && menuReply <= 5) break;
            }
            switch (menuReply) {
                case 1 -> setupSuppliers();
                case 2 -> amendSupplier();
                case 3 -> deleteSupplier();
                case 4 -> reportSupplier();
                default -> displaySuppliers();
            }
        }
    }

    static int digit(String s) {
        s = s.trim();
        return s.length() == 1 && Character.isDigit(s.charAt(0)) ? s.charAt(0) - '0' : 0;
    }

    private void clearErrorLine() { eraseEol(23, 1); }

    private void testEscape() {
        show(20, 71, escapeCode, 6);
        while (true) {
            escapeCode = upper(acceptUpdate(20, 71, 1, escapeCode));
            if ("BSQKD".contains(escapeCode) && !escapeCode.isBlank()) return;
        }
    }

    private void displayHeading() {
        clearScreen();
        d2402 = " "; d24check = "";
        d2403 = "]";
        if (menuReply != 4) {
            display(1, 1, PROG_NAME);
            show(1, 71, fromUk(toDay()), 2);
        }
        switch (menuReply) {
            case 0 -> {
                display(1, 24, "Supplier File Set-Up & Maintenance");
                display(4, 34, "Function  Menu");
            }
            case 1 -> {
                display(1, 29, "Supplier Record Creation");
                d24check = "Check Digit { }";
                d2402 = "]"; d2403 = " ";
            }
            case 2 -> display(1, 29, "Supplier Record Amendment");
            case 3 -> display(1, 29, "Supplier Record Deletion");
            case 5 -> display(1, 29, "Supplier Record Display");
            default -> { }
        }
    }

    /** display display-02（固定文言と項目値）。 */
    private void display02() {
        display(4, 1, "Supplier Nos : [");
        show(4, 23, d2402, 2);
        show(4, 24, d2403, 2);
        if (d24check.isBlank()) show(4, 26, pad("", 15), 2);
        else { display(4, 26, "Check Digit {"); show(4, 39, d24check.substring(13, 14), 2); display(4, 40, "}"); }
        display(6, 1, "Supplier Name: [");
        show(6, 17, purch.str("purch-name"), 2);
        display(6, 47, "]");
        display(7, 10, "Addr: [");
        show(7, 17, purch.str("purch-addr1"), 2);
        display(7, 65, "]");
        display(8, 16, "[");
        show(8, 17, purch.str("purch-addr2"), 2);
        display(8, 65, "]");
        display(9, 1, "Suppliers Bank Details");
        display(10, 3, "Sort Code  : [");
        show(10, 17, Num.z9(purch.longv("purch-sortcode"), 6), 2);
        display(10, 23, "]");
        display(11, 3, "Account No : [");
        show(11, 17, Num.z9(purch.longv("purch-accountno"), 8), 2);
        display(11, 25, "]");
        display(12, 1, "Supplier Note: [");
        show(12, 17, pad(notes1, 48), 2);
        if (notes1.equals("Record Not Found")) display(12, 17, notes1);
        display(12, 65, "]");
        display(13, 16, "[");
        show(13, 17, pad(notes2, 48), 2);
        display(13, 65, "]");
        display(14, 1, "Telephone    : [");
        show(14, 17, purch.str("purch-phone"), 2);
        display(14, 30, "]");
        display(14, 32, "Ext: [");
        show(14, 38, purch.str("purch-ext"), 2);
        display(14, 42, "]");
        display(14, 45, "Fax : [");
        show(14, 52, purch.str("purch-fax"), 2);
        display(14, 65, "]");
        display(15, 1, "Email Sales  : [");
        show(15, 17, purch.str("purch-email"), 2);
        display(15, 47, "]");
        display(18, 1, "Credit Period: [");
        show(18, 17, Num.z9(purch.intv("purch-credit"), 2), 2);
        display(18, 19, "]");
        display(19, 1, "Credit limit : [");
        show(19, 17, Num.z9(purch.longv("purch-limit"), 7), 2);
        display(19, 24, "] Discount : [");
        show(19, 38, disc(purch.num("purch-discount")), 2);
        display(19, 43, "]");
        display(19, 56, "*******************");
        display(20, 1, "Unapplied Bal: {");
        display(20, 29, "}");
        display(20, 56, "* Escape Code [");
        display(20, 72, "] *");
        display(21, 1, "Current Bal  : {");
        display(21, 29, "}");
        display(21, 56, "* <B> = Back      *");
        display(22, 1, "Last invoice : {");
        display(22, 27, "}");
        display(22, 56, "* <S> = Save      *");
        display(23, 1, "Last payment : {");
        display(23, 27, "}");
        display(23, 56, "* <Q> = Quit      *");
        display(24, 56, "*******************");
    }

    static String disc(BigDecimal v) {
        long c = v.movePointRight(2).longValue() % 10000;
        return Num.z9(c / 100, 2) + "." + Num.z9(c % 100, 2);
    }

    static String bal(BigDecimal v) { return String.format("%12s", v.setScale(2, java.math.RoundingMode.DOWN).toPlainString()); }

    static long digits(String s) {
        String d = s.replaceAll("[^0-9]", "");
        return d.isEmpty() ? 0 : Long.parseLong(d);
    }

    private void customerDisplay() {
        String k7 = purch.str("purch-key").substring(6, 7);
        if (menuReply == 1) d24check = "Check Digit {" + k7 + "}";
        else d2402 = k7;
        display02();
        if (menuReply == 1 || menuReply == 2) return;
        show(20, 17, bal(purch.num("purch-unapplied")));
        show(21, 17, bal(purch.num("purch-current")));
        if (purch.longv("purch-last-inv") != 0) show(22, 17, binToDate(purch.longv("purch-last-inv")));
        if (purch.longv("purch-last-pay") != 0) show(23, 17, binToDate(purch.longv("purch-last-pay")));
    }

    private void displayOutline() {
        displayHeading();
        initialize(purch); initialize(deliv);
        notes1 = ""; notes2 = "";
        display02();
    }

    private void customerData() {
        while (true) {
            int errorFlag = 0;
            display02();
            Terminal.Field name = afield(6, 17, 30, purch.str("purch-name")),
                    a1 = afield(7, 17, 48, purch.str("purch-addr1")),
                    a2 = afield(8, 17, 48, purch.str("purch-addr2")),
                    sort = field(10, 17, 6, Num.z9(purch.longv("purch-sortcode"), 6)),
                    acc = field(11, 17, 8, Num.z9(purch.longv("purch-accountno"), 8)),
                    n1 = afield(12, 17, 48, notes1), n2 = afield(13, 17, 48, notes2),
                    phone = afield(14, 17, 13, purch.str("purch-phone")),
                    ext = afield(14, 38, 4, purch.str("purch-ext")),
                    fax = afield(14, 52, 13, purch.str("purch-fax")),
                    email = afield(15, 17, 30, purch.str("purch-email")),
                    credit = field(18, 17, 2, Num.z9(purch.intv("purch-credit"), 2)),
                    limit = field(19, 17, 7, Num.z9(purch.longv("purch-limit"), 7)),
                    discount = field(19, 38, 5, disc(purch.num("purch-discount")));
            acceptScreen(List.of(name, a1, a2, sort, acc, n1, n2, phone, ext, fax, email, credit, limit, discount));
            purch.set("purch-name", aval(name));
            purch.set("purch-addr1", aval(a1));
            purch.set("purch-addr2", aval(a2));
            purch.setNum("purch-sortcode", digits(sort.value));
            purch.setNum("purch-accountno", digits(acc.value));
            notes1 = aval(n1); notes2 = aval(n2);
            purch.set("purch-phone", aval(phone));
            purch.set("purch-ext", aval(ext));
            purch.set("purch-fax", aval(fax));
            purch.set("purch-email", aval(email));
            purch.setNum("purch-credit", digits(credit.value));
            purch.setNum("purch-limit", digits(limit.value));
            purch.setNum("purch-discount", Num.parse(discount.value.trim().isEmpty() ? "0" : discount.value.trim()));
            if (!validateAddress(pad(purch.str("purch-address"), 92))) {
                display(7, 66, "PL101 Addr Err", 4);
                errorFlag = 1;
            } else eraseEol(7, 66);
            boolean notesBlank = (notes1 + notes2).isBlank();
            if (notesBlank && purch.intv("purch-notes-tag") != 0) {
                deliv.set("deliv-purchase-key", purch.str("purch-key"));
                deliv.set("deliv-key-type", "N");
                if (!deliveryFile.delete(deliv).equals("00")) purch.setNum("purch-notes-tag", 0);
            }
            purch.setNum("purch-notes-tag", notesBlank ? 0 : 1);
            if (errorFlag == 0) return;
        }
    }

    private boolean validateAddress(String test) {
        String d = sys.str("pl-delim");
        int a = 0;
        for (int i = 0; i < test.length(); i++) if (test.startsWith(d, i)) a++;
        boolean truth = !(a > 4 || a < 1);
        int b = test.indexOf(d);
        if (b < 0) b = test.length();
        if (b > 30) truth = false;
        return truth;
    }

    private void acceptKey() {
        purch.set("purch-key", upper(accept(4, 17, 7)));
        errorCode = 0;
        if (purch.str("purch-key").isBlank()) { errorCode = 999; return; }
        saveNotesTag = 0;
        if (!purchaseFile.read(purch).equals("00")) {
            errorCode = 3;
            maps99(3);
            customerCode = "";
            return;
        }
        clearErrorLine();
        customerCode = purch.str("purch-key");
        if (purch.intv("purch-notes-tag") != 0) {
            deliv.set("deliv-purchase-key", purch.str("purch-key"));
            deliv.set("deliv-key-type", "N");
            if (!deliveryFile.read(deliv).equals("00")) {
                purch.setNum("purch-notes-tag", 0);
                notes1 = "Record Not Found"; notes2 = "";
            } else {
                notes1 = deliv.str("deliv-addr1"); notes2 = deliv.str("deliv-addr2");
                saveNotesTag = 1;
                purch.setNum("purch-notes-tag", 1);
            }
        }
    }

    private void openIo() {
        purchaseFile.open(Mode.IO);
        if (!deliveryFile.open(Mode.IO).equals("00")) {
            deliveryFile.close();
            deliveryFile.open(Mode.OUTPUT);
            deliveryFile.close();
            deliveryFile.open(Mode.IO);
        }
    }

    private void closeFiles() { purchaseFile.close(); deliveryFile.close(); }

    private void setupSuppliers() {
        openIo();
        input:
        while (true) {
            notes1 = ""; notes2 = "";
            displayOutline();
            String nos;
            while (true) {
                nos = accept(4, 17, 6);
                if (nos.isBlank()) break input;
                nos = upper(nos);
                show(4, 17, nos);
                clearErrorLine();
                int cd = Maps09.checkDigit(nos);
                if (cd < 0) continue;
                customerCode = nos + cd;
                purch.set("purch-key", customerCode);
                if (purchaseFile.read(purch).equals("00")) {
                    maps99(22);
                    customerDisplay();
                    continue;
                }
                show(4, 44, String.valueOf(cd));
                break;
            }
            show(21, 6, pad("", 30)); show(22, 6, pad("", 30)); show(23, 6, pad("", 30));
            initialize(purch); initialize(deliv);
            purch.setNum("purch-status", 1);
            purch.set("purch-key", customerCode);
            purch.setNum("purch-create-date", sys.longv("run-date"));
            purch.setNum("purch-credit", sys.intv("age-to-pay"));
            do {
                customerDisplay();
                customerData();
                escapeCode = "S";
                testEscape();
            } while (escapeCode.equals("B"));
            if (escapeCode.equals("Q")) break;
            purchaseFile.write(purch);
            if (purch.intv("purch-notes-tag") != 0) {
                deliv.set("deliv-purchase-key", purch.str("purch-key"));
                deliv.set("deliv-key-type", "N");
                deliv.set("deliv-name", "");
                deliv.set("deliv-addr1", notes1); deliv.set("deliv-addr2", notes2);
                deliveryFile.write(deliv);
            }
            initialize(purch); initialize(deliv);
        }
        closeFiles();
    }

    private void noteAndReturn(String what, CobFile f) {
        display(23, 1, what);
        show(23, 20, f.status);
        display(24, 1, "Note and hit return");
        accept(24, 20, 1);
        eraseEos(23, 1);
    }

    private void amendSupplier() {
        openIo();
        input:
        while (true) {
            displayOutline();
            while (true) {
                acceptKey();
                if (errorCode == 999) break input;
                if (!customerCode.isBlank()) break;
            }
            saveNotesTag = purch.intv("purch-notes-tag");
            do {
                customerDisplay();
                customerData();
                escapeCode = "S";
                testEscape();
            } while (escapeCode.equals("B"));
            if (escapeCode.equals("Q")) continue;
            purchaseFile.rewrite(purch);
            deliv.set("deliv-key-type", "N");
            deliv.set("deliv-purchase-key", purch.str("purch-key"));
            deliv.set("deliv-name", "");
            deliv.set("deliv-addr1", notes1); deliv.set("deliv-addr2", notes2);
            int tag = purch.intv("purch-notes-tag");
            if (tag != 0 && saveNotesTag == 0) {
                if (!deliveryFile.write(deliv).equals("00")) noteAndReturn("write notes tag ", deliveryFile);
            } else if (tag != 0) {
                if (!deliveryFile.rewrite(deliv).equals("00")) noteAndReturn("Rewrite notes tag ", deliveryFile);
            }
            if (tag == 0 && saveNotesTag != 0) {
                if (!deliveryFile.delete(deliv).equals("00")) noteAndReturn("Delete notes tag ", deliveryFile);
            }
            if (!purchaseFile.rewrite(purch).equals("00")) noteAndReturn("Rewrite Sales Rec ", purchaseFile);
        }
        closeFiles();
    }

    private void deleteSupplier() {
        purchaseFile.open(Mode.IO); deliveryFile.open(Mode.IO);
        input:
        while (true) {
            displayOutline();
            display(21, 59, "D> = Dormant");
            display(22, 59, "K> = Kill   ");
            while (true) {
                acceptKey();
                if (errorCode == 999) break input;
                if (customerCode.isBlank()) continue;
                customerDisplay();
                escapeCode = "K";
                testEscape();
                if (escapeCode.equals("Q")) break input;
                if (purch.num("purch-current").signum() != 0 || purch.num("purch-unapplied").signum() != 0) {
                    display(5, 1, "PL109 <<<Can not Delete currently active account>>>", 4);
                    continue;
                }
                break;
            }
            eraseEol(5, 1);
            if (escapeCode.equals("D")) {
                purch.setNum("purch-status", 0);
                purchaseFile.rewrite(purch);
            }
            if (!escapeCode.equals("K")) continue;
            if (purch.intv("purch-notes-tag") != 0) deliv.set("deliv-key-type", "N");
            deliv.set("deliv-purchase-key", purch.str("purch-key"));
            deliveryFile.delete(deliv);
            purchaseFile.delete(purch);
            break;
        }
        closeFiles();
    }

    private void displaySuppliers() {
        purchaseFile.open(Mode.INPUT); deliveryFile.open(Mode.INPUT);
        input:
        while (true) {
            displayOutline();
            while (true) {
                acceptKey();
                if (errorCode == 999) break input;
                if (!customerCode.isBlank()) break;
            }
            customerDisplay();
            escapeCode = "S";
            testEscape();
            // 原文は ws-reply（未設定）を "Q" と比較するため常に次の照会へ戻る
        }
        closeFiles();
    }

    // ---------------- 帳票 ----------------

    private void display03(boolean values) {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 34, "Supplier File");
        show(1, 71, fromUk(toDay()), 2);
        display(3, 32, "Report Attributes");
        display(8, 3, "Supplier Number - [");
        display(8, 28, "]");
        display(8, 33, "Enter characters in positions to match");
        display(10, 3, "Status          - [");
        display(10, 23, "]");
        display(10, 33, "<L> Live;<D> Dormant;< > All");
        display(12, 3, "Credit Period   - [");
        display(12, 24, "]  [");
        display(12, 29, "]");
        display(12, 33, "Enter number of days & operator");
        display(13, 37, "<L>  for credit periods < than");
        display(14, 37, "<G>  for credit periods > than");
        display(15, 37, "<E>  for credit periods = to");
        display(17, 3, "Invoice Activity  [");
        display(17, 27, "] [");
        display(17, 31, "]");
        display(17, 33, "Enter number of invoices & operator");
        display(19, 3, "Average Value   - [");
        display(19, 27, "] [");
        display(19, 31, "]");
        display(19, 33, "Enter invoice value & operator");
        display(21, 3, "Overdue A/Cs    - [");
        display(21, 27, "] [");
        display(21, 31, "]");
        display(21, 33, "Enter number of days & operator");
        display(23, 3, "Date Entered-[");
        display(23, 27, "] [");
        display(23, 31, "]");
        display(23, 33, "Enter date & operator");
    }

    private static boolean op(String s) { return s.equals("L") || s.equals("G") || s.equals("E") || s.equals(" "); }

    private void reportSupplier() {
        // report-selection
        purchaseFile.open(Mode.INPUT); deliveryFile.open(Mode.INPUT);
        custIn = pad("", 6); statusIn = creditOp = invoiceOp = averageOp = overdueOp = enterDateOp = " ";
        enterDateIn = pad("", 10); printOut = " ";
        creditIn = invoiceIn = averageIn = overdueIn = 0; wsEnterDate = 0;
        display03(true);
        while (true) {
            Terminal.Field fCust = afield(8, 22, 6, custIn), fStatus = afield(10, 22, 1, statusIn),
                    fCredit = field(12, 22, 2, Num.z9(creditIn, 2)), fCreditOp = afield(12, 28, 1, creditOp),
                    fInv = field(17, 22, 5, Num.z9(invoiceIn, 5)), fInvOp = afield(17, 30, 1, invoiceOp),
                    fAvg = field(19, 22, 5, Num.z9(averageIn, 5)), fAvgOp = afield(19, 30, 1, averageOp),
                    fOvd = field(21, 22, 5, Num.z9(overdueIn, 5)), fOvdOp = afield(21, 30, 1, overdueOp),
                    fDate = afield(23, 17, 10, enterDateIn), fDateOp = afield(23, 30, 1, enterDateOp);
            acceptScreen(List.of(fCust, fStatus, fCredit, fCreditOp, fInv, fInvOp, fAvg, fAvgOp, fOvd, fOvdOp, fDate, fDateOp));
            custIn = upper(aval(fCust));
            customerIn = pad(custIn, 7);
            statusIn = upper(aval(fStatus));
            creditIn = (int) digits(fCredit.value); invoiceIn = (int) digits(fInv.value);
            averageIn = (int) digits(fAvg.value); overdueIn = (int) digits(fOvd.value);
            creditOp = upper(aval(fCreditOp)); invoiceOp = upper(aval(fInvOp)); averageOp = upper(aval(fAvgOp));
            overdueOp = upper(aval(fOvdOp)); enterDateOp = upper(aval(fDateOp)); enterDateIn = aval(fDate);
            if (!statusIn.equals("L") && !statusIn.equals("D") && !statusIn.equals(" ")) continue;
            if (!op(creditOp) || !op(invoiceOp) || !op(averageOp) || !op(overdueOp) || !op(enterDateOp)) continue;
            if (enterDateIn.isBlank()) break;
            long bin = validateDate(enterDateIn);
            if (bin == 0) { display(23, 62, "PL005 Invalid Date", 4); continue; }
            eraseEol(23, 62);
            wsEnterDate = bin;
            break;
        }
        reportHeadingSetup();
        produceReport();
        closeFiles();
    }

    private static String z(long v, int width) { return String.format("%" + width + "d", v); }

    private void reportHeadingSetup() {
        StringBuilder r = new StringBuilder();
        boolean all = statusIn.isBlank() && creditOp.isBlank() && invoiceOp.isBlank() && averageOp.isBlank()
                && overdueOp.isBlank() && customerIn.isBlank();
        r.append(all ? "All" : "Matched").append(' ');
        if (statusIn.equals("L")) r.append("Live");
        if (statusIn.equals("D")) r.append("Dormant");
        r.append(' ');
        if (!creditOp.isBlank()) r.append(opnd(creditOp)).append(z(creditIn, 2)).append(" Days Credit");
        r.append(' ');
        if (!invoiceOp.isBlank()) r.append(opnd(invoiceOp)).append(z(invoiceIn, 5)).append(" Invoices");
        r.append(' ');
        if (!averageOp.isBlank()) r.append(opnd(averageOp)).append(z(averageIn, 5)).append(" Av. Value");
        r.append(' ');
        if (!overdueOp.isBlank()) r.append(opnd(overdueOp)).append(z(overdueIn, 5)).append(" Days Overdue");
        r.append(' ');
        if (!enterDateOp.isBlank()) r.append(opnd(enterDateOp)).append(pad(enterDateIn, 8)).append(" Entry Date");
        r.append(' ');
        if (!customerIn.isBlank()) r.append(" Keys Matching - ").append(customerIn);
        l3report = pad(r.toString(), 70);
    }

    private static String opnd(String op) { return switch (op) { case "L" -> "< "; case "G" -> "> "; default -> "= "; }; }

    private void headings() {
        page++;
        String line1 = pad(PROG_NAME, 57) + pad("Supplier Listing", 67) + "Page " + z(page, 3);
        String line3 = pad(sys.str("usera"), 40) + "Report On : " + l3report + fromUk(toDay());
        if (page != 1) {
            prt.afterPage(line1);
            prt.after(line3, 1);
            prt.after("", 1);
        } else {
            prt.before(line1, 1);
            prt.before(line3, 1);
        }
        prt.after("Supplier  Status    <----------------Name & Address---------------->   ----Telephone---- -----Fax-----"
                + "    ----Credit----   Discount ", 1);
        prt.after(pad(" Number   ------", 87) + "                   Limit   Period       %", 1);
        prt.after("", 1);
        lineCnt = 6;
    }

    private boolean testNum(long t1, long t2, String op) {
        if (op.equals(" ")) return true;
        return op.equals("L") && t2 < t1 || op.equals("G") && t2 > t1 || op.equals("E") && t2 == t1;
    }

    private static String bwz(BigDecimal v, int width, int scale) {
        if (v.signum() == 0) return pad("", width);
        return String.format("%" + width + "s", v.setScale(scale, java.math.RoundingMode.DOWN).toPlainString());
    }

    private void produceReport() {
        prt = new Printer("prt-1");
        page = 0;
        headings();
        boolean eof = false;
        if (!customerIn.isBlank()) {
            purch.set("purch-key", customerIn);
            if (!purchaseFile.start(purch, ">=").equals("00")) page = 1;
            customerIn = customerIn.replace(' ', 'Z');
        }
        int pageLines = sys.intv("page-lines");
        while (!eof) {
            if (!purchaseFile.readNext(purch).equals("00")) break;
            int status = purch.intv("purch-status");
            if (statusIn.equals("L") && status == 0) continue;
            if (statusIn.equals("D") && status == 1) continue;
            if (!customerIn.isBlank() && purch.str("purch-key").compareTo(customerIn) > 0) break;
            if (!creditOp.isBlank() && !testNum(creditIn, purch.intv("purch-credit"), creditOp)) continue;
            if (!invoiceOp.isBlank() && !testNum(invoiceIn, purch.longv("purch-activety"), invoiceOp)) continue;
            if (!averageOp.isBlank() && !testNum(averageIn, purch.longv("purch-average"), averageOp)) continue;
            if (!overdueOp.isBlank() && purch.num("purch-current").signum() > 0
                    && !testNum(overdueIn, sys.longv("run-date") - purch.longv("purch-last-inv"), overdueOp)) continue;
            if (!enterDateOp.isBlank() && !testNum(wsEnterDate, purch.longv("purch-create-date"), enterDateOp)) continue;
            // listing
            if (lineCnt > pageLines) headings();
            String phone;
            if (purch.str("purch-ext").isBlank()) phone = purch.str("purch-phone");
            else {
                String p = purch.str("purch-phone");
                int sp = p.indexOf(' ');
                if (sp >= 0) p = p.substring(0, sp);
                // 原文は pointer を 1 戻すため電話番号の末尾 1 桁が "x" で上書きされる
                phone = (p.isEmpty() ? "" : p.substring(0, p.length() - 1)) + "x" + purch.str("purch-ext");
                if (p.isEmpty()) phone = purch.str("purch-phone");
            }
            String line6 = pad(purch.str("purch-key"), 10) + pad(status == 1 ? "Active" : "Dormant", 10)
                    + pad(purch.str("purch-name"), 51) + pad(phone, 18) + pad(purch.str("purch-fax"), 13)
                    + bwz(BigDecimal.valueOf(purch.longv("purch-limit")), 9, 0)
                    + bwz(BigDecimal.valueOf(purch.intv("purch-credit")), 8, 0)
                    + bwz(purch.num("purch-discount"), 11, 2);
            String line7 = pad("", 20) + pad(purch.str("purch-address"), 112).replace(sys.str("sl-delim"), ",");
            if (lineCnt > pageLines - 3) headings();
            prt.after(line6, 1);
            prt.after(line7, 1);
            if (purch.intv("purch-notes-tag") > 0) {
                deliv.set("deliv-key-type", "N");
                deliv.set("deliv-purchase-key", purch.str("purch-key"));
                if (!deliveryFile.read(deliv).equals("00")) deliv.set("deliv-address", "Record Not Found");
                String a = deliv.str("deliv-address");
                int sp = a.indexOf(' ');
                if (sp >= 0) a = a.substring(0, sp);
                prt.after(pad("", 20) + "Notes: " + a, 1);
                lineCnt++;
            }
            prt.after("", 1);
            lineCnt += 3;
            printOut = "Y";
        }
        prt.close();
        if (printOut.equals("Y")) spoolPrt1();
    }

    private boolean plcreate() {
        while (true) {
            displayHeading();
            display(12, 1, "PL103 Purchase Ledger files have not been set up yet", 4);
            display(13, 1, "PL104 Do you wish to create them (Y/N) ? [ ]");
            String r = upper(acceptUpdate(13, 43, 1, " "));
            if (r.equals("N")) return false;
            if (r.equals("Y")) break;
        }
        display(15, 6, "PL105 Creating Purchase & Delivery Files");
        if (!purchaseFile.open(Mode.OUTPUT).equals("00")) {
            display(12, 1, "PL106 Opening Purchase files gives "); eraseEol(12, 36);
            show(12, 37, purchaseFile.status); display(12, 40, "hit return");
            purchaseFile.close();
            return true;
        }
        if (!deliveryFile.open(Mode.OUTPUT).equals("00")) {
            display(12, 1, "PL107 Opening Delivery files gives "); eraseEol(12, 36);
            show(12, 37, deliveryFile.status); display(12, 40, "hit return");
            deliveryFile.close();
            return true;
        }
        closeFiles();
        sys.setNum("file-status", 1, 22);
        sys.setNum("file-status", 1, 14);
        sys.set("purchase-ledger", "Y");
        return true;
    }
}
