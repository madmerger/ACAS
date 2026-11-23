package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Ctx;

/**
 * 印刷ファイル（LINE SEQUENTIAL の WRITE ... BEFORE / AFTER ADVANCING）の行送りを再現する。
 * AFTER n は n 回改行してから印字、BEFORE n は印字してから n 回改行、PAGE は改ページ（FF）。
 */
final class Prt {
    private final CobFile file;
    private final StringBuilder buf = new StringBuilder();
    private boolean open;
    /** 可変長レコード順ファイル（FD に長さの異なる 01 が複数ある印刷ファイル）のレコード見出し。レガシーの出力バイトに合わせる。 */
    private String prefix = "";

    /** レコード長 len の可変長レコード見出し（2 バイト長 + 2 バイト 0）を各印字行の先頭に付ける。 */
    Prt variable(int len) { prefix = "" + (char) (len >> 8) + (char) (len & 0xff) + "\0\0"; return this; }

    Prt(Ctx ctx, String name) { file = CobFile.lineSequential(ctx.store, ctx.path(name)); }

    void openOutput() { file.open(CobFile.Mode.OUTPUT); buf.setLength(0); open = true; }
    boolean isOpen() { return open; }
    void after(String line, int n) { buf.append("\n".repeat(n)).append(prefix).append(line.stripTrailing()); }
    void afterPage(String line) { buf.append('\f').append(prefix).append(line.stripTrailing()); }
    void before(String line, int n) { buf.append(prefix).append(line.stripTrailing()).append("\n".repeat(n)); }
    void beforePage(String line) { buf.append(prefix).append(line.stripTrailing()).append('\f'); }
    /** ADVANCING 指定なしの WRITE（行順ファイルの既定: 印字して改行）。 */
    void write(String line) { before(line, 1); }
    void close() {
        if (!open) return;
        open = false;
        String s = buf.toString();
        if (s.endsWith("\n")) s = s.substring(0, s.length() - 1);
        if (!s.isEmpty() || buf.length() > 0) for (String l : s.split("\n", -1)) file.writeLine(l);
        file.close();
    }
}
