package jp.co.acas.core;

/**
 * レガシー COBOL プログラム 1 本に対応する基底クラス。
 * 画面入出力は COBOL の DISPLAY/ACCEPT AT と同じ座標（行 1-24, 桁 1-80）で記述する。
 * 色番号は COBOL と同じ（2=緑, 3=水色, 4=赤, 6=黄, 7=白）。
 */
public abstract class Program {
    protected Ctx ctx;
    public static final int AUTO = Terminal.AUTO, SECURE = Terminal.SECURE, UPPER = Terminal.UPPER, NUMERIC = Terminal.NUMERIC;

    /** 手続き部。args は CALL ... USING の引数。GOBACK は return、STOP RUN は stopRun()。 */
    public abstract void run(Object... args);

    protected Terminal term() { return ctx.term; }
    /** DISPLAY 固定文言 AT line/col（日本語面は対応表で変換される）。 */
    protected void display(int line, int col, String text) { ctx.term.display(line, col, text, 2); }
    protected void display(int line, int col, String text, int fg) { ctx.term.display(line, col, text, fg); }
    /** DISPLAY データ項目（変換なし）。 */
    protected void show(int line, int col, String data) { ctx.term.displayData(line, col, data, 3); }
    protected void show(int line, int col, String data, int fg) { ctx.term.displayData(line, col, data, fg); }
    /** DISPLAY ... WITH ERASE EOS。 */
    protected void eraseEos(int line, int col) { ctx.term.eraseEos(line, col); }
    protected void eraseEol(int line, int col) { ctx.term.eraseEol(line, col); }
    protected void clearScreen() { ctx.term.eraseEos(1, 1); }
    /** ACCEPT（UPDATE なし）。 */
    protected String accept(int line, int col, int size) { return ctx.term.accept(line, col, size, null, 0, 3); }
    protected String accept(int line, int col, int size, int flags) { return ctx.term.accept(line, col, size, null, flags, 3); }
    /** ACCEPT ... WITH UPDATE。 */
    protected String acceptUpdate(int line, int col, int size, String current) { return ctx.term.accept(line, col, size, current, 0, 3); }
    protected String acceptUpdate(int line, int col, int size, String current, int flags) { return ctx.term.accept(line, col, size, current, flags, 3); }
    protected int crtStatus() { return ctx.term.crtStatus; }
    /** CALL。未実装プログラムは false。 */
    protected boolean call(String name, Object... args) { return ctx.call(name, args); }
    protected void stopRun() { throw new StopRun(); }
    protected static String upper(String s) { return s.toUpperCase(java.util.Locale.ROOT); }
}
