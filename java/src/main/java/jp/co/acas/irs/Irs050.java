package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** irs050.cbl: 転記レポート（監査証跡 / 元帳 / VAT 日計表）の表示・印刷。 */
public class Irs050 extends IrsBase {
    static final String PROG_NAME = "irs050 (3.01.13)";
    private static final int LINES = 24, ACCEPT_LINES = 23, L22 = 22, L21 = 21, L17 = 17, ESC = 2005;
    private static final BigDecimal Z = BigDecimal.ZERO;
    private static final String C_CONTINUE = "Press return to continue or Esc to quit";
    private static final String C_EXIT = "Return for next screen or <X> to exit....[ ]";
    private static final String Q_REPORT = pad(" Day Book      Quarter  To", 28);
    private static final String L4A = "Transaction    Date    Code   ---Account---", L4B = "   Net Amount    VAT Amount    Type";
    private static final String L5A = "-----------    ----    ----   Debit  Credit", L5B = "   ----------    ----------    ----";
    private static final String L4C = "Transaction    Date     Code         ", L4D = "-----Input Tax-----   ----Output Tax------";
    private static final String L5C = "-----------    ----     ----         ", L5D = "   Net        VAT        Net        VAT   ";
    private static final String LINE_4_L = "Code/Nos  --Date--  ------------Legend------------- Contra --Debit--  -Credit--";
    private static final String SUB_LEGEND = "Sub-Nominal Balance A/C - ";
    private static final String LINE_7 = " ".repeat(36) + "---------- ---------- " + "---------- ----------";
    private static final String LINE_7_A = " ".repeat(44) + "===========   ===========";
    private static final String LINE_7_M = " ".repeat(58) + "---------- ----------";

    private Rec sys, post, nl, def;
    private FileAccess fa;
    private CobFile prt;
    private int sortSequ, acMarker, vatCheck, lineCnt = 99, wsAccountUsed, counter, lin;
    private String useCode = "  ", saveCode = "  ", wsReply = " ", empty = " ", tipe = " ", outputReply = " ";
    private String periodStart = " ".repeat(8), periodEnd = " ".repeat(8), pReport = "", qDate = "", pPage = "   ";
    private BigDecimal totalInNet = Z, totalInVat = Z, totalOutNet = Z, totalOutVat = Z, totalDr = Z, totalCr = Z;
    private long checkAccount, ledgAccount, wsbStart, wscEnd;
    private String ledgName = "";
    // line-6-l の項目（レコード間で値が残る）
    private String pCodeL = "  ", pSpacerL = "/", pDateL = " ".repeat(8), pLegendL = " ".repeat(32);
    private long pTranL, pContraL;
    private BigDecimal pDebitL = Z, pCreditL = Z;
    private boolean subLegend;
    // line-6-a / line-6-v
    private String line6 = "", pVatType = "";

    private void irsub1() { call("irsub1", nl, fa); }
    private void irsub1(int fn) { fa.fileFunction = fn; irsub1(); }
    private void irsubp(int fn) { fa.fileFunction = fn; call("irsubp", post, fa, sys); }
    private boolean audit() { return tipe.equals("A"); }
    private boolean ledgers() { return tipe.equals("L"); }
    private boolean vatReport() { return tipe.equals("D"); }
    private boolean printing() { return outputReply.equals("P"); }
    private static String z5(long v) { return Num.edit(BigDecimal.valueOf(v), "zzzz9"); }
    private static String ed(BigDecimal v, String pic) { return Num.edit(v, pic); }
    private static String bz(BigDecimal v, String pic, int len) { return v.signum() == 0 ? " ".repeat(len) : Num.edit(v, pic); }
    private static final String M7 = "-(7)9.99", M6 = "-(6)9.99", M8 = "-(8)9.99", M9 = "-(9)9.99";
    private static long toNum(String s) { return Num.parse(s).longValue(); }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        post = newPostingRecord(); nl = newNlRecord(); def = newDefaultRecord();
        fa = fa();
        term().exceptionsEnabled = true; term().escEnabled = true;
        fa.fileNames = sys.str("system-files");
        fa.fileFunction = 3;
        call("irsub3", def, fa);
        boolean reaccept = false;
        while (true) {
            if (!reaccept) {
                totalInNet = totalInVat = totalOutNet = totalOutVat = totalDr = totalCr = Z;
                clearScreen();
                show(1, 1, PROG_NAME, 2);
                display(1, 28, "Posting  Reports", 7);
                show(1, 73, sys.str("run-date"), 2);
                display(5, 1, "Input Report required by letter...[ ]");
                display(5, 41, "Press <RETURN> to exit");
                display(7, 1, "(A) - Audit Report");
                display(8, 1, "(L) - Ledgers");
                display(9, 1, "(D) - VAT Day Book");
                display(11, 1, "Display or Print  <D> or <P>......[ ]");
                display(13, 1, "Select required sort by number....[ ]");
                display(15, 1, "(1) - Code order sequence");
                display(16, 1, "(2) - Date order sequence");
                display(17, 1, "(3) - Transaction number sequence");
                tipe = " "; wsReply = " ";
            }
            reaccept = false;
            tipe = up(accept(5, 36, 1));
            if (tipe.isBlank()) return;
            if (!audit() && !ledgers() && !vatReport()) continue;
            if (vatReport()) {
                while (true) {
                    display(7, 41, "Period Start Date  .......[dd/mm/yy]");
                    display(9, 41, "Period End Date  .........[dd/mm/yy]");
                    periodStart = pad(sys.str("start-date"), 8);
                    periodEnd = pad(sys.str("end-date"), 8);
                    periodStart = pad(acceptUpdate(7, 68, 8, periodStart), 8);
                    periodEnd = pad(acceptUpdate(9, 68, 8, periodEnd), 8);
                    if (dateNumeric(periodStart) && dateNumeric(periodEnd)) break;
                }
                wsbStart = yymmdd(periodStart);
                wscEnd = yymmdd(periodEnd);
            }
            do { outputReply = up(pad(accept(11, 36, 1), 1)); } while (!outputReply.equals("D") && !outputReply.equals("P"));
            do { sortSequ = (int) toNum(acceptUpdate(13, 36, 1, "0")); } while (sortSequ < 1 || sortSequ > 3);
            if (sortSequ != sys.intv("save-sequ")) {
                sys.setNum("save-sequ", sortSequ);
                sys.set("system-work-group", pad(tipe, 1) + outputReply + periodStart + periodEnd);
                call("irs055", sys);
            }
            if (ledgers()) { ledgerReport(); continue; }
            fa.accessType = 1;
            irsubp(1);
            if (fa.weError == 99) {
                display(ACCEPT_LINES, 1, "No Posting data present", 4);
                reaccept = true;
                continue;
            }
            if (printing()) reportPrint(); else displayReport();
        }
    }

    private static boolean dateNumeric(String d) { return numeric(d.substring(0, 2)) && numeric(d.substring(3, 5)) && numeric(d.substring(6, 8)); }
    private static long yymmdd(String d) { return Long.parseLong(d.substring(6, 8) + d.substring(3, 5) + d.substring(0, 2)); }
    /** dd/mm/yy を 9(6) の yymmdd として解釈する（非数字はレガシー同様に桁の数値部として扱う）。 */
    private static long yymmddLoose(String d) {
        StringBuilder b = new StringBuilder();
        for (char c : (d.substring(6, 8) + d.substring(3, 5) + d.substring(0, 2)).toCharArray()) b.append((char) ('0' + (c & 0x0f) % 10));
        return Long.parseLong(b.toString());
    }

    // ---- 見出し ----
    private String line1() { return pad(sys.str("suser"), 24) + " ".repeat(5) + pad(pReport, 36) + " ".repeat(6) + pad(sys.str("run-date"), 8); }
    private String line3() { return pad(sys.str("client"), 24) + "    End Date - " + pad(sys.str("end-date"), 8) + " ".repeat(24) + "Page " + pPage; }
    private String lineLedger() { return "Account - " + z5(ledgAccount) + " ".repeat(4) + pad(ledgName, 24); }
    private void setReport() {
        if (vatReport()) { qDate = periodEnd; pReport = Q_REPORT + qDate; } else pReport = "Audit  Trail";
    }
    private void showLine1() {
        show(1, 1, pad(sys.str("suser"), 24), 2);
        if (pReport.startsWith(Q_REPORT)) { display(1, 30, Q_REPORT); show(1, 58, qDate, 2); } else display(1, 30, pad(pReport, 36));
        show(1, 72, pad(sys.str("run-date"), 8), 2);
    }
    private void showLine3() {
        show(3, 1, pad(sys.str("client"), 24));
        show(3, 40, pad(sys.str("end-date"), 8));
        show(3, 77, pPage);
        display(3, 29, "End Date -");
        display(3, 72, "Page");
    }
    private void setPage() { pPage = Num.edit(BigDecimal.valueOf(counter), "zz9"); }
    private void addCounter() { counter = (counter + 1) % 1000; }

    // ---- 明細行 ----
    private void fixVatDef() { if (!numeric(post.str("vat-ac-def"))) post.setNum("vat-ac-def", 0); }
    private void buildAudit() {
        fixVatDef();
        int vd = post.intv("vat-ac-def");
        pVatType = vd == 31 ? "Input" : vd == 32 ? "Output" : "";
        line6 = "   " + z5(post.longv("post-key")) + " ".repeat(5) + post.str("post-date") + "   " + post.str("post-code") + " ".repeat(4)
                + z5(post.longv("post-dr")) + "   " + z5(post.longv("post-cr")) + ed(post.num("post-amount"), M9) + " " + ed(post.num("vat-amount"), M9)
                + " ".repeat(4) + pad(pVatType, 6);
    }
    private BigDecimal pInNet = Z, pInVat = Z, pOutNet = Z, pOutVat = Z;
    /** vat-area / vat-area-p。対象外なら false。 */
    private boolean buildVat() {
        String d = post.str("post-date");
        long pd = yymmddLoose(d);
        if (pd < wsbStart || pd > wscEnd) return false;
        fixVatDef();
        int vd = post.intv("vat-ac-def");
        if (vd < 31 || vd > 32) return false;
        BigDecimal amt = post.num("post-amount"), vat = post.num("vat-amount");
        String side = post.str("post-vat-side");
        if (vd == 31) {
            pInNet = amt; pInVat = vat; pOutNet = pOutVat = Z;
            if (side.equals("DR")) { totalInNet = totalInNet.add(amt); totalInVat = totalInVat.add(vat); }
            if (side.equals("CR")) { totalInNet = totalInNet.subtract(amt); totalInVat = totalInVat.subtract(vat); pInNet = amt.negate(); pInVat = vat.negate(); }
        } else {
            pOutNet = amt; pOutVat = vat; pInNet = pInVat = Z;
            if (side.equals("CR")) { totalOutNet = totalOutNet.add(amt); totalOutVat = totalOutVat.add(vat); }
            if (side.equals("DR")) { totalOutNet = totalOutNet.subtract(amt); totalOutVat = totalOutVat.subtract(vat); pOutNet = amt.negate(); pOutVat = vat.negate(); }
        }
        line6 = "   " + z5(post.longv("post-key")) + " ".repeat(5) + d + " ".repeat(4) + post.str("post-code") + " ".repeat(8)
                + bz(pInNet, M7, 11) + bz(pInVat, M7, 11) + bz(pOutNet, M7, 11) + bz(pOutVat, M7, 11);
        return true;
    }
    private String line8() {
        return "   Total" + " ".repeat(27) + bz(totalInNet, M7, 11) + bz(totalInVat, M7, 11) + bz(totalOutNet, M8, 12) + bz(totalOutVat, M7, 11);
    }
    private String line6L() {
        return pCodeL + pSpacerL + z5(pTranL) + "  " + pDateL + "  " + pLegendL + z5(pContraL) + bz(pDebitL, M7, 11) + bz(pCreditL, M7, 11);
    }
    private void showLine6L(int line) {
        show(line, 1, line6L());
        if (subLegend) display(line, 21, SUB_LEGEND, 3);
    }

    // ---- display-report ----
    private void displayReport() {
        counter = 0;
        useCode = "  ";
        if (audit()) askCode();
        while (true) {
            addCounter(); setPage();
            clearScreen();
            setReport();
            showLine1(); showLine3();
            if (vatReport()) { display(5, 1, L4C); display(5, 38, L4D); display(6, 1, L5C); display(6, 38, L5D); }
            else { display(5, 1, L4A); display(5, 44, L4B); display(6, 1, L5A); display(6, 44, L5B); }
            display(LINES, 1, C_EXIT);
            lin = 8;
            boolean nextPage = false;
            while (true) {
                irsubp(3);
                if (fa.weError == 3 || fa.weError == 99) break;
                if (vatReport()) { if (!buildVat()) continue; }
                else {
                    if (!useCode.isBlank() && !useCode.equals(post.str("post-code"))) continue;
                    buildAudit();
                }
                show(lin, 1, line6);
                if (audit() && !pVatType.isEmpty()) display(lin, 75, pad(pVatType, 6), 3);
                lin++;
                if (lin < ACCEPT_LINES) continue;
                lin = 8;
                wsReply = pad(accept(LINES, 43, 1), 1);
                if (wsReply.equalsIgnoreCase("X") || crtStatus() == ESC) { irsubp(2); return; }
                wsReply = " ";
                nextPage = true;
                break;
            }
            if (nextPage) continue;
            break;
        }
        if (!audit()) {
            if (lin >= L21) {
                lin = 8;
                wsReply = pad(accept(LINES, 43, 1), 1);
                for (; lin < ACCEPT_LINES; lin++) show(lin, 1, " ".repeat(80));
                lin = 8;
                wsReply = " ";
                addCounter(); setPage();
                show(3, 1, pad(sys.str("client"), 24));
                display(3, 25, "    End Date - ", 3);
                show(3, 40, pad(sys.str("end-date"), 8));
                display(3, 72, "Page ", 3);
                show(3, 77, pPage);
            }
            display(L21, 1, LINE_7);
            String l8 = line8();
            show(L22, 1, l8);
            display(L22, 4, "Total", 3);
            display(ACCEPT_LINES, 1, LINE_7);
        }
        eraseEol(LINES, 1);
        display(LINES, 1, "Press return for menu");
        wsReply = pad(accept(LINES, 23, 1), 1);
        irsubp(2);
    }

    private void askCode() {
        clearScreen();
        display(5, 1, "Input Code to Print (blank for all) ....[  ]");
        useCode = pad(accept(5, 42, 2), 2);
    }

    // ---- report-print ----
    private void reportPrint() {
        saveCode = "  "; useCode = "  ";
        if (audit()) askCode();
        prt = openPrint();
        counter = 0;
        setReport();
        headings();
        String pCodeA = "  ";
        while (true) {
            irsubp(3);
            if (fa.weError == 3 || fa.weError == 99) break;
            if (vatReport()) {
                if (post.num("vat-amount").signum() == 0 && post.num("post-amount").signum() == 0) continue;
                if (!buildVat()) continue;
            } else {
                String code = post.str("post-code");
                if (!useCode.isBlank() && !useCode.equals(code)) continue;
                if (sortSequ == 1 && !saveCode.equals(code) && !saveCode.isBlank()) { tranTotal(pCodeA); headings(); }
                pCodeA = code; saveCode = code;
                totalInNet = totalInNet.add(post.num("post-amount"));
                totalInVat = totalInVat.add(post.num("vat-amount"));
                buildAudit();
            }
            writeAfter(prt, line6, 1);
            lineCnt = (lineCnt + 1) % 100;
            if (lineCnt > 79) headings();
        }
        if (lineCnt > 74) headings();
        if (audit()) tranTotal(pCodeA);
        else {
            writeAfter(prt, LINE_7, 2);
            writeAfter(prt, line8(), 1);
            writeAfter(prt, LINE_7, 1);
            lineCnt = (lineCnt + 4) % 100;
        }
        printReport(sys, prt);
        irsubp(2);
    }

    private void tranTotal(String pCodeA) {
        if (useCode.isBlank()) return;
        String l8a = pad("Transaction Type   -   ", 24) + pCodeA + pad("    Total        ", 18) + ed(totalInNet, M8) + "  " + ed(totalInVat, M8);
        totalInNet = totalInVat = Z;
        writeAfter(prt, LINE_7_A, 2);
        writeAfter(prt, l8a, 1);
        writeAfter(prt, LINE_7_A, 1);
        lineCnt = (lineCnt + 4) % 100;
    }

    private void headings() {
        addCounter(); setPage();
        if (counter > 1) writeAfterPage(prt, line1()); else writeAfter(prt, line1(), 1);
        writeAfter(prt, line3(), 1);
        if (vatReport()) { writeAfter(prt, L4C + L4D, 1); writeAfter(prt, L5C + L5D, 1); }
        else { writeAfter(prt, L4A + L4B, 1); writeAfter(prt, L5A + L5B, 1); }
        lineCnt = 4;
    }

    // ---- ledger-report ----
    private void ledgerReport() {
        counter = 1; pPage = "  1";
        fa.accessType = 1;
        irsub1(1);
        pReport = "L e d g e r s";
        if (printing()) {
            prt = openPrint();
            writeAfter(prt, line1(), 1);
            writeAfter(prt, line3(), 2);
            writeAfter(prt, LINE_4_L, 2);
            lineCnt = 5;
        }
        while (true) {
            clearScreen();
            display(6, 1, "Enter account code required (zero for all)............  [     ]");
            long target = toNum(acceptUpdate(6, 58, 5, "00000"));
            if (target == 0) {
                while (true) {
                    irsub1(3);
                    if (fa.weError == 3) break;
                    getPostings();
                    if (wsReply.equals("X") || crtStatus() == ESC) break;
                }
                break;
            }
            nl.setNum("nl-owning", target);
            nl.setNum("nl-sub-nominal", 0);
            irsub1(4);
            if (fa.weError == 2) continue;
            getPostings();
            break;
        }
        irsub1(2);
        if (printing()) printReport(sys, prt);
    }

    private void ledgerMainDisplay() {
        clearScreen();
        showLine1(); showLine3();
        show(4, 11, z5(ledgAccount) + " ".repeat(4) + pad(ledgName, 24));
        display(4, 1, "Account -");
        display(5, 1, LINE_4_L);
        lin = 7;
        addCounter(); setPage();
    }

    private void getPostings() {
        ledgAccount = checkAccount = nl.longv("nl-sub-nominal") == 0 ? nl.longv("nl-owning") : nl.longv("nl-sub-nominal");
        ledgName = nl.str("nl-name");
        if (!printing()) ledgerMainDisplay();
        fa.accessType = 1;
        irsubp(1);
        totalDr = totalCr = Z; wsAccountUsed = 0;
        empty = "Y";
        long acs31 = def.longv("def-acs", 31), acs32 = def.longv("def-acs", 32);
        boolean toTotals = false;
        while (true) {
            irsubp(3);
            if (fa.weError == 3) { toTotals = true; break; }
            if (fa.weError == 99) break;
            long dr = post.longv("post-dr"), cr = post.longv("post-cr");
            if (checkAccount != dr && checkAccount != cr && checkAccount != acs31 && checkAccount != acs32) continue;
            if (empty.equals("Y") && printing()) { accountHeadings(); empty = " "; }
            wsAccountUsed = 1;
            pCodeL = post.str("post-code");
            pTranL = post.longv("post-key");
            pDateL = post.str("post-date");
            String legend = post.str("post-legend");
            int lv = legend.indexOf('\0');
            pLegendL = pad(lv < 0 ? legend : legend.substring(0, lv), 32);
            subLegend = false;
            BigDecimal vat = post.num("vat-amount");
            String side = post.str("post-vat-side");
            if (checkAccount == dr) {
                pContraL = cr; pDebitL = post.num("post-amount"); pCreditL = Z;
                totalDr = totalDr.add(post.num("post-amount"));
                if (side.equals("CR")) { post.add("post-amount", vat); pDebitL = post.num("post-amount"); totalDr = totalDr.add(vat); }
            }
            if (checkAccount == cr) {
                pContraL = dr; pCreditL = post.num("post-amount"); pDebitL = Z;
                totalCr = totalCr.add(post.num("post-amount"));
                if (side.equals("DR")) { post.add("post-amount", vat); pCreditL = post.num("post-amount"); totalCr = totalCr.add(vat); }
            }
            if (checkAccount == acs31) {
                getVat(31, dr, cr, vat, side);
                if (vat.signum() == 0) { vatCheck = 0; continue; }
            }
            if (checkAccount == acs32) {
                getVat(32, dr, cr, vat, side);
                if (vat.signum() == 0) { vatCheck = 0; continue; }
            }
            if (vatCheck == 9) { vatCheck = 0; continue; }
            if (printing()) {
                writeAfter(prt, line6L(), 1);
                lineCnt = (lineCnt + 1) % 100;
                if (lineCnt > 74) { printHeadings(); accountHeadings(); }
                continue;
            }
            showLine6L(lin);
            lin++;
            if (lin < ACCEPT_LINES) continue;
            display(LINES, 1, C_EXIT);
            wsReply = pad(accept(LINES, 43, 1), 1);
            if (wsReply.equalsIgnoreCase("X") || crtStatus() == ESC) { wsReply = "X"; break; }
            ledgerMainDisplay();
        }
        if (toTotals) totals();
        acMarker = 0;
        irsubp(2);
    }

    /** get-input-vat / get-output-vat。 */
    private void getVat(int want, long dr, long cr, BigDecimal vat, String side) {
        fixVatDef();
        if (post.intv("vat-ac-def") != want) { vatCheck = 9; return; }
        if (side.equals("CR")) { pContraL = dr; pCreditL = vat; pDebitL = Z; totalCr = totalCr.add(vat); }
        if (side.equals("DR")) { pContraL = cr; pDebitL = vat; pCreditL = Z; totalDr = totalDr.add(vat); }
    }

    private void totals() {
        if (nl.longv("nl-sub-nominal") == 0) if (!subNominalSearch()) { /* Esc でも合計へ進む（レガシー同様） */ }
        if (wsAccountUsed == 0) return;
        if (empty.equals("Y") && printing()) return;
        String l8l = " ".repeat(58) + bz(totalDr, M6, 10) + bz(totalCr, M7, 11);
        String name = nl.str("nl-name");
        int i = name.indexOf("  ");
        String nm = i < 0 ? name : name.substring(0, i);
        String balName = pad(nm + "  Balance", 40);
        totalDr = totalDr.subtract(totalCr);
        String d1 = " ".repeat(10), d2 = d1, l9l;
        if (totalDr.signum() > 0) { l9l = " ".repeat(18) + balName + bz(totalDr, M6, 10) + " ".repeat(11); d1 = "=".repeat(10); }
        else { l9l = " ".repeat(18) + balName + " ".repeat(10) + bz(totalDr, M7, 11); d2 = "=".repeat(10); }
        String l7l = " ".repeat(58) + d1 + " " + d2;
        if (printing()) {
            if (lineCnt > 78) printHeadings();
            writeAfter(prt, LINE_7_M, 1);
            writeAfter(prt, l8l, 1);
            writeAfter(prt, LINE_7_M, 1);
            writeAfter(prt, l9l, 1);
            writeAfter(prt, l7l, 1);
            lineCnt = (lineCnt + 5) % 100;
            return;
        }
        if (lin > L17) {
            totalCont();
            if (crtStatus() == ESC) { wsReply = "X"; return; }
            ledgerMainDisplay();
        }
        lin++;
        display(lin, 1, LINE_7_M);
        lin++;
        show(lin, 1, l8l);
        lin++;
        display(lin, 1, LINE_7_M);
        lin++;
        show(lin, 1, l9l);
        if (nm.length() + 9 <= 40) display(lin, 19 + nm.length(), "  Balance", 3);
        lin++;
        display(lin, 1, l7l);
        totalCont();
    }

    private void totalCont() {
        show(LINES, 1, " ".repeat(80));
        display(LINES, 1, C_CONTINUE);
        wsReply = pad(accept(LINES, 43, 1), 1);
    }

    /** sub-nominal-search: 主勘定配下の補助勘定残高を明細として出力する。 */
    private boolean subNominalSearch() {
        pSpacerL = " ";
        long holdOwning = nl.longv("nl-owning");
        boolean ok = true;
        while (true) {
            irsub1(3);
            if (fa.weError == 3) break;
            if (nl.longv("nl-owning") != holdOwning) break;
            BigDecimal dr = nl.num("nl-dr"), cr = nl.num("nl-cr");
            if (dr.compareTo(cr) == 0) continue;
            if (acMarker == 0 && printing()) accountHeadings();
            wsAccountUsed = 1;
            pCodeL = "  "; pDateL = " ".repeat(8);
            pTranL = 0; pContraL = 0;
            pLegendL = pad(SUB_LEGEND + z5(nl.longv("nl-sub-nominal")), 32);
            subLegend = true;
            if (dr.compareTo(cr) > 0) { totalDr = totalDr.add(dr).subtract(cr); pDebitL = dr.subtract(cr); pCreditL = Z; }
            else { totalCr = totalCr.add(cr).subtract(dr); pCreditL = cr.subtract(dr); pDebitL = Z; }
            empty = " ";
            if (printing()) {
                writeAfter(prt, line6L(), 1);
                lineCnt = (lineCnt + 1) % 100;
                if (lineCnt > 79) { printHeadings(); accountHeadings(); }
                continue;
            }
            showLine6L(lin);
            lin++;
            if (lin < L22) continue;
            display(ACCEPT_LINES, 1, C_CONTINUE);
            wsReply = pad(accept(ACCEPT_LINES, 43, 1), 1);
            if (crtStatus() == ESC) { ok = false; break; }
            for (lin = 7; lin < ACCEPT_LINES; lin++) show(lin, 1, " ".repeat(80));
            lin = 7;
        }
        pSpacerL = "/";
        subLegend = false;
        nl.setNum("nl-owning", holdOwning);
        nl.setNum("nl-sub-nominal", 0);
        fa.accessType = 5;
        irsub1(9);
        return ok;
    }

    private void accountHeadings() {
        if (lineCnt > 70) printHeadings();
        acMarker = 1;
        writeAfter(prt, lineLedger(), 2);
        writeAfter(prt, "", 1);
        lineCnt = (lineCnt + 3) % 100;
    }

    private void printHeadings() {
        addCounter(); setPage();
        if (counter > 1) writeAfterPage(prt, line1()); else writeAfter(prt, line1(), 1);
        writeAfter(prt, line3(), 2);
        writeAfter(prt, LINE_4_L, 2);
        lineCnt = 5;
    }
}
