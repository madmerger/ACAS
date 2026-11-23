package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;

/** irsub2.cbl: IRS システムファイル（system.dat、行順）の読み書き。 */
public class Irsub2 extends IrsBase {
    @Override
    public void run(Object... args) {
        Rec sys = (Rec) args[0]; FileAccess fa = (FileAccess) args[1];
        fa.weError = 0;
        CobFile f = CobFile.lineSequential(ctx.store, ctx.irsPath("system.dat"));
        if (fa.fileFunction == 5) {
            // do-write
            if (!f.open(CobFile.Mode.OUTPUT).equals("00")) {
                display(23, 1, "System File Open OU Failure", 4);
                displayFileError(f.status); fa.weError = 1; return;
            }
            if (!f.writeLine(new String(sys.bytes(), StandardCharsets.ISO_8859_1)).equals("00")) {
                display(23, 1, "System File Write Failure", 4);
                displayFileError(f.status); fa.weError = 1; return;
            }
            f.close();
            return;
        }
        // do-read
        if (!f.open(CobFile.Mode.INPUT).equals("00")) { fa.weError = 1; return; }
        String line = f.readLine();
        if (line == null) { fa.weError = 1; return; }
        sys.load(pad(line, sys.layout.size).getBytes(StandardCharsets.ISO_8859_1));
        fa.fileNames = sys.str("system-files");
        f.close();
    }
}
