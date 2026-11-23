package jp.co.acas.st;

import jp.co.acas.core.Num;
import jp.co.acas.core.Program;

/** 在庫管理プログラム共通の補助（maps99 エラー表示）。 */
abstract class StProgram extends Program {
    /**
     * maps99: エラーメッセージ表示。共通実装（call("maps99")）があればそれを使い、
     * 無ければ error.txt 未登録時のレガシー動作（番号表示して応答待ち）を行う。
     */
    protected void maps99(int code) {
        if (call("maps99", code)) return;
        ctx.shared.put("ws-term-code", 0);
        show(23, 1, "T-" + Num.z9(code, 3) + " ", 4);
        display(23, 7, "Error not in error.txt. Hit return to close", 4);
        show(23, 50, "       ", 4);
        accept(24, 79, 1);
    }
}
