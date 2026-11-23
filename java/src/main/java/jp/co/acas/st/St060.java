package jp.co.acas.st;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.math.BigDecimal;

/**
 * st060.cbl: 在庫品目の一括取込（カンマ区切り）。レガシーの在庫メニューからは呼ばれない（load06 は GO TO 表から外されている）。
 * 原文の Import-Mode は 1（カンマ区切り）固定のため、固定長（ba020-Process-Regular）は到達不能で移植していない。
 */
public class St060 extends StProgram {
    static final String PROG_NAME = "ST060 (3.01.00)";
    private static final String DEFAULT_PA = "Pa1", DEFAULT_SA = "Sa1", DEFAULT_SUPPLIER = "A000011";

    private Rec sys, stock;
    private CobFile stockFile, importFile;
    private String rec = "";     // Import-Record（512 桁）
    private int b, c;            // UNSTRING の POINTER / COUNT
    private long abrevValue;

    /** STOP RUN 相当で取込みを打ち切る。 */
    private static final class Abort extends RuntimeException { }

    @Override
    public void run(Object... args) {
        sys = SystemFile.shared(ctx);
        String toDay = St.x((String) ctx.shared.getOrDefault("to-day", ""), 10);
        // zz010-Display-Heading
        eraseEos(1, 1);
        display(1, 1, PROG_NAME);
        show(3, 1, sys.str("usera"));
        show(1, 71, St.fromUk(toDay, sys.intv("date-form")), 2);
        display(1, 24, "Stock File Importer");
        display(7, 1, "Provide full path and file name of file to be imported");
        String file101 = acceptUpdate(9, 2, 64, St.x("", 64), 0);
        try {
            importStock(file101.strip());
        } catch (Abort e) {
            stockFile.close(); importFile.close();
            stopRun();
        }
    }

    /** ba000-Import-Stock。 */
    private void importStock(String name) {
        stock = Layout.of("copybooks/fdstock.cob", "Stock-Record").newRec();
        stockFile = St.stockFile(ctx, stock);
        importFile = CobFile.sequential(ctx.store, name);
        if (!stockFile.open(CobFile.Mode.IO).equals("00")) {
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
        }
        if (name.isEmpty() || !importFile.open(CobFile.Mode.INPUT).equals("00")) {
            fileError("ST601 Error on Open/Reading Import File - ", 37, name.isEmpty() ? "31" : importFile.status);
            return;
        }
        long recordCount = 0, writeCount = 0;
        while (true) {
            String data = importFile.readLine();
            if (data == null) break;
            rec = St.x(data, 512);
            recordCount++;
            stock.initialize();
            // ba030-Process-Comma
            b = 1;
            String key = unstring(13, false);
            if (key != null) stock.set("stock-key", key);
            if (c <= 7) stock.set("stock-abrev-key", stock.str("stock-key"));
            else stock.set("stock-abrev-key", Num.z9(++abrevValue % 10_000_000, 7));
            stock.set("stock-supplier-p1", DEFAULT_SUPPLIER);
            String desc = unstring(36, false);
            if (desc == null) desc = St.x("", 36);
            char q = desc.charAt(0);
            if (q == '"' || q == '\'' || q == '`') {
                int cc = 36;
                while (cc >= 4 && desc.charAt(cc - 1) != q) cc--;
                stock.set("stock-desc", cc - 2 > 0 ? desc.substring(1, cc - 1) : "");
            } else stock.set("stock-desc", desc);
            stock.set("stock-pa-code", DEFAULT_PA);
            stock.set("stock-sa-code", DEFAULT_SA);
            stock.set("stock-services-flag", "N");
            for (String f : new String[] {"stock-reorder-pnt", "stock-std-reorder", "stock-back-ordered", "stock-on-order",
                "stock-held", "stock-pre-sales"}) {
                String x8 = unstring(8, false);
                stock.setNum(f, formatNumber(x8 == null ? "00000000" : x8));
            }
            String x14 = unstring(14, false);
            stock.setNum("stock-retail", formatAmount(x14 == null ? "0".repeat(14) : x14));
            x14 = unstring(14, false);
            stock.setNum("stock-cost", formatAmount(x14 == null ? "0".repeat(14) : x14));
            x14 = unstring(14, true);
            stock.setNum("stock-value", formatAmount(x14 == null ? "0".repeat(14) : x14));
            String d = unstring(12, true);
            long bin = d == null ? 0 : Maps04.toBin(d.substring(1, 11));
            if (bin != 0) stock.setNum("stock-order-date", bin);
            String d2 = unstring(12, true);
            if (d2 == null) d2 = St.x("", 12);
            bin = Maps04.toBin(d2.substring(1, 11));
            if (bin != 0) stock.setNum("stock-order-due", bin);
            // ba040-Write-Stock
            String fs = stockFile.write(stock);
            if (!fs.equals("00")) {
                fileError("ST000 Error on Writing to Stock File", 38, fs);
                return;
            }
            writeCount++;
        }
        // ba998-Main-End
        stockFile.close(); importFile.close();
        eraseEos(6, 1);
        display(6, 1, "Records Imported - ");
        show(6, 20, Num.edit(recordCount, "z(6)9"), 2);
        display(6, 1, "Records Written  - ");
        show(6, 20, Num.edit(writeCount, "z(6)9"), 2);
        display(8, 1, "ST603 Note total and hit return");
        accept(8, 35, 1);
    }

    /** DECLARATIVES（File-Error-On-IF / File-Error-On-Stock）。 */
    private void fileError(String msg, int col, String fs) {
        display(23, 1, msg, 4);
        show(23, col, fs, 4);
        display(23, 40, St.evalStatus(fs));
        display(24, 1, "ST602 Note error and hit return");
        accept(24, 33, 1);
        stockFile.close(); importFile.close();
    }

    /**
     * UNSTRING Import-Record DELIMITED BY "," [OR SPACE] INTO 受取り項目 COUNT c POINTER b。
     * ポインタが範囲外（オーバーフロー）のときは null（受取り項目・COUNT とも不変）。
     */
    private String unstring(int size, boolean orSpace) {
        if (b < 1 || b > rec.length()) return null;
        int i = b - 1;
        while (i < rec.length() && rec.charAt(i) != ',' && !(orSpace && rec.charAt(i) == ' ')) i++;
        String v = rec.substring(b - 1, i);
        c = v.length();
        b = i + 2;
        return St.x(v, size);
    }

    private static boolean numeric(String s) { return !s.isEmpty() && s.chars().allMatch(ch -> ch >= '0' && ch <= '9'); }
    /** 英数字 → 数字項目への MOVE（右詰め・ゼロ埋め・左切捨て）。 */
    private static String toNumeric(String s, int n) {
        String t = s.length() > n ? s.substring(s.length() - n) : "0".repeat(n - s.length()) + s;
        return t;
    }

    /** zz025-Format-Number / zz027-Clean-Number（原文の桁合わせをそのまま再現）。 */
    private long formatNumber(String x8) {
        String number;
        int c2 = c;
        char q = x8.charAt(0);
        if (q == '"' || q == '\'' || q == '`') {
            c = 8;
            while (c >= 3 && x8.charAt(c - 1) != q) c--;
            number = c - 2 > 0 ? toNumeric(x8.substring(1, c - 1), 6) : "000000";
        } else number = St.x(x8.substring(0, Math.min(c2, 8)), 6);
        if (!numeric(number)) number = "000000";
        char[] chk = "000000".toCharArray();
        for (int d = 6; c >= 1 && d >= 1; d--, c--) if (c <= 6) chk[d - 1] = number.charAt(c - 1);
        return Long.parseLong(new String(chk));
    }

    /** zz030-Format-Amount（9(9)v9(4) へ整形）。不正データは原文どおり表示して打ち切る。 */
    private BigDecimal formatAmount(String x14) {
        String amount;
        int c2 = c;
        char q = x14.charAt(0);
        if (q == '"' || q == '\'' || q == '`') {
            c = c2;
            while (c >= 3 && x14.charAt(c - 1) != q) c--;
            amount = St.x(c2 - 2 > 0 ? x14.substring(1, Math.min(c2 - 1, 14)) : "", 13);
            if (c == c2) c2 -= 2;
            else {
                display(16, 1, "Problem with amount - ", 3);
                show(16, 23, x14);
                display(16, 38, "Has invalid quotes or other!", 3);
                display(17, 1, "ST604 Note error and hit return to quit", 3);
                accept(17, 41, 1);
                throw new Abort();
            }
        } else amount = St.x(x14.substring(0, Math.min(c2, 14)), 13);
        int amountLength = c2;
        boolean period = amount.indexOf('.') >= 0;
        if (period) {
            c = c2;
            while (c >= 2 && (c > 13 || amount.charAt(c - 1) != '.')) c--;
        }
        char[] chk = "0000000000000".toCharArray();
        if (period && c > 1) {
            int pence = Math.min(c2 - c, 4), pounds = Math.min(c - 1, 9);
            for (int i = 0; i < pence; i++) chk[9 + i] = amount.charAt(c + i);
            for (int i = 0; i < pounds; i++) chk[9 - pounds + i] = amount.charAt(c - 1 - pounds + i);
        }
        if (!period) {
            int f = Math.min(amountLength, 9);
            for (int i = 0; i < f; i++) chk[9 - f + i] = amount.charAt(i);
        }
        String s = new String(chk);
        if (!numeric(s)) {
            display(16, 1, "Problem with amount - ", 3);
            show(16, 23, x14);
            display(16, 38, "Has become - ", 3);
            show(16, 51, s);
            display(17, 1, "ST604 Note error and hit return to quit", 3);
            accept(17, 41, 1);
            throw new Abort();
        }
        return new BigDecimal(s).movePointLeft(4);
    }
}
