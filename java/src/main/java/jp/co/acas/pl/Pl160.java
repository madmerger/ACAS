package jp.co.acas.pl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.CobFile.Mode;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;


/** pl160.cbl: 仕入先名順一覧。 */
public class Pl160 extends PlSelect {
    static final String PROG_NAME = "PL160 (3.01.05)";
    private Printer prt;
    private int a, lineCnt, pageLines;
    private String l3Report, wsDate;

    @Override
    public void run(Object... args) {
        init();
        wsDate = fromUk(toDay());
        term().exceptionsEnabled = true; term().escEnabled = true;
        pageLines = sys.intv("page-lines");
        Rec purch = purchRec();
        CobFile purchaseFile = purchaseFile(purch);
        purchaseFile.open(Mode.INPUT);
        reportSelection(PROG_NAME, "Supplier File", true);
        String customerIn = pad(custIn, 7).replace(' ', 'Z');
        l3Report = reportHeading(false, custIn, true, " days overdue");
        CobFile sort = CobFile.sequential(ctx.store, ctx.path("suppsort.inx"));
        sort.open(Mode.INPUT);
        prt = new Printer("prt-1");
        a = 0;
        headings();
        String cust7 = pad(custIn, 7);
        Rec kr = Layout.ofSource(" 01 sales-sort-record.\n 03 sales-sort-key pic x(7).\n", "sales-sort-record").newRec();
        while (sort.readNext(kr).equals("00")) {
            String key = kr.str("sales-sort-key");
            purch.set("purch-key", key);
            if (key.compareTo(cust7) < 0 || key.compareTo(customerIn) > 0) continue;
            if (invalid(purchaseFile.read(purch))) {
                display(23, 1, "PL170 Not Found - ", 4);
                show(23, 13, key, 4);
                continue;
            }
            eraseEol(23, 1);
            boolean live = purch.intv("purch-status") == 1;
            if (statusIn.equals("L") && !live || statusIn.equals("D") && live) continue;
            if (!numericTests(purch, true)) continue;
            listing(purch, live);
        }
        prt.close();
        sort.close(); purchaseFile.close();
        spoolPrt1();
        sort.open(Mode.OUTPUT);
        sort.close();
    }

    private void headings() {
        a++;
        String l1 = pad(PROG_NAME, 51) + pad("Supplier Alphabetical Listing", 73) + "Page " + Num.edit(a % 1000, "zz9");
        String l3 = pad(sys.str("usera"), 40) + "Report on : " + l3Report + wsDate;
        if (a != 1) {
            prt.afterPage(l1);
            prt.after(l3, 1);
            prt.after("", 1);
        } else {
            prt.before(l1, 1);
            prt.before(l3, 1);
        }
        prt.after("Supplier  Status    <----------------Name & Address---------------->   ----Telephone----    ----Fax---"
                + "    ----Credit----   Discount ", 1);
        prt.after(pad(" Number   ------", 87) + "                   Limit   Period", 1);
        prt.after("", 1);
        lineCnt = 6;
    }

    private void listing(Rec purch, boolean live) {
        if (lineCnt > pageLines) headings();
        String phone = purch.str("purch-phone");
        if (!purch.str("purch-ext").isBlank()) {
            int i = phone.indexOf("  ");
            phone = (i < 0 ? phone : phone.substring(0, i)) + "x" + purch.str("purch-ext");
        }
        if (lineCnt > pageLines - 3) headings();
        long limit = purch.longv("purch-limit"), credit = purch.longv("purch-credit");
        prt.after(pad(purch.str("purch-key"), 10) + pad(live ? "Active" : "Dormant", 10) + pad(purch.str("purch-name"), 51)
                + pad(phone, 17).substring(0, 17) + pad(purch.str("purch-fax"), 14)
                + pad(limit == 0 ? "" : Num.edit(Math.abs(limit), "z(9)9"), 14)
                + pad(credit % 100 == 0 ? "" : Num.edit(Math.abs(credit) % 100, "z9"), 8)
                + Pl095.bwz(purch.num("purch-discount"), "z9.99", 5), 1);
        prt.after(pad("", 20) + pad(purch.str("purch-address").replace(sys.str("pl-delim"), ","), 96), 1);
        prt.after("", 1);
        lineCnt += 3;
    }
}
