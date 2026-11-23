package jp.co.acas.gl;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import jp.co.acas.core.CobFile;

/**
 * gl100.cbl: 元帳印刷の前処理（保管仕訳 archive.dat を勘定・P/C・バッチ・仕訳番号順に整列して workarc.tmp へ出力）。
 * レガシーでは disk-change 冒頭の STRING が NULL の LINKAGE 項目 file-defs-os-delimiter を参照するため、
 * general から呼ばれるとデータ内容に関係なくここで異常終了する（{@link GlProgram#osDelimiter}）。
 */
public class Gl100 extends GlProgram {
    static final String PROG_NAME = "gl100 (3.00.01)";
    private String file2 = "archive.dat", arcOutName = "workarc.tmp";
    private int a;

    @Override
    public void run(Object... args) {
        init();
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 31, "Ledger Print - Sort");
        diskChange();
        if (a == 9) { GlCommon.termCode(ctx, 5); return; }
        CobFile archive = CobFile.lineSequential(ctx.store, ctx.path(file2.trim()));
        if (!archive.open(CobFile.Mode.INPUT).equals("00")) { GlCommon.termCode(ctx, 4); return; }
        archive.close();
        // SORT ... ASCENDING srt-ac(21-26) srt-pc(27-28) srt-batch(1-5) srt-post(6-10) USING archive GIVING arch-out
        List<String> recs = new ArrayList<>();
        archive.open(CobFile.Mode.INPUT);
        for (String l = archive.readLine(); l != null; l = archive.readLine()) recs.add(pad(l, 78));
        archive.close();
        recs.sort(Comparator.comparing((String r) -> r.substring(20, 28) + r.substring(0, 10)));
        CobFile out = CobFile.lineSequential(ctx.store, ctx.path(arcOutName.trim()));
        out.open(CobFile.Mode.OUTPUT);
        for (String r : recs) out.writeLine(r);
        out.close();
    }

    private void diskChange() {
        // file-24 は空白のため STRING の結果は "archives" + 区切り + ファイル名
        file2 = "archives" + osDelimiter(1) + file2.trim();
        arcOutName = "archives" + osDelimiter(1) + arcOutName.trim();
        display(12, 1, "GL115 Ensure Archive USB Memory Stick is in path"); eraseEol(12, 49);
        display(13, 1, "GL114 Enter <0> to signify change made or <9> to abort this run :- [ ]"); eraseEol(13, 71);
        while (true) {
            a = (int) acceptNum(13, 69, 1);
            if (a == 9) return;
            if (a != 0) continue;
            display(14, 1, "Current path/name is :"); eraseEol(14, 23);
            show(15, 1, pad(file2, 80), 2);
            file2 = acceptUpdate(15, 1, 80, pad(file2, 80));
            if (file2.isEmpty() || file2.charAt(0) == ' ') continue;
            return;
        }
    }
}
