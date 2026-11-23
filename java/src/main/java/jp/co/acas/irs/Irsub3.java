package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;

/** irsub3.cbl: 既定勘定ファイル（dflt.dat、行順編成）のファイルハンドラー。 */
public class Irsub3 extends IrsBase {
    @Override
    public void run(Object... args) {
        Rec def = (Rec) args[0]; FileAccess fa = (FileAccess) args[1];
        fa.weError = 0;
        CobFile f = CobFile.lineSequential(ctx.store, ctx.irsPath(fa.file(3)));
        if (fa.fileFunction == 5) {
            f.open(CobFile.Mode.OUTPUT);
            f.writeLine(new String(def.bytes(), StandardCharsets.ISO_8859_1));
            f.close();
            return;
        }
        if (!f.open(CobFile.Mode.INPUT).equals("00")) {
            display(23, 1, "Failure to Open Default File", 4);
            displayFileError(f.status);
            fa.weError = 1;
            return;
        }
        String line = f.readLine();
        if (line != null) def.load(pad(line, def.layout.size).getBytes(StandardCharsets.ISO_8859_1));
        f.close();
    }
}
