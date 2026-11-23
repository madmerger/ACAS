package jp.co.acas.sys;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;
import jp.co.acas.core.ScreenDef;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

/** COBOL sys002: システムパラメータの保守（会社・運用・GL・SL・PL・在庫の各設定）と設定帳票。 */
public class Sys002 extends Program implements ScreenDef.Binder {
    static final String PROG_NAME = "SYS002 (3.01.39)";
    private Rec sys;
    private CobFile file;
    private final Map<String, String> ws = new HashMap<>();
    private long uBin;
    private String uDate = "", wsDate = "";
    private String psn = "HPLJ4TCP ";

    // ---------- 画面項目の対応付け ----------
    @Override
    public Object get(String name) {
        if (ws.containsKey(name)) return ws.get(name);
        Layout.Field f = sys.layout.field(name);
        return f.kind == Layout.Kind.ALPHA || f.kind == Layout.Kind.GROUP ? sys.str(name) : sys.num(name);
    }
    @Override
    public void set(String name, String text) {
        if (ws.containsKey(name)) { ws.put(name, text); return; }
        try { sys.set(name, text); } catch (RuntimeException e) { sys.setNum(name, 0); }
    }
    private ScreenDef screen(String name) { return ScreenDef.of("sys002.scr", name); }
    private void displayScreen(String name) { screen(name).display(term(), this, 2); }
    private void acceptScreen(String name) { screen(name).accept(term(), this, 2); }
    private void banner(int nos, String title) {
        ws.put("screen-nos", Integer.toString(nos));
        clearScreen();
        displayScreen("banner");
        display(4, 36, title);
    }
    private void eol(int line, int col, String text, int fg) { eraseEol(line, col); display(line, col, text, fg); }
    private int n(String f) { return sys.intv(f); }
    private String s(String f) { return sys.str(f); }
    private boolean is(String f, String v) { return sys.str(f).equals(v); }
    private void up(String f) { sys.set(f, upper(sys.str(f))); }
    /** verify-screen と確認応答。true: やり直し（N）。 */
    private boolean redo(String message, int fg) {
        ws.put("verify-message", message);
        displayScreen("verify-screen");
        display(13, 55, String.format("%-24s", message), 2);   // 文言（日本語面で訳す）。桁・内容は verify-message と同じ
        show(15, 76, "Y", fg);
        String r = ctx.term.accept(15, 76, 1, "Y", 0, 6);
        return r.equalsIgnoreCase("N");
    }

    // ---------- 日付 ----------
    private void validateDate(String test) {
        String t = test.replace('.', '/').replace(',', '/').replace('-', '/');
        String d = t;
        if (n("date-form") == 0) sys.setNum("date-form", 1);
        if (n("date-form") == 2) d = t.substring(3, 5) + t.charAt(2) + t.substring(0, 2) + t.substring(5);
        else if (n("date-form") != 1) d = t.substring(8, 10) + "/" + t.substring(5, 7) + "/" + t.substring(0, 4);
        uDate = d;
        uBin = Maps04.toBin(d);
    }
    private void convertDate() {
        uDate = uBin == 0 ? " ".repeat(10) : Maps04.toDate(uBin);
        if (uDate.isBlank()) { wsDate = uDate; return; }
        if (n("date-form") == 0 || n("date-form") > 3) sys.setNum("date-form", 1);
        wsDate = Acas.convertDate(sys, uDate);
    }

    @Override
    public void run(Object... args) {
        sys = SystemFile.shared(ctx);
        term().exceptionsEnabled = true; term().escEnabled = true;
        clearScreen();
        display(1, 1, PROG_NAME);
        display(1, 30, "System Parameters");
        file = SystemFile.file(ctx);
        diskError("SY101 Open I-O Err = ", file.open(CobFile.Mode.IO));
        ensure(4, Layout.of("copybooks/wssys4.cob", "System-Record-4").newRec().bytes());
        byte[] fin = Layout.of("copybooks/wsfinal.cob", "Final-Record").newRec().bytes();
        ensure(3, fin);
        ensure(2, Layout.of("copybooks/wsdflt.cob", "Default-Record").newRec().bytes());
        file.rrn = 1;
        String st = file.read(sys);
        if (!st.equals("00")) {
            st = "00";
            sys.initialize();
            sys.setNum("system-record-version-prime", 1);
            sys.setNum("system-record-version-secondary", 1);
            sys.setNum("date-form", 1);
            file.rrn = 1;
            file.write(sys);
            file.read(sys);
        }
        diskError("SY102 Read Err 1 = ", st);
        uBin = sys.longv("run-date");
        convertDate();
        ctx.shared.put("to-day", uDate);
        ws.put("prog-name", PROG_NAME);
        ws.put("line-1-date", wsDate);
        ws.put("screen-nos", "0");
        ws.put("verify-message", "");
        ws.put("p-start", ""); ws.put("p-end", ""); ws.put("s-pass-word", "");
        ws.put("num-6", "00000");
        if (!userParams()) { file.close(); return; }
        systemParams();
        if (n("level-1") == 1) glParams();
        if (n("level-3") == 1) slParams();
        if (n("level-2") == 1) plParams();
        if (n("level-4") == 1) stockParams();
        printParams();
        clearScreen();
        file.rrn = 1;
        diskError("SY103 Rewrite Err 1 = ", file.rewrite(sys));
        file.close();
        ctx.shared.put("ws-term-code", 0);
    }

    private void ensure(int rrn, byte[] init) {
        file.rrn = rrn;
        Rec probe = sys.layout.newRec();
        if (file.read(probe).equals("00")) return;
        byte[] rec = new byte[sys.layout.size];
        Arrays.fill(rec, (byte) ' ');
        System.arraycopy(init, 0, rec, 0, Math.min(init.length, rec.length));
        file.write(rec);
    }
    private void diskError(String action, String status) {
        if (status.equals("00")) return;
        show(3, 10, action);
        show(3, 30, status);
        display(24, 1, "SY104 Fix and Press Enter");
        accept(24, 20, 2);
    }

    // ---------- User-Params ----------
    private boolean userParams() {
        while (true) {
            banner(1, "User Data");
            for (String[] p : new String[][]{{"start-date", "p-start"}, {"end-date", "p-end"}}) {
                if (sys.longv(p[0]) != 0) { uBin = sys.longv(p[0]); convertDate(); ws.put(p[1], wsDate); }
                else ws.put(p[1], " ".repeat(10));
            }
            ws.put("s-pass-word", "    ");
            displayScreen("user-data");
            while (true) {
                acceptScreen("user-data");
                if (crtStatus() == 2005) return false;
                switch (n("date-form")) {
                    case 1 -> eol(14, 20, "    Using UK format dd/mm/ccyy", 3);
                    case 2 -> eol(14, 20, "    Using USA format mm/dd/ccyy", 3);
                    case 3 -> eol(14, 20, "    Using Intl format ccyy/mm/dd", 3);
                    default -> { eol(14, 20, "    Incorectly Set. You MUST set this", 4); sys.setNum("date-form", 1); }
                }
                if (!ws.get("p-start").isBlank()) { validateDate(ws.get("p-start")); ws.put("p-start", uDate); }
                if (uBin == 0) { display(15, 40, "SY005 Invalid Date", 3); continue; }
                eraseEol(15, 40);
                sys.setNum("start-date", uBin);
                if (!ws.get("p-end").isBlank()) { validateDate(ws.get("p-end")); ws.put("p-end", uDate); }
                if (uBin == 0) { display(16, 40, "SY005 Invalid Date", 3); continue; }
                eraseEol(16, 40);
                sys.setNum("end-date", uBin);
                if (!ws.get("s-pass-word").isBlank()) sys.set("pass-word", Maps01.password(ctx, ws.get("s-pass-word")));
                if (n("period") == 13) display(22, 70, "Weekly    ", 3);
                else if (n("period") == 6) display(22, 70, "Fortnightly", 3);
                else { sys.setNum("period", 3); display(22, 70, "Monthly   ", 3); }
                if (n("page-lines") <= 28) { sys.setNum("page-lines", 48); display(17, 50, "SY105 Lines > 28", 3); continue; }
                eraseEol(17, 50);
                int fs = n("file-system-used");
                if (fs > 1) { sys.setNum("file-system-used", 0); display(24, 10, "Range 0 thru 1 only   ", 3); }
                else if (fs == 0) display(24, 10, "Cobol data files used ", 3);
                else display(24, 10, "Rdbms is used  ", 3);
                if (n("file-duplicates-in-use") > 1) { sys.setNum("file-duplicates-in-use", 0); display(24, 50, "Range 0 thru 1 only   ", 3); }
                else if (n("file-duplicates-in-use") == 1) display(24, 41, "Duplicate file processing used", 3);
                else display(24, 41, "Duplicate file processing NOT used", 3);
                up("sl-vat-printed");
                if (!is("sl-vat-printed", "Y") && !is("sl-vat-printed", "N")) { sys.set("sl-vat-printed", "N"); show(21, 37, "N", 3); }
                break;
            }
            if (!redo("   User Data Complete", 6)) return true;
        }
    }

    // ---------- System-Params ----------
    private void systemParams() {
        do {
            banner(2, "OPS  Data 1");
            displayScreen("ops-data");
            acceptScreen("ops-data");
            int host = n("host"), os = n("op-system");
            if (host != 0 && host != 1) { sys.setNum("host", 1); host = 1; display(18, 23, "Multi-user system assumed", 3); }
            else if (host == 0) display(18, 23, "Single-user system    ", 3);
            else display(18, 23, "Multi-user system     ", 3);
            show(20, 1, " ".repeat(51));
            if (host == 0 && (os < 1 || os > 6)) { sys.setNum("op-system", 1); display(20, 23, "MSDOS assumed", 3); }
            else if (host == 1 && (os < 2 || os > 6)) { sys.setNum("op-system", 6); display(20, 23, "Linux assumed", 3); }
            else display(20, 23, new String[]{"DOS", "Windows", "Mac OSX", "OS/2", "Unix", "Linux"}[os - 1], 3);
            os = n("op-system");
            if (os == 3 || os == 5 || os == 6) {
                if (s("print-spool-name2").isBlank()) sys.set("print-spool-name2", s("print-spool-name"));
                if (s("print-spool-name3").isBlank()) sys.set("print-spool-name3", s("print-spool-name"));
                displayScreen("ops-data-2");
                acceptScreen("ops-data-2");
                if (s("print-spool-name").charAt(0) == ' ') display(24, 2, " Print Spool Name must be defined", 3);
                else psn = s("print-spool-name");
            }
            switch (n("data-capture-used")) {
                case 0 -> display(20, 54, "Cobol Standard Display  ", 3);
                case 1 -> display(20, 54, "Gui Display             ", 3);
                case 2 -> display(20, 54, "Widget Display          ", 3);
                default -> { display(20, 54, " Invalid - Std selected ", 3); sys.setNum("data-capture-used", 0); }
            }
            display(15, 1, openSource() ? "Using (Free) Open Source Version of ACAS" : "Using Commercial Version of ACAS", 3);
        } while (redo("    OPS Data 1 Complete ", 6));
        if (n("file-system-used") == 0) return;
        do {
            banner(3, "OPS  Data 2");
            displayScreen("ops-data-3");
            acceptScreen("ops-data-3");
            if (!s("rdbms-db-name").isBlank()) display(7, 46, " DB name, set as requested", 3);
            if (!s("rdbms-user").isBlank()) display(8, 46, " DB User, set as requested", 3);
            if (!s("rdbms-passwd").isBlank()) { display(9, 46, " DB User pwd, set as requested", 3); show(9, 22, "************"); }
        } while (redo("    OPS Data 2 Complete ", 6));
    }
    private boolean openSource() { return is("maps-ser-xx", "mp") && n("maps-ser-nn") == 9999; }

    // ---------- GL-Params ----------
    private void sel(String f, int line) {
        up(f);
        if (is(f, "Y")) display(line, 32, "Selected        ");
        else { sys.set(f, " "); display(line, 32, "Not selected    "); }
    }
    private void glParams() {
        do {
            banner(4, "G-L  Data");
            ws.put("num-6", Num.z9(n("next-batch"), 5));
            displayScreen("gl-data");
            acceptScreen("gl-data");
            sys.setNum("next-batch", Num.parse(ws.get("num-6")));
            up("p-c");
            if (is("p-c", "P")) display(7, 32, "Profit centres selected");
            else if (is("p-c", "B")) display(7, 32, "Branches selected");
            else { sys.set("p-c", " "); display(7, 32, "Not selected  "); }
            up("p-c-level");
            if (is("p-c", " ") && !is("p-c-level", " ")) sys.set("p-c-level", " ");
            if (!is("p-c", " ") && is("p-c-level", "R")) display(8, 32, "Revenue A/cs only ");
            if (!is("p-c", " ") && !is("p-c-level", "R")) { sys.set("p-c-level", " "); display(8, 32, "All A/cs          "); }
            up("p-c-grouped");
            display(9, 32, "1st digit of P.C./Branch ");
            if (is("p-c-grouped", "Y")) display(9, 57, "is the group identifier");
            else { display(9, 57, "is not significant"); sys.set("p-c-grouped", " "); }
            sel("comps", 10);
            sel("ledger-2nd-index", 11);
            sel("m-v", 12);
            sel("arch", 13);
            sel("vat", 16);
            up("irs-instead");
            display(18, 32, is("irs-instead", "Y") ? "Selected        " : "Not selected    ");
        } while (redo("    G-L Data Complete  ", 2));
    }

    // ---------- SL-Params ----------
    private void setUnset(String f, int line) {
        if (n(f) != 0) eol(line, 28, "Selected & Set", 2); else eol(line, 28, "Unset", 3);
    }
    private void slParams() {
        do {
            banner(5, "S-L  Data 1");
            displayScreen("sl-data");
            acceptScreen("sl-data");
            if (n("sl-dunning") == 1) display(7, 22, "Late letters selected    ");
            else { sys.setNum("sl-dunning", 0); display(7, 22, "Late letters not selected"); }
            if (n("sl-charges") == 1) display(8, 22, "Late charges selected    ");
            else { sys.setNum("sl-charges", 0); display(8, 22, "Late charges not selected"); }
            if (is("sl-delim", " ")) { display(14, 22, "Delimiter <\\> assumed"); sys.set("sl-delim", "\\"); }
            up("sl-own-nos");
            display(15, 28, is("sl-own-nos", "Y") ? "Selected & Set" : "Unset         ");
            up("sl-stock-link");
            if (is("sl-stock-link", "Y") && n("level-4") == 1) display(18, 28, "Selected & Set       ");
            else { sys.set("sl-stock-link", "N"); display(18, 28, "Unset and/or No Stock", 3); }
            if (n("sl-pay-ac") != 0) display(19, 28, "Selected & Set"); else eol(19, 28, "Unset", 3);
            setUnset("sl-sales-ac", 20);
            setUnset("s-debtors", 21);
        } while (redo("    S-L Data Complete  ", 6));
        do {
            banner(6, "S-L  Data 2");
            displayScreen("sl-data-2");
            acceptScreen("sl-data-2");
            String[] heads = {"sl-comp-head-inv", "sl-comp-head-stat", "sl-comp-head-lets", "sl-comp-head-pick"};
            for (String h : heads) up(h);
            for (int i = 0; i < 4; i++)
                if (!is(heads[i], "Y") && !is(heads[i], "N")) { display(8 + i, 22, "Error, set to N", 4); sys.set(heads[i], "N"); }
        } while (redo("  S-L Data 2 Complete  ", 6));
    }

    // ---------- PL-Params ----------
    private void plParams() {
        do {
            banner(7, "P-L  Data");
            displayScreen("pl-data");
            acceptScreen("pl-data");
            if (is("pl-delim", " ")) { display(14, 22, "Delimiter <\\> assumed"); sys.set("pl-delim", "\\"); }
            up("pl-stock-link");
            if (is("pl-stock-link", "Y") && n("level-4") == 1) eol(15, 28, "Selected & Set", 2);
            else { sys.set("pl-stock-link", "N"); eol(15, 28, "Unset and/or No Stock", 3); }
            setUnset("bl-pay-ac", 18);
            setUnset("bl-purch-ac", 19);
            setUnset("p-creditors", 20);
        } while (redo("    P-L Data Complete", 6));
    }

    // ---------- Stock-Params ----------
    private void flag(String f, int line) {
        if (n(f) == 1) eol(line, 20, "    Set", 3); else { sys.setNum(f, 0); eol(line, 20, "    UnSet", 3); }
    }
    private void stockParams() {
        do {
            banner(8, "Stock Data");
            displayScreen("stock-data");
            acceptScreen("stock-data");
            flag("stk-debug", 7);
            flag("stk-manu-used", 9);
            flag("stk-oe-used", 10);
            flag("stk-audit-used", 11);
            flag("stk-mov-audit", 12);
            up("stk-period-cur");
            switch (s("stk-period-cur")) {
                case "M" -> eol(13, 20, "    Set to Monthly", 3);
                case "Q" -> eol(13, 20, "    Set to Quarterly", 3);
                case "W" -> eol(13, 20, "    Set to Weekly", 3);
                default -> { sys.set("stk-period-cur", "M"); eol(13, 20, "    Unset: Has been set to Monthly", 3); }
            }
            up("stk-period-dat");
            switch (s("stk-period-dat")) {
                case "M" -> eol(14, 20, "    Set to Monthly", 3);
                case "Q" -> eol(14, 20, "    Set to Quarterly", 3);
                case "Y" -> eol(14, 20, "    Set to Yearly", 3);
                default -> { sys.set("stk-period-dat", "Y"); eol(14, 20, "    Unset: Has been set to Yearly", 3); }
            }
            flag("stk-averaging", 15);
            flag("stk-activity-rep-run", 18);
            if (n("stk-audit-no") > 0 && n("stk-audit-no") < 99999) eol(19, 22, "  Set", 3);
            else { sys.setNum("stk-audit-no", 0); eol(19, 22, "  Set to zero", 4); }
        } while (redo("  Stock Data Complete", 6));
    }

    // ---------- Print-Params ----------
    private final StringBuilder out = new StringBuilder();
    private final char[] l5 = new char[120];
    private static final int NAME = 10, D1 = 27, D2 = 70;
    private static final int[] LEN = new int[121];
    static { LEN[NAME] = 17; LEN[D1] = 43; LEN[D2] = 50; }

    private static String pad(String s, int n) { return s.length() >= n ? s.substring(0, n) : s + " ".repeat(n - s.length()); }
    private void after(int n, String rec) { out.append("\n".repeat(n)).append(pad(rec, 132)); }
    private void mv(int area, String v) { String p = pad(v, LEN[area]); p.getChars(0, p.length(), l5, area); }
    /** STRING ... INTO 領域 WITH POINTER（1 起点）。戻り値は更新後のポインタ。 */
    private int str(int area, int pointer, String v) {
        for (int i = 0; i < v.length() && pointer <= LEN[area]; i++) l5[area + pointer++ - 1] = v.charAt(i);
        return pointer;
    }
    private void clear5() { Arrays.fill(l5, ' '); }
    private void w5(int n) { after(n, new String(l5)); }
    private static String bySpace(String v) { int i = v.indexOf(' '); return i < 0 ? v : v.substring(0, i); }
    private static String by2(String v) { int i = v.indexOf("  "); return i < 0 ? v : v.substring(0, i); }
    private String e(String f, String pic) { return Num.edit(sys.num(f), pic); }
    private String e(BigDecimal v, String pic) { return Num.edit(v, pic); }
    private String z(String f, int digits) { return Num.z9(sys.longv(f), digits); }
    private static String sect(int lead, String left, String right) { return " ".repeat(lead) + left + " ".repeat(40) + right; }
    private static final String STARS = " ".repeat(24) + "*".repeat(16) + " ".repeat(40) + "*".repeat(16);
    private void account(String label, String f, int skip) { int p = str(D2, 1, label); str(D2, p + skip, z(f, 6)); }
    private void yesNo(String label, int skip, boolean yes) { int p = str(D2, 1, label); str(D2, p + skip, yes ? "Yes" : "No"); }

    private void printParams() {
        clearScreen();
        display(12, 1, "Do you want printed copy (Y/N) [ ]");
        String r = ctx.term.accept(12, 33, 1, "Y", 0, 4);
        if (r.equalsIgnoreCase("N")) return;
        boolean stock = n("level-4") == 1;
        boolean pcs = is("p-c", "P"), br = is("p-c", "B");
        out.setLength(0);
        clear5();
        out.append(header(1)).append('\n');
        after(1, sect(24, "User  Parameters", "G/L   Parameters"));
        after(1, STARS);
        mv(NAME, "Name"); mv(D1, s("usera"));
        mv(D2, pcs ? "Profit-Centres Selected" : br ? "Branches Selected" : "Neither P/C or Branches Selected");
        w5(2);
        mv(NAME, "Address"); mv(D1, s("address-1"));
        mv(D2, !pcs && !br ? "" : is("p-c-level", "R") ? "Only for Revenue Accounts" : "For all Accounts");
        w5(1);
        mv(NAME, ""); mv(D2, ""); mv(D1, s("address-2"));
        mv(D2, !pcs && !br ? "" : is("p-c-grouped", "Y") ? "P-C / Branches Grouped on 1st Digit" : "P-C / Branches not Grouped");
        w5(1);
        mv(D1, s("address-3"));
        mv(D2, is("comps", "Y") ? "Comparative Figures Required" : "Comparative Figures not Required");
        w5(1);
        str(D1, 1, by2(s("address-4")) + "," + by2(s("post-code")) + "," + by2(s("country")));
        mv(D2, is("ledger-2nd-index", "Y") ? "Alphabetic Ledger Index Selected" : "Alphabetic Ledger Index not Selected");
        w5(1);
        mv(NAME, "Date Format");
        if (n("date-form") <= 1) { mv(D1, "UK Format"); sys.setNum("date-form", 1); }
        else mv(D1, n("date-form") == 2 ? "USA Format" : "Intl Format");
        mv(D2, "");
        w5(1);
        uBin = sys.longv("start-date"); convertDate();
        mv(D1, wsDate); mv(NAME, "Period Start");
        mv(D2, is("m-v", "Y") ? "Min. Validation During Data Entry" : "Full Validation During Data Entry");
        w5(1);
        uBin = sys.longv("end-date"); convertDate();
        mv(D1, wsDate); mv(NAME, "       End");
        mv(D2, is("arch", "Y") ? "Transaction Archiving Selected" : "Transactions Deleted at End of Cycle");
        w5(1);
        clear5();
        str(D1, 1, e("vat-rate-1", "z9.99") + " / " + e("vat-rate-4", "z9.99") + "  VAT Reg: " + s("vat-reg-number"));
        mv(NAME, "VAT    Rate 1/4.");
        if (n("sales-range") == 0) mv(D2, "No Reserved Sales Range");
        else { mv(D2, "Sales Range most Significant Digit is - "); l5[D2 + 40] = z("sales-range", 1).charAt(0); }
        w5(1);
        mv(D1, "");
        str(D1, 1, e("vat-rate-2", "z9.99") + " / " + e("vat-rate-5", "z9.99"));
        mv(NAME, "       Rate 2/5.");
        if (n("purchase-range") == 0) mv(D2, "No Reserved Purchase Range");
        else { mv(D2, "Purchase Range Most Signif.  Digit is - "); l5[D2 + 40] = z("purchase-range", 1).charAt(0); }
        w5(1);
        mv(D1, e("vat-rate-3", "z9.99")); mv(NAME, "       Rate 3.");
        mv(D2, is("vat", "Y") ? "Auto VAT Posting Selected" : "Manual VAT Posting Selected");
        w5(1);
        mv(NAME, ""); mv(D1, ""); mv(D2, "");
        str(D2, 1, "Cycles per Quarter - " + e("period", "zzzz9"));
        mv(NAME, "Current Quarter ");
        str(D1, 1, e("current-quarter", "z9"));
        w5(1);
        mv(D2, ""); mv(D1, "");
        str(D2, 1, "Next Batch Number  - " + e("next-batch", "zzzz9"));
        mv(NAME, "Current Cycle");
        str(D1, 1, e("cyclea", "z9"));
        w5(1);
        clear5();
        str(D2, 1, "Using IRS instead of GL - " + (is("irs-instead", "Y") ? "Yes" : "No"));
        mv(NAME, "Print Lines"); mv(D1, e("page-lines", "zz9"));
        w5(1);
        mv(D2, "");
        after(2, sect(24, "ACAS  Parameters", "P/L   Parameters"));
        after(1, STARS);
        mv(D2, "Address Delimiter"); l5[D2 + 28] = s("pl-delim").charAt(0);
        mv(NAME, "Environment"); mv(D1, n("host") == 1 ? "Multi-User" : "Single User");
        w5(2);
        mv(NAME, "Op. System");
        String os = switch (n("op-system")) { case 2 -> "Windows"; case 1 -> "Dos"; case 4 -> "OS/2"; case 5 -> "Unix"; case 6 -> "Linux"; default -> ""; };
        // レガシーは l5-data-1 を消さずに STRING するため、直前の値の残りがそのまま印字される
        str(D1, 1, os);
        mv(D2, "Next Batch Number"); str(D2, 25, z("bl-next-batch", 5));
        w5(1);
        mv(NAME, "System version");
        mv(D1, openSource() ? "Using (Free) Open Source Version of ACAS" : "Using Commercial Version of ACAS");
        str(D2, str(D2, 1, "Next Folio Number ") + 3, z("next-folio", 8));
        w5(1);
        clear5();
        if (n("file-system-used") > 1) sys.setNum("file-system-used", 0);
        String fsText = n("file-system-used") == 0 ? "Cobol Data Files Used" : "Rdbms is used ";
        if (n("file-duplicates-in-use") > 1) sys.setNum("file-duplicates-in-use", 0);
        str(D1, 1, bySpace(fsText) + (n("file-duplicates-in-use") == 1 ? "/Dup Mode Used" : "/Dup Mode Not Used"));
        account("Pay      Account ", "bl-pay-ac", 6);
        w5(1);
        clear5();
        mv(NAME, "Path to IRS"); mv(D1, "/" + ctx.irsDir);
        account("Ledger   Account ", "bl-purch-ac", 6);
        w5(1);
        clear5();
        mv(NAME, "Path to Ledgers"); mv(D1, "/" + ctx.ledgersDir);
        account("Creditor Account ", "p-creditors", 6);
        w5(1);
        boolean single = n("op-system") == 1 || n("op-system") == 2 || n("op-system") == 4;
        clear5();
        mv(NAME, "Prt Spool Name 1"); mv(D1, single ? "Not Used" : s("print-spool-name"));
        yesNo("Stock Control Link ", 7, is("pl-stock-link", "Y") && stock);
        w5(1);
        clear5();
        mv(NAME, "Prt Spool Name 2"); mv(D1, single ? "Not Used" : s("print-spool-name2"));
        w5(1);
        clear5();
        mv(NAME, "Prt Spool Name 3"); mv(D1, single ? "Not Used" : s("print-spool-name3"));
        w5(1);
        after(2, sect(24, "Inv.  Parameters", "S/L   Parameters"));
        after(1, STARS);
        after(1, "");
        for (int a : new int[]{3, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11}) { slPrint(a); w5(1); }
        clear5();
        mv(NAME, "Company Heads Pri");
        str(D1, 1, "nt on Delivery notes: " + s("sl-comp-head-pick"));
        yesNo("Stock Control Link ", 7, is("sl-stock-link", "Y") && stock);
        w5(1);
        str(D1, 1, "nt on Invoices      : " + s("sl-comp-head-inv"));
        mv(D2, ""); account("Pay      Account ", "sl-pay-ac", 6);
        w5(1);
        str(D1, 1, "nt on Statements    : " + s("sl-comp-head-stat"));
        mv(D2, ""); account("Ledger   Account ", "sl-sales-ac", 6);
        w5(1);
        str(D1, 1, "nt on Late Letters  : " + s("sl-comp-head-lets"));
        mv(D2, ""); account("Debtors  Account ", "s-debtors", 6);
        w5(1);
        out.append('\f').append(header(2));
        after(2, sect(24, "Stock Parameters", "O/E   Parameters"));
        after(1, STARS);
        clear5();
        mv(NAME, "Debug Mode"); mv(D1, n("stk-debug") == 1 ? "Yes" : "No");
        yesNo("O/Entry in Use   ", 7, n("stk-oe-used") == 1);
        w5(2);
        clear5();
        mv(NAME, "Manufacturing"); mv(D1, n("stk-manu-used") == 1 ? "Yes" : "No"); w5(1);
        mv(NAME, "Audit in Use"); mv(D1, n("stk-audit-used") == 1 ? "Yes" : "No"); w5(1);
        mv(NAME, "Movement Audits"); mv(D1, n("stk-mov-audit") == 1 ? "Yes" : "No"); w5(1);
        mv(NAME, "Current Period"); mv(D1, periodName(s("stk-period-cur"))); w5(1);
        mv(NAME, "To Date Period"); mv(D1, periodName(s("stk-period-dat"))); w5(1);
        mv(NAME, "Stock Averaging"); mv(D1, n("stk-averaging") == 1 ? "Yes" : "No"); w5(1);
        mv(NAME, "Current Audit No"); mv(D1, z("stk-audit-no", 8)); w5(1);
        after(2, sect(22, "Payroll Parameters", "RDMBS Parameters"));
        after(1, " ".repeat(22) + "*".repeat(18) + " ".repeat(40) + "*".repeat(16));
        clear5();
        mv(NAME, "Payroll in Use   "); mv(D1, "No");
        boolean rdb = n("file-system-used") == 1;
        if (rdb) { mv(D2, "RDBMS DB Schema "); str(D2, 21, s("rdbms-db-name")); }
        w5(2);
        String line3e = " ".repeat(24) + "System Paramters";
        if (rdb) {
            mv(D1, ""); mv(NAME, "");
            mv(D2, "RDB User Name   "); str(D2, 21, s("rdbms-user"));
            w5(1);
            mv(D2, "RDB User Passwd "); str(D2, 21, pad("It's SECRET", 12));
            pad(line3e, 40).getChars(0, 40, l5, 0);
            w5(1);
        } else after(2, line3e);
        after(1, " ".repeat(24) + "*".repeat(16));
        clear5();
        mv(NAME, "File Statuses"); mv(D1, s("file-statuses"));
        w5(2);
        after(2, " ".repeat(51) + "End of System Parameter Report");
        after(1, " ".repeat(51) + "=".repeat(30));
        CobFile prt = CobFile.lineSequential(ctx.store, ctx.path("prt-1"));
        prt.open(CobFile.Mode.OUTPUT);
        for (String line : out.toString().split("\n", -1)) prt.write(line.getBytes(StandardCharsets.ISO_8859_1));
        prt.close();
        ctx.spool("prt-1", "lpr -r -o 'orientation-requested=4 page-left=21 page-top=48 page-right=10 sides=two-sided-long-edge cpi=12 lpi=8' -P "
                + psn.strip() + " prt-1");
    }
    private String header(int page) {
        return pad(PROG_NAME, 50) + "S Y S T E M   P A R A M E T E R S" + " ".repeat(27) + pad(ws.get("line-1-date"), 10)
                + " ".repeat(6) + "Page" + Num.edit(page, "z9");
    }
    private static String periodName(String p) {
        return switch (p) { case "M" -> "Monthly"; case "Q" -> "Quarterly"; case "Y" -> "Yearly"; default -> "NOT SET"; };
    }

    private void slPrint(int a) {
        clear5();
        String type = s("extra-type");
        boolean c = type.equals("C"), d = type.equals("D");
        switch (a) {
            case 1 -> {
                mv(D2, n("sl-dunning") == 0 ? "Dunning Letters not Selected" : "Dunning Letters Selected");
                if (c) { mv(NAME, "Ext. Charge Desc"); mv(D1, s("extra-desc")); }
                if (d) { mv(NAME, "Extra Disc. Desc"); mv(D1, s("extra-desc")); }
            }
            case 2 -> {
                mv(D2, n("sl-charges") == 0 ? "Late Charges not Selected" : "Late Charges Selected");
                if (c) { mv(NAME, "Ext. Charge Rate"); mv(D1, e("extra-rate", "z9.99")); }
                if (d) { mv(NAME, "Ext. Disc. Rate"); mv(D1, e("extra-rate", "z9.99")); }
            }
            case 3 -> {
                mv(D2, is("sl-own-nos", "N") ? "Computer Generated Invoice Numbers Selected" : "Manually Entered Invoice Numbers Selected");
                mv(NAME, "Next Inv. Number"); mv(D1, z("next-invoice", 8));
            }
            case 4 -> {
                mv(D2, "Credit Period nn Days"); str(D2, 15, e("sl-credit", "z9"));
                mv(NAME, "Inv. Data Level"); mv(D1, z("invoicer", 1));
            }
            case 5 -> {
                mv(D2, "Standard Credit Limit"); str(D2, 23, e("sl-limit", "zzzzzz9"));
                if (c) { mv(NAME, "Extra Charge A/C"); mv(D1, z("extra-charge-ac", 6)); }
                if (d) { mv(NAME, "Extra Disc. A/C"); mv(D1, z("extra-charge-ac", 6)); }
            }
            case 6 -> {
                mv(D2, "Standard Discount is   nn.nn%"); str(D2, 24, e("sl-disc", "z9.99"));
                mv(NAME, "VAT Account"); mv(D1, z("vat-ac", 6));
            }
            case 7 -> {
                mv(D2, "Min. Late Balance"); str(D2, 25, e("sl-min", "zzzz9"));
                mv(NAME, "Print VAT Nunber"); mv(D1, is("sl-vat-printed", "Y") ? "Yes" : "No ");
            }
            case 8 -> { mv(D2, "Max. Late Charge"); str(D2, 25, e("sl-max", "zzzz9")); }
            case 9 -> { mv(D2, "Late Charge Rate       nn.nn%"); str(D2, 24, e("sl-late-per", "z9.99")); }
            case 10 -> { mv(D2, "Address Delimiter"); l5[D2 + 28] = s("sl-delim").charAt(0); }
            default -> {
                mv(D2, "Next Batch Number"); str(D2, 25, z("first-sl-batch", 5));
                mv(NAME, "Proforma Retent."); mv(D1, e("pf-retention", "zz9"));
            }
        }
    }
}
