package jp.co.acas.gl;

import jp.co.acas.core.StopRun;

/**
 * gl100.cbl: 元帳印刷の前処理（保管仕訳の整列）。
 * レガシー実測: 見出し表示直後の disk-change で SIGSEGV により異常終了し、GnuCOBOL ランタイムの終了文言を
 * 2 行目に出してキー待ちののちプロセスが終了する（整列処理・gl105 には到達しない）。この実測挙動を再現する。
 */
public class Gl100 extends GlProgram {
    static final String PROG_NAME = "gl100 (3.00.01)";

    @Override
    public void run(Object... args) {
        init();
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 31, "Ledger Print - Sort");
        display(2, 1, "end of program, please press a key to exit", 7);
        accept(2, 79, 1);
        throw new StopRun("gl100: レガシー実測どおり異常終了（SIGSEGV 相当）");
    }
}
