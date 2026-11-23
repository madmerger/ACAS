package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl055.cbl: 請求書転記抽出（請求書 → 未消込明細 2、分析金額の集計）。 */
public class Sl055 extends SlProgram {
    static final String PROG_NAME = "SL055 (3.01.06)";
    static final String SL002 = "SL002 Note error and hit return";
    static final String SL121 = "SL121 Error writing to Open Item 2 File ";
    static final String SL122 = "SL122 Unprinted Invoices Exist. Correct & Run Again";

    private Rec sys, inv, ih, il, val, anal, oi;
    private CobFile invFile, valFile, analFile, oi2File;
    private BigDecimal work2 = BigDecimal.ZERO;
    private long work3;

    @Override
    public void run(Object... args) {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        inv = invoiceRec(); ih = invoiceHeader(); il = invoiceLine();
        val = valueRec(); anal = analysisRec(); oi = oiHeader();
        invFile = invoiceFile(inv); valFile = valueFile(val); analFile = analysisFile(anal);
        oi2File = CobFile.sequential(ctx.store, ctx.path(F_OI2));
        valFile.open(CobFile.Mode.INPUT);
        if (!valFile.status.equals("00")) { valFile.close(); valFile.open(CobFile.Mode.OUTPUT); }
        valFile.close();
        if (sys.intv("file-status", 15) != 1) {
            ctx.shared.put("ws-process-func", 1); ctx.shared.put("ws-sub-function", 1);
            call("sl070");
            if (sys.intv("file-status", 15) != 1) { maps99(29); maps99(15); return; }
        }
        clearScreen();
        display(1, 1, PROG_NAME);
        display(12, 1, "Invoice Post Extract");
        show(1, 71, fromUk(toDay()), 2);
        display(12, 1, "Working...........Please Wait");
        invFile.open(CobFile.Mode.IO); valFile.open(CobFile.Mode.IO); analFile.open(CobFile.Mode.IO);
        oi2File.open(CobFile.Mode.EXTEND);
        if (!oi2File.status.equals("00")) {
            // USE AFTER ERROR PROCEDURE ON open-item-file-2（宣言節は表示後 goback する）
            display(23, 1, SL121);
            show(23, 41, oi2File.status);
            display(23, 44, fileStatMsg(oi2File.status));
            display(24, 1, SL002);
            accept(24, 33, 1);
            return;
        }
        BigDecimal vatV = BigDecimal.ZERO, vatrV = BigDecimal.ZERO, carrV = BigDecimal.ZERO, discV = BigDecimal.ZERO;
        long vatT = 0, vatrT = 0, carrT = 0, discT = 0;
        boolean pFlag = false;
        while (true) {
            invFile.readNext(inv);
            if (!invFile.status.equals("00")) break;
            get();
            if (ih.intv("ih-test") != 0) {
                if (il.str("il-update").equalsIgnoreCase("z")) continue;
                if (il.str("il-product").startsWith("/")) continue;
                BigDecimal net = il.intv("il-type") == 3 ? il.num("il-net").negate() : il.num("il-net");
                val.set("va-system", "S"); val.set("va-group", il.str("il-pa"));
                valFile.read(val);
                boolean exists = !invalidKey(valFile);
                if (!exists) create();
                addValue(1, net);
                if (exists) valFile.rewrite(val); else valFile.write(val);
                if (val.str("va-second").equals(" ")) continue;
                val.set("va-second", " ");
                valFile.read(val);
                if (invalidKey(valFile)) continue;
                addValue(1, net);
                valFile.rewrite(val);
                il.set("il-update", "Z");
                System.arraycopy(il.bytes(), 0, inv.bytes(), 0, il.bytes().length);
                invFile.rewrite(inv);
                continue;
            }
            // da020-Header-Analysis
            boolean analysed = ih.str("ih-update").equalsIgnoreCase("z"), applied = ih.str("ih-status").equalsIgnoreCase("z");
            if (analysed && applied) continue;
            int type = ih.intv("ih-type");
            if (type == 4 || ih.str("ih-status").equals("P") || !ih.str("ih-status-l").equals("L")) {
                if (type != 4) pFlag = true;
                // da030-Skip-Invoice
                inv.setNum("invoice-nos", inv.longv("invoice-nos") + 1);
                inv.set("invoice-let", " "); inv.setNum("item-nos", 0);
                invFile.start(inv, ">=");
                if (invalidKey(invFile)) break;
                continue;
            }
            extract();
            if (analysed) { put(); invFile.rewrite(inv); continue; }
            BigDecimal sg = BigDecimal.valueOf(type == 3 ? -1 : 1);
            BigDecimal w = ih.num("ih-c-vat").add(ih.num("ih-vat")).add(ih.num("ih-e-vat")).multiply(sg);
            if (w.signum() != 0 && type != 1) { vatT++; vatV = vatV.add(w); }
            if (w.signum() != 0 && type == 1) { vatrT++; vatrV = vatrV.add(w); }
            w = ih.num("ih-carriage").multiply(sg);
            if (w.signum() != 0) { carrT++; carrV = carrV.add(w); }
            w = ih.num("ih-deduct-amt").multiply(sg);
            if (w.signum() != 0) { discT++; discV = discV.add(w); }
            ih.set("ih-update", "Z");
            put();
            invFile.rewrite(inv);
        }
        // da040-Close-Files
        val.set("va-code", "Svo"); storeSpecials(vatT, vatV);
        val.set("va-group", "vp"); storeSpecials(vatrT, vatrV);
        val.set("va-group", "zc"); storeSpecials(carrT, carrV);
        val.set("va-group", "zd"); storeSpecials(discT, discV);
        invFile.close(); analFile.close(); valFile.close(); oi2File.close();
        sys.setNum("file-status", 1, 18);
        if (pFlag) {
            display(23, 1, SL122);
            display(24, 1, SL002);
            accept(24, 33, 1);
        }
    }

    private void get() {
        System.arraycopy(inv.bytes(), 0, ih.bytes(), 0, ih.bytes().length);
        System.arraycopy(inv.bytes(), 0, il.bytes(), 0, il.bytes().length);
    }
    private void put() { System.arraycopy(ih.bytes(), 0, inv.bytes(), 0, ih.bytes().length); }

    private void addValue(long t, BigDecimal v) {
        val.setNum("va-t-this", val.longv("va-t-this") + t); val.setNum("va-t-year", val.longv("va-t-year") + t);
        val.setNum("va-v-this", val.num("va-v-this").add(v)); val.setNum("va-v-year", val.num("va-v-year").add(v));
    }

    private void analToValue() {
        System.arraycopy(anal.bytes(), 0, val.bytes(), 0, anal.bytes().length);
        for (String f : new String[] {"va-t-this", "va-t-last", "va-t-year", "va-v-this", "va-v-last", "va-v-year"}) val.setNum(f, 0);
    }

    /** db000-Create: 分析コードから集計レコードを作る（無ければ分析コードを仮登録）。 */
    private void create() {
        while (true) {
            anal.set("pa-code", val.str("va-code"));
            analFile.read(anal);
            if (!invalidKey(analFile)) break;
            // db010-Create-Anal
            anal.set("pa-code", val.str("va-code"));
            anal.setNum("pa-gl", 0); anal.set("pa-print", " "); anal.set("pa-desc", "Emergency Name");
            analFile.write(anal);
            if (!anal.str("pa-second").equals(" ")) { anal.set("pa-second", " "); analFile.write(anal); }
        }
        analToValue();
        if (val.str("va-second").equals(" ")) return;
        String save = val.str("va-code");
        val.set("va-second", " ");
        anal.set("pa-code", val.str("va-code"));
        analFile.read(anal);
        if (invalidKey(analFile)) { anal.set("pa-code", save); return; }
        analToValue();
        valFile.write(val);
        val.set("va-code", save); anal.set("pa-code", save);
        analFile.read(anal);
        if (invalidKey(analFile)) return;
        analToValue();
    }

    /** dc000-Store-Specials */
    private void storeSpecials(long t, BigDecimal v) {
        valFile.read(val);
        boolean exists = !invalidKey(valFile);
        if (!exists) create();
        addValue(t, v);
        if (exists) valFile.rewrite(val); else valFile.write(val);
        val.set("va-second", " ");
        valFile.read(val);
        if (invalidKey(valFile)) return;
        addValue(t, v);
        valFile.rewrite(val);
    }

    /** dd000-Extract */
    private void extract() {
        if (ih.str("ih-status").equalsIgnoreCase("z")) return;
        initialize(oi);
        int type = ih.intv("ih-type");
        BigDecimal sg = BigDecimal.valueOf(type == 3 ? -1 : 1);
        oi.setNum("oi-p-c", ih.num("ih-p-c"));
        oi.setNum("oi-invoice", ih.longv("ih-invoice"));
        oi.set("oi-customer", ih.str("ih-customer"));
        oi.setNum("oi-date", ih.longv("ih-date"));
        oi.setNum("oi-b-nos", 0); oi.setNum("oi-b-item", 0);
        oi.set("oi-description", ih.str("ih-order"));
        for (String f : new String[] {"net", "extra", "carriage", "vat", "c-vat", "e-vat", "discount"}) oi.setNum("oi-" + f, ih.num("ih-" + f).multiply(sg));
        oi.setNum("oi-paid", 0);
        oi.setNum("oi-deduct-amt", ih.num("ih-deduct-amt").multiply(sg));
        oi.setNum("oi-deduct-vat", ih.num("ih-deduct-vat").multiply(sg));
        oi.setNum("oi-deduct-days", ih.longv("ih-deduct-days"));
        oi.setNum("oi-status", 0); oi.setNum("oi-date-cleared", 0); oi.setNum("oi-days", 0);
        oi.setNum("oi-type", type);
        oi.set("oi-applied", " "); oi.set("oi-unapl", " "); oi.set("oi-hold-flag", " ");
        oi.setNum("oi-cr", ih.longv("ih-cr"));
        if (type != 1) {
            BigDecimal amt = BigDecimal.ZERO;
            for (String f : new String[] {"net", "extra", "carriage", "discount", "vat", "c-vat", "e-vat", "deduct-amt", "deduct-vat"}) amt = amt.add(ih.num("ih-" + f));
            Rec s4 = sys4();
            if (type == 2) s4.setNum("sl-invoices-this-month", s4.num("sl-invoices-this-month").add(amt));
            if (type == 3) s4.setNum("sl-credit-notes-this-month", s4.num("sl-credit-notes-this-month").add(amt));
        }
        ih.set("ih-status", "Z"); ih.set("ih-status-a", "A");
        byte[] out = new byte[114];
        java.util.Arrays.fill(out, (byte) ' ');
        System.arraycopy(oi.bytes(), 0, out, 0, Math.min(114, oi.bytes().length));
        oi2File.write(out);
    }
}
