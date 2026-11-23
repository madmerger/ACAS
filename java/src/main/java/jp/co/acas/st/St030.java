package jp.co.acas.st;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;
import jp.co.acas.sys.Maps04;
import jp.co.acas.sys.SystemFile;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/** st030.cbl: 在庫帳票（評価・活動・発注点・履歴・在庫一覧）。 */
public class St030 extends Program {
    static final String PROG_NAME = "ST030 (3.01.22)";
    private static final int L23 = 23;
    private static final String H13 = "<------- Stock ------>                                      Average       Replace     Stock     ";
    private static final String H14 = "Abrev    Number         Description                           Cost          Cost        Qty     ";
    private static final String H13B = "     Value in    Retail";
    private static final String H14B = "     Stockroom    Price ";
    private static final String H23 = "<------ Stock ------>                                  Current  Retail  ";
    private static final String H24 = "Abrev     Number      Description                       Stock   Price      Cost";
    private static final String H24B = "Add   Ded    Net   Add   Ded    Net";
    private static final String H33 = "<------ Stock ------>                                     Supp    Stock < ReOrder >  Unit     On   <------- Date ------>    Bk   WIP";
    private static final String H34 = "Abrev     Number     Flg Description                      Number   Qty    Pnt   Qty  Cost    Order  Ordered      Due       Ord   Qty";
    private static final String H43 = "<------ Stock ------> Supplier  Location     Unit      Unit        Value    Number <- ReOrder -> <------- Date ------>  Quantity On";
    private static final String H44 = "Abrev   Number         Number               Price      Cost        in Stk   in Stk  Point    Qty   Ordered     Due      Order  B/Ord";
    private static final String H53 = "<------ Stock ------> Description          This <----------------------------- History for the Year ------------------------------->";
    private static final String H54 = "Abrev   Number        ";

    private Rec sys, stock;
    private CobFile stockFile;
    private St.Printer print;
    private int menuReply, wsReply, partial, lineCnt = 99, pageNos, a, b, c;
    private String reportName = "", convDate = "", hh = "  ", mm = "  ";
    private String stockFrom = "", stockTo = "", abrevFrom = "", abrevTo = "";
    private String currentPeriod = "", todatePeriod = "", litPeriod = "Quarter";
    private final StringBuilder line0 = new StringBuilder();
    private boolean manu, averaging;

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        sys = SystemFile.shared(ctx);
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        convDate = St.fromUk(St.x((String) ctx.shared.getOrDefault("to-day", ""), 10), sys.intv("date-form"));
        LocalDateTime now = ctx.now();
        if (now.getHour() != 0 || now.getMinute() != 0 || now.getSecond() != 0 || now.getNano() >= 10_000_000) {
            hh = String.format("%02d", now.getHour()); mm = String.format("%02d", now.getMinute());
        }
        String cur = sys.str("stk-period-cur"), dat = sys.str("stk-period-dat");
        if (cur.equals("Q")) { currentPeriod = "Quarter"; litPeriod = "Quarter"; }
        else if (cur.equals("W")) { currentPeriod = "Week"; litPeriod = "   Week"; }
        else { currentPeriod = "Month"; litPeriod = "  Month"; }
        todatePeriod = dat.equals("M") ? "Month To Date" : dat.equals("Q") ? "Quarter To Date" : "Year To Date";
        manu = sys.intv("stk-manu-used") == 1;
        averaging = sys.intv("stk-averaging") == 1;
        if (sys.intv("file-status", 11) != 1) {
            display(L23, 1, "ST300 Stock File not yet created", 4);
            call("maps99", 45);
            return;
        }
        stock = Layout.of("copybooks/fdstock.cob", "Stock-Record").newRec();
        stockFile = St.stockFile(ctx, stock);
        if (!stockFile.open(CobFile.Mode.INPUT).equals("00")) {
            display(L23, 1, "ST301 Stock File not found", 4);
            show(L23, 28, stockFile.status, 2);
            call("maps99", 45);
            return;
        }
        menuReply = 0;
        stockFile.close();
        boolean heads = true;
        while (true) {
            if (heads) displayHeadings();
            // aa020-Display-Heads
            eraseEos(1, 1);
            display(1, 1, PROG_NAME);
            display(1, menuReply == 0 ? 27 : 30, reportName);
            show(1, 71, convDate, 2);
            String td = St.x((String) ctx.shared.getOrDefault("to-day", ""), 10);
            String pm = td.substring(3, 5);
            if (!pm.matches("\\d\\d") || Integer.parseInt(pm) < 1 || Integer.parseInt(pm) > 12) {
                display(L23, 1, "ST313 Bad month in date", 4);
                show(L23, 25, pm, 2);
                show(L23, 28, td, 2);
                call("maps99", 45);
                return;
            }
            // aa100-Main-Menu
            eraseEos(4, 1);
            display(4, 1, "Select one of the following by number :- [ ]");
            display(6, 4, "(1)  Valuation Report");
            display(7, 4, "(2)  Activity Report");
            display(8, 4, "(3)  Re-Order Report");
            display(9, 4, "(4)  Stock History Report");
            display(10, 4, "(5)  Stock Report");
            display(12, 4, "(9)  Return to System Menu");
            heads = true;
            while (true) {
                // aa110-Accept-Loop
                menuReply = (int) St.digits(acceptUpdate(4, 43, 1, "0", AUTO));
                if (menuReply == 9) return;
                displayHeadings();
                reportSelection();
                if (wsReply == 9) { heads = false; break; }
                if (menuReply == 0 || menuReply > 5) continue;
                eraseEol(L23, 1);
                stockFile.open(CobFile.Mode.INPUT);
                print = new St.Printer(ctx, "prt-1");
                switch (menuReply) {
                    case 1 -> valuations();
                    case 2 -> activity();
                    case 3 -> reOrder();
                    case 4 -> history();
                    default -> stockLists();
                }
                print.close();
                stockFile.close();
                if (pageNos != 0) ctx.spool("prt-1", St.printCommand(sys.str("print-spool-name")));
                menuReply = 0;
                break;
            }
        }
    }

    /** aa010-Display-Headings。 */
    private void displayHeadings() {
        pageNos = 0; lineCnt = 99;
        reportName = switch (menuReply) {
            case 1 -> "Stock Valuation Report";
            case 2 -> "Stock Activity Report ";
            case 3 -> "Stock Re-Order Report ";
            case 4 -> " Stock History Report ";
            case 5 -> "     Stock Report     ";
            default -> "Stock Control - Reports Menu";
        };
    }

    private void screenTop() {
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 26, reportName);
        show(1, 71, convDate);
        display(3, 32, "Report Attributes");
    }

    /** zz050-Report-Selection。 */
    private void reportSelection() {
        while (true) {
            stockFrom = stockTo = St.x("", 13); abrevFrom = abrevTo = St.x("", 7);
            partial = 0; wsReply = 0;
            if (menuReply == 1 || menuReply == 4 || menuReply == 5) { rangeScreen(); return; }
            if (menuReply == 3) {
                while (true) {
                    // display-01
                    screenTop();
                    display(5, 1, "Select an Report Option Number : [");
                    display(5, 36, "]");
                    display(7, 10, "(1)   All Stock Items");
                    display(8, 10, "(2)   A Range of Items");
                    display(9, 10, "(3)   Items that are Understocked");
                    display(10, 10, "(4)   Range of Understocked Items");
                    display(11, 10, "(5)   Items, Not in Stock");
                    display(12, 10, "(6)   Range of Items, Not in Stock ");
                    display(13, 10, "(7)   Items on Order");
                    display(14, 10, "(8)   Range of Items on Order");
                    display(16, 10, "(9)   Return to Main Menu");
                    acceptReply();
                    if (wsReply == 9) return;
                    if (wsReply < 1) continue;
                    if (wsReply == 2 || wsReply == 4 || wsReply == 6 || wsReply == 8) rangeScreen();
                    return;
                }
            }
            // display-02
            screenTop();
            display(5, 1, "Select an Report Option Number : [");
            display(5, 36, "]");
            display(7, 10, "(1)   All Stock Items");
            display(8, 10, "(2)   Range of Items");
            display(9, 10, "(3)   Items Active in current ");
            display(9, 40, currentPeriod);
            display(10, 10, "(4)   Items Active in ");
            display(10, 32, todatePeriod);
            display(11, 10, "(5)   Range of active Items in Current ");
            display(11, 49, currentPeriod);
            display(12, 10, "(6)   Range of active Items in ");
            display(12, 41, todatePeriod);
            display(14, 10, "(9)   Return to Main Menu");
            acceptReply();
            if (wsReply == 9) return;
            if (wsReply < 1 || wsReply > 6) continue;
            if (wsReply == 2 || wsReply == 5 || wsReply == 6) rangeScreen();
            return;
        }
    }

    private void acceptReply() {
        Terminal.Field f = new Terminal.Field(5, 35, 1, String.valueOf(wsReply), NUMERIC);
        acceptScreen(List.of(f));
        wsReply = (int) St.digits(f.value);
    }

    /** zz050-Get-Disp-03: 品目番号／略称の範囲指定。 */
    private void rangeScreen() {
        while (true) {
            screenTop();
            display(5, 24, "Leave fields blank to select All");
            display(6, 17, "Select Stock no. or Abrev Stock no. but NOT both");
            display(8, 4, "From Stock Number - [");
            display(8, 38, "]");
            display(8, 41, "Enter characters in positions to match");
            display(9, 4, "  To Stock Number - [");
            display(9, 38, "]");
            display(9, 41, "Enter characters in positions to match");
            display(10, 14, "OR");
            display(11, 4, "From Abrev Number - [");
            display(11, 32, "]");
            display(11, 41, "Enter characters in positions to match");
            display(12, 4, "  To Abrev Number - [");
            display(12, 32, "]");
            display(12, 41, "Enter characters in positions to match");
            Terminal.Field f1 = field(8, 25, 13, stockFrom), f2 = field(9, 25, 13, stockTo),
                    f3 = field(11, 25, 7, abrevFrom), f4 = field(12, 25, 7, abrevTo);
            acceptScreen(List.of(f1, f2, f3, f4));
            stockFrom = upper(f1.value); stockTo = upper(f2.value); abrevFrom = upper(f3.value); abrevTo = upper(f4.value);
            boolean sf = !stockFrom.isBlank(), st = !stockTo.isBlank(), af = !abrevFrom.isBlank(), at = !abrevTo.isBlank();
            String err = null;
            if ((sf || st) && (af || at)) err = "ST304 You cannot specify both Stock AND Abrev numbers";
            else if (sf && st && stockFrom.compareTo(stockTo) > 0) err = "ST307 Stock From MUST be less than Stock To";
            else if (af && at && abrevFrom.compareTo(abrevTo) > 0) err = "ST308 Abrev From MUST be less than Abrev To";
            if (err != null) {
                display(L23, 1, err, 4);
                call("maps99", 15);
                continue;
            }
            partial = sf || st || af || at ? 1 : 0;
            return;
        }
    }

    /** 各帳票共通の位置付け。false は ST305 / ST306 で中断。 */
    private boolean position() {
        if (!abrevTo.isBlank()) {
            char[] t = abrevTo.toCharArray();
            for (int i = 6; i >= 1 && t[i] == ' '; i--) t[i] = 'z';
            abrevTo = new String(t);
        }
        if (!stockFrom.isBlank()) {
            stock.set("stock-key", stockFrom);
            if (!stockFile.start(stock, ">=").equals("00")) {
                display(L23, 1, "ST306 Stock Number not found", 4);
                call("maps99", 15);
                return false;
            }
        }
        if (!abrevFrom.isBlank()) {
            String k = abrevFrom.charAt(6) == ' ' ? abrevFrom.substring(0, 6) + "0" : abrevFrom;
            stock.set("stock-abrev-key", k);
            if (!stockFile.startAlt(stock, 0, ">=").equals("00")) {
                display(L23, 1, "ST305 Abbreviated Stock number not present", 4);
                call("maps99", 15);
                return false;
            }
        }
        if (partial == 0) {
            stock.set("stock-abrev-key", "0000000");
            stockFile.startAlt(stock, 0, ">=");
        }
        return true;
    }
    /** 0 = 印字対象, 1 = 読み飛ばし, 2 = 終了。 */
    private boolean belowFrom() {
        return !stockFrom.isBlank() && stockFrom.compareTo(stock.str("stock-key")) > 0
                || !abrevFrom.isBlank() && abrevFrom.compareTo(stock.str("stock-abrev-key")) > 0;
    }
    private boolean aboveTo() {
        return !stockTo.isBlank() && stock.str("stock-key").compareTo(stockTo) > 0
                || !abrevTo.isBlank() && stock.str("stock-abrev-key").compareTo(abrevTo) > 0;
    }
    /** 対象なし時の ST302 / ST303。true は該当なし。 */
    private boolean nothingFound() {
        if (pageNos != 0) return false;
        if (!stockFrom.isBlank() || !stockTo.isBlank()) { display(L23, 1, "ST302 There were no Stock numbers within the specified range", 4); return true; }
        if (!abrevFrom.isBlank() || !abrevTo.isBlank()) { display(L23, 1, "ST303 There were no Abrev Stock numbers within the specified range", 4); return true; }
        return false;
    }
    private void write(String rec) { print.after(St.x(rec, 132), 1); }
    private String date(long bin) {
        return bin == 0 ? St.x("", 10) : St.fromUk(Maps04.toDate(bin), sys.intv("date-form"));
    }
    private static String e(long v, String pic) { return Num.edit(v, pic); }
    private static String e(BigDecimal v, String pic) { return Num.edit(v, pic); }

    /** ba000-Process-Valuations。 */
    private void valuations() {
        if (!position()) return;
        BigDecimal total = BigDecimal.ZERO;
        String wip = St.x("", 8);
        while (stockFile.readNext(stock).equals("00")) {
            if (belowFrom()) continue;
            if (aboveTo()) break;
            heads(1);
            String ave = e(stock.num("stock-cost"), "zzzzz,zz9.9999");
            if (ave.endsWith("00")) ave = ave.substring(0, 12) + "  ";
            if (manu) wip = e(stock.longv("stock-work-in-progress"), "z(7)9");
            write(St.x(stock.str("stock-abrev-key"), 9) + St.x(stock.str("stock-key"), 15) + St.x(stock.str("stock-desc"), 33)
                    + ave + e(stock.num("stock-last-actual-cost"), "zzzzz,zz9.99") + e(stock.longv("stock-held"), "z(7)9") + wip
                    + e(stock.num("stock-value"), "zzz,zzz,zz9.99") + e(stock.num("stock-retail"), "zzzzz,zz9.99"));
            total = total.add(stock.num("stock-value"));
            lineCnt++;
        }
        if (nothingFound()) return;
        if (lineCnt > sys.intv("page-lines") - 4) { lineCnt = 99; heads(1); }
        print.after(St.x(St.x("", 99) + "-".repeat(14), 132), 2);
        write(St.x("", 86) + "Total Value: " + e(total, "zzz,zzz,zz9.99"));
        write(St.x("", 99) + "=".repeat(14));
    }

    /** ca000-Process-Activity。 */
    private void activity() {
        if (!position()) return;
        while (stockFile.readNext(stock).equals("00")) {
            long tAdd = 0, tDed = 0, wAdd = 0, wDed = 0;
            if (wsReply != 1) {
                if (belowFrom()) continue;
                if ((wsReply == 3 || wsReply == 5) && stock.longv("stock-adds") == 0 && stock.longv("stock-deducts") == 0
                        && stock.longv("stock-wip-adds") == 0 && stock.longv("stock-wip-deds") == 0) continue;
            }
            for (int m = 1; m <= 12; m++) {
                tAdd += stock.longv("stock-td-adds", m); tDed += stock.longv("stock-td-deds", m);
                wAdd += stock.longv("stock-td-wip-adds", m); wDed += stock.longv("stock-td-wip-deds", m);
            }
            if (wsReply != 1) {
                if ((wsReply == 4 || wsReply == 6) && tAdd == 0 && tDed == 0 && wAdd == 0 && wDed == 0) continue;
                if (aboveTo()) break;
            } else { tAdd = prevAdd; tDed = prevDed; wAdd = prevWAdd; wDed = prevWDed; }
            prevAdd = tAdd; prevDed = tDed; prevWAdd = wAdd; prevWDed = wDed;
            heads(2);
            String cost, value;
            if (averaging) { cost = e(stock.num("stock-cost"), "zzz,zz9.99"); value = e(stock.num("stock-value"), "zzzzz,zz9.99"); }
            else { cost = e(stock.num("stock-last-actual-cost"), "zzz,zz9.99"); value = St.x("", 12); }
            write(St.x(stock.str("stock-abrev-key"), 8) + St.x(stock.str("stock-key"), 14) + St.x(stock.str("stock-desc"), 33)
                    + e(stock.longv("stock-held"), "zzz,zz9") + e(stock.num("stock-retail"), "zzz,zz9.99") + cost + value
                    + e(stock.longv("stock-adds"), "z(5)9") + e(stock.longv("stock-deducts"), "z(5)9")
                    + e(stock.longv("stock-adds") - stock.longv("stock-deducts"), "z(5)9-")
                    + e(tAdd, "z(5)9") + e(tDed, "z(5)9") + e(tAdd - tDed, "z(5)9-"));
            lineCnt++;
            if (manu && (stock.longv("stock-work-in-progress") != 0 || stock.longv("stock-wip-adds") != 0
                    || stock.longv("stock-wip-deds") != 0 || wAdd != 0 || wDed != 0)) {
                // Line-25B は Line-25 の再定義: "Work in Progress:" が 78 桁目から、その後の項目で上書きされる
                char[] l = St.x("", 132).toCharArray();
                put(l, 78, "Work in Progress:");
                put(l, 56, e(stock.longv("stock-work-in-progress"), "zzz,zz9"));
                put(l, 51, St.x("WIP:", 5));
                put(l, 95, e(stock.longv("stock-wip-adds"), "z(5)9") + e(stock.longv("stock-wip-deds"), "z(5)9")
                        + e(stock.longv("stock-wip-adds") - stock.longv("stock-wip-deds"), "z(5)9-")
                        + e(wAdd, "z(5)9") + e(wDed, "z(5)9") + e(wAdd - wDed, "z(5)9-"));
                write(new String(l));
                lineCnt++;
            }
        }
        nothingFound();
    }
    private long prevAdd, prevDed, prevWAdd, prevWDed;
    private static void put(char[] l, int col, String s) { s.getChars(0, s.length(), l, col - 1); }

    /** da000-Process-ReOrder。 */
    private void reOrder() {
        if (!position()) return;
        String wip = St.x("", 6);
        while (stockFile.readNext(stock).equals("00")) {
            long held = stock.longv("stock-held"), pnt = stock.longv("stock-reorder-pnt");
            boolean service = stock.str("stock-services-flag").equals("Y");
            if (wsReply != 1) {
                if (service) continue;
                if (belowFrom()) continue;
                if (wsReply != 2) {
                    if ((wsReply == 3 || wsReply == 4) && pnt < held) continue;
                    if ((wsReply == 5 || wsReply == 6) && held != 0) continue;
                    if ((wsReply == 7 || wsReply == 8) && stock.longv("stock-on-order") == 0 && stock.longv("stock-back-ordered") == 0
                            && stock.longv("stock-order-date") == 0 && stock.longv("stock-order-due") == 0) continue;
                }
                if (aboveTo()) break;
            }
            heads(3);
            String flag = held < pnt ? "U" : held == 0 ? "0" : " ";
            if (service) flag = " ";
            BigDecimal cost = averaging ? stock.num("stock-cost") : stock.num("stock-last-actual-cost");
            if (manu) wip = e(stock.longv("stock-work-in-progress"), "z(6)");
            write(St.x(stock.str("stock-abrev-key"), 8) + St.x(stock.str("stock-key"), 14) + flag + "  " + St.x(stock.str("stock-desc"), 33)
                    + St.x(stock.str("stock-supplier-p1"), 7) + e(held, "z(5)9") + e(pnt, "z(5)9") + e(stock.longv("stock-std-reorder"), "z(5)9")
                    + e(cost, "z(5)9.99") + e(stock.longv("stock-on-order"), "z(5)9") + " "
                    + St.x(date(stock.longv("stock-order-date")), 11) + date(stock.longv("stock-order-due"))
                    + e(stock.longv("stock-back-ordered"), "z(5)9") + wip);
            lineCnt++;
        }
        nothingFound();
    }

    /** ea000-Process-Stock-Lists。 */
    private void stockLists() {
        if (!position()) return;
        long recCnt = 0;
        while (stockFile.readNext(stock).equals("00")) {
            if (belowFrom()) continue;
            if (aboveTo()) break;
            heads(4);
            recCnt++;
            boolean service = stock.str("stock-services-flag").equals("Y");
            String cost = e(stock.num("stock-cost"), "z(6)9.9999");
            if (cost.endsWith("00")) cost = cost.substring(0, 10) + "  ";
            String l45 = St.x(stock.str("stock-abrev-key"), 8) + St.x(stock.str("stock-key"), 14) + St.x(stock.str("stock-supplier-p1"), 8)
                    + St.x(stock.str("stock-location"), 11) + e(stock.num("stock-retail"), "z(6)9.99") + cost;
            if (!service)
                l45 += e(stock.num("stock-value"), "zzzzz,zz9.99") + e(stock.longv("stock-held"), "z(6)9")
                        + e(stock.longv("stock-reorder-pnt"), "z(6)9") + e(stock.longv("stock-std-reorder"), "z(6)9") + " ";
            else l45 += St.x("", 34);
            l45 += St.x(date(stock.longv("stock-order-date")), 11) + date(stock.longv("stock-order-due"));
            if (!service) l45 += e(stock.longv("stock-on-order"), "z(6)9") + e(stock.longv("stock-back-ordered"), "z(6)9");
            StringBuilder vars = new StringBuilder();
            String p2 = stock.str("stock-supplier-p2"), p3 = stock.str("stock-supplier-p3");
            if (!p2.isBlank() || !p3.isBlank()) {
                vars.append("Secondary Suppliers");
                if (!p2.isBlank()) vars.append(" 1: ").append(p2);
                if (!p3.isBlank()) vars.append(" 2: ").append(p3);
                vars.append("  ");
            }
            if (!stock.str("stock-sa-code").isBlank()) vars.append("SA Code: ").append(stock.str("stock-sa-group")).append("  ");
            if (!stock.str("stock-pa-code").isBlank()) vars.append("PA Code: ").append(stock.str("stock-pa-group"));
            if (stock.longv("stock-pre-sales") != 0) vars.append("  Pre Sales :").append(e(stock.longv("stock-pre-sales"), "z(6)"));
            if (lineCnt > 6) write("-".repeat(132));
            write(l45);
            write(St.x("", 5) + "Description: " + St.x(stock.str("stock-desc"), 32) + St.x("", 5) + St.x(vars.toString(), 77));
            lineCnt += 2;
            if (!service && (stock.longv("stock-construct-bundle") != 0 || stock.longv("stock-under-construction") != 0
                    || stock.longv("stock-work-in-progress") != 0 || !stock.str("stock-construct-item").isBlank())) {
                write("Construction Bundle :" + e(stock.longv("stock-construct-bundle"), "z(6)") + "  WIP :"
                        + e(stock.longv("stock-work-in-progress"), "z(6)") + "  Under Construction :"
                        + e(stock.longv("stock-under-construction"), "z(6)") + " For Constructed Item : " + stock.str("stock-construct-item"));
                lineCnt++;
            }
            if (service) { write("Services only Product"); lineCnt++; }
        }
        if (nothingFound()) return;
        if (lineCnt > sys.intv("page-lines") - 3) { lineCnt += 60; heads(4); }
        print.after(St.x(" Total stock records Printed " + e(recCnt, "zzz,zzz,zz9").strip(), 132), 3);
    }

    /** fa000-Process-History。 */
    private void history() {
        if (!position()) return;
        long recCnt = 0; c = 0;
        while (stockFile.readNext(stock).equals("00")) {
            if (belowFrom()) continue;
            if (aboveTo()) break;
            recCnt++;
            heads(5);
            StringBuilder l = new StringBuilder(St.x(stock.str("stock-abrev-key"), 8) + St.x(stock.str("stock-key"), 14)
                    + St.x(stock.str("stock-desc"), 18) + " " + e(stock.longv("stock-adds") + stock.longv("stock-deducts"), "-(6)9"));
            for (int m = 1; m <= 12; m++) l.append(e(stock.longv("stock-td-adds", m) + stock.longv("stock-td-deds", m), "-(6)9"));
            write(l.toString());
            lineCnt++;
            if (manu) {
                boolean any = stock.longv("stock-wip-adds") != 0 || stock.longv("stock-wip-deds") != 0;
                for (int m = 1; m <= 12; m++)
                    if (stock.longv("stock-td-wip-adds", m) != 0 || stock.longv("stock-td-wip-deds", m) != 0) any = true;
                if (any) {
                    l = new StringBuilder(St.x("", 36) + "WIP: " + e(stock.longv("stock-wip-adds") + stock.longv("stock-wip-deds"), "-(6)9"));
                    for (int m = 1; m <= 12; m++) l.append(e(stock.longv("stock-td-wip-adds", m) + stock.longv("stock-td-wip-deds", m), "-(6)9"));
                    write(l.toString());
                    lineCnt++;
                    c = 1;
                }
            }
        }
        if (nothingFound()) return;
        if (lineCnt > sys.intv("page-lines") - 5) { lineCnt += 60; heads(5); }
        print.after(St.x(" Total stock records Printed " + e(recCnt, "zzz,zzz,zz9").strip(), 132), 3);
        if (manu && c == 0) print.after(St.x("WIP records were present but none had data", 132), 2);
    }

    // ---------- 見出し ----------

    /** zz004-String-Range。 */
    private void stringRange() {
        line0.append("Items ranging from ");
        if (!stockFrom.isBlank() || !stockTo.isBlank()) {
            line0.append(stockFrom.isBlank() ? "Start" : stockFrom).append(" through ").append(stockTo.isBlank() ? "End" : stockTo);
        } else {
            line0.append(abrevFrom.isBlank() ? "Start" : abrevFrom.stripTrailing()).append(" through ").append(abrevTo.isBlank() ? "End" : abrevTo);
        }
    }

    /** zz010 / zz020 / zz030 / zz040 / zz045-Print-Heads。 */
    private void heads(int kind) {
        if (lineCnt <= sys.intv("page-lines")) return;
        line0.setLength(0);
        if (kind == 2) {
            if (wsReply == 1 || wsReply == 2) line0.append("All");
            if (wsReply == 3 || wsReply == 5) line0.append("Active in Current ").append(currentPeriod);
            if (wsReply == 4 || wsReply == 6) {
                int i = todatePeriod.indexOf("  ");
                line0.append("Active in ").append(i < 0 ? St.x(todatePeriod, 16).stripTrailing() : todatePeriod.substring(0, i)).append(" To Date");
            }
            line0.append(' ');
            if (partial == 1) stringRange(); else line0.append("Items");
        } else if (kind == 3) {
            if (wsReply == 1 || wsReply == 2) line0.append("All ");
            if (wsReply == 3 || wsReply == 4) line0.append("Understocked ");
            if (wsReply == 5 || wsReply == 6) line0.append("Not in Stock ");
            if (wsReply == 7 || wsReply == 8) line0.append("On Order ");
            if (partial == 1) stringRange(); else line0.append("Items");
        } else if (partial == 1) stringRange();
        else line0.append("All Items");
        if (line0.length() > 100) line0.setLength(100);
        b = line0.length() + 1;
        a = (132 - b + 2) / 2;
        // zz002-Print-Head-Top
        pageNos++;
        String line11 = St.x(PROG_NAME, 16) + St.x("", 39) + St.x(reportName, 42) + St.x("", 27) + "Page " + e(pageNos, "zz9");
        char[] l12 = (St.x(sys.str("usera"), 40) + St.x("", 76) + St.x(convDate, 10) + " " + hh + ":" + mm).toCharArray();
        if (b > 1) put(l12, a, St.x(line0.toString(), b));
        if (pageNos != 1) {
            print.afterPage(line11);
            print.after(new String(l12), 1);
            print.after(St.x("", 132), 1);
        } else {
            print.before(line11, 1);
            print.before(new String(l12), 1);
        }
        lineCnt = 6;
        switch (kind) {
            case 1 -> {
                write(St.x(H13, 96) + (manu ? "WIP" : "   ") + St.x(H13B, 24));
                write(St.x(H14, 96) + (manu ? "Qty" : "   ") + St.x(H14B, 24));
            }
            case 2 -> {
                String cur = sys.str("stk-period-cur");
                String litCur = cur.equals("Q") ? "< Current Quarter >" : cur.equals("W") ? "<- Current Week -->" : "<- Current Month ->";
                String litYtd = sys.str("stk-period-dat").equals("Q") ? "< Quarter to Date >" : "<- Year to Date -->";
                write(St.x(H23, 72) + St.x(averaging ? " Average" : "   Unit", 13) + St.x(averaging ? " Stock" : "", 9) + litCur + litYtd);
                write(St.x(H24, 86) + St.x(averaging ? "Value" : "", 11) + St.x(H24B, 35));
            }
            case 3 -> { write(H33); write(H34); }
            case 4 -> { write(H43); write(H44); }
            default -> { write(H53); write(St.x(H54, 41) + litPeriod); }
        }
        write("");
    }
}
