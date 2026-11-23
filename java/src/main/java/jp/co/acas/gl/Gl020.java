package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;

/** gl020.cbl: 既定勘定（Default Accounts）の登録・修正・照会。 */
public class Gl020 extends GlProgram {
    static final String PROG_NAME = "GL020 (3.00.02)";

    private Rec dflt, led; private CobFile ledger;
    private int w, lin, cole;
    private String wsReply = " ";

    @Override
    public void run(Object... args) {
        init();
        dflt = GlCommon.dflt(ctx);
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        while (true) {
            display(1, 1, PROG_NAME); eraseEos(1, 16);
            display(1, 29, "Default File Utilities");
            show(1, 71, wsDate(), 2);
            show(3, 1, sys.str("usera"), 2);
            if (ledger.isOpen()) ledger.close();
            if (!ledger.open(CobFile.Mode.INPUT).equals("00")) {
                display(23, 1, "GL100 Chart of Accounts not set up", 4);
                display(24, 1, "GL010 Hit Return");
                accept(24, 20, 1);
                return;
            }
            display(5, 1, "Select the required function by number    [ ]");
            display(8, 6, "(1)  Set-Up Default Accounts");
            display(10, 6, "(2)  Amend  Default Accounts");
            display(12, 6, "(3)  Display The Defaults");
            display(20, 6, "(9)  Return To System Menu");
            int menu = (int) digits(acceptUpdate(5, 44, 1, "0", AUTO), 1);
            if (menu == 1) setUp();
            if (menu == 2) amend();
            if (menu == 3) showDefaults();
            if (menu == 9) return;
        }
    }

    private long acs(int i) { return dflt.num("def-acs", i).movePointRight(2).longValue(); }
    private void setAcs(int i, long v) { dflt.setNum("def-acs", BigDecimal.valueOf(v, 2), i); }
    private static String acsEdit(long v) { return Num.z9(v / 100, 4) + "." + Num.z9(v % 100, 2); }

    /** accept-money: 9(4).99 の画面項目を UPDATE 付きで受ける。 */
    private long acceptMoney(int line, int col, long cur) {
        String s = pad(acceptUpdate(line, col, 7, acsEdit(cur)), 7);
        return digits(s.substring(0, 4), 4) * 100 + digits(s.substring(5, 7), 2);
    }

    private void setUp() {
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        show(1, 71, wsDate(), 2);
        display(1, 29, "Default Accounts Set-Up");
        show(3, 1, sys.str("usera"), 2);
        while (true) {
            display(5, 1, "Add To Existing Defaults (Y/N) ? - [ ]");
            display(7, 1, "N.B. (1) If first time set-up for this client answer no (N)");
            display(8, 6, "(2) Answering no (N)");
            display(8, 27, "destroys", 4);
            display(8, 36, "the existing defaults");
            wsReply = upper(pad(accept(5, 37, 1), 1));
            if (wsReply.equals("N")) fileInit();
            if (wsReply.equals("Y") || wsReply.equals("N")) break;
        }
        for (int l = 5; l <= 8; l++) eraseEol(l, 1);
        inputHeadings();
        boolean autoVat = sys.str("vat").equals("Y");
        input:
        while (true) {
            show(lin, cole, Num.z9(w, 2), 2);
            setAcs(w, acceptMoney(lin, cole + 3, acs(w)));
            if (esc() && w < 30) { jump(30); continue; }
            if (esc()) { if (w < 31 && autoVat) { jump(31); continue; } break; }
            if (acs(w) == 0 && w < 30) { jump(30); continue; }
            if (acs(w) == 0 && autoVat) { jump(31); continue; }
            getDescription();
            if (weError == 255) continue;
            show(lin, cole + 12, led.str("ledger-name"));
            display(lin, cole + 32, "[  ] ");
            String codes = dflt.str("def-codes", w);
            show(lin, cole + 33, codes);
            if (w < 30) codes = upper(pad(acceptUpdate(lin, cole + 33, 2, codes), 2));
            else codes = w == 30 ? "OB" : w == 31 ? "VI" : "VO";
            show(lin, cole + 33, codes, 2);
            if (esc()) {
                if (w < 30) { jump(30); continue; }
                if (autoVat && w < 31) { jump(31); continue; }
                break;
            }
            dflt.set("def-codes", codes, w);
            while (true) {
                String vat = dflt.str("def-vat", w);
                show(lin, cole + 38, vat);
                if (w < 30) vat = upper(pad(acceptUpdate(lin, cole + 38, 1, vat), 1));
                else { vat = "N"; show(lin, cole + 38, vat); }
                if (esc()) {
                    if (autoVat && w < 31) { jump(31); continue input; }
                    break input;
                }
                dflt.set("def-vat", vat, w);
                if (vat.equals("I") || vat.equals("N") || vat.equals("O")) break;
            }
            w++;
            if (w > 32) break;
            if (w == 17) { cole = 41; lin = 6; }
            lin++;
        }
        amend();
    }
    private void jump(int to) { cole = 41; w = to; lin = to - 10; }

    private void amend() {
        eraseEos(1, 1);
        display(1, 1, PROG_NAME);
        display(1, 27, "Default Accounts Amendment");
        show(1, 71, toDay(), 2);
        show(3, 1, sys.str("usera"), 2);
        inputHeadings();
        while (true) {
            display(24, 1, "Enter Number To Alter (Return to exit)  :- [  ]");
            int y = (int) acceptNum(24, 45, 2, 0);
            if (y == 0) break;
            if (y < 1 || y > 32) continue;
            w = y;
            if (y > 16) { y -= 16; cole = 41; } else cole = 1;
            lin = y + 6;
            show(lin, cole, Num.z9(w, 2), 2);
            setAcs(w, acceptMoney(lin, cole + 3, acs(w)));
            getDescription();
            if (weError == 255) continue;
            show(lin, cole + 12, led.str("ledger-name"));
            display(lin, cole + 32, "[  ] ");
            String codes = pad(acceptUpdate(lin, cole + 33, 2, dflt.str("def-codes", w)), 2);
            dflt.set("def-codes", codes, w);
            show(lin, cole + 33, codes);
            String vat;
            do {
                vat = pad(acceptUpdate(lin, cole + 38, 1, dflt.str("def-vat", w)), 1);
            } while (!(vat.equals("I") || vat.equals("N") || vat.equals("O")));
            dflt.set("def-vat", vat, w);
        }
        ledger.close();
    }

    private void showDefaults() {
        eraseEos(1, 1);
        display(1, 1, PROG_NAME);
        display(1, 26, "default accounts display");
        show(1, 71, toDay(), 2);
        show(3, 1, sys.str("usera"), 2);
        inputHeadings();
        display(23, 1, "End of listing. Hit return for Menu.");
        wsReply = pad(accept(23, 79, 1), 1);
        ledger.close();
    }

    /** file-init: パスワード照合後に default-record を初期化する。 */
    private void fileInit() {
        display(5, 51, "Enter Password  - [    ]");
        String pw = pad(accept(5, 70, 4), 4);
        display(5, 70, "****");
        if (!jp.co.acas.sys.Maps01.password(ctx, pw).equals(sys.str("pass-word"))) { wsReply = "Z"; return; }
        dflt.initialize();
    }

    private void inputHeadings() {
        display(5, 4, "A/C Nos"); display(5, 33, "Code Vat");
        display(5, 44, "A/C Nos"); display(5, 73, "Code Vat");
        lin = 7; cole = 1;
        for (w = 1; w <= 32; w++) {
            if (w == 17) { lin = 7; cole = 41; }
            show(lin, cole, Num.z9(w, 2), 2);
            display(lin, cole + 2, "[       ]");
            display(lin, cole + 32, "[  ] [ ]");
            lin++;
        }
        lin = 7; cole = 1;
        for (w = 1; w <= 32; w++) {
            if (w == 17) { lin = 7; cole = 41; }
            show(lin, cole + 3, acsEdit(acs(w)));
            if (acs(w) != 0) {
                getDescription();
                if (weError != 255) {
                    show(lin, cole + 12, led.str("ledger-name"));
                    display(lin, cole + 32, "[  ] ");
                }
            }
            show(lin, cole + 33, dflt.str("def-codes", w));
            show(lin, cole + 38, dflt.str("def-vat", w));
            lin++;
        }
        w = 1; cole = 1; lin = 7;
    }

    private void getDescription() {
        led.setNum("ledger-nos", acs(w));
        led.setNum("ledger-pc", 0);
        weError = ledger.read(led).equals("00") ? 0 : 255;
    }
}
