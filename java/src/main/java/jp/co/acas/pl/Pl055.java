package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl055.cbl: 仕入請求書 転記前抽出（分析値の集計と未決済項目の抽出）。 */
public class Pl055 extends PlBase {
    static final String PROG_NAME = "PL055 (3.01.03)";
    private Rec anal, val, ih, il, oi;
    private CobFile analysisFile, valueFile, invoiceFile, oi4;
    private int analCreated, vExists;

    @Override
    public void run(Object... args) {
        init();
        term().exceptionsEnabled = true; term().escEnabled = true;
        anal = analRec();
        val = Layout.of("copybooks/fdval.cob", "value-record").newRec();
        java.util.Arrays.fill(val.bytes(), (byte) 0);
        ih = invHeaderRec(); il = Layout.of("purchase/fdpinv2.cob", "invoice-line").wrap(ih.bytes());
        oi = oiRec();
        java.util.Arrays.fill(oi.bytes(), (byte) 0);
        analysisFile = analysisFile(anal);
        valueFile = CobFile.indexed(ctx.store, ctx.path("value.dat"), val, "va-code");
        invoiceFile = invoiceFile();
        oi4 = CobFile.sequential(ctx.store, ctx.path("openitm4.dat"));
        if (!valueFile.open(Mode.INPUT).equals("00")) {
            valueFile.close();
            valueFile.open(Mode.OUTPUT);
        }
        valueFile.close();
        if (sys.intv("file-status", 15) == 0) {
            maps99(29);
            maps99(15);
            return;
        }
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 33, "Invoice Post Extract");
        show(1, 71, fromUk(toDay()), 2);
        invoiceFile.open(Mode.IO); valueFile.open(Mode.IO); analysisFile.open(Mode.IO);
        if (!oi4.open(Mode.EXTEND).equals("00")) {
            oi4.close();
            oi4.open(Mode.OUTPUT);
        }
        int vatT = 0, vatrT = 0, carrT = 0, discT = 0;
        BigDecimal vatV = BigDecimal.ZERO, vatrV = BigDecimal.ZERO, carrV = BigDecimal.ZERO, discV = BigDecimal.ZERO;
        while (invoiceFile.readNext(ih).equals("00")) {
            if (ih.intv("ih-test") != 0) {
                // 明細行
                if (il.str("il-update").equalsIgnoreCase("z")) continue;
                val.set("va-system", "P");
                val.set("va-group", il.str("il-pa"));
                vExists = 1;
                if (invalid(valueFile.read(val))) { create(); vExists = 0; }
                BigDecimal net = il.str("il-type").equals("3") ? il.num("il-net").negate() : il.num("il-net");
                bump(1, net);
                if (vExists == 0) valueFile.write(val); else valueFile.rewrite(val);
                if (val.str("va-second").equals(" ")) continue;
                val.set("va-second", " ");
                if (invalid(valueFile.read(val))) continue;
                bump(1, net);
                valueFile.rewrite(val);
                il.set("il-update", "z");
                invoiceFile.rewrite(ih);
                continue;
            }
            // header-analysis
            boolean analysed = ih.str("ih-update").equalsIgnoreCase("z"), applied = ih.str("ih-status").equalsIgnoreCase("z");
            if (analysed && applied) continue;
            extract(applied);
            if (analysed) { invoiceFile.rewrite(ih); continue; }
            int type = ih.intv("ih-type");
            BigDecimal w = ih.num("ih-c-vat").add(ih.num("ih-vat"));
            if (type == 3) w = w.negate();
            if (w.signum() != 0 && type != 1) { vatT++; vatV = vatV.add(w); }
            if (w.signum() != 0 && type == 1) { vatrT++; vatrV = vatrV.add(w); }
            w = ih.num("ih-carriage");
            if (type == 3) w = w.negate();
            if (w.signum() != 0) { carrT++; carrV = carrV.add(w); }
            w = ih.num("ih-deduct-amt");
            if (w.signum() != 0) { discT++; discV = discV.add(w); }
            ih.set("ih-update", "z");
            invoiceFile.rewrite(ih);
        }
        val.set("va-system", "P");
        val.set("va-group", "vi"); storeSpecials(vatT, vatV);
        val.set("va-group", "vj"); storeSpecials(vatrT, vatrV);
        val.set("va-group", "za"); storeSpecials(carrT, carrV);
        val.set("va-group", "zb"); storeSpecials(discT, discV);
        invoiceFile.close(); analysisFile.close(); valueFile.close(); oi4.close();
        sys.setNum("file-status", 1, 28);
        if (analCreated != 0) {
            display(12, 1, "PL201 Analyst records with desc, 'Emergency Name' created");
            display(14, 1, "PL202 You will need to update these");
            display(16, 1, "PL006 Note Details & Hit Return to continue");
            accept(16, 45, 1);
        }
    }

    private void bump(int count, BigDecimal v) {
        val.setNum("va-t-this", val.longv("va-t-this") + count);
        val.setNum("va-t-year", val.longv("va-t-year") + count);
        val.setNum("va-v-this", val.num("va-v-this").add(v));
        val.setNum("va-v-year", val.num("va-v-year").add(v));
    }

    /** move analysis-record to value-record（36 バイト + 空白埋め）と件数・金額のゼロ化。 */
    private void fromAnalysis() {
        byte[] v = val.bytes();
        java.util.Arrays.fill(v, (byte) ' ');
        System.arraycopy(anal.bytes(), 0, v, 0, 36);
        for (String f : new String[]{"va-t-this", "va-t-last", "va-t-year", "va-v-this", "va-v-last", "va-v-year"}) val.setNum(f, 0);
    }

    private void create() {
        while (true) {
            anal.set("pa-code", val.str("va-code"));
            if (invalid(analysisFile.read(anal))) {
                // create-anal
                anal.set("pa-code", val.str("va-code"));
                anal.setNum("pa-gl", 0);
                anal.set("pa-print", "");
                anal.set("pa-desc", "Emergency Name");
                analCreated = 1;
                analysisFile.write(anal);
                if (!anal.str("pa-second").equals(" ")) {
                    anal.set("pa-second", " ");
                    analysisFile.write(anal);
                }
                continue;
            }
            fromAnalysis();
            if (val.str("va-second").equals(" ")) return;
            String save = val.str("va-code");
            val.set("va-second", " ");
            anal.set("pa-code", val.str("va-code"));
            if (invalid(analysisFile.read(anal))) { anal.set("pa-code", save); return; }
            fromAnalysis();
            valueFile.write(val);
            val.set("va-code", save); anal.set("pa-code", save);
            if (invalid(analysisFile.read(anal))) return;
            fromAnalysis();
            return;
        }
    }

    private void storeSpecials(int count, BigDecimal v) {
        vExists = 1;
        if (invalid(valueFile.read(val))) { create(); vExists = 0; }
        bump(count, v);
        if (vExists == 0) valueFile.write(val); else valueFile.rewrite(val);
        val.set("va-second", " ");
        if (invalid(valueFile.read(val))) return;
        bump(count, v);
        valueFile.rewrite(val);
    }

    private void extract(boolean applied) {
        if (applied) return;
        int type = ih.intv("ih-type");
        oi.setNum("oi-p-c", 0);
        oi.setNum("oi-invoice", ih.longv("ih-invoice"));
        oi.set("oi-supplier", ih.str("ih-supplier"));
        oi.setNum("oi-date", ih.longv("ih-date"));
        oi.setNum("oi-b-nos", 0); oi.setNum("oi-b-item", 0);
        oi.set("oi-order", ih.str("ih-order"));
        oi.set("oi-ref", ih.str("ih-ref"));
        oi.setNum("oi-net", ih.num("ih-net"));
        oi.setNum("oi-extra", 0);
        oi.setNum("oi-carriage", ih.num("ih-carriage"));
        oi.setNum("oi-vat", ih.num("ih-vat"));
        oi.setNum("oi-c-vat", ih.num("ih-c-vat"));
        oi.setNum("oi-e-vat", 0); oi.setNum("oi-discount", 0); oi.setNum("oi-paid", 0);
        oi.setNum("oi-days", ih.intv("ih-days"));
        oi.setNum("oi-deduct-amt", ih.num("ih-deduct-amt"));
        oi.setNum("oi-deduct-vat", 0);
        oi.setNum("oi-deduct-days", ih.intv("ih-deduct-days"));
        oi.setNum("oi-status", 0); oi.setNum("oi-date-cleared", 0);
        oi.setNum("oi-type", type);
        oi.set("oi-applied", " "); oi.set("oi-hold-flag", " ");
        if (type == 3) for (String f : new String[]{"oi-net", "oi-carriage", "oi-vat", "oi-c-vat"}) oi.setNum(f, oi.num(f).negate());
        oi.setNum("oi-cr", ih.longv("ih-cr"));
        Rec s4 = sys4();
        BigDecimal amt = ih.num("ih-net").add(ih.num("ih-carriage")).add(ih.num("ih-vat")).add(ih.num("ih-c-vat"));
        if (type == 2) s4.setNum("pl-invoices-this-month", s4.num("pl-invoices-this-month").add(amt));
        if (type == 3) s4.setNum("pl-credit-notes-this-month", s4.num("pl-credit-notes-this-month").add(amt));
        ih.set("ih-status", "z");
        oi4.write(java.util.Arrays.copyOf(oi.bytes(), 109));
    }
}
