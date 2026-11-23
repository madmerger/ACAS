package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** pl930.cbl: 支払予定の検証帳票（Payments Due Proof Report）。 */
public class Pl930 extends PlPay {
    static final String PROG_NAME = "PL930 (3.01.07)";
    private static final String LINE4 = pad("", 38)
            + "Folio M    Date     Invoice      Current       30 +        60 +        90 +       Total to Pay";

    @Override
    public void run(Object... args) {
        init();
        String line1 = pad(PROG_NAME, 53) + pad("Payments Due Proof Report", 71) + "Page ";
        String line2 = pad(sys.str("usera"), 53) + pad("", 69) + fromUk(toDay());
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        Rec pay = payRec();
        CobFile payFile = payFile(pay);
        purchaseFile.open(Mode.INPUT);
        boolean payOpen = payFile.open(Mode.INPUT).equals("00");
        prt = new Printer("prt-1");
        headings(line1, line2, LINE4);
        if (!payOpen) {
            // レガシーは未オープンの READ（状態 47）が AT END にならず、空行を際限なく印字し続ける。
            // Web 版では見出しのみ出力して打ち切る。
            prt.close();
            purchaseFile.close();
            return;
        }
        int pageLines = sys.intv("page-lines");
        boolean more = payFile.readNext(pay).equals("00");
        boolean newKey = true;
        while (more) {
            if (newKey) {
                if (lineCnt != 5) prt.after("", 1);
                lineCnt++;
                purch.set("purch-key", pay.str("pay-supl-key"));
                if (invalid(purchaseFile.read(purch))) {
                    purch.set("purch-key", "Z".repeat(7));
                    purch.set("purch-name", "Z".repeat(30));
                }
                l5Supplier = pad(purch.str("purch-name"), 23);
                l5Key = pay.str("pay-supl-key") + "/" + Num.z9(Math.floorMod(pay.intv("pay-nos"), 100), 2);
            }
            for (int z = 1; z <= 9; z++) {
                BigDecimal v = pay.num("pay-value", z);
                if (v.signum() == 0) continue;
                l5Method = pay.longv("pay-sortcode") != 0 ? "B" : "C";
                l5Invoice = pay.str("pay-invoice", z);
                l5Folio = Num.edit(pay.longv("pay-folio", z), "z(7)9");
                l5Date = binToDate(pay.longv("pay-date"));
                switch (pay.intv("pay-period", z)) {
                    case 0 -> bal0 = u9(v);
                    case 30 -> bal30 = u9(v);
                    case 60 -> bal60 = u9(v);
                    case 90 -> bal90 = u9(v);
                    default -> { }
                }
                balT = u9(balT.add(v));
                tot0 = u9(tot0.add(bal0)); tot30 = u9(tot30.add(bal30));
                tot60 = u9(tot60.add(bal60)); tot90 = u9(tot90.add(bal90));
                prt.after(line5(12), 1);
                lineCnt++;
                if (lineCnt > pageLines) headings(line1, line2, LINE4);
                bal0 = bal30 = bal60 = bal90 = BigDecimal.ZERO;
                l5Key = ""; l5Supplier = "";
            }
            if (pay.str("pay-cont").equals("C")) {
                more = payFile.readNext(pay).equals("00");
                if (!more) { totT = u9(totT.add(balT)); break; }
                newKey = !purch.str("purch-key").equals(pay.str("pay-supl-key"));
            } else {
                totT = u9(totT.add(balT));
                balT = BigDecimal.ZERO;
                more = payFile.readNext(pay).equals("00");
                newKey = true;
            }
        }
        prt.after(line7(), 1);
        prt.after(line6(totT), 1);
        prt.close();
        purchaseFile.close(); payFile.close();
        spoolPrt1();
    }
}
