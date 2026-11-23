package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl940.cbl: 小切手印刷用データ（cheque.dat）の生成。 */
public class Pl940 extends PlPay {
    static final String PROG_NAME = "PL940 (3.01.04)";
    private static final String[] UNITS = {"", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
            "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"};
    private static final String[] TENS = {"", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"};

    /** wordn(n): 1〜99 の英語表記（小切手の金額文言はデータとしてそのまま出力する）。 */
    static String wordn(int n) {
        if (n < 20) return UNITS[n];
        return TENS[n / 10] + (n % 10 == 0 ? "" : "-" + UNITS[n % 10]);
    }

    /** 金額（9(7)v99）→ c-words-1 / c-words-2（各 64 桁）。 */
    static String[] words(BigDecimal gross) {
        long t = u9(gross).movePointRight(2).longValue();
        StringBuilder w1 = new StringBuilder(), w2 = new StringBuilder();
        boolean poundFlag = false;
        int y = (int) (t / 100_000_000) % 100; t %= 100_000_000;
        if (y > 0) w1.append(wordn(y)).append(" Million ");
        y = (int) (t / 10_000_000); t %= 10_000_000;
        if (y > 0) w1.append(wordn(y)).append(" Hundred and ");
        y = (int) (t / 100_000); t %= 100_000;
        if (y > 0) w1.append(wordn(y)).append(" Thousand ");
        if (w1.length() > 0) poundFlag = true;
        w1.append("*".repeat(64));
        y = (int) (t / 10_000); t %= 10_000;
        if (y > 0) w2.append(wordn(y)).append(" Hundred and ");
        y = (int) (t / 100); t %= 100;
        if (y > 0) w2.append(wordn(y));
        if (w2.length() > 0) poundFlag = true;
        if (y > 0 || poundFlag) w2.append(" Pounds ");
        y = (int) t;
        if (y > 0) w2.append(wordn(y)).append(" Pence ");
        else w2.append("ONLY");
        return new String[]{pad(w1.toString(), 64), pad(w2.toString(), 64)};
    }

    @Override
    public void run(Object... args) {
        init();
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 28, "Cheque Print File Generation");
        String wsDate = fromUk(toDay());
        show(1, 71, wsDate, 2);
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        Rec pay = payRec();
        CobFile payFile = payFile(pay);
        purchaseFile.open(Mode.INPUT);
        if (!payFile.open(Mode.IO).equals("00")) {
            display(4, 1, "PL903 No data to process. Hit return");
            accept(4, 38, 1);
            purchaseFile.close(); payFile.close();
            return;
        }
        CobFile cheque = CobFile.lineSequential(ctx.store, ctx.path("cheque.dat"));
        cheque.open(Mode.OUTPUT);
        display(6, 11, "First Cheque number - [        ]");
        long chequeNos = numOf(accept(6, 34, 8));
        display(8, 11, "Payment date        - [          ]");
        String testDate = wsDate;
        long uBin;
        do {
            show(8, 34, testDate);
            testDate = pad(acceptUpdate(8, 34, 10, testDate), 10);
            uBin = validateDate(testDate);
        } while (uBin == 0);
        String delim = sys.str("pl-delim");
        while (payFile.readNext(pay).equals("00")) {
            if (pay.num("pay-gross").compareTo(bd("0.01")) < 0) continue;
            String key = pay.str("pay-supl-key");
            purch.set("purch-key", key);
            if (invalid(purchaseFile.read(purch))) {
                purch.set("purch-name", "PL902 Missing data");
                purch.set("purch-addr1", "PL902 Missing data");
                purch.set("purch-addr2", "");
            }
            String[] adr = pieces(purch.str("purch-addr1") + purch.str("purch-addr2"), delim, 5);
            String[] w = words(pay.num("pay-gross"));
            StringBuilder sb = new StringBuilder();
            sb.append(pad(key, 7)).append(',').append(pad(purch.str("purch-name"), 30)).append(',');
            for (int y = 0; y < 5; y++) sb.append(pad(adr[y], 32)).append(',');
            sb.append(w[0]).append(',').append(w[1]).append(',');
            sb.append(Num.edit(u9(pay.num("pay-gross")), "z(6)9.99")).append(',');
            if (pay.longv("pay-sortcode") == 0) {
                sb.append(Num.edit(chequeNos, "z(8)9"));
                pay.setNum("pay-cheque", chequeNos);
                chequeNos = (chequeNos + 1) % 100_000_000;
            } else {
                pay.setNum("pay-cheque", 0);
                sb.append(pad("BACS", 9));
            }
            sb.append(',').append(testDate).append(',');
            for (int z = 1; z <= 9; z++) {
                sb.append(pad(pay.str("pay-invoice", z), 10)).append(',')
                        .append(Pl095.bwz(pay.longv("pay-folio", z), "z(7)9", 8)).append(',')
                        .append(Pl095.bwz(pay.num("pay-value", z).abs(), "z(6)9.99", 10)).append(z < 9 ? ',' : ' ');
            }
            cheque.writeLine(sb.toString());
            pay.setNum("pay-date", uBin);
            payFile.rewrite(pay);
        }
        cheque.close(); purchaseFile.close(); payFile.close();
    }
}
