package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;

/** irsub5.cbl: 決算書見出しファイル（final.dat、行順編成）のファイルハンドラー。 */
public class Irsub5 extends IrsBase {
    @Override
    public void run(Object... args) {
        Rec fin = (Rec) args[0]; FileAccess fa = (FileAccess) args[1];
        fa.weError = 0;
        CobFile f = CobFile.lineSequential(ctx.store, ctx.irsPath("final.dat"));
        if (fa.fileFunction == 5) {
            if (!f.open(CobFile.Mode.OUTPUT).equals("00")) {
                display(23, 1, "Failure to open O/P Final File", 4);
                displayFileError(f.status);
                fa.weError = f.status.charAt(0) - '0';
                return;
            }
            f.writeLine(new String(fin.bytes(), StandardCharsets.ISO_8859_1));
            f.close();
            return;
        }
        if (!f.open(CobFile.Mode.INPUT).equals("00")) {
            f.close();
            f.open(CobFile.Mode.OUTPUT);
            fin.initialize();
            f.writeLine(new String(fin.bytes(), StandardCharsets.ISO_8859_1));
            f.close();
            return;
        }
        String line = f.readLine();
        if (line == null) {
            display(23, 1, "Failure to read Final File rec. !", 4);
            displayFileError("10");
            fa.weError = 1;
        } else fin.load(pad(line, fin.layout.size).getBytes(StandardCharsets.ISO_8859_1));
        f.close();
    }
}
