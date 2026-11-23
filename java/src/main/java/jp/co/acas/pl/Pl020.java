package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** pl020.cbl: 仕入請求書データ入力。 */
public class Pl020 extends PlBase {
    static final String PROG_NAME = "PL020 (3.01.08)";
    static final String[] D_TYPES = {"Receipt <<<    ", "Account <<<    ", "Credit Note <<<"};
    static final BigDecimal HUNDRED = BigDecimal.valueOf(100);
    private static final String DELETED_FOLIOS = "delfolio.dat";
    protected Rec ih, lines, purch, anal, del;
    protected CobFile purchaseFile, analysisFile, invoiceFile;
    protected int z, i, j, lin, newScreen, vatCode;
    private byte[] deletedFolioCursor;
    private byte[] selectedDeletedFolio;
    private boolean delExists;
    protected String escapeCode = " ", wsNamed = " ", wsDate = "";
    protected BigDecimal wsNet = BigDecimal.ZERO, wsVat = BigDecimal.ZERO;

    protected static final int LINE_SIZE = 75, HEADER_SIZE = 100, REC_SIZE = 129;

    @Override
    public void run(Object... args) {
        init();
        term().escEnabled = true;
        ih = Layout.of("purchase/wspinv.cob", "invoice-header").newRec();
        lines = Layout.of("purchase/wspinv.cob", "Pinvoice-lines").newRec();
        purch = purchRec(); anal = analRec();
        del = fdRec(Layout.of("purchase/fdpdnos.cob", "del-inv-nos-record"));
        purchaseFile = purchaseFile(purch); analysisFile = analysisFile(anal); invoiceFile = invoiceFile();
        wsDate = fromUk(toDay());
        programStart();
        main:
        while (true) {
            ih.initialize();
            if (!invoiceDetails()) continue;     // 再入力（invoice-details のやり直しは内部で処理）
            if (z != 0 || escapeCode.equals("Q")) break;
            eraseEos(16, 1);
            // data-input
            lines.initialize();
            for (String f : new String[]{"ih-deduct-days", "ih-deduct-amt", "ih-discount", "ih-p-c", "ih-net", "ih-vat"}) ih.setNum(f, 0);
            i = 0;
            invLevel1();
            if (crtStatus() == 2005) continue;
            if (i != 1) endTotals();
            while (true) {
                display(24, 29, "Enter Further Invoices? (Y/N) [Y] ");
                term().crtStatus = 0;
                String r = upper(acceptUpdate(24, 60, 1, "Y"));
                eraseEol(24, 1);
                if (r.equals("Y")) continue main;
                if (r.equals("N")) break main;
            }
        }
        // menu-exit
        sys.setNum("pass-value", 0);
        purchaseFile.close(); analysisFile.close(); invoiceFile.close();
    }

    protected byte[] fdBytes(byte[] src, int len) {
        byte[] out = new byte[REC_SIZE];
        java.util.Arrays.fill(out, (byte) ' ');
        System.arraycopy(src, 0, out, 0, len);
        return out;
    }

    protected byte[] lineBytes(int n) {
        byte[] b = new byte[LINE_SIZE];
        System.arraycopy(lines.bytes(), (n - 1) * LINE_SIZE, b, 0, LINE_SIZE);
        return b;
    }

    protected void writeError(CobFile f, byte[] rec, int l1, int l2) {
        display(l1, 1, "PL180 Err on Invoice file write : ", 4); eraseEol(l1, 35);
        show(l1, 36, f.status);
        show(l1, 64, new String(rec, 0, 8, java.nio.charset.StandardCharsets.ISO_8859_1));
        display(l2, 1, "PL006 Note Details & Hit Return to continue", 3);
        accept(l2, 30, 1);
        eraseEol(l1, 1);
        eraseEol(l2, 1);
    }

    protected void runningTotals() {
        BigDecimal net = BigDecimal.ZERO, vat = BigDecimal.ZERO;
        for (int k = 1; k <= i; k++) {
            net = net.add(lines.num("il-net", k));
            vat = vat.add(lines.num("il-vat", k));
        }
        ih.setNum("ih-net", net);
        ih.setNum("ih-vat", vat);
        show(12, 37, Num.edit(ih.num("ih-net"), "z(6)9.99"));
        show(12, 55, Num.edit(ih.num("ih-vat"), "z(6)9.99"));
        show(12, 68, Num.edit(ih.num("ih-net").add(ih.num("ih-vat")), "z(6)9.99"));
    }

    protected void invLevel1() {
        display(11, 1, "-".repeat(80));
        display(12, 1, "Level 1");
        display(12, 16, "Line - ");
        display(12, 36, "[          ]");
        display(12, 54, "[          ]");
        display(12, 67, "[          ]");
        display(14, 5, "Code");
        display(14, 36, "<---Net----> Vat   Vat Amount  Gross Amount");
        while (true) {
            for (lin = 16; lin <= 23; lin++) {
                i++;
                eraseEol(lin, 1);
                display(lin, 1, "(");
                show(lin, 2, Num.z9(i, 2), 2);
                display(lin, 4, ") [  ]");
                display(lin, 36, "[          ] [ ]   {         } (");
                display(lin, 78, ")");
            }
            i -= 7;
            j = 1;
            show(12, 23, Num.z9(i, 2));
            term().crtStatus = 0;
            getData1();
            if (crtStatus() == 2005) return;
            if (newScreen == 1) continue;
            if (i < 40 && !lines.str("il-description", i).isBlank()) continue;
            return;
        }
    }

    protected void getData1() {
        data:
        while (true) {
            lin = j + 15;
            if (lin > 23) {
                if (i > 40) { newScreen = 0; return; }
                i--;
                newScreen = 1;
                return;
            }
            newScreen = 0;
            while (true) {
                // get-code
                if (i > 1 && lines.str("il-pa", i).isBlank()) lines.set("il-pa", lines.str("il-pa", i - 1), i);
                String pa = lines.str("il-pa", i);
                show(lin, 7, pa);
                pa = pad(acceptUpdate(lin, 7, 2, pa), 2);
                lines.set("il-pa", pa, i);
                anal.set("pa-group", pa);
                lines.set("il-description", "", i);
                if (pa.isBlank()) return;
                if (crtStatus() == 2005) return;
                if (pa.equals("<<") && i == 1) continue;
                if (pa.equals("<<")) {
                    lin--;
                    if (lin > 15) { i--; j--; continue; }
                    i -= 8;
                    continue data;
                }
                anal.set("pa-system", "P");
                String st = analysisFile.read(anal);
                if (st.startsWith("2")) {
                    display(lin, 11, "PL186 P.A. Code Does Not Exist", 4);
                    continue;
                }
                show(lin, 11, text(anal.raw("pa-desc")));
                lines.setRaw("il-description", anal.raw("pa-desc"), i);
                // get-net
                BigDecimal net = acceptMoney(lin, 37, 7, BigDecimal.ZERO);
                if (net.signum() == 0) continue;
                lines.setNum("il-net", net, i);
                wsNet = net;
                break;
            }
            do {
                vatCode = (int) acceptNum(lin, 50, 1, vatCode);
            } while (vatCode > 3);
            lines.setNum("il-vat-code", vatCode, i);
            BigDecimal vat = BigDecimal.ZERO;
            if (vatCode != 0) {
                vat = wsNet.multiply(sys.num("vat-rate", vatCode)).divide(HUNDRED, 2, RoundingMode.HALF_UP);
                vat = vat.remainder(BigDecimal.valueOf(1000000));
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

    /** NUL を含むデータ項目の表示（NUL は画面に何も出さない）。 */
    protected static String text(byte[] b) {
        return new String(b, java.nio.charset.StandardCharsets.ISO_8859_1).replace('\0', ' ');
    }

    protected void endTotals() {
        while (true) {
            term().crtStatus = 0;
            totalScreen();
            if (crtStatus() == 2005) return;
            eraseEos(15, 1);
            display(16, 60, "*********************");
            display(17, 60, "*"); display(17, 80, "*");
            display(18, 60, "*"); display(18, 80, "*");
            display(19, 60, "*"); display(19, 80, "*");
            display(20, 60, "*********************");
            display(17, 61, "Invoice ok to store");
            display(19, 68, "(Y/N) ? [Y]");
            String r;
            while (true) {
                r = upper(acceptUpdate(19, 77, 1, "Y"));
                if (crtStatus() == 2005) return;
                if (r.equals("N") || r.equals("Y")) break;
            }
            if (r.equals("Y")) break;
        }
        if (storeInvoice()) {
            if (selectedDeletedFolio == null) sys.setNum("next-folio", sys.longv("next-folio") + 1);
            sys.setNum("p-flag-i", 1);
        }
        eraseEos(11, 1);
    }

    /** ヘッダーを新規作成できた請求だけ明細を書き込む。 */
    protected boolean storeInvoice() {
        ih.set("ih-status", "P");
        i--;
        ih.setNum("ih-lines", i);
        byte[] rec = fdBytes(ih.bytes(), HEADER_SIZE);
        String headerStatus;
        synchronized (ctx.store) {
            headerStatus = invoiceFile.write(rec);
        }
        if (!headerStatus.equals("00")) {
            writeError(invoiceFile, rec, 23, 24);
            return false;
        }
        j = 0;
        for (int n = 0; n < i; n++) {
            j++;
            lines.setNum("il-invoice", ih.longv("ih-invoice"), j);
            lines.setNum("il-line", j, j);
            lines.set("il-type", ih.str("ih-type"), j);
            rec = fdBytes(lineBytes(j), LINE_SIZE);
            if (!invoiceFile.write(rec).equals("00")) writeError(invoiceFile, rec, 20, 21);
        }
        if (selectedDeletedFolio != null) {
            ctx.store.remove(ctx.path(DELETED_FOLIOS), selectedDeletedFolio);
        }
        return true;
    }

    protected void totalScreen() {
        while (true) {
            eraseEos(11, 1);
            display(11, 1, "-".repeat(80));
            display(12, 1, "Level 1");
            display(12, 25, "<---Net---->   <---Vat--->");
            display(12, 54, "<---Gross-->     Days");
            display(14, 4, "Sub-Totals");
            display(14, 25, "{          }   {         }");
            display(14, 54, "{          }     [  ]");
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
            show(14, 26, Num.edit(ih.num("ih-net"), "z(6)9.99"));
            show(14, 41, Num.edit(ih.num("ih-vat"), "z(5)9.99"));
            show(14, 55, Num.edit(ih.num("ih-net").add(ih.num("ih-vat")), "z(6)9.99"));
            // get-days
            ih.setNum("ih-days", 0); ih.setNum("ih-carriage", 0);
            if (ih.intv("ih-type") == 2) ih.setNum("ih-days", purch.intv("purch-credit"));
            int days = ih.intv("ih-days") % 100;
            show(14, 72, Num.z9(days, 2));
            if (ih.intv("ih-type") == 2) {
                days = (int) acceptNum(14, 72, 2, days);
                ih.setNum("ih-days", days);
                while (true) {
                    // get-extra
                    for (String f : new String[]{"ih-extra", "ih-e-vat", "ih-deduct-amt", "ih-deduct-vat", "ih-deduct-days"}) ih.setNum(f, 0);
                    BigDecimal amt = acceptMoney(17, 26, 7, ih.num("ih-deduct-amt"));
                    if (amt.compareTo(BigDecimal.valueOf(1000)) >= 0) continue;
                    ih.setNum("ih-deduct-amt", amt);
                    if (ih.num("ih-deduct-amt").signum() != 0) {
                        show(17, 55, Num.edit(amt, "z(6)9.99"));
                        show(17, 72, Num.z9(days, 2));
                        days = (int) acceptNum(17, 72, 2, days);
                        ih.setNum("ih-deduct-days", days);
                    }
                    break;
                }
            }
            // get-carriage
            BigDecimal carriage = acceptMoney(19, 26, 7, BigDecimal.ZERO);
            ih.setNum("ih-carriage", carriage);
            BigDecimal cvat = ih.num("ih-carriage").multiply(sys.num("vat-rate-1")).divide(HUNDRED, 2, RoundingMode.HALF_UP)
                    .remainder(BigDecimal.valueOf(1000000));
            cvat = acceptMoney(19, 41, 6, cvat);
            ih.setNum("ih-c-vat", cvat);
            show(19, 55, Num.edit(ih.num("ih-carriage").add(ih.num("ih-c-vat")), "z(6)9.99"));
            show(23, 26, Num.edit(ih.num("ih-net").add(ih.num("ih-carriage")), "z(6)9.99"));
            show(23, 41, Num.edit(ih.num("ih-vat").add(ih.num("ih-c-vat")), "z(5)9.99"));
            show(23, 55, Num.edit(ih.num("ih-net").add(ih.num("ih-carriage")).add(ih.num("ih-vat")).add(ih.num("ih-c-vat")), "z(6)9.99"));
            display(23, 74, "ok  [ ]");
            if (upper(accept(23, 79, 1)).equals("Y")) return;
        }
    }

    protected void heading(String title) {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 32, title);
        show(1, 71, fromUk(toDay()), 2);
    }

    /** invoice-details。false: main からやり直し（原文の go to invoice-details 相当は内部ループ）。 */
    protected boolean invoiceDetails() {
        details:
        while (true) {
            heading("Invoice Data Entry");
            display(4, 41, "****************************************");
            display(5, 41, "*Date [  /  /    ]*A/C Nos    [       ]*");
            display(6, 41, "**                *Order   [          ]*");
            display(7, 41, "*Folio  [        ]*Invoice [          ]*");
            display(8, 41, "****************************************");
            display(9, 11, "F1 = Setup new Supplier");
            display(10, 1, "Type [ ]  <1> = Receipt; <2> = Account; <3> = Credit Note");
            while (true) {
                show(5, 48, wsDate);
                wsDate = pad(acceptUpdate(5, 48, 10, wsDate), 10);
                if (crtStatus() == 2005 || wsDate.isBlank()) { z = 1; return true; }
                long bin = validateDate(wsDate);
                if (bin == 0) continue;
                ih.setNum("ih-date", bin);
                break;
            }
            while (true) {
                // supplier-input
                term().crtStatus = 0;
                String sup = upper(pad(accept(5, 72, 7), 7));
                ih.set("ih-supplier", sup);
                if (sup.trim().equals("NEW") || crtStatus() == 1001) {
                    purchaseFile.close(); invoiceFile.close(); analysisFile.close();
                    call("pl025");
                    programStart();
                    continue details;
                }
                if (sup.isBlank()) { escapeCode = "Q"; return true; }
                purch.set("purch-key", sup);
                if (!purchaseFile.read(purch).equals("00")) {
                    maps99(21);
                    continue;
                }
                break;
            }
            show(9, 11, pad("", 23));
            eraseEol(23, 1);
            selectedDeletedFolio = null;
            if (delExists) getADeletedInvoice();
            if (ih.longv("ih-invoice") == 0) {
                if (sys.longv("next-folio") == 0) sys.setNum("next-folio", 1);
                ih.setNum("ih-invoice", sys.longv("next-folio"));
            }
            show(7, 50, ih.str("ih-invoice"));
            show(3, 1, purch.str("purch-name"));
            String[] ad = pieces(purch.str("purch-address"), sys.str("pl-delim"), 4);
            for (int n = 0; n < 5; n++) show(4 + n, 1, pad(ad[n], 36));
            ih.set("ih-ref", ""); ih.set("ih-order", "");
            ih.set("ih-order", accept(6, 69, 10));
            ih.set("ih-ref", accept(7, 69, 10));
            int type;
            do {
                type = (int) numOf(accept(10, 7, 1));
                ih.setNum("ih-type", type);
                wsNamed = " ";
                if (type == 0) continue details;
            } while (type > 3);
            eraseEol(10, 1);
            display(10, 31, ">>> ");
            display(10, 35, D_TYPES[type - 1]);
            ih.setNum("ih-cr", 0);
            if (type == 3) {
                crNote();
                if (escapeCode.equals("Q")) continue details;
            }
            z = 0;
            return true;
        }
    }

    protected void getADeletedInvoice() {
        var key = invHeaderRec();
        while (true) {
            var entry = ctx.store.next(ctx.path(DELETED_FOLIOS), deletedFolioCursor, false);
            if (entry == null) break;
            deletedFolioCursor = entry.getKey();
            del.load(entry.getValue());
            long number = del.longv("del-inv-nos");
            if (number == 0) continue;
            key.setNum("ih-invoice", number);
            key.setNum("ih-test", 0);
            if (invoiceFile.read(key).equals("00")) continue;
            selectedDeletedFolio = deletedFolioCursor;
            ih.setNum("ih-invoice", number);
            display(3, 45, "Using Deleted Folio Numbers");
            return;
        }
        show(3, 45, pad("", 29));
        long nextInvoice = sys.longv("next-invoice");
        key.setNum("ih-invoice", nextInvoice);
        key.setNum("ih-test", 0);
        if (nextInvoice > 0 && !invoiceFile.read(key).equals("00")) {
            ih.setNum("ih-invoice", nextInvoice);
        }
        delExists = false;
    }

    protected void crNote() {
        Rec other = invHeaderRec();
        main:
        while (true) {
            for (int l = 12; l <= 16; l++) eraseEol(l, 1);
            while (true) {
                display(12, 1, "Invoice to Credit - [        ]");
                long cr = acceptNum(12, 22, 8, 0);
                if (crtStatus() == 2005) { escapeCode = "Q"; return; }
                ih.setNum("ih-cr", cr);
                if (cr == 0) { wsNamed = "Z"; break main; }
                wsNamed = " ";
                if (cr == 99999999L) { escapeCode = "Q"; return; }
                escapeCode = " ";
                other.setNum("ih-invoice", cr);
                other.setNum("ih-test", 0);
                if (!invoiceFile.read(other).equals("00")) {
                    display(23, 1, "PL181 Invoice To Credit Does Not Exist On Open Item File", 4);
                    while (true) {
                        display(14, 1, "Do you wish to use this invoice no.? {N}");
                        display(15, 1, "..If so, you must ensure that it belongs to the same Supplier and that it is a ");
                        display(16, 1, "INVOICE, ie not a Receipt");
                        String r = upper(acceptUpdate(14, 39, 1, "N"));
                        if (r.equals("Y")) break main;
                        if (r.equals("N")) continue main;
                    }
                }
                eraseEol(23, 1);
                if (other.intv("ih-type") != 2) {
                    display(23, 1, "PL184 You Can Only Credit Invoices. Not Receipts, Credit Notes", 4);
                    continue;
                }
                if (!other.str("ih-supplier").equals(purch.str("purch-key"))) {
                    display(23, 1, "PL187 You can only credit an invoice with the same account number", 4);
                    continue;
                }
                break main;
            }
        }
        for (int l = 12; l <= 16; l++) eraseEol(l, 1);
    }

    protected void programStart() {
        clearScreen();
        if (sys.intv("file-status", 15) != 1) {
            maps99(29);
            maps99(15);
        }
        purchaseFile.open(Mode.INPUT); analysisFile.open(Mode.INPUT);
        synchronized (ctx.store) {
            if (!invoiceFile.exists()) {
                display(23, 1, "Creating Invoice File                    ");
            }
            if (invoiceFile.open(Mode.IO, true).charAt(0) == '0') {
                sys.setNum("file-status", 1, 26);
            }
        }
        deletedFolioCursor = null;
        delExists = ctx.store.exists(ctx.path(DELETED_FOLIOS));
    }
}
