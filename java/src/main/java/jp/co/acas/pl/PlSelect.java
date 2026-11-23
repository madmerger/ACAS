package jp.co.acas.pl;

import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;

import java.util.ArrayList;
import java.util.List;

/** pl160 / pl170 / pl190 共通の帳票抽出条件画面（display-03）と条件判定。 */
abstract class PlSelect extends PlBase {
    protected String custIn = "", statusIn = " ", creditOp = " ", invoiceOp = " ", averageOp = " ", overdueOp = " ",
            enterDateIn = "", enterDateOp = " ";
    protected long creditIn, invoiceIn, averageIn, overdueIn, wsEnterDate;
    private final char[] report = new char[70];
    private int y;

    private static boolean badOp(String op) { return !op.equals("L") && !op.equals("G") && !op.equals("E") && !op.equals(" "); }

    /** report-selection。withDate = Date Entered 行あり（pl160 / pl170）。 */
    protected void reportSelection(String progName, String title, boolean withDate) {
        clearScreen();
        display(1, 1, progName);
        display(1, 34, title);
        show(1, 71, toDay(), 2);
        display(3, 32, "Report Attributes");
        display(8, 9, "Supplier Number - [");
        display(8, 34, "]");
        display(8, 39, "Enter characters in positions to match");
        display(10, 9, "Status          - [");
        display(10, 29, "]");
        display(10, 39, "<L> Live;<D> Dormant;< > All");
        display(12, 9, "Credit Period   - [");
        display(12, 30, "]  [");
        display(12, 35, "]");
        display(12, 39, "Enter number of days & operator");
        display(13, 43, "<L>  for credit periods < than");
        display(14, 43, "<G>  for credit periods > than");
        display(15, 43, "<E>  for credit periods = to");
        display(17, 9, "Invoice Activity  [");
        display(17, 33, "] [");
        display(17, 37, "]");
        display(17, 39, "Enter number of invoices & operator");
        display(19, 9, "Average Value   - [");
        display(19, 33, "] [");
        display(19, 37, "]");
        display(19, 39, "Enter invoice value & operator");
        display(21, 9, "Overdue A/Cs    - [");
        display(21, 33, "] [");
        display(21, 37, "]");
        display(21, 39, "Enter number of days & operator");
        if (withDate) {
            display(23, 9, "Date Entered-[");
            display(23, 33, "] [");
            display(23, 37, "]");
            display(23, 39, "Enter date & operator");
        }
        while (true) {
            Terminal.Field cust = afield(8, 28, 6, custIn), status = afield(10, 28, 1, statusIn),
                    crIn = field(12, 28, 2, Num.z9(creditIn, 2)), crOp = afield(12, 34, 1, creditOp),
                    invIn = field(17, 28, 5, Num.z9(invoiceIn, 5)), invOp = afield(17, 36, 1, invoiceOp),
                    avIn = field(19, 28, 5, Num.z9(averageIn, 5)), avOp = afield(19, 36, 1, averageOp),
                    ovIn = field(21, 28, 5, Num.z9(overdueIn, 5)), ovOp = afield(21, 36, 1, overdueOp),
                    dtIn = afield(23, 23, 10, enterDateIn), dtOp = afield(23, 36, 1, enterDateOp);
            List<Terminal.Field> fs = new ArrayList<>(List.of(cust, status, crIn, crOp, invIn, invOp, avIn, avOp, ovIn, ovOp));
            if (withDate) { fs.add(dtIn); fs.add(dtOp); }
            acceptScreen(fs);
            custIn = upper(pad(aval(cust), 6));
            statusIn = upper(aval(status));
            creditIn = numOf(crIn.value); invoiceIn = numOf(invIn.value);
            averageIn = numOf(avIn.value); overdueIn = numOf(ovIn.value);
            creditOp = upper(aval(crOp)); invoiceOp = upper(aval(invOp));
            averageOp = upper(aval(avOp)); overdueOp = upper(aval(ovOp));
            if (withDate) { enterDateIn = pad(aval(dtIn), 10); enterDateOp = aval(dtOp); }
            if (!statusIn.equals("L") && !statusIn.equals("D") && !statusIn.equals(" ")) continue;
            if (badOp(creditOp) || badOp(invoiceOp) || badOp(averageOp) || badOp(overdueOp)) continue;
            if (!withDate) return;
            enterDateOp = upper(enterDateOp);
            if (badOp(enterDateOp)) continue;
            if (enterDateIn.isBlank()) return;
            long bin = validateDate(enterDateIn);
            if (bin == 0) {
                display(23, 68, "PL005 Invalid Date");
                continue;
            }
            eraseEol(23, 68);
            wsEnterDate = bin;
            return;
        }
    }

    protected static boolean testNum(String op, long test1, long test2) {
        return switch (op) {
            case " " -> true;
            case "L" -> test2 < test1;
            case "G" -> test2 > test1;
            case "E" -> test2 == test1;
            default -> false;
        };
    }

    /** credit / invoice / average / overdue（＋ enter-date）の条件判定。 */
    protected boolean numericTests(Rec purch, boolean withDate) {
        if (!creditOp.equals(" ") && !testNum(creditOp, creditIn, purch.longv("purch-credit"))) return false;
        if (!invoiceOp.equals(" ") && !testNum(invoiceOp, invoiceIn, purch.longv("purch-activety"))) return false;
        if (!averageOp.equals(" ") && !testNum(averageOp, averageIn, purch.longv("purch-average"))) return false;
        if (!overdueOp.equals(" ") && purch.num("purch-current").signum() > 0
                && !testNum(overdueOp, overdueIn, sys.longv("run-date") - purch.longv("purch-last-inv"))) return false;
        return !withDate || enterDateOp.equals(" ") || testNum(enterDateOp, wsEnterDate, purch.longv("purch-create-date"));
    }

    private void string(String s) {
        for (int i = 0; i < s.length() && y >= 1 && y <= 70; i++) report[y++ - 1] = s.charAt(i);
    }
    private static String operand(String op) { return op.equals("L") ? "< " : op.equals("G") ? "> " : op.equals("E") ? "= " : "  "; }

    /** report-heading-setup。all = 「All」とする条件、keys = Keys Matching に出す値（空白なら出さない）。 */
    protected String reportHeading(boolean all, String keys, boolean withDate, String overdueLit) {
        java.util.Arrays.fill(report, ' ');
        y = 1;
        string(all ? "All" : "Matched");
        y++;
        if (statusIn.equals("L")) string("Live");
        if (statusIn.equals("D")) string("Dormant");
        y++;
        if (!creditOp.equals(" ")) string(operand(creditOp) + Num.edit(creditIn, "z9") + " Days Credit");
        y++;
        if (!invoiceOp.equals(" ")) string(operand(invoiceOp) + Num.edit(invoiceIn, "zzzz9") + " Invoices");
        y++;
        if (!averageOp.equals(" ")) string(operand(averageOp) + Num.edit(averageIn, "zzzz9") + " Av. Value");
        y++;
        if (!overdueOp.equals(" ")) string(operand(overdueOp) + Num.edit(overdueIn, "zzzz9") + overdueLit);
        y++;
        if (withDate) {
            if (!enterDateOp.equals(" ")) string(operand(enterDateOp) + enterDateIn.substring(0, 8) + " Entry Date");
            y++;
        }
        if (!keys.isBlank()) string(" Keys Matching - " + keys);
        return new String(report);
    }

    protected boolean allBlank() {
        return statusIn.equals(" ") && creditOp.equals(" ") && invoiceOp.equals(" ") && averageOp.equals(" ")
                && overdueOp.equals(" ");
    }
}
