package jp.co.acas.sys;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;
import jp.co.acas.sl.SlProgram;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * common/xl150.cbl: 期末（サイクル末）処理。SL メニュー U・PL メニュー T から呼ばれ、
 * 売掛（sl-processing）と買掛（pl-processing）の両方を処理する。
 */
public class Xl150 extends SlProgram {
    static final String PROG_NAME = "xl150 (3.00.03)";
    static final String XL001 = "XL001 Aborting. Press return   ";
    static final String XL101 = "XL101 WARNING..... Proofed but NOT posted invoices";
    static final String XL102 = "XL102 !!ERROR..... Proofed but NOT posted payments";
    static final String XL103 = "XL103 !!ERROR.... Sales Analysis NOT run";
    static final String XL104 = "XL104 I'm confused: You appear to have rejected the run, try again";
    private static final String F_PURCHASE = "purchled.dat", F_PINVOICE = "pinvoice.dat", F_OI5 = "openitm5.dat";
    /** temp-invoice-record（file-21 = work.tmp）のレコード長。 */
    private static final int TEMP_INVOICE_LEN = 129, TEMP_LEDGER_LEN = 300, OI_SORT_LEN = 114;

    private Rec sys, sys4;
    private long uBin;
    private int newQuarter, newYear, slEoc, plEoc;

    /** 英数字項目間の MOVE（長さが違えば切り詰め／空白埋め）。 */
    private static byte[] fit(byte[] src, int len) {
        byte[] b = Arrays.copyOf(src, len);
        for (int i = src.length; i < len; i++) b[i] = ' ';
        return b;
    }

    @Override
    public void run(Object... args) {
        sys = sys(); sys4 = sys4();
        term().exceptionsEnabled = true; term().escEnabled = true;
        displayHeads();
        uBin = Maps04.toBin(toDay());
        if (sys.intv("file-status", 15) != 1) { maps99(26); callFoul(); return; }
        String reply;
        while (true) {
            display(5, 1, "WARNING: MAKE SURE THAT DATE IS AT END OF CYCLE.IE END OF MONTH", 4);
            display(6, 12, "Have you made a Backup of ALL DATA FILES? If so; ", 2);
            display(7, 12, "Confirm end of Cycle Processing to be Run (Y/N) - [ ]", 2);
            reply = upper(acceptUpdate(7, 63, 1, "N"));
            if (reply.equals("N")) { menuError(); return; }
            if (!reply.equals("Y")) continue;
            if (sys.intv("s-flag-i") == 1 || sys.intv("p-flag-i") == 1) {
                display(12, 1, XL101, 4);
                display(13, 1, "ok to proceed (Y/N) - [Y]", 2);
                reply = upper(acceptUpdate(13, 24, 1, "Y"));
                if (reply.equals("N")) { menuError(); return; }
            }
            int sp = sys.intv("s-flag-p"), pp = sys.intv("p-flag-p");
            if (sp == 1 || sp == 2 || pp == 1 || pp == 2) {
                display(12, 1, XL102, 4);
                display(13, 1, XL001, 2);
                accept(13, 31, 1);
                menuError();
                return;
            }
            if (sys.intv("s-flag-a") == 1 || sys.intv("p-flag-a") == 1) {
                display(12, 1, XL103, 4);
                display(13, 1, XL001, 2);
                accept(13, 31, 1);
                termCode(1);
                menuExit();
                return;
            }
            display(16, 1, "Give password [****]", 2);
            String passwd = pad(term().accept(16, 16, 4, " ".repeat(4), Terminal.SECURE, 2), 4);
            String encoded = passwd.isBlank() ? " ".repeat(4) : Maps01.password(ctx, passwd);
            if (!pad(sys.str("pass-word"), 4).equals(pad(encoded, 4))) { termCode(3); return; }
            // request-ledgers
            if (sys.intv("level-3") == 1) {
                display(16, 1, "Do you wish to run Sales Ledger? (Y/N) - [ ]", 2);
                if (upper(accept(16, 43, 1)).equals("Y")) slEoc = 1;
            }
            if (sys.intv("level-2") == 1) display(17, 1, "Do you wish to run Purchase Ledger? (Y/N) - [ ]", 2);
            // レガシーは DISPLAY の後にピリオドがあり、B-L でなくても買掛の問合せ入力を行う。
            if (upper(accept(17, 46, 1)).equals("Y")) plEoc = 1;
            if (slEoc == 0 && plEoc == 0) { display(19, 1, XL104, 2); continue; }
            break;
        }
        if (sys.intv("file-status", 29) != 1 && plEoc == 1) { maps99(25); callFoul(); return; }
        if (sys.intv("file-status", 19) != 1 && slEoc == 1) { maps99(19); callFoul(); return; }
        displayHeads();
        checkEndOfCycle();
        if (slEoc == 1) { processing(true); sys.setNum("s-end-cycle-date", uBin); }
        if (plEoc == 1) { processing(false); sys.setNum("bl-end-cycle-date", uBin); }
        menuExit();
    }

    private void displayHeads() {
        eraseEos(1, 1);
        show(1, 1, PROG_NAME, 2);
        display(1, 30, "End of Cycle Processing", 2);
        show(1, 71, fromUk(toDay()), 2);
    }

    private void callFoul() { maps99(15); menuError(); }
    private void menuError() { termCode(2); menuExit(); }
    private void menuExit() {
        if (slEoc == 1) sys.set("oi-3-flag", "Y");
        if (plEoc == 1) sys.set("oi-5-flag", "Y");
    }

    // ---- check-end-of-cycle ----
    private void checkEndOfCycle() {
        int cyclea = sys.intv("cyclea") + 1;
        sys.setNum("cyclea", cyclea);
        int period = sys.intv("period");
        if (period == 3) cycleCheck(cyclea, 4, 7, 10, 13);
        else if (period == 13) cycleCheck(cyclea, 14, 27, 40, 53);
        else queryCheck();
    }

    private void nextQuarter() { sys.setNum("current-quarter", (sys.intv("current-quarter") + 1) % 10); newQuarter = 1; }
    private void nextYear() { sys.setNum("cyclea", 1); sys.setNum("current-quarter", 1); newYear = 1; newQuarter = 1; }

    private void cycleCheck(int cyclea, int q2, int q3, int q4, int yearEnd) {
        if (cyclea == q2 || cyclea == q3 || cyclea == q4) nextQuarter();
        else if (cyclea == yearEnd) nextYear();
    }

    private void queryCheck() {
        while (true) {
            display(16, 1, "Is this the end of a quarter (Y/N) - [ ]", 2);
            String reply = upper(accept(16, 39, 1));
            if (reply.equals("N")) return;
            if (reply.equals("Y")) break;
        }
        if (sys.intv("current-quarter") != 4) nextQuarter(); else nextYear();
    }

    // ---- sl-processing / pl-processing ----
    private void processing(boolean sl) {
        String p = sl ? "sales-" : "purch-";
        display(12, 1, sl ? "Phase 1  - Sales" : "Phase 1  - Purchase", 2);
        display(13, 1, "*******", 2);
        display(15, 1, sl ? "Please wait." : "Please Wait", 2);
        CobFile temp = CobFile.sequential(ctx.store, ctx.path(F_WORK));
        CobFile sort = CobFile.sequential(ctx.store, ctx.path(F_OISORT));

        // phase 1: 顧客／仕入先マスタの繰越
        Rec led = sl ? salesRec() : fdRec("copybooks/fdpl.cob", "Purch-Record");
        CobFile ledFile = sl ? salesFile(led) : CobFile.indexed(ctx.store, ctx.path(F_PURCHASE), led, "purch-key");
        List<byte[]> copies = new ArrayList<>();
        if (newQuarter == 1) { ledFile.open(CobFile.Mode.INPUT); display(12, 8, "A", 2); }
        else ledFile.open(CobFile.Mode.IO);
        int quarter = sys.intv("current-quarter");
        while (ledFile.readNext(led).equals("00")) {
            BigDecimal current = led.num(p + "current");
            if (current.signum() == 0 && led.num(p + "last").signum() == 0 && led.num(p + "unapplied").signum() == 0)
                led.setNum(p + "status", 0);
            if (current.signum() < 0) {
                led.setNum(p + "unapplied", led.num(p + "unapplied").add(current.negate()));
                led.setNum(p + "current", 0);
            }
            led.setNum(p + "last", led.num(p + "current"));
            if (newQuarter == 1 && quarter >= 1 && quarter <= 4) led.setNum(sl ? "sturnover-q" : "pturnover-q", 0, quarter);
            if (newYear == 1) { led.setNum(p + "average", 0); led.setNum(p + "activety", 0); }
            if (newQuarter == 1) copies.add(fit(led.bytes(), TEMP_LEDGER_LEN));
            else ledFile.rewrite(led);
        }
        ledFile.close();
        if (newQuarter == 1) {
            // phase 1B: 一時ファイル経由でマスタを作り直す
            ledFile.open(CobFile.Mode.OUTPUT);
            display(12, 7, "1B", 2);
            for (byte[] c : copies) ledFile.write(fit(c, led.bytes().length));
            ledFile.close();
            temp.open(CobFile.Mode.OUTPUT); temp.close();
        }

        // phase 2: 未決済明細の整理（決済済みを除去）
        display(12, 7, "2A", 2);
        Rec oi = sl ? oi3Rec() : fdRec("purchase/fdoi5.cob", "open-item-record-5");
        CobFile oiFile = sl ? oi3File(oi) : CobFile.indexed(ctx.store, ctx.path(F_OI5), oi, "oi5-key");
        Rec soi = Layout.of(sl ? "sales/wssoi.cob" : "purchase/wssoi.cob", "si-header").newRec();
        Rec inv = sl ? invoiceRec() : fdRec("purchase/fdpinv.cob", "invoice-record");
        CobFile invFile = sl ? invoiceFile(inv) : CobFile.indexed(ctx.store, ctx.path(F_PINVOICE), inv, "invoice-key");
        Rec hdr = sl ? Layout.of("sales/wsinv.cob", "sinvoice-header").newRec() : Layout.of("purchase/wspinv.cob", "invoice-header").newRec();
        String h = sl ? "sih-" : "ih-";
        oiFile.open(CobFile.Mode.INPUT);
        sort.open(CobFile.Mode.OUTPUT);
        invFile.open(CobFile.Mode.IO);
        List<byte[]> kept = new ArrayList<>();
        while (oiFile.readNext(oi).equals("00")) {
            soi.load(fit(oi.bytes(), soi.bytes().length));
            int type = soi.intv("si-type");
            if (soi.intv("si-status") == 1) { killInvoices(sl, soi, inv, invFile, hdr, h); continue; }
            if (type == 1) continue;
            if (type == 5 || type == 6) soi.setNum("si-deduct-amt", 0);
            soi.set("si-applied", "z");
            soi.setNum("si-p-c", 0);
            byte[] s = fit(soi.bytes(), OI_SORT_LEN);
            sort.write(s);
            kept.add(s);
        }
        oiFile.close(); sort.close(); invFile.close();
        display(12, 7, "2B", 2);
        oiFile.open(CobFile.Mode.OUTPUT);
        for (byte[] k : kept) oiFile.write(fit(k, oi.bytes().length));
        oiFile.close();
        sort.open(CobFile.Mode.OUTPUT); sort.close();

        // phase 3: 分析金額の繰越
        display(12, 7, "3 ", 2);
        Rec val = valueRec();
        CobFile valFile = valueFile(val);
        if (newYear == 1) {
            valFile.open(CobFile.Mode.OUTPUT);
            display(14, 1, "End of year; VALUE File reset", 2);
        } else {
            valFile.open(CobFile.Mode.IO);
            while (valFile.readNext(val).equals("00")) {
                if (!val.str("va-system").equals(sl ? "S" : "P")) continue;
                val.setNum("va-t-last", val.num("va-t-this"));
                val.setNum("va-t-this", 0);
                val.setNum("va-v-last", val.num("va-v-this"));
                val.setNum("va-v-this", 0);
                valFile.rewrite(val);
            }
        }
        valFile.close();

        // phase 4: 請求書ファイルの整理
        display(12, 7, "4A", 2);
        long pfTest = uBin - sys.longv("pf-retention"), invTest = uBin - 92;
        invFile.open(CobFile.Mode.INPUT);
        List<byte[]> out = new ArrayList<>();
        boolean ownNos = sys.str("sl-own-nos").equals("Y");
        phase4:
        while (invFile.readNext(inv).equals("00")) {
            hdr.load(fit(inv.bytes(), hdr.bytes().length));
            int type = hdr.intv(h + "type"), lines = hdr.intv(h + "lines");
            boolean applied = hdr.str(h + "status").equalsIgnoreCase("z");
            if (hdr.intv(h + "test") == 0) {
                if (sl && type == 4 && pfTest > hdr.longv("sih-date")) {
                    if (!skip(invFile, inv, lines)) break;
                    continue;
                }
                if (applied) {
                    if (type < 4) hdr.set(h + "day-book-flag", "B");
                    if (sl) {
                        if (lines != 0 && type == 2) {
                            if (!skip(invFile, inv, lines)) break phase4;
                            hdr.setNum(h + "lines", 0);
                        } else if (type == 1 || type == 3) {
                            if (!skip(invFile, inv, lines)) break phase4;
                            continue;
                        } else if (ownNos && type == 2 && invTest > hdr.longv("sih-date")) continue;
                    } else {
                        if (type == 1 || type == 3) {
                            if (!skip(invFile, inv, lines)) break phase4;
                            continue;
                        }
                        if (lines != 0 && type == 2) {
                            if (!skip(invFile, inv, lines)) break phase4;
                            hdr.setNum(h + "lines", 0);
                        }
                    }
                }
            }
            out.add(fit(hdr.bytes(), TEMP_INVOICE_LEN));
        }
        invFile.close();
        temp.open(CobFile.Mode.OUTPUT);
        for (byte[] o : out) temp.write(o);
        temp.close();
        display(12, 7, "4B", 2);
        invFile.open(CobFile.Mode.OUTPUT);
        for (byte[] o : out) invFile.write(fit(o, inv.bytes().length));
        invFile.close();

        // phase 6: 照合用累計の繰越
        display(12, 7, "5 ", 2);
        String q = sl ? "sl-" : "pl-";
        sys4.setNum(q + "os-bal-last-month", sys4.num(q + "os-bal-this-month"));
        for (String f : new String[] {"os-bal-this-month", "variance", "invoices-this-month", "payments", "credit-deductions",
            "cn-unappl-this-month", "credit-notes-this-month"}) sys4.setNum(q + f, 0);
    }

    /** skip-reader を n 回。ファイル終端なら false（phase-4-end へ）。 */
    private static boolean skip(CobFile invFile, Rec inv, int n) {
        for (int i = 0; i < n; i++) if (!invFile.readNext(inv).equals("00")) return false;
        return true;
    }

    /** kill-invoices / kill-invoicep: 決済済み請求書（type 2）のヘッダと明細行を削除する。 */
    private void killInvoices(boolean sl, Rec soi, Rec inv, CobFile invFile, Rec hdr, String h) {
        if (soi.intv("si-type") != 2) return;
        if (sl && sys.str("sl-own-nos").equals("Y")) return;
        inv.setNum("invoice-nos", soi.longv("si-invoice"));
        if (sl) inv.set("invoice-let", " ");
        int item = 0;
        inv.setNum("item-nos", item);
        invFile.read(inv);
        if (!invFile.status.equals("00")) {
            // test-for-subs
            while (true) {
                inv.setNum("item-nos", ++item);
                invFile.read(inv);
                if (invalidKey(invFile)) return;
                invFile.delete(inv);
                if (invalidKey(invFile)) return;
            }
        }
        hdr.load(fit(inv.bytes(), hdr.bytes().length));
        invFile.delete(inv);
        if (invalidKey(invFile)) return;
        int lines = hdr.intv(h + "lines");
        for (int i = 0; i < lines; i++) {
            inv.setNum("item-nos", ++item);
            invFile.delete(inv);
        }
    }
}
