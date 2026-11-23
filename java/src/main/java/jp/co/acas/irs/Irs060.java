package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * irs060.cbl: 決算書作成（損益計算書・貸借対照表・売上比率）と期末処理。
 * irs065 が勘定種別順に整列した worksort.tmp を入力とする。
 * レガシーは名目勘定元帳と作業ファイルが同一レコード域（same record area）なので、rec を共用する。
 */
public class Irs060 extends IrsBase {
    static final String PROG_NAME = "irs060 (3.01.12)";
    private static final BigDecimal Z = BigDecimal.ZERO, E7 = BigDecimal.valueOf(10_000_000);
    private static final String HYPHENS = "---------", EQUALS = "=========", B9 = " ".repeat(9), B7 = " ".repeat(7);
    private static final String PORTRAIT = "orientation-requested=3 page-left=48 page-top=24 page-right=24";
    private static final int[] DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

    private Rec sys, rec, nl, def, post;
    private FileAccess fa;
    private CobFile wf, nlFile, prt;
    private boolean wfEof;
    private int j, y;
    private final BigDecimal[] total1 = new BigDecimal[27], total2 = new BigDecimal[27];
    private BigDecimal level11 = Z, level12 = Z, level21 = Z, level22 = Z, net1 = Z, net2 = Z, work1 = Z, work2 = Z;
    private boolean subTotal;
    private String line1, line2, line3, line5;
    private String l7name = "", l7v1 = B7, l7v2 = B7, l7v3 = B7, l7v4 = B7, l9name = "", l9v2 = B7, ratio = "   0.00";
    private final char[] l7s = "        ".toCharArray();
    private String u1 = B9, u2 = B9, u3 = B9, u4 = B9;
    private long plAc;
    private String wsAc = " ";

    private static String centre(String s, int n) {
        String t = s.strip();
        if (t.isEmpty()) return pad("", n);
        return pad(" ".repeat((n - t.length()) / 2) + t, n);
    }
    /** z(6)9 blank when zero への ROUNDED 転記（符号なし、上位桁あふれは切り捨て）。 */
    private static String v7(BigDecimal v) {
        BigDecimal r = v.setScale(0, RoundingMode.HALF_UP).abs().remainder(E7);
        return r.signum() == 0 ? B7 : Num.edit(r, "z(6)9");
    }
    private static BigDecimal t7(BigDecimal v) { return v.remainder(E7); }   // s9(7)v99 への転記
    private void hitReturn(int line, int col) { accept(line, col, 1); }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        rec = newNlRecord(); nl = newNlRecord(); def = newDefaultRecord(); post = newPostingRecord();
        fa = fa();
        fa.fileNames = sys.str("system-files");
        term().exceptionsEnabled = true; term().escEnabled = true;
        String wsClient = centre(sys.str("client"), 24);
        screenHeads();
        for (int i = 1; i <= 26; i++) total1[i] = total2[i] = Z;
        while (true) {
            display(8, 1, "Enter comparative to use (0 to 4) -  [ ]");
            String s = acceptUpdate(8, 39, 1, "0");
            j = numeric(s) ? Integer.parseInt(s) : 0;
            if (j <= 4) break;
        }
        display(10, 1, "Enter Profit & Loss Report Title     [");
        display(10, 79, "]");
        String plTitle = pad(acceptUpdate(10, 39, 40, pad("Profit and Loss Report", 40)), 40);
        String repType;
        do {
            display(12, 1, "Period Report (P) or Year Report (Y) [ ]");
            repType = up(pad(accept(12, 39, 1), 1));
        } while (!repType.equals("P") && !repType.equals("Y"));
        String endDate = pad(sys.str("end-date"), 8);
        String yy = endDate.substring(6, 8);
        String yy2 = numeric(yy) ? Num.z9((Integer.parseInt(yy) + 99) % 100, 2) : yy;
        line5 = " ".repeat(34) + "--------20" + yy + "--------" + " ".repeat(5) + (j == 0 ? "" : "--------20" + yy2 + "--------");
        display(16, 1, "Checking Accounts Please Wait");
        wf = CobFile.sequential(ctx.store, ctx.irsPath("worksort.tmp"));
        if (!wf.open(CobFile.Mode.INPUT).equals("00")) {
            display(24, 1, "failure to open Work File!!!!");
            display(24, 41, "Hit return for menu");
            hitReturn(24, 61);
            stopRun();
        }
        // read-loop / accumulate
        while (wf.readNext(rec).equals("00")) {
            String ac = rec.str("nl-ac");
            int w = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(up(ac)) + 1;
            if (w == 0 || ac.isBlank()) {
                clearScreen();
                display(5, 1, "Ledgers Incorrectly Coded! Aborting.");
                display(7, 1, "ACCOUNT  - ");
                show(7, 13, rec.str("nl-owning"), 2);
                show(7, 18, "/", 2);
                show(7, 19, rec.str("nl-sub-nominal"), 2);
                display(7, 1, "Hit return for menu");
                hitReturn(7, 21);
                wf.close();
                stopRun();
            }
            char c = ac.charAt(0);
            boolean crSide = c < 'E' || c == 'I' || c == 'J' || c > 'T';
            if (c > 'D' && c < 'I') crSide = false;
            BigDecimal dr = rec.num("nl-dr"), cr = rec.num("nl-cr");
            total1[w] = total1[w].add(crSide ? cr.subtract(dr) : dr.subtract(cr));
            if (j != 0) {
                BigDecimal drl = rec.num("nl-dr-last", j), crl = rec.num("nl-cr-last", j);
                total2[w] = total2[w].add(crSide ? crl.subtract(drl) : drl.subtract(crl));
            }
        }
        // read-end
        display(16, 1, "Printing Account Ledgers. Please Wait");
        wf.close();
        wf.open(CobFile.Mode.INPUT);
        prt = openPrint();
        line1 = " ".repeat(28) + wsClient;
        line2 = " ".repeat(20) + centre(plTitle, 40);
        line3 = repType.equals("Y") ? " ".repeat(25) + "For the Year Ended " + endDate
                : " ".repeat(19) + "For the Period From " + pad(sys.str("start-date"), 8) + " to " + endDate;
        writeAfter(prt, line1, 1);
        writeAfter(prt, line2, 2);
        writeAfter(prt, line3, 2);
        writeAfter(prt, line5, 2);
        blank();
        y = 1;
        if (!wf.readNext(rec).equals("00")) {
            wfEof = true;
            display(24, 1, "PE 005946");
            display(24, 41, "Hit return for menu");
            hitReturn(24, 61);
            wf.close();
            stopRun();
        }
        lines(5);
        groupTotal("Total Income");
        level21 = t7(level11); level22 = t7(level12);
        level11 = level12 = Z;
        blank(); blank();
        lines(9);
        groupTotal("Less Total Direct Costs");
        level21 = t7(level21.subtract(level11)); level22 = t7(level22.subtract(level12));
        level11 = level21; level12 = level22;
        subTotal = true;
        underline2(HYPHENS); w8(); clear8();
        groupTotal("Gross Profit");
        level11 = level12 = Z;
        subTotal = false;
        blank();
        lines(11);
        groupTotal("Plus Sundry Income");
        level21 = t7(level21.add(level11)); level22 = t7(level22.add(level12));
        blank();
        level11 = level12 = Z;
        blank();
        lines(15);
        groupTotal("Less Total Indirect Costs");
        level21 = t7(level21.subtract(level11)); level22 = t7(level22.subtract(level12));
        level11 = net1 = level21; level12 = net2 = level22;
        subTotal = true;
        underline2(HYPHENS); w8(); clear8();
        groupTotal("Net Profit");
        subTotal = false;
        level11 = level12 = level21 = level22 = Z;
        underline2(EQUALS); w8(); clear8();
        writeAfterPage(prt, line1);
        line2 = " ".repeat(20) + "             Balance Sheet              ";
        writeAfter(prt, line2, 2);
        writeAfter(prt, line3, 2);
        writeAfter(prt, line5, 2);
        clear8();
        lines(18);
        groupTotal("Fixed Asset Total");
        level21 = t7(level11); level22 = t7(level12);
        level11 = level12 = Z;
        blank();
        lines(21);
        groupTotal("Plus Total Current Assets");
        level21 = t7(level21.add(level11)); level22 = t7(level22.add(level12));
        level11 = level21; level12 = level22;
        subTotal = true;
        underline2(HYPHENS); w8(); clear8();
        groupTotal("Total Assets");
        level11 = level12 = Z;
        subTotal = false;
        blank();
        lines(23);
        groupTotal("Less Current Liabilities");
        level21 = t7(level21.subtract(level11)); level22 = t7(level22.subtract(level12));
        level11 = level21; level12 = level22;
        underline2(HYPHENS); w8(); clear8();
        subTotal = true;
        groupTotal("Net Current Assets");
        underline2(EQUALS); w8();
        level11 = level12 = level21 = level22 = Z;
        subTotal = false;
        u2 = u4 = B9;
        writeAfter(prt, "", 2);
        lines(27);
        groupTotal("Capital Account Total");
        w8();
        level21 = t7(level11); level22 = t7(level12);
        level11 = level12 = Z;
        clear8();
        blank();
        level11 = net1; level12 = net2;
        groupTotal("Net Profits");
        level21 = t7(level21.add(level11)); level22 = t7(level22.add(level12));
        level11 = level21; level12 = level22;
        subTotal = true;
        underline2(HYPHENS); w8(); clear8();
        groupTotal("Net Current Assets");
        level11 = level12 = level21 = level22 = Z;
        underline2(EQUALS); w8();
        wf.close();
        ratio();
        printReport(sys, prt, PORTRAIT);
        screenHeads();
        display(5, 1, "End of period processing outputs the current year figures to a comparative.");
        display(6, 1, "Revenue accounts are zeroed but Capital Accounts retain their value.");
        endOfPeriod();
    }

    private void screenHeads() {
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 29, "Final Accounts Production", 7);
        show(1, 73, sys.str("run-date"), 2);
    }

    private void blank() { writeAfter(prt, "", 1); }
    private void underline2(String s) { u2 = s; if (j > 0) u4 = s; }
    private void clear8() { u1 = u2 = u3 = u4 = B9; }
    private void w8() { writeAfter(prt, " ".repeat(34) + u1 + "  " + u2 + " ".repeat(5) + u3 + "  " + u4, 1); }
    private void lines(int until) { do { lineTotal(); y++; } while (y < until); }

    /** line-total section: 種別 y の勘定を 1 行ずつ印字し、種別合計を level-1x へ加える。 */
    private void lineTotal() {
        l7v1 = v7(total1[y]);
        if (j > 0) { l7v3 = v7(total2[y]); level12 = level12.add(total2[y]); }
        level11 = level11.add(total1[y]);
        boolean n1 = total1[y].signum() < 0, n2 = total2[y].signum() < 0 && j > 0;
        l7s[0] = n1 ? '(' : ' '; l7s[1] = n1 ? ')' : ' ';
        l7s[4] = n2 ? '(' : ' '; l7s[5] = n2 ? ')' : ' ';
        char letter = (char) ('A' + y - 1);
        boolean read = false;   // false = by-pass から開始
        while (true) {
            // loop-1: 既に終端に達した後の READ は FILE STATUS 46（AT END ではない）となり、
            // レガシーは直前のレコードのまま by-pass へ進む（PE009865 を繰り返す。レガシー実測）。
            if (read) { boolean wasEof = wfEof; if (!readWork() && !wasEof) break; }
            read = true;
            // by-pass
            char ac = rec.str("nl-ac").charAt(0);
            if (ac < letter) {
                display(20, 1, "PE009865");
                display(24, 11, "Note error and Hit return to continue");
                hitReturn(24, 51);
                continue;
            }
            if (ac > letter) break;
            nl.load(rec.copyBytes());
            l9name = nl.str("nl-name");
            boolean more = true;
            // loop-2
            while (true) {
                if (!readWork()) { more = false; break; }
                if (rec.longv("nl-sub-nominal") == 0) { writeOut(); break; }
                nl.add("nl-dr", rec.num("nl-dr"));
                nl.add("nl-cr", rec.num("nl-cr"));
                if (j != 0) {
                    nl.add("nl-dr-last", rec.num("nl-dr-last", j), j);
                    nl.add("nl-cr-last", rec.num("nl-cr-last", j), j);
                }
            }
            if (!more) break;
            read = false;
        }
        writeOut();   // main-end
    }

    private boolean readWork() {
        if (wfEof) return false;
        if (wf.readNext(rec).equals("00")) return true;
        wfEof = true;
        return false;
    }

    /** group-total section。 */
    private void groupTotal(String name) {
        l7name = name;
        l7v2 = v7(level11);
        if (j > 0) l7v4 = v7(level12);
        if (subTotal) l7v1 = l7v3 = B7;
        boolean n1 = level11.signum() < 0, n2 = level12.signum() < 0 && j > 0;
        l7s[2] = n1 ? '(' : ' '; l7s[3] = n1 ? ')' : ' ';
        l7s[6] = n2 ? '(' : ' '; l7s[7] = n2 ? ')' : ' ';
        u1 = HYPHENS;
        if (j > 0) u3 = HYPHENS;
        if (!subTotal) w8();
        writeAfter(prt, "  " + pad(l7name, 27) + " ".repeat(5) + l7s[0] + l7v1 + l7s[1] + "  " + l7s[2] + l7v2 + l7s[3]
                + " ".repeat(5) + l7s[4] + l7v3 + l7s[5] + "  " + l7s[6] + l7v4 + l7s[7], 1);
        java.util.Arrays.fill(l7s, ' ');
        l7v1 = l7v2 = l7v3 = l7v4 = B7;
        clear8();
    }

    /** write-out section: 集計済みの勘定（nl）を 1 行印字する。 */
    private void writeOut() {
        char c = nl.str("nl-ac").charAt(0);
        boolean crSide = c < 'E' || c == 'I' || c == 'J' || c > 'T';
        if (c > 'D' && c < 'I') crSide = false;
        BigDecimal dr = nl.num("nl-dr"), cr = nl.num("nl-cr");
        work1 = crSide ? cr.subtract(dr) : dr.subtract(cr);
        work2 = Z;
        if (j > 0) {
            BigDecimal drl = nl.num("nl-dr-last", j), crl = nl.num("nl-cr-last", j);
            work2 = crSide ? crl.subtract(drl) : drl.subtract(crl);
        }
        if (!(work1.signum() == 0 && work2.signum() == 0) && !l9name.isBlank()) {
            boolean n1 = work1.signum() < 0, n2 = work2.signum() < 0 && j > 0;
            if (j > 0) l9v2 = v7(work2);
            writeAfter(prt, pad(l9name, 34) + (n1 ? "(" : " ") + v7(work1) + (n1 ? ")" : " ") + " ".repeat(16)
                    + (n2 ? "(" : " ") + l9v2 + (n2 ? ")" : " "), 1);
        }
        l9name = "";
        work1 = work2 = Z;
    }

    /** ratio section: 売上比率。 */
    private void ratio() {
        writeAfterPage(prt, line1);
        writeAfter(prt, line2, 2);
        writeAfter(prt, pad(sys.str("client"), 24) + " ".repeat(6) + pad("    Sales Ratios    ", 23) + "      Period To - " + pad(sys.str("end-date"), 8), 2);
        blank();
        BigDecimal w1 = total1[1].add(total1[2]).add(total1[3]).add(total1[4]);
        BigDecimal w2 = w1.subtract(total1[5].add(total1[6]).add(total1[7]).add(total1[8]));
        BigDecimal w3 = w1.divide(BigDecimal.valueOf(100), 2, RoundingMode.DOWN);
        divide(w2, w3);
        writeAfter(prt, pad("Gross Profit % to Sales", 24) + ratio, 2);
        w2 = w2.subtract(total1[11]).subtract(total1[12]).subtract(total1[13]).subtract(total1[14]);
        divide(w2, w3);
        writeAfter(prt, pad("Net Profit % to Sales", 24) + ratio, 2);
    }
    /** divide ... giving l11-ratio rounded（0 除算時は l11-ratio を変更しない）。 */
    private void divide(BigDecimal a, BigDecimal b) {
        if (b.signum() == 0) return;
        ratio = Num.edit(a.divide(b, 2, RoundingMode.HALF_UP).abs().remainder(BigDecimal.valueOf(10000)), "zzz9.99");
    }

    // ---------- 期末処理 ----------
    private void endOfPeriod() {
        while (true) {   // e-o-p-option
            display(9, 1, "Do you require end of period processing (Y/N) :- ");
            String r = up(pad(accept(9, 50, 1), 1));
            if (r.equals("N")) return;
            if (!r.equals("Y")) continue;
            fa.fileFunction = 3;
            call("irsub3", def, fa);
            while (true) {
                display(11, 1, "Comparative field to use - ");
                String s = acceptUpdate(11, 28, 1, "0");
                j = numeric(s) ? Integer.parseInt(s) : 0;
                if (j >= 1 && j <= 4) break;
            }
            if (def.longv("def-acs", 30) == 0 || def.longv("def-acs", 31) == 0) {
                display(12, 1, "Default A/C 30 or 31 Not setup", 4);
                stopRun();
            }
            boolean again = false;
            while (true) {   // get-pl
                display(13, 1, "Enter P/L Appropriation or Capital A/C :- ");
                plAc = Num.parse(acceptUpdate(13, 43, 5, "00000")).longValue();
                display(15, 1, "You have selected end of period processing overwriting comparative field - ");
                show(15, 77, String.valueOf(j), 2);
                display(16, 1, "with P/L or Capital A/C - ");
                show(16, 27, Num.z9(plAc, 5), 2);
                display(17, 1, "Is This Correct ? (Y/N) - ");
                if (!up(pad(accept(17, 27, 1), 1)).equals("Y")) { again = true; break; }
                nlFile = CobFile.indexed(ctx.store, ctx.irsPath(fa.file(1)), 0, 10);
                nlFile.open(CobFile.Mode.INPUT);
                rec.setNum("nl-owning", plAc);
                rec.setNum("nl-sub-nominal", 0);
                if (nlFile.read(rec).equals("00")) break;
                clearScreen();
                show(5, 5, Num.z9(plAc, 5), 2);
                display(5, 13, "Does not exist. Hit return, then Check & re-enter");
                hitReturn(5, 65);
                nlFile.close();
            }
            if (!again) break;
        }
        wsAc = up(rec.str("nl-ac"));
        nlFile.close();
        nlFile.open(CobFile.Mode.IO);
        // loop-a / by-pass / loop-b: 当期残高を比較欄 j へ移し、損益勘定（種別 O 未満）をゼロにする
        boolean inSub = false;
        while (nlFile.readNext(rec).equals("00")) {
            if (inSub) {
                if (rec.str("nl-type").equals("S")) continue;
                if (rec.longv("nl-sub-nominal") != 0) {
                    carry(nl.str("nl-ac"));
                    rec.set("nl-ac", nl.str("nl-ac"));
                    nlFile.rewrite(rec);
                    continue;
                }
            }
            nl.load(rec.copyBytes());
            if (nl.str("nl-type").equals("S")) { inSub = false; continue; }
            carry(rec.str("nl-ac"));
            nlFile.rewrite(rec);
            inSub = true;
        }
        vatTidyup();
        if (!plCapitalTidyup()) return;
        rec.setNum("nl-owning", plAc);
        rec.setNum("nl-sub-nominal", 0);
        while (true) {   // jump-back
            if (!nlFile.read(rec).equals("00")) {
                display(5, 5, "PE 009610");
                display(7, 1, "Hit return for menu");
                hitReturn(7, 21);
                stopRun();
            }
            if (rec.str("nl-type").equals("O")) break;
            long owning = rec.longv("nl-owning");
            rec.setNum("nl-sub-nominal", owning);
            rec.setNum("nl-owning", rec.longv("nl-pointer"));
        }
        if (net1.signum() > 0) rec.add("nl-cr", net1); else rec.add("nl-dr", net1);
        nlFile.rewrite(rec);
        nlFile.close();
        resetPostings();
    }

    private void carry(String ac) {
        rec.setNum("nl-dr-last", rec.num("nl-dr"), j);
        rec.setNum("nl-cr-last", rec.num("nl-cr"), j);
        if (ac.compareTo("O") < 0) { rec.setNum("nl-dr", 0); rec.setNum("nl-cr", 0); }
    }

    private void abort(String msg, int line, int col, String hit) {
        display(23, 1, msg);
        display(24, line, hit);
        hitReturn(24, col);
        stopRun();
    }

    /** vat-ac-tidyup section: 既定勘定 31（VAT）の補助勘定残高を主勘定へ集約する。 */
    private void vatTidyup() {
        rec.setNum("nl-owning", def.longv("def-acs", 31));
        rec.setNum("nl-sub-nominal", 0);
        while (true) {
            if (!nlFile.read(rec).equals("00")) {
                clearScreen();
                show(5, 1, rec.str("nl-owning"), 2);
                display(5, 7, "(Default 31 A/C) does not exist..ABORTING");
                display(24, 41, "Hit return ");
                hitReturn(24, 61);
                nlFile.close();
                stopRun();
            }
            if (!rec.str("nl-type").equals("S")) break;
            if (rec.longv("nl-pointer") == rec.longv("nl-owning")) {
                clearScreen();
                display(23, 1, "PE VAT01: Problems with CoA file");
                display(24, 41, "Hit return ");
                hitReturn(24, 61);
                nlFile.close();
                stopRun();
            }
            rec.setNum("nl-owning", rec.longv("nl-pointer"));
        }
        nl.load(rec.copyBytes());
        while (nlFile.readNext(rec).equals("00")) {
            if (rec.longv("nl-owning") != nl.longv("nl-owning")) break;
            if (rec.str("nl-type").equals("S")) continue;
            nl.add("nl-dr", rec.num("nl-dr"));
            nl.add("nl-cr", rec.num("nl-cr"));
            rec.setNum("nl-dr", 0); rec.setNum("nl-cr", 0);
            if (!nlFile.rewrite(rec).equals("00")) abort("PE 015370: Problems with CoA file cant rewrite", 1, 21, "Hit return for menu");
        }
        rec.load(nl.copyBytes());
        if (!nlFile.rewrite(rec).equals("00")) abort("PE 015470: Problems on rewrite for CoA file", 1, 21, "Hit return for menu");
    }

    /** pl-capital-ac-tidyup section: 指定勘定と同じ種別の全勘定残高を指定勘定へ集約する。false = 中断（goback）。 */
    private boolean plCapitalTidyup() {
        nl.setNum("nl-cr", 0); nl.setNum("nl-dr", 0);
        nlFile.close();
        nlFile.open(CobFile.Mode.IO);
        while (nlFile.readNext(rec).equals("00")) {
            String ac2 = up(rec.str("nl-ac"));
            if (!ac2.equals(wsAc)) continue;
            if (rec.str("nl-type").equals("S")) continue;
            rec.set("nl-ac", ac2);
            nl.add("nl-cr", rec.num("nl-cr"));
            nl.add("nl-dr", rec.num("nl-dr"));
            rec.setNum("nl-cr", 0); rec.setNum("nl-dr", 0);
            if (!nlFile.rewrite(rec).equals("00")) abort("PE 014900", 1, 21, "Hit return to continue");
        }
        rec.setNum("nl-owning", plAc);
        rec.setNum("nl-sub-nominal", 0);
        if (!nlFile.read(rec).equals("00")) abort("PE 015000", 1, 21, "Hit return to continue");
        if (rec.str("nl-type").equals("S")) {
            show(23, 1, Num.z9(plAc, 5), 2);
            display(23, 7, "is a Sub-nominal account, you must give me a main-account only..ABORTING!!");
            display(24, 41, "Hit return for menu");
            hitReturn(24, 61);
            return false;
        }
        rec.setNum("nl-dr", nl.num("nl-dr"));
        rec.setNum("nl-cr", nl.num("nl-cr"));
        if (!nlFile.rewrite(rec).equals("00")) abort("PE 015100", 1, 21, "Hit return to continue");
        return true;
    }

    /** reset-postings section: 転記ファイルを作り直し、各勘定の残高を期末翌日付の繰越転記として書く。 */
    private void resetPostings() {
        nlFile.open(CobFile.Mode.INPUT);
        fa.fileFunction = 1; fa.accessType = 3;
        call("irsub4", post, fa);
        plAc = 0;
        sys.setNum("save-sequ", 0);
        long uBin = ((Number) dateValidate(sys.str("end-date"))[1]).longValue() + 1;
        String uDate = unpack(uBin);
        long def30 = def.longv("def-acs", 30);
        while (nlFile.readNext(rec).equals("00")) {
            if (rec.str("nl-type").equals("S")) continue;
            BigDecimal dr = rec.num("nl-dr"), cr = rec.num("nl-cr");
            if (dr.compareTo(cr) == 0) continue;
            if (dr.compareTo(cr) > 0) { dr = dr.subtract(cr); cr = Z; } else { cr = cr.subtract(dr); dr = Z; }
            post.set("post-date", uDate);
            post.set("post-vat-side", "  ");
            plAc = (plAc + 1) % 100000;
            post.setNum("post-key", plAc);
            post.set("post-code", def.str("def-codes", 30));
            post.setNum("vat-ac-def", 0); post.setNum("vat-amount", 0);
            post.set("post-legend", "Balance Forward");
            post.setNum("post-cr", def30); post.setNum("post-dr", def30);
            long owning = rec.longv("nl-sub-nominal") != 0 ? rec.longv("nl-sub-nominal") : rec.longv("nl-owning");
            if (dr.signum() > 0) { post.setNum("post-dr", owning); post.setNum("post-amount", dr); }
            else if (cr.signum() > 0) { post.setNum("post-cr", owning); post.setNum("post-amount", cr); }
            if (post.longv("post-cr") == def30 && post.longv("post-dr") == def30) continue;
            fa.fileFunction = 5;
            call("irsub4", post, fa);
        }
        nlFile.close();
        fa.fileFunction = 2;
        call("irsub4", post, fa);
        sys.setNum("next-post", plAc);
    }

    /** ws-unpack: 通算日数 u-bin を dd/mm/yy へ戻す。 */
    static String unpack(long uBin) {
        long save = uBin;
        int yy = 0, mm = 1, dd = 0, w1 = 1, w2 = 0;
        boolean done = false;
        while (true) {
            save -= 365;
            if (save > 0) yy++; else { save += 365; break; }
            if (yy == w2 && save > 59) { w2 += 4; save -= 1; }
            if (save == 0) { yy--; save = 365; break; }
        }
        if (save == 365) { dd = 31; mm = 12; done = true; }
        if (!done) {
            while (true) {
                save -= DAYS[Math.min(w1, 12) - 1];
                if (save > 0) { w1++; mm++; } else break;
            }
            dd += (int) (save + DAYS[Math.min(w1, 12) - 1]);
        }
        return Num.z9(Math.floorMod(dd, 100), 2) + "/" + Num.z9(mm % 100, 2) + "/" + Num.z9(Math.floorMod(yy, 100), 2);
    }
}
