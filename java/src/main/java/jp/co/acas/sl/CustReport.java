package jp.co.acas.sl;

import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

/** sl160 / sl170 / sl180 共通: 顧客帳票の抽出条件画面（display-03）と条件判定・見出し文言。プログラムではない。 */
abstract class CustReport extends SlProgram {
    static final String SL005 = "SL005 Invalid Date";
    static final String F_CUSTSORT = "custsort.tmp";

    protected Rec sys;
    protected String custIn = "", customerIn = "", statusIn = " ", creditOp = " ", invoiceOp = " ", averageOp = " ", overdueOp = " ",
        enterDateIn = " ".repeat(10), enterDateOp = " ";
    protected int creditIn, invoiceIn, averageIn, overdueIn;
    protected long wsEnterDate;
    /** 入力値を大文字化するか（sl170 は大文字化しない）。 */
    protected boolean upperCase = true;
    private String up(String v) { return upperCase ? upper(v) : v; }

    protected static Rec sortKeyRec() { return Layout.ofSource(" 01  sales-sort-record.\n     03  sales-sort-key  pic x(7).\n", "sales-sort-record").newRec(); }

    private static boolean badOp(String op) { return !op.equals("L") && !op.equals("G") && !op.equals("E") && !op.equals(" "); }

    /** report-selection。withDate: 登録日条件（23 行目）を持つ版。 */
    protected void reportSelection(String progName, boolean withDate) {
        custIn = " ".repeat(6); statusIn = creditOp = invoiceOp = averageOp = overdueOp = enterDateOp = " ";
        enterDateIn = " ".repeat(10);
        creditIn = invoiceIn = averageIn = overdueIn = 0;
        Scr s = new Scr().blankScreen()
            .from(1, 1, 15, () -> progName)
            .value(1, 34, "Customer File")
            .from(1, 71, 10, () -> fromUk(toDay()))
            .value(3, 32, "Report Attributes")
            .value(8, 9, "Customer Number - [").using(8, 28, 6, () -> custIn, v -> custIn = v).value(8, 34, "]")
            .value(8, 39, "Enter characters in positions to match")
            .value(10, 9, "Status          - [").using(10, 28, 1, () -> statusIn, v -> statusIn = v).value(10, 29, "]")
            .value(10, 39, "<L> Live;<D> Dormant;< > All")
            .value(12, 9, "Credit Period   - [").usingNum(12, 28, 2, () -> z(creditIn, 2), v -> creditIn = intOf(v)).value(12, 30, "]  [")
            .using(12, 34, 1, () -> creditOp, v -> creditOp = v).value(12, 35, "]")
            .value(12, 39, "Enter number of days & operator")
            .value(13, 43, "<L>  for credit periods < than")
            .value(14, 43, "<G>  for credit periods > than")
            .value(15, 43, "<E>  for credit periods = to")
            .value(17, 9, "Invoice Activity  [").usingNum(17, 28, 5, () -> z(invoiceIn, 5), v -> invoiceIn = intOf(v)).value(17, 33, "] [")
            .using(17, 36, 1, () -> invoiceOp, v -> invoiceOp = v).value(17, 37, "]")
            .value(17, 39, "Enter number of invoices & operator")
            .value(19, 9, "Average Value   - [").usingNum(19, 28, 5, () -> z(averageIn, 5), v -> averageIn = intOf(v)).value(19, 33, "] [")
            .using(19, 36, 1, () -> averageOp, v -> averageOp = v).value(19, 37, "]")
            .value(19, 39, "Enter invoice value & operator")
            .value(21, 9, "Overdue A/Cs    - [").usingNum(21, 28, 5, () -> z(overdueIn, 5), v -> overdueIn = intOf(v)).value(21, 33, "] [")
            .using(21, 36, 1, () -> overdueOp, v -> overdueOp = v).value(21, 37, "]")
            .value(21, 39, "Enter number of days & operator");
        if (withDate)
            s.value(23, 9, "Date Entered-[").using(23, 23, 10, () -> enterDateIn, v -> enterDateIn = v).value(23, 33, "] [")
                .using(23, 36, 1, () -> enterDateOp, v -> enterDateOp = v).value(23, 37, "]")
                .value(23, 39, "Enter date & operator");
        s.display();
        while (true) {
            s.accept();
            custIn = up(pad(custIn, 6));
            customerIn = pad(custIn, 7);
            if (!customerIn.isBlank()) customerIn = customerIn.replace(' ', 'Z');
            statusIn = up(statusIn);
            if (!statusIn.equals("L") && !statusIn.equals("D") && !statusIn.equals(" ")) continue;
            creditOp = up(creditOp); if (badOp(creditOp)) continue;
            invoiceOp = up(invoiceOp); if (badOp(invoiceOp)) continue;
            averageOp = up(averageOp); if (badOp(averageOp)) continue;
            overdueOp = up(overdueOp); if (badOp(overdueOp)) continue;
            if (!withDate) return;
            enterDateOp = up(enterDateOp); if (badOp(enterDateOp)) continue;
            if (enterDateIn.isBlank()) return;
            long bin = validateDate(enterDateIn);
            if (bin == 0) { display(23, 61, SL005); continue; }
            eraseEol(23, 68);
            wsEnterDate = bin;
            return;
        }
    }

    /** test-num。 */
    protected static boolean testNum(String op, long test1, long test2) {
        return switch (op) {
            case " " -> true;
            case "L" -> test2 < test1;
            case "G" -> test2 > test1;
            case "E" -> test2 == test1;
            default -> false;
        };
    }

    /** 顧客レコードが与信日数・請求件数・平均額・延滞・登録日の条件を満たすか。 */
    protected boolean matchNumeric(Rec sales, boolean withDate) {
        if (!creditOp.equals(" ") && !testNum(creditOp, creditIn, sales.longv("sales-credit"))) return false;
        if (!invoiceOp.equals(" ") && !testNum(invoiceOp, invoiceIn, sales.longv("sales-activety"))) return false;
        if (!averageOp.equals(" ") && !testNum(averageOp, averageIn, sales.longv("sales-average"))) return false;
        if (!overdueOp.equals(" ") && sales.num("sales-current").signum() > 0
            && !testNum(overdueOp, overdueIn, sys.longv("run-date") - sales.longv("sales-last-inv"))) return false;
        return !withDate || enterDateOp.equals(" ") || testNum(enterDateOp, wsEnterDate, sales.longv("sales-create-date"));
    }

    private static String operand(String op) { return op.equals("L") ? "< " : op.equals("G") ? "> " : op.equals("E") ? "= " : "  "; }

    /** report-heading-setup（l3-report 70 桁）。overdueText は版により " days overdue" / " Days Overdue"。 */
    protected String reportHeadingSetup(boolean withDate, String overdueText) {
        StringBuilder r = new StringBuilder(" ".repeat(70));
        int y = 1;
        boolean all = statusIn.equals(" ") && creditOp.equals(" ") && invoiceOp.equals(" ") && averageOp.equals(" ") && overdueOp.equals(" ") && customerIn.isBlank();
        y = stringInto(r, y, all ? "All" : "Matched");
        y++;
        if (statusIn.equals("L")) y = stringInto(r, y, "Live");
        if (statusIn.equals("D")) y = stringInto(r, y, "Dormant");
        y++;
        if (!creditOp.equals(" ")) y = stringInto(r, y, operand(creditOp) + Num.edit(creditIn, "z9") + " Days Credit");
        y++;
        if (!invoiceOp.equals(" ")) y = stringInto(r, y, operand(invoiceOp) + Num.edit(invoiceIn, "zzzz9") + " Invoices");
        y++;
        if (!averageOp.equals(" ")) y = stringInto(r, y, operand(averageOp) + Num.edit(averageIn, "zzzz9") + " Av. Value");
        y++;
        if (!overdueOp.equals(" ")) y = stringInto(r, y, operand(overdueOp) + Num.edit(overdueIn, "zzzz9") + overdueText);
        y++;
        if (withDate) {
            if (!enterDateOp.equals(" ")) y = stringInto(r, y, operand(enterDateOp) + pad(enterDateIn, 8) + " Entry Date");
            y++;
        }
        if (!custIn.isBlank()) { y = stringInto(r, y, " Keys Matching - "); stringInto(r, y, custIn); }
        return r.toString();
    }
}
