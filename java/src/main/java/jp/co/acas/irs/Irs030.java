package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;

/** irs030.cbl: 仕訳転記（Transaction Posting）。 */
public class Irs030 extends IrsBase {
    static final String PROG_NAME = "irs030 (3.01.15)";
    static final String AMT = "z(6)9.99-";
    private static final BigDecimal HUNDRED = BigDecimal.valueOf(100);
    private Rec sys, nl, def, post;
    private FileAccess fa;
    private int a, c, d, e, w, y, lin, vatFlag, vatFlag2, revFlag;
    private final int wsLines = 24, ws20 = 20, ws21 = 21, ws22 = 22, ws23 = 23;
    private String wsReply = " ", wsType = "  ", wsTypeDisplay = "  ", wsDefName = "", wsVatAc = "", wsVatCode = " ";
    private String displayAccount = "", displayLegend = "", netDisplay = "", vatDisplay = "";
    private BigDecimal wsDefault = BigDecimal.ZERO, wsVat = BigDecimal.ZERO, wsBatch = BigDecimal.ZERO, amtOk = BigDecimal.ZERO;
    private long inputAccount;
    private int postRecordCnt;

    private void irsub1(int fn) { fa.fileFunction = fn; call("irsub1", nl, fa); }
    private void irsub3(int fn) { fa.fileFunction = fn; call("irsub3", def, fa); }
    private void irsub4(int fn) { fa.fileFunction = fn; call("irsub4", post, fa); }
    private static long toNum(String s) { return Num.parse(s).longValue(); }
    private BigDecimal amount() { return post.num("post-amount"); }
    private BigDecimal vatAmount() { return post.num("vat-amount"); }
    private void readNl(long owning) { nl.setNum("nl-owning", owning); nl.setNum("nl-sub-nominal", 0); irsub1(4); }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        nl = newNlRecord(); def = newDefaultRecord(); post = newPostingRecord();
        fa = fa();
        initialiseMain();
        if (a > 0) return;
        while (true) {
            // main-loop
            w = 0;
            eraseEos(1, 1);
            show(1, 1, PROG_NAME, 2);
            display(1, 31, "Transaction Posting", 1);
            display(5, 1, "Enter Run Option     -    [  ]");
            display(5, 32, "(<99>    Display Existing Defaults)");
            display(6, 32, "(<88>    Add to Existing Postings)");
            display(7, 32, "(<77>    Clear Existing Postings)");
            display(8, 32, "(<66>    Add PL or SL Postings from file)");
            display(10, 32, "(<Return> to exit to System Menu)");
            w = (int) toNum(acceptUpdate(5, 28, 2, "00"));
            if (w == 0) { irsub1(2); return; }
            if (w == 99) showDefault();
            if (w == 77) {
                fileInit();
                if (wsReply.equals("Z")) continue;
                sys.setNum("next-post", 0); sys.setNum("save-sequ", 0);
            } else {
                if (w == 66) { sys.setNum("save-sequ", 0); ledgerPostingsAdd(); }
                if (w != 88) continue;
            }
            if (!getDefaultThruSetUp()) return;
            eraseEos(1, 1);
            setUp2();
            if (!inputLoop()) return;
        }
    }

    /** get-default 〜 set-up。false は main-exit（プログラム終了）。 */
    private boolean getDefaultThruSetUp() {
        boolean prompt = true;
        while (true) {
            if (prompt) { eraseEol(wsLines, 1); display(wsLines, 1, "Enter Default Number -    [  ]"); }
            prompt = true;
            w = (int) toNum(acceptUpdate(wsLines, 28, 2, "00"));   // 数値項目の ACCEPT はゼロ表示から始まる（レガシー実測）
            if (w < 1 || w > 32) continue;
            readNl(def.longv("def-acs", w));
            if (fa.weError == 2) {
                eraseEol(wsLines, 34);
                display(wsLines, 34, "That Account now deleted!!!  Re-enter!");
                prompt = false;
                continue;
            }
            vatFlag = w > 30 || nl.longv("nl-owning") == def.longv("def-acs", 31) || nl.longv("nl-owning") == def.longv("def-acs", 32) ? 1 : 0;
            eraseEol(wsLines, 1);
            show(wsLines, 1, nl.str("nl-name"), 2);
            String dv = def.str("def-vat", w);
            if (dv.equals("N")) display(wsLines, 26, "(No VAT)    ");
            else if (dv.equals("O")) display(wsLines, 26, "(Output VAT - Sales)");
            else display(wsLines, 26, "(Input VAT - Purchases) ");
            wsDefName = nl.str("nl-name");
            boolean again = false;
            while (true) {
                display(wsLines, 51, "Correct Account (Y/N)....[ ]");
                wsReply = accept(wsLines, 77, 1);
                if (wsReply.equalsIgnoreCase("n")) { again = true; break; }
                if (wsReply.equalsIgnoreCase("y")) break;
            }
            if (again) continue;
            break;
        }
        do {
            eraseEol(wsLines, 1);
            display(wsLines, 1, "Enter Run Characteristic [  ]");
            display(wsLines, 31, "('DR' or 'CR') DR if entered a/c, is debited (TO)");
            wsType = up(accept(wsLines, 27, 2));
        } while (!wsType.equals("DR") && !wsType.equals("CR"));
        eraseEol(wsLines, 1);
        wsTypeDisplay = wsType;
        wsType = wsType.equals("DR") ? "CR" : "DR";
        wsDefault = nl.num("nl-dr").subtract(nl.num("nl-cr"));
        if (def.str("def-vat", w).equals("N")) {
            wsVatAc = ""; wsVat = BigDecimal.ZERO; post.setNum("vat-ac-def", 0);
        } else {
            y = def.str("def-vat", w).equals("O") ? 32 : 31;
            post.setNum("vat-ac-def", y);
            readNl(def.longv("def-acs", y));
            if (fa.weError == 2) {
                eraseEol(wsLines, 1);
                display(wsLines, 1, "VAT Account not present, Fix it!,returning to main menu. Now hit return", 4);
                wsReply = accept(wsLines, 74, 1);
                eraseEol(wsLines, 1);
                return false;
            }
            wsVat = nl.num("nl-cr").subtract(nl.num("nl-dr"));
            wsVatAc = nl.str("nl-name");
        }
        // set-up
        fa.accessType = 2;
        irsub4(1);
        wsBatch = BigDecimal.ZERO; sys.setNum("save-sequ", 0);
        return true;
    }

    private void setUp2() {
        headingScreen();
        display(5, 1, "--Date--  Account");
        display(5, 43, "----Narrative----     Net       VAT");
        lin = 6;
        post.set("post-date", sys.str("run-date"));
        post.setNum("post-key", sys.longv("next-post"));
        post.set("post-code", def.str("def-codes", w));
        post.set("post-legend", "");
    }

    private void headingScreen() {
        show(1, 1, PROG_NAME, 2);
        display(1, 31, "Transaction Posting", 1);
        show(1, 73, sys.str("run-date"), 2);
        display(2, 1, "Default -");
        show(2, 11, Num.edit(w, "z9"));
        display(2, 14, "Run is - ");
        show(2, 23, wsTypeDisplay);
        show(2, 50, pad(wsDefName, 20));
        show(2, 70, Num.edit(wsDefault, AMT));
        display(3, 1, "Client ");
        show(3, 8, sys.str("client"));
        display(3, 32, "End Date ");
        show(3, 41, sys.str("end-date"));
        show(3, 50, pad(wsVatAc, 20));
        show(3, 70, Num.edit(wsVat, AMT));
        display(4, 50, "Batch Total");
        show(4, 70, Num.edit(wsBatch, AMT));
    }

    private void amountPrompts() {
        display(ws23, 1, "Amount    - [           ]");
        display(ws23, 41, "VAT Code (P/M or space) - [ ]");
    }

    /** input-loop 〜 batch-close。false は main-exit。 */
    private boolean inputLoop() {
        while (true) {
            display(ws21, 1, "Date      - [        ]");
            display(ws21, 41, "Account                 -[     ]");
            display(ws22, 1, "Narrative - [");
            display(ws22, 46, "]");
            long postTrue = post.longv("post-key") + 1;
            display(ws22, 51, "{Posting number :- ");
            show(ws22, 70, Num.edit(postTrue, "z(4)9"));
            display(ws22, 75, "}");
            amountPrompts();
            post.setNum("post-amount", 0);
            show(ws21, 14, post.str("post-date"));
            // date-inp
            while (true) {
                post.set("post-date", acceptUpdate(ws21, 14, 8, post.str("post-date")));
                if (crtStatus() == 1003) {
                    endBatchThruBatchClose();
                    if (!getDefaultThruSetUp()) return false;
                    setUp2();
                    continue;
                }
                if (post.str("post-date").isBlank()) { endBatchThruBatchClose(); return true; }
                Object[] dv = dateValidate(post.str("post-date"));
                if ((int) dv[1] == 0) continue;
                post.set("post-date", (String) dv[0]);
                break;
            }
            show(lin, 1, post.str("post-date"));
            // account-input
            while (true) {
                inputAccount = toNum(acceptUpdate(ws21, 67, 5, Num.z9(Math.abs(inputAccount), 5)));
                displayAccount = Num.edit(inputAccount, "zzzz9");
                if (inputAccount == 0) { endBatchThruBatchClose(); return true; }
                if (inputAccount < 0) continue;
                if (inputAccount == def.longv("def-acs", w)) {
                    display(wsLines, 1, "Posting & Default a/c must not be the same");
                    continue;
                }
                show(wsLines, 1, " ".repeat(80));
                show(lin, 11, displayAccount);
                readNl(inputAccount);
                if (fa.weError == 2) { display(wsLines, 1, "That account does not exist. Re-enter"); continue; }
                show(wsLines, 1, " ".repeat(80));
                break;
            }
            vatFlag2 = inputAccount == def.longv("def-acs", 31) || inputAccount == def.longv("def-acs", 32) || vatFlag == 1 ? 1 : 0;
            amountPrompts();
            show(lin, 18, nl.str("nl-name"));
            show(ws22, 14, post.str("post-legend"));
            post.set("post-legend", acceptUpdate(ws22, 14, 32, post.str("post-legend")));
            displayLegend = post.str("post-legend").substring(0, 16);
            show(lin, 43, displayLegend);
            amtOk = BigDecimal.ZERO;
            if (vatFlag2 == 0) acceptMoney(ws23, 14);
            post.setNum("post-amount", amtOk);
            show(lin, 61, Num.edit(amount(), AMT));
            boolean noVat = def.str("def-vat", w).equals("N");
            if (noVat) {
                post.setNum("vat-amount", 0); wsVat = BigDecimal.ZERO;
            } else {
                // vat-input
                wsVatCode = " ";
                if (vatFlag2 == 1) post.setNum("vat-amount", 0);
                else while (true) {
                    wsVatCode = accept(ws23, 68, 1);
                    if (wsVatCode.equalsIgnoreCase("p")) { wsVatCode = "P"; net(); break; }
                    if (wsVatCode.equalsIgnoreCase("m")) { wsVatCode = "M"; gross(); break; }
                    if (wsVatCode.equals(" ")) { post.setNum("vat-amount", 0); break; }
                }
                show(lin, 61, Num.edit(amount(), AMT));
                show(lin, 71, Num.edit(vatAmount(), AMT));
                amtOk = vatAmount();
                acceptMoney2(lin, 71);
                if (vatAmount().compareTo(amtOk) != 0 && wsVatCode.equals("M")) {
                    post.setNum("post-amount", amount().add(vatAmount()).subtract(amtOk));
                    show(lin, 61, Num.edit(amount(), AMT));
                }
                post.setNum("vat-amount", amtOk.abs());
                if (amount().signum() == 0 && vatAmount().signum() == 0) continue;
            }
            // input-tidy / credit-tidy
            boolean credit = (wsType.equals("CR") && amount().signum() > 0) || (wsType.equals("DR") && amount().signum() < 0);
            if (amount().signum() < 0) { revFlag = 1; post.setNum("post-amount", amount().negate()); }
            BigDecimal gross = amount().add(vatAmount());
            wsBatch = revFlag == 1 ? wsBatch.subtract(gross) : wsBatch.add(gross);
            if (!credit) {
                post.setNum("post-dr", def.longv("def-acs", w));
                post.setNum("post-cr", inputAccount);
                post.set("post-vat-side", "CR");
                wsDefault = wsDefault.add(gross);
                wsVat = wsVat.add(vatAmount());
                nl.add("nl-cr", amount());
                if (inputAccount == def.longv("def-acs", w)) wsDefault = wsDefault.subtract(amount());
            } else {
                post.setNum("post-cr", def.longv("def-acs", w));
                post.setNum("post-dr", inputAccount);
                post.set("post-vat-side", "DR");
                wsDefault = wsDefault.subtract(gross);
                wsVat = wsVat.subtract(vatAmount());
                nl.add("nl-dr", amount());
                if (inputAccount == def.longv("def-acs", w)) wsDefault = wsDefault.add(amount());
            }
            if (!noVat && inputAccount == def.longv("def-acs", y)) wsVat = wsVat.add(amount());
            // input-end
            headingScreen();
            irsub1(7);
            netDisplay = Num.edit(revFlag == 1 ? amount().negate() : amount(), AMT);
            vatDisplay = Num.edit(revFlag == 1 ? vatAmount().negate() : vatAmount(), AMT);
            show(lin, 61, netDisplay);
            show(lin, 71, vatDisplay);
            post.setNum("post-key", post.longv("post-key") + 1);
            lin++;
            revFlag = 0;
            irsub4(5);
            if (lin < ws20) continue;
            for (lin = 6; lin < ws20; lin++) show(lin, 1, " ".repeat(80));
            show(6, 1, post.str("post-date"));
            show(6, 11, displayAccount);
            show(6, 18, nl.str("nl-name"));
            show(6, 43, displayLegend);
            show(6, 61, netDisplay);
            show(6, 71, vatDisplay);
            lin = 7;
        }
    }

    private void acceptMoney(int line, int col) {
        while (true) {
            show(line, col, " ".repeat(11));
            String s = accept(line, col, 11);
            justify(s);
            if (c > 1 || d > 1) display(wsLines, 1, "Amount not numeric. Re-Enter", 4);
            else { show(wsLines, 1, " ".repeat(28)); return; }
        }
    }
    private void acceptMoney2(int line, int col) {
        while (true) {
            BigDecimal abs = amtOk.abs();
            String cur = Num.z9(abs.longValue(), 7) + "." + Num.z9(abs.remainder(BigDecimal.ONE).movePointRight(2).longValue(), 2)
                    + (amtOk.signum() < 0 ? "-" : " ");
            String s = acceptUpdate(line, col, 11, cur);
            justify(s);
            if (c > 1 || d > 1) display(wsLines, 1, "Amount not numeric. Re-Enter", 4);
            else { show(wsLines, 1, " ".repeat(28)); return; }
        }
    }
    /** justify-accept-money 段落（e は呼出し間で保持される）。 */
    private void justify(String in) {
        String s = pad(in, 11);
        amtOk = BigDecimal.ZERO; c = 0; d = 0;
        char[] n = "000000000".toCharArray();
        int b = 10;
        for (a = 11; a >= 1; a--) {
            char ch = s.charAt(a - 1);
            boolean num = ch >= '0' && ch <= '9';
            if (ch == '-' && c == 1) { c = 2; break; }
            if (ch == '.' && d == 1) { d = 2; break; }
            if (ch == '-') { c = 1; continue; }
            if (ch == '.') { d = 1; e = 10 - b; continue; }
            if (!num && b != 10) { c = 3; break; }
            if (num) { b--; if (b >= 1) n[b - 1] = ch; }
        }
        if (c < 2 && d < 2) {
            BigDecimal v = new BigDecimal(new String(n));
            if (e == 2) v = v.movePointLeft(2);
            else if (e == 1) v = v.movePointLeft(1);
            v = v.remainder(BigDecimal.valueOf(10_000_000));
            amtOk = c == 1 ? v.negate() : v;
        }
    }

    /** end-batch 〜 batch-close。 */
    private void endBatchThruBatchClose() {
        readNl(def.longv("def-acs", w));
        if (wsDefault.signum() < 0) {
            wsDefault = wsDefault.negate();
            nl.setNum("nl-cr", wsDefault); nl.setNum("nl-dr", 0);
        } else {
            nl.setNum("nl-dr", wsDefault); nl.setNum("nl-cr", 0);
        }
        irsub1(7);
        if (!def.str("def-vat", w).equals("N")) {
            readNl(def.longv("def-acs", y));
            if (wsVat.signum() > 0) { nl.setNum("nl-cr", wsVat); nl.setNum("nl-dr", 0); }
            if (wsVat.compareTo(new BigDecimal("0.01")) < 0) { nl.setNum("nl-dr", wsVat.abs()); nl.setNum("nl-cr", 0); }
            irsub1(7);
        }
        irsub4(2);
        sys.setNum("next-post", post.longv("post-key"));
        fa.fileFunction = 5;
        call("irsub2", sys, fa);
    }

    private void inputHeadings() {
        int cole = 1;
        w = 1; lin = 7;
        while (true) {
            show(lin, cole, Num.z9(w, 2), 2);
            long acs = def.longv("def-acs", w);
            show(lin, cole + 4, Num.z9(acs, 5), 6);
            nl.setNum("nl-owning", acs); nl.setNum("nl-sub-nominal", 0);
            if (acs != 0) { irsub1(4); show(lin, cole + 10, nl.str("nl-name").substring(0, 22), 6); }
            show(lin, cole + 33, def.str("def-codes", w), 6);
            show(lin, cole + 38, def.str("def-vat", w), 6);
            show(lin, cole + 39, "]", 2);
            w++;
            if (w > 32) break;
            if (w == 17) { cole = 41; lin = 6; }
            lin++;
        }
        w = 1; lin = 7;
    }

    private void initialiseMain() {
        eraseEos(1, 1);
        fa.fileNames = sys.str("system-files");
        irsub3(3);
        fa.accessType = 2;
        irsub1(1);
        a = 0;
        for (y = 31; y <= 32; y++) {
            readNl(def.longv("def-acs", y));
            if (fa.weError == 2) {
                eraseEol(wsLines, 1);
                display(wsLines, 1, "VAT Account/s not present, Fix it. Now hit return", 4);
                wsReply = accept(wsLines, 77, 1);
                eraseEol(wsLines, 1);
                a++;
            }
        }
        if (a > 0) {
            eraseEos(1, 1);
            eraseEos(12, 1);
            display(12, 1, "You will need to fix the VAT account problems before posting", 4);
            display(14, 1, "So hit return to get back to main menu", 4);
            wsReply = accept(14, 40, 1);
        }
    }

    private void showDefault() {
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 27, "Default Accounts Display", 7);
        show(1, 73, sys.str("run-date"), 2);
        display(3, 1, "Client -");
        show(3, 10, sys.str("client"), 6);
        display(3, 39, "Start date -");
        show(3, 52, sys.str("start-date"), 6);
        display(3, 62, "End date -");
        show(3, 73, sys.str("end-date"), 6);
        display(5, 4, "A/C Nos");
        display(5, 14, "Description");
        display(5, 33, "Code VAT   A/C Nos");
        display(5, 54, "Description");
        display(5, 73, "Code VAT");
        eraseEol(6, 1);
        display(7, 1, "01 [00000]                      [AB] [C]17 [00000]                      [DE] [F");
        inputHeadings();
        eraseEos(ws23, 1);
        display(wsLines, 1, "End of listing. Hit return for Menu.", 7);
        wsReply = accept(wsLines, 79, 1);
    }

    private void fileInit() {
        wsReply = " ";
        display(3, 1, " Make sure that you have backed up your data", 4);
        eraseEol(4, 1);
        display(4, 32, "Enter Pass-word - [****]");
        show(4, 51, "    ");
        String wsPass = accept(4, 51, 4, SECURE);
        if (!wsPass.equals(sys.str("pass-word"))) { wsReply = "Z"; return; }
        fa.accessType = 3;
        irsub4(1);
        irsub4(2);
    }

    /** net section。 */
    private void net() {
        post.setNum("vat-amount", amount().multiply(sys.num("vat")).divide(HUNDRED, 2, RoundingMode.HALF_UP));
    }
    /** gross section。 */
    private void gross() {
        BigDecimal div = sys.num("vat").add(HUNDRED).divide(HUNDRED);
        BigDecimal v = amount().subtract(amount().divide(div, 20, RoundingMode.DOWN)).setScale(2, RoundingMode.HALF_UP);
        post.setNum("vat-amount", v);
        post.setNum("post-amount", amount().subtract(vatAmount()));
    }

    /** Ledger-Postings-Add section: 販売・購買元帳からの転記ファイル（postings2irs.dat）を取り込む。 */
    private void ledgerPostingsAdd() {
        Rec ip = Layout.of(CB + "fdpost-irs.cob", "irs-posting-record").newRec();
        CobFile in = CobFile.sequential(ctx.store, ctx.irsPath("postings2irs.dat"));
        if (!in.open(CobFile.Mode.INPUT).equals("00")) {
            display(23, 1, "No Ledger posting file found. Process Aborted");
            return;
        }
        irsub3(3);
        fa.accessType = 2;
        irsub1(1);
        Rec nl31, nl32;
        readNl(def.longv("def-acs", 31));
        if (fa.weError != 0) { subErr("IRSUB1-31 returns "); return; }
        nl31 = nl.copy();
        readNl(def.longv("def-acs", 32));
        if (fa.weError != 0) { subErr("IRSUB1-32 returns "); return; }
        nl32 = nl.copy();
        display(24, 1, "Updating Nominal Ledger");
        fa.accessType = 2;
        irsub4(1);
        while (in.readNext(ip).equals("00")) {
            postRecordCnt++;
            readNl(ip.longv("irs-post-dr"));
            if (fa.weError == 2) { keyErr("Invalid key 1 = ", ip.str("irs-post-dr")); continue; }
            nl.add("nl-dr", ip.num("irs-post-amount"));
            if (ip.str("irs-post-vat-side").equals("CR")) nl.add("nl-dr", ip.num("irs-vat-amount"));
            irsub1(7);
            readNl(ip.longv("irs-post-cr"));
            if (fa.weError == 2) { keyErr("Invalid key 2 = ", ip.str("irs-post-cr")); continue; }
            nl.add("nl-cr", ip.num("irs-post-amount"));
            if (ip.str("irs-post-vat-side").equals("DR")) nl.add("nl-cr", ip.num("irs-vat-amount"));
            irsub1(7);
            post.set("post-code", ip.str("irs-post-code"));
            post.set("post-date", ip.str("irs-post-date"));
            post.setNum("post-cr", ip.longv("irs-post-cr"));
            post.setNum("post-dr", ip.longv("irs-post-dr"));
            post.setNum("post-amount", ip.num("irs-post-amount"));
            post.set("post-legend", ip.str("irs-post-legend"));
            post.setNum("vat-ac-def", ip.longv("irs-vat-ac-def"));
            post.set("post-vat-side", ip.str("irs-post-vat-side"));
            post.setNum("vat-amount", ip.num("irs-vat-amount"));
            post.setNum("post-key", sys.longv("next-post"));
            sys.setNum("next-post", sys.longv("next-post") + 1);
            irsub4(5);
            if (fa.weError != 0) {
                display(23, 1, "Error writing to Posting File");
                accept(23, 30, 1);
                break;
            }
            int vd = ip.intv("irs-vat-ac-def");
            if (vd == 0) continue;
            String side = ip.str("irs-post-vat-side");
            Rec t = vd == 31 ? nl31 : vd == 32 ? nl32 : null;
            if (t != null && side.equals("CR")) t.add("nl-cr", ip.num("irs-vat-amount"));
            else if (t != null && side.equals("DR")) t.add("nl-dr", ip.num("irs-vat-amount"));
        }
        // eoj
        nl.load(nl31.bytes()); irsub1(7);
        nl.load(nl32.bytes()); irsub1(7);
        irsub4(2);
        irsub1(2);
        fa.fileFunction = 5;
        call("irsub2", sys, fa);
        in.close();
        eraseEol(12, 1);
        show(13, 1, "Processing Complete on " + Num.z9(postRecordCnt, 5) + " records", 2);
        do {
            eraseEol(14, 1);
            display(14, 1, "Can I clear the Ledgers Posting file? [Y]");
            wsReply = up(accept(14, 40, 1));
        } while (!wsReply.equals("Y") && !wsReply.equals("N"));
        if (wsReply.equals("Y")) { in.open(CobFile.Mode.OUTPUT); in.close(); }
        eraseEol(14, 1);
        display(14, 1, "Note counts and any messages");
        wsReply = accept(14, 30, 1);
    }
    private void subErr(String msg) {
        display(23, 1, msg, 4);
        show(23, 19, String.valueOf(fa.weError), 4);
        accept(23, 40, 1);
    }
    private void keyErr(String msg, String key) {
        display(23, 1, msg, 4);
        show(23, 17, key, 4);
        accept(23, 40, 1);
    }
}
