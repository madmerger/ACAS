package jp.co.acas.sl;

import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** sl900.cbl: 請求書サブシステムのメニューと固定項目設定。 */
public class Sl900 extends SlProgram {
    static final String PROG_NAME = "SL900 (3.01.09)";
    private Rec sys;
    private String wsDate;

    @Override
    public void run(Object... args) {
        sys = sys();
        term().exceptionsEnabled = true; term().escEnabled = true;
        wsDate = fromUk(toDay());
        Object caller = ctx.shared.get("ws-caller"), called = ctx.shared.get("ws-called");
        ctx.shared.put("ws-del-link", caller);
        ctx.shared.put("ws-caller", called);
        if (sys.longv("next-invoice") == 0) fixedData();
        while (true) {
            boolean notInvoicing = sys.intv("invoicer") == 9;
            clearScreen();
            display(1, 1, PROG_NAME);
            display(1, 34, "Invoicing Menu");
            show(1, 71, wsDate, 2);
            display(5, 1, "Select one of the following by number :- [ ]");
            display(8, 11, "(1)  Amend Invoicing Fixed Data");
            if (notInvoicing) display(9, 11, "(2)  Enter Invoice Details");
            else {
                display(9, 11, "(2)  Enter Invoices For Batch Printing");
                display(10, 11, "(3)  Enter Invoice For Immediate Printing");
                display(14, 11, "(7)  Print Invoices");
                display(15, 11, "(8)  Print Delivery Notes/Picking Lists");
            }
            display(11, 11, "(4)  Amend Invoices");
            display(12, 11, "(5)  Delete Invoices");
            display(13, 11, "(6)  Invoice Deletion Report");
            display(17, 11, "(9)  Return To System menu");
            int reply;
            while (true) {
                reply = intOf(term().accept(5, 43, 1, "0", AUTO | NUMERIC, 6));
                if (reply == 9) {
                    sys.setNum("pass-value", 0);
                    ctx.shared.put("ws-called", ctx.shared.get("ws-caller"));
                    ctx.shared.put("ws-caller", ctx.shared.get("ws-del-link"));
                    return;
                }
                if (notInvoicing && (reply == 3 || reply == 7 || reply == 8)) { display(20, 15, "Invalid option, try again", 3); continue; }
                break;
            }
            String prog = switch (reply) {
                case 1 -> { fixedData(); yield null; }
                case 4 -> "sl920";
                case 5 -> "sl940";
                case 6 -> "sl200";
                case 7 -> "sl930";
                case 8 -> "sl950";
                case 2, 3 -> "sl910";
                default -> null;
            };
            if (prog == null) continue;
            sys.setNum("pass-value", reply);
            ctx.shared.put("ws-called", prog);
            call(prog);
        }
    }

    private String yn(int line, int col, String field, String a, String b) {
        String v;
        do { v = upper(acceptUpdate(line, col, 1, sys.str(field))); sys.set(field, v); } while (!v.equals(a) && !v.equals(b));
        return v;
    }

    private void fixedData() {
        boolean gl = sys.intv("level-1") == 1;
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 31, "Invoicing Fixed Data");
        show(1, 71, wsDate, 2);
        display(5, 11, "Next Invoice");
        display(5, 45, "- [        ]");
        display(7, 11, "Extra Charge/Discount Description - [");
        display(7, 62, "]");
        display(9, 11, "Extra Charge/Discount Type (C/D)  - [ ]");
        display(10, 11, "Print Extra on Invoices (N/Y)     - [ ]");
        display(11, 11, "Extra Charge/Discount Percentage  - [     ]");
        display(13, 11, "Invoice Entry Level (1, 2) ");
        display(13, 45, "- [ ]");
        display(14, 11, "Invoice to Stock Link  - [ ]");
        display(15, 11, "Invoice to Stock Audit - [ ]");
        if (gl) {
            display(16, 11, "Extra Charge Discount Account");
            display(16, 45, "- [      ]");
            display(17, 11, "Vat Account");
            display(17, 45, "- [      ]");
        }
        display(19, 11, "Proforma Retention In Days ");
        display(19, 45, "- [   ]");
        display(21, 11, "Details Ok To File (Y/N) ...........[Y]");
        show(5, 48, z(sys.longv("next-invoice"), 8));
        show(7, 48, sys.str("extra-desc"), 2);
        show(9, 48, sys.str("extra-type"));
        show(10, 48, sys.str("extra-print"));
        show(11, 48, Num.edit(sys.num("extra-rate"), "99.99"));
        show(13, 48, sys.str("invoicer"));
        show(14, 37, sys.str("sl-stock-link"));
        show(15, 37, sys.str("sl-stock-audit"));
        show(16, 48, z(sys.longv("extra-charge-ac") % 1000000, 6));
        show(17, 48, z(sys.longv("vat-ac") % 1000000, 6));
        show(19, 48, z(sys.longv("pf-retention") % 1000, 3));
        while (true) {
            // data-entry
            do {
                sys.setNum("next-invoice", intOf(acceptUpdate(5, 48, 8, z(sys.longv("next-invoice"), 8), NUMERIC)));
            } while (sys.longv("next-invoice") == 0);
            sys.set("extra-desc", term().accept(7, 48, 14, sys.str("extra-desc"), 0, 2));
            if (sys.str("extra-desc").isBlank()) {
                sys.set("extra-type", " "); sys.set("extra-print", " "); sys.setNum("extra-rate", 0);
            } else {
                yn(9, 48, "extra-type", "C", "D");
                yn(10, 48, "extra-print", "Y", "N");
                String d = acceptUpdate(11, 48, 5, Num.edit(sys.num("extra-rate"), "99.99"));
                sys.setNum("extra-rate", new BigDecimal(z(intOf(d.substring(0, 2)), 2) + "." + z(intOf(d.substring(3, 5)), 2)));
            }
            int lvl;
            do {
                lvl = intOf(acceptUpdate(13, 48, 1, sys.str("invoicer"), NUMERIC));
                sys.setNum("invoicer", lvl);
            } while (lvl != 1 && lvl != 2);
            if (yn(14, 37, "sl-stock-link", "Y", "N").equals("N")) sys.set("sl-stock-audit", "N");
            else { sys.set("sl-stock-audit", "Y"); yn(15, 37, "sl-stock-audit", "Y", "N"); }
            if (gl) {
                sys.setNum("extra-charge-ac", intOf(acceptUpdate(16, 48, 6, z(sys.longv("extra-charge-ac") % 1000000, 6), NUMERIC)));
                sys.setNum("vat-ac", intOf(acceptUpdate(17, 48, 6, z(sys.longv("vat-ac") % 1000000, 6), NUMERIC)));
            }
            String reply;
            do {
                sys.setNum("pf-retention", intOf(acceptUpdate(19, 48, 3, z(sys.longv("pf-retention") % 1000, 3), NUMERIC)));
                reply = upper(term().accept(21, 48, 1, "Y", 0, 6));
            } while (!reply.equals("N") && !reply.equals("Y"));
            if (reply.equals("Y")) return;
        }
    }
}
