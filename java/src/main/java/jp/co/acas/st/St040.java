package jp.co.acas.st;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.SystemFile;

/** st040.cbl: 期末処理（在庫移動累計のクリア）。 */
public class St040 extends StProgram {
    static final String PROG_NAME = "ST040 (3.01.06)";
    private static final int L23 = 23;

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        Rec sys = SystemFile.shared(ctx);
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        String convDate = St.fromUk((String) ctx.shared.getOrDefault("to-day", ""), sys.intv("date-form"));
        // aa010-Questions
        eraseEos(1, 1);
        display(1, 1, PROG_NAME);
        display(1, 31, "Stock Activity Reset");
        show(1, 71, convDate, 2);
        display(4, 10, "Can I clear this ");
        String cur = sys.str("stk-period-cur");
        if (cur.equals("Q")) display(4, 27, "Quarter");
        else if (cur.equals("W")) display(4, 27, "   Week");
        else display(4, 27, "  Month");
        display(4, 34, " Totals? [ ] (N/Y)");
        display(6, 10, "Can I clear End of Year Totals on Stock records [ ] (N/Y)");
        String period, year;
        while (true) {
            // aa020-Accept-Loop
            period = upper(acceptUpdate(4, 44, 1, "N"));
            if (!period.equals("Y") && !period.equals("N")) { display(L23, 1, "ST402 Y or N only", 4); continue; }
            year = upper(acceptUpdate(6, 59, 1, "N"));
            if (!year.equals("Y") && !year.equals("N")) { display(L23, 1, "ST402 Y or N only", 4); continue; }
            break;
        }
        eraseEol(L23, 1);
        boolean clearPeriod = period.equals("Y"), clearYear = year.equals("Y");
        if (!clearYear && !clearPeriod) return;
        if (clearPeriod) display(8, 1, "Will Clear Period totals", 3);
        if (clearYear) display(9, 1, "Will Clear Year totals", 3);
        while (true) {
            // aa030-U-Sure
            if (sys.intv("stk-activity-rep-run") == 0) {
                display(L23, 1, "You have NOT run audit reports", 6);
                maps99(45);
                return;
            }
            display(12, 10, "Have you made backups of your data and are you sure?  [ ] (N/Y)");
            String reply = upper(acceptUpdate(12, 65, 1, "N"));
            if (!reply.equals("N") && !reply.equals("Y")) { display(L23, 1, "ST402 Y or N only", 4); continue; }
            if (reply.equals("N")) return;
            break;
        }
        eraseEol(L23, 1);
        Rec stock = Layout.of("copybooks/fdstock.cob", "Stock-Record").newRec();
        CobFile f = St.stockFile(ctx, stock);
        String fs = f.open(CobFile.Mode.IO);
        if (!fs.equals("00")) {
            display(L23, 1, "ST401 Stock File not found", 4);
            show(L23, 28, fs, 2);
            maps99(45);
            return;
        }
        eraseEol(12, 10);
        display(12, 10, "Updating your Stock file as requested");
        // ba000-Clear-Totals
        while (f.readNext(stock).equals("00")) {
            if (clearPeriod) for (String n : new String[] {"stock-adds", "stock-deducts", "stock-wip-adds", "stock-wip-deds"}) stock.setNum(n, 0);
            if (clearYear)
                for (int m = 1; m <= 12; m++)
                    for (String n : new String[] {"stock-td-adds", "stock-td-deds", "stock-td-wip-adds", "stock-td-wip-deds"}) stock.setNum(n, 0, m);
            if (!f.rewrite(stock).equals("00")) {
                display(L23, 1, "ST000 Error on Writing to Stock File", 4);
                show(L23, 38, f.status, 2);
                maps99(45);
                break;
            }
        }
        f.close();
    }
}
