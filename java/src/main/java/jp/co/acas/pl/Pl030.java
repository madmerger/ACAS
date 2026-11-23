package jp.co.acas.pl;

import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** pl030.cbl: 仕入請求書データ修正。 */
public class Pl030 extends Pl020 {
    static final String PROG_NAME = "PL030 (3.01.01)";
    private boolean exit;

    /** cr-note の「go to main」（init01 の main へ戻る）を表す。 */
    private static final class RestartMain extends RuntimeException {
        RestartMain() { super(null, null, false, false); }
    }

    @Override
    public void run(Object... args) {
        init();
        term().escEnabled = true;
        ih = Layout.of("purchase/wspinv.cob", "invoice-header").newRec();
        lines = Layout.of("purchase/wspinv.cob", "Pinvoice-lines").newRec();
        purch = purchRec(); anal = analRec();
        purchaseFile = purchaseFile(purch); analysisFile = analysisFile(anal); invoiceFile = invoiceFile();
        wsDate = pad("", 10);
        // program-start
        clearScreen();
        if (sys.intv("file-status", 15) != 1) {
            maps99(29);
            maps99(15);
        }
        purchaseFile.open(Mode.INPUT); analysisFile.open(Mode.INPUT);
        invoiceFile.open(Mode.IO);
        main:
        while (true) {
            try {
                lines.initialize();
                exit = false;
                amendDetails();
                if (crtStatus() == 2005 || exit || escapeCode.equals("Q")) break;
                eraseEos(16, 1);
                ih.setNum("ih-p-c", 0); ih.setNum("ih-net", 0); ih.setNum("ih-vat", 0);
                i = 0;
                invLevel1();
                if (crtStatus() == 2005) continue;
                if (i != 1) endTotals();
                while (true) {
                    display(16, 29, "Amend further invoices? (Y/N)  [Y]");
                    String r = upper(acceptUpdate(16, 61, 1, "Y"));
                    eraseEol(16, 1);
                    if (r.equals("Y")) continue main;
                    if (r.equals("N")) break main;
                }
            } catch (RestartMain e) {
                // main からやり直す
            }
        }
        sys.setNum("pass-value", 0);
        purchaseFile.close(); analysisFile.close(); invoiceFile.close();
    }

    @Override
    protected void runningTotals() {
        BigDecimal net = BigDecimal.ZERO, vat = BigDecimal.ZERO;
        for (int k = 1; k <= i; k++) {
            if (lines.str("il-type", k).equals("D")) continue;
            net = net.add(lines.num("il-net", k));
            vat = vat.add(lines.num("il-vat", k));
        }
        ih.setNum("ih-net", net);
        ih.setNum("ih-vat", vat);
        show(12, 37, Num.edit(ih.num("ih-net"), "z(6)9.99"));
        show(12, 55, Num.edit(ih.num("ih-vat"), "z(6)9.99"));
        show(12, 68, Num.edit(ih.num("ih-net").add(ih.num("ih-vat")), "z(6)9.99"));
    }

    private void displayOutline1() {
        i++;
        eraseEol(lin, 1);
        display(lin, 1, "(");
        show(lin, 2, Num.z9(i, 2));
        display(lin, 4, ") [  ]");
        display(lin, 36, "[          ] [ ]   {         } (");
        display(lin, 78, ")");
    }

    @Override
    protected void invLevel1() {
        display(11, 1, "-".repeat(80));
        display(12, 1, "Level 1");
        display(12, 16, "Line - ");
        display(12, 36, "<          >");
        display(12, 54, "<          >");
        display(12, 67, "<          >");
        display(14, 6, "Code");
        display(14, 36, "<---Net----> Vat   Vat Amount  Gross Amount");
        while (true) {
            for (lin = 16; lin <= 23; lin++) displayOutline1();
            i -= 7;
            j = 1;
            show(12, 23, Num.z9(i, 2));
            getData1();
            if (crtStatus() == 2005) return;
            if (newScreen == 1) continue;
            if (!lines.str("il-description", i).isBlank() && i != 40 && !escapeCode.equals("Q")) continue;
            return;
        }
    }

    @Override
    protected void getData1() {
        data:
        while (true) {
            lin = j + 15;
            if (lin > 23) {
                i--;
                newScreen = 1;
                return;
            }
            newScreen = 0;
            while (true) {
                String pa = lines.str("il-pa", i);
                show(lin, 7, pa);
                pa = pad(acceptUpdate(lin, 7, 2, pa), 2);
                if (pa.isBlank()) return;
                if (crtStatus() == 2005) return;
                if (pa.equals("<<") && i == 1) continue;
                if (pa.equals("<<")) {
                    lin--;
                    if (lin > 15) { i--; j--; continue; }
                    i -= 8;
                    continue data;
                }
                if (pa.equals("**")) {
                    clearDownLine();
                    i--;
                    displayOutline1();
                    continue;
                }
                lines.set("il-pa", pa, i);
                anal.set("pa-group", pa);
                anal.set("pa-system", "P");
                if (analysisFile.read(anal).startsWith("2")) {
                    display(lin, 11, "P.A. Code Does Not Exist!", 4);
                    continue;
                }
                show(lin, 11, text(anal.raw("pa-desc")));
                lines.setRaw("il-description", anal.raw("pa-desc"), i);
                BigDecimal net = acceptMoney(lin, 37, 7, lines.num("il-net", i));
                if (net.signum() == 0) continue;
                lines.setNum("il-net", net, i);
                wsNet = net;
                break;
            }
            vatCode = lines.intv("il-vat-code", i);
            do {
                show(lin, 50, String.valueOf(vatCode));
                vatCode = (int) acceptNum(lin, 50, 1, vatCode);
            } while (vatCode > 3);
            lines.setNum("il-vat-code", vatCode, i);
            BigDecimal vat = BigDecimal.ZERO;
            if (vatCode != 0) {
                vat = wsNet.multiply(sys.num("vat-rate", vatCode)).divide(HUNDRED, 2, RoundingMode.HALF_UP)
                        .remainder(BigDecimal.valueOf(1000000));
            }
            vat = acceptMoney(lin, 56, 6, vat);
            lines.setNum("il-vat", vat, i);
            wsVat = vat;
            show(lin, 68, Num.edit(wsVat.add(wsNet), "z(6)9.99"));
            runningTotals();
            j++;
            i++;
        }
    }

    private void clearDownLine() {
        byte[] b = lines.bytes();
        for (int zz = i; zz <= 39; zz++) {
            System.arraycopy(b, zz * LINE_SIZE, b, (zz - 1) * LINE_SIZE, LINE_SIZE);
            lines.setNum("il-line", zz, zz);
        }
        if (i <= ih.intv("ih-lines")) {
            Rec k = invHeaderRec();
            k.setNum("ih-invoice", ih.longv("ih-invoice"));
            k.setNum("ih-test", ih.intv("ih-lines"));
            invoiceFile.delete(k);
            ih.setNum("ih-lines", ih.intv("ih-lines") - 1);
        }
    }

    @Override
    protected void endTotals() {
        while (true) {
            totalScreenAmend();
            eraseEos(15, 1);
            display(16, 60, "*********************");
            display(17, 60, "*"); display(17, 80, "*");
            display(18, 60, "*"); display(18, 80, "*");
            display(19, 60, "*"); display(19, 80, "*");
            display(20, 60, "*********************");
            display(17, 61, "Invoice ok to store");
            display(19, 68, "(Y/N) ? [Y]");
            String r;
            do { r = upper(acceptUpdate(19, 77, 1, "Y")); } while (!r.equals("N") && !r.equals("Y"));
            if (r.equals("Y")) break;
        }
        ih.set("ih-status", "P");
        i--;
        ih.setNum("ih-lines", i);
        byte[] rec = fdBytes(ih.bytes(), HEADER_SIZE);
        if (!invoiceFile.rewrite(rec).equals("00")) {
            display(20, 1, "PL186 Err on Invoice file rewrite : ", 4); eraseEol(20, 37);
            show(20, 36, invoiceFile.status);
            show(20, 64, ih.str("ih-invoice"));
            display(21, 1, "PL006 Note Details & Hit Return to continue", 3);
            accept(21, 30, 1);
            eraseEol(20, 1); eraseEol(21, 1);
        }
        j = 0;
        for (int n = 0; n < i; n++) {
            j++;
            lines.setNum("il-invoice", ih.longv("ih-invoice"), j);
            lines.setNum("il-line", j, j);
            lines.set("il-type", ih.str("ih-type"), j);
            rec = fdBytes(lineBytes(j), LINE_SIZE);
            if (invoiceFile.rewrite(rec).startsWith("2")) invoiceFile.write(rec);
            if (!invoiceFile.status.equals("00")) writeError(invoiceFile, rec, 20, 21);
        }
        sys.setNum("p-flag-i", 1);
        eraseEos(11, 1);
    }

    private void totalScreenAmend() {
        eraseEos(11, 1);
        display(11, 1, "-".repeat(80));
        display(12, 1, "Level 1");
        display(13, 25, "<---Net---->   <---Vat--->");
        display(13, 54, "<---Gross-->     Days");
        display(15, 4, "Sub-Totals");
        display(15, 25, "{          }   {         }");
        display(15, 54, "{          }     [  ]");
        display(17, 4, "Prompt Payment Disc");
        display(17, 25, "[          ]");
        display(17, 54, "{          }     [  ]");
        display(19, 4, "Shipping & Handling");
        display(19, 25, "[          ]   [         ]");
        display(19, 54, "{          }");
        display(22, 25, "------------   -----------");
        display(22, 54, "------------");
        display(23, 4, "Itemised Totals");
        display(23, 25, "{          }   {         }");
        display(23, 54, "{          }");
        show(15, 26, Num.edit(ih.num("ih-net"), "z(6)9.99"));
        show(15, 41, Num.edit(ih.num("ih-vat"), "z(5)9.99"));
        show(15, 55, Num.edit(ih.num("ih-net").add(ih.num("ih-vat")), "z(6)9.99"));
        int days = ih.intv("ih-days") % 100;
        show(15, 72, Num.z9(days, 2));
        if (ih.intv("ih-type") != 2) ih.setNum("ih-days", 0);
        else {
            ih.setNum("ih-days", acceptNum(15, 72, 2, days));
            BigDecimal amt;
            do { amt = acceptMoney(17, 26, 7, ih.num("ih-deduct-amt")); } while (amt.compareTo(BigDecimal.valueOf(1000)) >= 0);
            ih.setNum("ih-deduct-amt", amt);
            if (ih.num("ih-deduct-amt").signum() == 0) { ih.setNum("ih-deduct-vat", 0); ih.setNum("ih-deduct-days", 0); }
            else {
                show(17, 55, Num.edit(amt, "z(6)9.99"));
                // 原文は英数字 2 桁の ws-days（ws-date の先頭 2 桁）経由で受ける
                String d = Num.z9(ih.intv("ih-deduct-days") % 100, 2);
                show(17, 72, d);
                d = acceptUpdate(17, 72, 2, d);
                wsDate = pad(d, 2) + wsDate.substring(2);
                ih.setNum("ih-deduct-days", numOf(d));
            }
        }
        ih.setNum("ih-carriage", acceptMoney(19, 26, 7, ih.num("ih-carriage")));
        BigDecimal cvat = ih.num("ih-carriage").multiply(sys.num("vat-rate-1")).divide(HUNDRED, 2, RoundingMode.HALF_UP)
                .remainder(BigDecimal.valueOf(1000000));
        ih.setNum("ih-c-vat", acceptMoney(19, 41, 6, cvat));
        show(19, 55, Num.edit(ih.num("ih-carriage").add(ih.num("ih-c-vat")), "z(6)9.99"));
        show(23, 26, Num.edit(ih.num("ih-net").add(ih.num("ih-carriage")), "z(6)9.99"));
        show(23, 41, Num.edit(ih.num("ih-vat").add(ih.num("ih-c-vat")), "z(5)9.99"));
        show(23, 55, Num.edit(ih.num("ih-net").add(ih.num("ih-carriage")).add(ih.num("ih-vat")).add(ih.num("ih-c-vat")), "z(6)9.99"));
        display(23, 74, "ok  [ ]");
        accept(23, 79, 1);
    }

    private void typeLine() { display(10, 1, "Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note"); }

    /** invoice-details（修正版）。exit=true は z ≠ 0 相当。 */
    private void amendDetails() {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 33, "Invoice Data Amend");
        show(1, 71, fromUk(toDay()), 2);
        display(4, 41, "****************************************");
        display(5, 41, "*Date [  /  /    ]*A/C Nos    [       ]*");
        display(6, 41, "**                *Order   [          ]*");
        display(7, 41, "*Folio  [        ]*Invoice [          ]*");
        display(8, 41, "****************************************");
        typeLine();
        while (true) {
            ih.setNum("ih-invoice", 0);
            show(7, 50, "00000000");
            long inv = acceptNum(7, 50, 8, 0);
            ih.setNum("ih-invoice", inv);
            if (inv == 0 || crtStatus() == 2005) { exit = true; return; }
            Rec k = invHeaderRec();
            k.setNum("ih-invoice", inv);
            k.setNum("ih-test", 0);
            if (!invoiceFile.read(k).equals("00")) {
                display(16, 40, "PL187 Invoice Not Found!!!!");
                continue;
            }
            System.arraycopy(k.bytes(), 0, ih.bytes(), 0, HEADER_SIZE);
            eraseEol(16, 40);
            if (ih.str("ih-status").equalsIgnoreCase("z")) {
                display(16, 1, "PL188 Invoice Already Passed To Purchase Ledger!"); eraseEol(16, 49);
                continue;
            }
            break;
        }
        eraseEol(16, 1);
        wsDate = binToDate(ih.longv("ih-date"));
        // read-details
        Rec l = invLineRec();
        for (int n = 1; n <= ih.intv("ih-lines"); n++) {
            l.setNum("il-invoice", ih.longv("ih-invoice"));
            l.setNum("il-line", n);
            invoiceFile.read(l);
            System.arraycopy(l.bytes(), 0, lines.bytes(), (n - 1) * LINE_SIZE, LINE_SIZE);
        }
        while (true) {
            show(5, 48, wsDate);
            wsDate = pad(acceptUpdate(5, 48, 10, wsDate), 10);
            if (crtStatus() == 2005 || wsDate.isBlank()) { exit = true; return; }
            long bin = validateDate(wsDate);
            if (bin == 0) continue;
            ih.setNum("ih-date", bin);
            break;
        }
        while (true) {
            show(5, 72, ih.str("ih-supplier"));
            String sup = upper(pad(acceptUpdate(5, 72, 7, ih.str("ih-supplier")), 7));
            ih.set("ih-supplier", sup);
            if (crtStatus() == 2005 || sup.isBlank()) { escapeCode = "Q"; return; }
            purch.set("purch-key", sup);
            if (purchaseFile.read(purch).equals("00")) break;
        }
        show(3, 1, purch.str("purch-name"));
        String[] ad = pieces(purch.str("purch-address"), sys.str("pl-delim"), 4);
        for (int n = 0; n < 5; n++) show(4 + n, 1, pad(ad[n], 36));
        show(6, 69, ih.str("ih-order"));
        ih.set("ih-order", acceptUpdate(6, 69, 10, ih.str("ih-order")));
        show(7, 69, ih.str("ih-ref"));
        ih.set("ih-ref", acceptUpdate(7, 69, 10, ih.str("ih-ref")));
        while (true) {
            int type = ih.intv("ih-type");
            show(10, 7, String.valueOf(type));
            type = (int) acceptNum(10, 7, 1, type);
            ih.setNum("ih-type", type);
            if (type == 0) { exit = true; return; }   // z は UNSTRING のポインタ値（非ゼロ）のまま
            if (type > 3) continue;
            if (type == 3) {
                crNoteAmend();
                if (escapeCode.equals("Q")) { typeLine(); continue; }
            }
            return;
        }
    }

    private void crNoteAmend() {
        Rec other = invHeaderRec();
        for (int l = 12; l <= 16; l++) eraseEol(l, 1);
        input:
        while (true) {
            display(12, 1, "Invoice to Credit - [        ]");
            show(12, 22, Num.z9(ih.longv("ih-cr"), 8));
            long cr = acceptNum(12, 22, 8, ih.longv("ih-cr"));
            ih.setNum("ih-cr", cr);
            if (cr == 0) { wsNamed = "Z"; break; }
            wsNamed = " ";
            if (cr == 99999999L) { escapeCode = "Q"; return; }
            escapeCode = " ";
            other.setNum("ih-invoice", cr);
            other.setNum("ih-test", 0);
            if (!invoiceFile.read(other).equals("00")) {
                display(13, 32, "PL189 Invoice To Credit Does Not Exist On Invoice File");
                while (true) {
                    display(14, 1, "Do you wish to use this invoice no.? {N}");
                    display(15, 1, "..If so, you must ensure that it belongs to the same Supplier and that it is a ");
                    display(16, 1, "INVOICE ie not a Receipt");
                    String r = upper(acceptUpdate(14, 39, 1, "N"));
                    if (r.equals("Y")) break input;
                    if (r.equals("N")) throw new RestartMain();
                }
            }
            eraseEol(13, 1);
            if (other.intv("ih-type") != 2) {
                display(13, 1, "PL184 You Can Only Credit Invoices. Not Receipts, Credit Notes");
                continue;
            }
            if (!other.str("ih-supplier").equals(purch.str("purch-key"))) {
                display(13, 1, "PL190 You Can Only Credit An Invoice With The Same Account Number");
                continue;
            }
            break;
        }
        for (int l = 12; l <= 16; l++) eraseEol(l, 1);
    }
}
