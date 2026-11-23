package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

/** sl160.cbl: 顧客名順一覧（sl165 が作る custsort.tmp の順に印字）。 */
public class Sl160 extends CustReport {
    static final String PROG_NAME = "SL160 (3.01.16)";
    static final String SL170 = "SL170 Not Found - ";

    private Rec sales, deliv;
    private CobFile salesFile, delivFile;
    private Prt print;
    private int a, lineCnt, pageLines;
    private String l3Report = "";

    @Override
    public void run(Object... args) {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        sales = salesRec(); deliv = deliveryRec();
        salesFile = salesFile(sales); delivFile = deliveryFile(deliv);
        salesFile.open(CobFile.Mode.INPUT); delivFile.open(CobFile.Mode.INPUT);
        reportSelection(PROG_NAME, true);
        l3Report = reportHeadingSetup(true, " days overdue");
        CobFile sort = CobFile.sequential(ctx.store, ctx.path(F_CUSTSORT));
        reportProduce(sort);
        print.close(); sort.close();
        salesFile.close(); delivFile.close();
        spoolReport("prt-1", sys.str("print-spool-name"), true);
        sort.open(CobFile.Mode.OUTPUT); sort.close();
    }

    private void reportProduce(CobFile sort) {
        Rec key = sortKeyRec();
        sort.open(CobFile.Mode.INPUT);
        pageLines = sys.intv("page-lines");
        print = new Prt(ctx, "prt-1");
        print.openOutput();
        a = 0;
        headings();
        while (sort.readNext(key).equals("00")) {
            String k = pad(key.str("sales-sort-key"), 7);
            sales.set("sales-key", k);
            if (!customerIn.isBlank() && k.compareTo(customerIn) < 0) continue;
            if (!customerIn.isBlank() && k.compareTo(pad(custIn, 7)) > 0) continue;
            salesFile.read(sales);
            if (invalidKey(salesFile)) {
                display(23, 1, SL170, 4);
                show(23, 20, k, 4);
                continue;
            }
            eraseEol(23, 1);
            int status = sales.intv("sales-status");
            if (statusIn.equals("L") && status == 0) continue;
            if (statusIn.equals("D") && status == 1) continue;
            if (!matchNumeric(sales, true)) continue;
            listing();
        }
    }

    private void headings() {
        a++;
        String l1 = pad(PROG_NAME, 51) + pad("Customer Alphabetical Listing", 73) + "Page " + Num.edit(a, "zz9");
        String l3 = pad(sys.str("usera"), 40) + "Report On : " + pad(l3Report, 70) + pad(fromUk(toDay()), 10);
        if (a != 1) { print.afterPage(l1); print.after(l3, 1); print.after("", 1); }
        else { print.before(l1, 1); print.before(l3, 1); }
        print.after(pad("Customer  Status    <---------------Name & Address-------------->     ----Telephone---- -----Fax-----     Late       Credit", 127) + "Disc ", 2);
        print.after(" " + pad("Number   ------", 103) + "Chg  Let   Limit/Days    %", 1);
        print.after("", 1);
        lineCnt = 6;
    }

    private static String bwz(long v, String pic, int width) { return v == 0 ? " ".repeat(width) : pad(Num.edit(v, pic), width); }

    private String line6(String key, String status, String name, String phone, String fax, String charges, String letter, String limit, String credit, String discount) {
        return pad(key, 10) + pad(status, 10) + pad(name, 50) + pad(phone, 18) + pad(fax, 13) + "    " + pad(charges, 5) + pad(letter, 3) + limit + credit + discount;
    }

    private void listing() {
        if (lineCnt > pageLines) headings();
        String delim = pad(sys.str("sl-delim"), 1);
        String phone;
        if (sales.str("sales-ext").isBlank()) phone = pad(sales.str("sales-phone"), 18);
        else {
            StringBuilder p = new StringBuilder(" ".repeat(18));
            int y = stringInto(p, 1, delimited(pad(sales.str("sales-phone"), 13), "  "));
            y++;
            y = stringInto(p, y, "x");
            stringInto(p, y, pad(sales.str("sales-ext"), 4));
            phone = p.toString();
        }
        java.math.BigDecimal disc = sales.num("sales-discount");
        String l6 = line6(sales.str("sales-key"), sales.intv("sales-status") == 1 ? "Active" : "Dormant", sales.str("sales-name"), phone, sales.str("sales-fax"),
            sales.intv("sales-late") == 1 ? "Y" : " ", sales.intv("sales-dunning") == 1 ? "Y" : " ",
            bwz(sales.longv("sales-limit") % 10000000, "z(6)9", 7), bwz(sales.longv("sales-credit"), "zzz9", 7),
            disc.signum() == 0 ? " ".repeat(5) : Num.edit(disc, "z9.99"));
        String l7 = " ".repeat(20) + pad(sales.str("sales-address"), 112).replace(delim, ",");
        if (lineCnt > pageLines - 3) headings();
        print.after(l6, 1);
        print.after(l7, 1);
        if (sales.intv("delivery-tag") > 0) {
            readDeliv("D");
            print.after(line6("   Deliver", "y Address", deliv.str("deliv-name"), "", sales.str("sales-fax"), " ", " ", " ".repeat(7), " ".repeat(7), " ".repeat(5)), 1);
            l7 = " ".repeat(20) + pad(deliv.str("deliv-address"), 112).replace(delim, ",");
            print.after(l7, 1);
            lineCnt += 2;
        }
        if (sales.intv("notes-tag") > 0) {
            readDeliv("N");
            // STRING は l7-address の先頭から上書きし、残りは直前の内容が残る。
            String prev = l7.substring(20);
            String s = "Notes: " + pad(deliv.str("deliv-address"), 96);
            print.after(" ".repeat(20) + s + prev.substring(Math.min(s.length(), 112)), 1);
            lineCnt++;
        }
        print.after("", 1);
        lineCnt += 3;
        if (lineCnt > pageLines) headings();
    }

    private void readDeliv(String type) {
        deliv.set("deliv-key-type", type);
        deliv.set("deliv-sales-key", sales.str("sales-key"));
        delivFile.read(deliv);
        if (invalidKey(delivFile)) { deliv.set("deliv-name", "Record not found"); deliv.set("deliv-address", "Record not found"); }
    }
}
