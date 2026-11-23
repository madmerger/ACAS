package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** sl190.cbl: 督促状データ作成（letter.001〜003 に差込み用 CSV を出力）。 */
public class Sl190 extends SlProgram {
    static final String PROG_NAME = "SL190 (3.01.04)";

    private Rec sys;
    private final CobFile[] letters = new CobFile[3];
    private String wsDate = "";

    private static int d(char c) { return c & 0x0F; }

    @Override
    public void run(Object... args) {
        sys = sys();
        if (sys.intv("file-status", 19) != 1) {
            maps99(19); maps99(15);
            accept(24, 79, 1);
            return;
        }
        eraseEos(1, 1);
        show(2, 2, PROG_NAME, 2);
        display(2, 33, "Letter Production", 2);
        wsDate = pad(fromUk(toDay()), 10);
        show(2, 71, wsDate, 2);
        for (int i = 0; i < 3; i++) {
            letters[i] = CobFile.lineSequential(ctx.store, ctx.path("letter.00" + (i + 1)));
            letters[i].open(CobFile.Mode.OUTPUT);
        }
        statements();
        for (CobFile f : letters) f.close();
    }

    private void statements() {
        display(4, 41, "****************************************", 2);
        display(5, 41, "*Date    [  /  /    ]                  *", 2);
        display(6, 41, "*A/C Nos   [       ]                 ***", 2);
        display(7, 41, "*Value  [         ]*                   *", 2);
        display(8, 41, "****************************************", 2);
        display(12, 1, "Notes", 2);
        display(13, 1, "*****", 2);
        display(15, 1, " (1) - <A/C>   :  A/Cs To Match For Printing", 2);
        display(16, 1, " (2) - <Value> :  Minimum O/S To Print", 2);
        // レガシーは入力した日付を ws-test-date へ移さずに検証する（ws-test-date は空白のまま）。
        // そのため検証は常に失敗し、日付入力を繰り返す。レガシー挙動をそのまま再現する。
        String wsTestDate = " ".repeat(10);
        long payDate;
        while (true) {
            show(5, 51, wsDate, 3);
            acceptUpdate(5, 51, 10, wsDate);
            wsDate = wsTestDate;
            payDate = validateDate(wsTestDate);
            if (payDate != 0) break;
        }
        String customerIn = upper(pad(accept(6, 53, 7), 7));
        show(7, 50, "000000.00");
        long v = 0;
        for (char c : pad(accept(7, 50, 8), 8).toCharArray()) v = v * 10 + d(c);
        BigDecimal payValue = BigDecimal.valueOf(v, 2);
        display(18, 20, "Low Date    - [  ]", 2);
        display(19, 20, "Medium Date - [  ]", 2);
        display(20, 20, "High Date   - [  ]", 2);
        show(18, 35, z(sys.intv("sl-days-1"), 2), 2);
        show(19, 35, z(sys.intv("sl-days-2"), 2), 2);
        show(20, 35, z(sys.intv("sl-days-3"), 2), 2);
        sys.setNum("sl-days-1", intOf(accept(18, 35, 2)));
        sys.setNum("sl-days-2", intOf(accept(19, 35, 2)));
        sys.setNum("sl-days-3", intOf(accept(20, 35, 2)));

        Rec sales = salesRec(), oi = oiHeader(), in = oi3Rec();
        CobFile salesFile = salesFile(sales), oiFile = oi3File(in);
        salesFile.open(CobFile.Mode.INPUT); oiFile.open(CobFile.Mode.INPUT);
        String delim = pad(sys.str("sl-delim"), 1);
        String lastRead = " ".repeat(7);
        long storeWork = 0, siDate = 0;
        String[] lf = new String[4];
        sales:
        while (salesFile.readNext(sales).equals("00")) {
            if (sales.intv("sales-dunning") != 1) continue;
            BigDecimal current = sales.num("sales-current").subtract(sales.num("sales-unapplied"));
            if (current.compareTo(new BigDecimal("0.01")) < 0) continue;
            if (payValue.signum() != 0 && current.compareTo(payValue) < 0) continue;
            String key = pad(sales.str("sales-key"), 7);
            if (!customerIn.isBlank()) {
                boolean truth = true;
                for (int y = 0; y < 6; y++) if (customerIn.charAt(y) != ' ' && customerIn.charAt(y) != key.charAt(y)) truth = false;
                if (!truth) continue;
            }
            String addr = pad(sales.str("sales-address"), 96);
            int a = 1;
            for (int i = 0; i < 4; i++) {
                Object[] u = unstring(addr, delim, a, 36);
                lf[i] = pad(u[0] == null ? "" : (String) u[0], 34);
                a = (Integer) u[1];
            }
            boolean eof = false;
            while (true) {
                if (lastRead.isBlank() && !oiFile.readNext(in).equals("00")) eof = true;
                if (eof) break;
                move(in, oi);
                lastRead = pad(oi.str("oi-customer"), 7);
                if (lastRead.compareTo(key) > 0) break;
                if (lastRead.equals(key) && oi.intv("oi-type") == 2 && oi.intv("oi-status") != 1) {
                    long work1 = (payDate - oi.longv("oi-date")) % 1000000;
                    if (work1 > storeWork) {
                        storeWork = work1;
                        if (oi.longv("oi-date") > siDate) siDate = oi.longv("oi-date");
                    }
                }
                lastRead = " ".repeat(7);
            }
            if (storeWork >= sys.intv("sl-days-1")) letterOut(sales, key, current, lf, storeWork, siDate);
            storeWork = 0; siDate = 0;
            if (eof) break sales;
        }
        oiFile.close(); salesFile.close();
    }

    /** pic £(6)9.99 への転記。 */
    private static String lfOs(BigDecimal v) {
        String s = v.abs().setScale(2, RoundingMode.DOWN).remainder(new BigDecimal(1000000)).toPlainString();
        return " ".repeat(Math.max(0, 9 - s.length())) + "\u00a3" + s;
    }

    private void letterOut(Rec sales, String key, BigDecimal current, String[] lf, long storeWork, long siDate) {
        int nos = storeWork < sys.intv("sl-days-2") ? 1 : storeWork < sys.intv("sl-days-3") ? 2 : 3;
        String q = "\"";
        StringBuilder sb = new StringBuilder();
        sb.append(q).append(delimited(pad(sales.str("sales-name"), 34).replace(',', ';'), "  ")).append(q).append(',');
        for (int i = 0; i < 4; i++) sb.append(q).append(delimited(lf[i].replace(',', ';'), "  ")).append(q).append(',');
        sb.append(q).append(key).append(q).append(',');
        sb.append(lfOs(current)).append(q).append(',');
        wsDate = pad(binToDate(siDate), 10);
        sb.append(q).append(wsDate).append(q);
        String rec = sb.length() > 208 ? sb.substring(0, 208) : sb.toString();
        letters[nos - 1].writeLine(rec);
    }
}
