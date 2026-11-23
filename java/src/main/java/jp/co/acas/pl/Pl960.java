package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;

/** pl960.cbl: 送金案内（Remittance Advice）の印刷。 */
public class Pl960 extends PlBase {
    @Override
    public void run(Object... args) {
        init();
        CobFile cheque = CobFile.lineSequential(ctx.store, ctx.path("cheque.dat"));
        if (!cheque.open(Mode.INPUT).equals("00")) return;
        Printer prt = new Printer("prt-1");
        String box = pad("", 29) + "*".repeat(24), line5 = pad("", 48) + "=".repeat(10);
        boolean first = true;
        String rec;
        while ((rec = cheque.readLine()) != null) {
            String c = pad(rec, 645);
            if (first) prt.after("", 1); else prt.afterPage("");
            first = false;
            prt.after(box, 1);
            prt.after(pad("", 29) + "** Remittance  Advice **", 1);
            prt.after(box, 1);
            prt.after(line1("To ", c.substring(8, 38), "From   ", sys.str("usera")), 3);
            for (int i = 0; i < 5; i++)
                prt.after(line1("", c.substring(39 + 33 * i, 71 + 33 * i), "", i < 4 ? sys.str("address-" + (i + 1)) : ""), 1);
            prt.after("   A/C Number - " + pad(c.substring(0, 7), 19) + "Date " + c.substring(355, 365), 4);
            prt.after(pad("", 10) + "Invoice Nos       Folio" + pad("", 17) + "Amount", 3);
            prt.after("", 1);
            for (int z = 0; z < 9; z++) {
                int o = 366 + 31 * z;
                String amount = c.substring(o + 20, o + 30);
                if (!amount.isBlank())
                    prt.after(pad("", 11) + pad(c.substring(o, o + 10), 14) + pad(c.substring(o + 11, o + 19), 23) + amount, 1);
            }
            prt.after(line5, 3);
            String chq = c.substring(345, 354);
            boolean bacs = chq.equals(pad("BACS", 9));
            prt.after(pad("", 11) + "Total Paid by " + pad(bacs ? "BACS" : "Cheque", 7) + pad(bacs ? "to your Bank" : chq, 16)
                    + c.substring(334, 344), 1);
            prt.after(line5, 1);
        }
        prt.close();
        cheque.close();
        ctx.spool("prt-1", "lpr -P " + sys.str("print-spool-name").trim() + " -r prt-1");
    }

    private static String line1(String to, String addr1, String from, String addr2) {
        return pad(to, 3) + pad(addr1, 32) + pad("", 6) + pad(from, 7) + pad(addr2, 32);
    }
}
