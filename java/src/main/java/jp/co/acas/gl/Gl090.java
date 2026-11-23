package jp.co.acas.gl;

/** gl090.cbl: 試算表メニュー（1: 明細試算表 gl090b、2: P/C・拠点別試算表 gl090a）。 */
public class Gl090 extends GlProgram {
    static final String PROG_NAME = "gl090 (3.00.03)";

    @Override
    public void run(Object... args) {
        init();
        while (true) {
            display(1, 1, PROG_NAME); eraseEos(1, 16);
            display(1, 35, "Trial Balance");
            show(1, 71, wsDate(), 2);
            show(3, 1, sys.str("usera"), 3);
            display(8, 1, "Select Option By Number :- [ ]");
            display(10, 1, "(1)  Detailed Trial Balance");
            if (profitCentres()) display(12, 1, "(2)  Profit Centre Trial Balance");
            else if (branches()) display(12, 1, "(2)  Branch Trial Balance");
            display(17, 1, "(9)  Exit to system menu");
            int reply = (int) acceptNum(8, 29, 1, 9);
            if (reply == 1) call("gl090b");
            if (reply == 2) call("gl090a");
            if (reply == 9) return;
        }
    }
}
