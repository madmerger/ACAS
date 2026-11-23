package jp.co.acas.gl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;
import jp.co.acas.core.Terminal;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;

/** gl080.cbl: 期末（サイクル末）処理。バッチ確認・仕訳の保管/削除・posting 圧縮・期間末の元帳四半期更新。 */
public class Gl080 extends GlProgram {
    static final String PROG_NAME = "gl080 (3.00.02)";
    static final String ARC_LAYOUT = """
             01  arc-trans-record.
                 03  arc-batch       pic 9(5).
                 03  arc-post        pic 9(5).
                 03  arc-code        pic xx.
                 03  arc-date        pic x(8).
                 03  arc-ac          pic 9(6).
                 03  arc-pc          pic 99.
                 03  arc-amount      pic s9(8)v99.
                 03  arc-legend      pic x(32).
                 03  arc-c-ac        pic 9(6).
                 03  arc-c-pc        pic 99.
            """;

    private Rec led, bat, post, arc; private CobFile ledger, batchFile, postingFile, archive;
    private int a, y; private String file2 = "archive.dat", lin2 = "00";

    @Override
    public void run(Object... args) {
        init();
        led = GlCommon.ledgerRec(); ledger = GlCommon.ledgerFile(ctx, led);
        bat = GlCommon.batchRec(); batchFile = GlCommon.batchFile(ctx, bat);
        bat.load(new byte[bat.bytes().length]);
        post = GlCommon.postingRec(); postingFile = GlCommon.postingFile(ctx);
        arc = Layout.ofSource(ARC_LAYOUT, "arc-trans-record").newRec();
        display(1, 1, PROG_NAME); eraseEos(1, 16);
        display(1, 30, "End Of Cycle Processing");
        show(1, 71, wsDate(), 2);
        show(3, 1, sys.str("usera"), 3);
        a = 0;
        lin2 = Num.z9(sys.intv("scycle"), 2);
        display(8, 1, "GL115 Ensure Archive USB Memory Stick is in path", 3);
        display(9, 1, "GL116 Ensure you have done a file backup prior to running!!!", 3);
        display(10, 1, "GL117 Hit Escape or press A to abort", 3);
        String k = pad(acceptUpdate(10, 65, 1, " ", Terminal.AUTO), 1);
        if (esc() || k.equals("A") || k.equals("a")) return;
        display(8, 1, "Phase - 1.  Batch Check"); eraseEos(8, 24);
        gl080a();
        if (a == 1) return;
        if (sys.str("arch").equals("Y")) {
            display(8, 1, "Phase - 2.  Transaction Archiving");
            gl080b();
        } else {
            display(8, 1, "Phase - 3.  Transaction Deletion");
            gl080c();
        }
        compressPost();
        int scycle = sys.intv("scycle"), period = sys.intv("period");
        if (a == 9 || scycle < period) return;
        if (period != 0) a = BigDecimal.valueOf(scycle).divide(BigDecimal.valueOf(period), 0, RoundingMode.HALF_UP).intValue() % 100;
        y = a * period % 100;
        if (scycle != y) return;
        sys.setNum("scycle", scycle + 1);
        display(8, 1, "Phase - 5.  End of Period Processing");
        ledger.open(CobFile.Mode.IO);
        while (ledger.readNext(led).equals("00")) {
            if (a >= 1 && a <= 4) led.setNum("ledger-q", led.num("ledger-balance"), a);
            if (sys.intv("current-quarter") == 4) led.setNum("ledger-last", led.num("ledger-balance"));
            ledger.rewrite(led);
        }
        ledger.close();
        int q = (sys.intv("current-quarter") + 1) % 10;
        sys.setNum("current-quarter", q == 5 ? 1 : q);
        if (period == 3 && sys.intv("scycle") > 12) sys.setNum("scycle", 1);
        if (period == 13 && sys.intv("scycle") > 52) sys.setNum("scycle", 1);
    }

    private boolean nextBatch() {
        String st = batchFile.readNext(bat);
        if (st.equals("10")) return false;
        if (!st.equals("00")) runaway();
        return true;
    }

    private void gl080a() {
        display(23, 1, "Checking Batches");
        batchFile.open(CobFile.Mode.INPUT);
        while (nextBatch()) {
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            if (bat.intv("batch-status") != 1 && bat.intv("cleared-status") != 1) a = 1;
        }
        batchFile.close();
    }

    private void progressHeader(String text) {
        display(23, 1, text);
        show(23, 30, lin2, 2);
        display(23, 34, "/ Batch - ");
        display(23, 52, "/ Item  - ");
    }

    private void closeBatch() {
        postingFile.close();
        bat.setNum("cleared-status", 2);
        bat.setNum("stored", sys.num("run-date"));
        bat.setNum("batch-start", 0);
        batchFile.rewrite(bat);
    }

    private void gl080b() {
        progressHeader("Archiving.      Cycle - ");
        diskChange();
        if (a == 9) return;
        archive = CobFile.lineSequential(ctx.store, ctx.path(file2.trim()));
        if (!archive.open(CobFile.Mode.EXTEND).equals("00")) { archive.close(); archive.open(CobFile.Mode.OUTPUT); }
        batchFile.open(CobFile.Mode.IO);
        while (nextBatch()) {
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            process(true);
            closeBatch();
        }
        batchFile.close(); archive.close();
    }

    private void gl080c() {
        progressHeader("Deleting.       Cycle - ");
        batchFile.open(CobFile.Mode.IO);
        while (nextBatch()) {
            if (bat.intv("bcycle") != sys.intv("scycle")) continue;
            process(false);
            closeBatch();
        }
        batchFile.close();
    }

    private void writeArc(long ac, int pc, long cac, int cpc, BigDecimal amount) {
        arc.setNum("arc-ac", ac); arc.setNum("arc-pc", pc);
        arc.setNum("arc-c-ac", cac); arc.setNum("arc-c-pc", cpc);
        arc.setNum("arc-amount", amount);
        archive.writeLine(latin(arc.bytes()));
    }

    /** arc-process / del-process: 当該バッチの仕訳を（保管して）削除する。 */
    private void process(boolean archiving) {
        show(23, 45, bat.str("batch-nos"), 2);
        arc.setNum("arc-batch", bat.intv("batch-nos"));
        if (!postingFile.open(CobFile.Mode.IO).equals("00")) return;
        int total = postingFile.count();
        for (long rrn = 1, seen = 0; seen < total; rrn++) {
            postingFile.rrn = rrn;
            if (!postingFile.read(post).equals("00")) continue;
            seen++;
            if ((post.intv("batch") == 0 && post.intv("post-number") == 0) || post.intv("batch") != bat.intv("batch-nos")) continue;
            show(23, 64, post.str("post-number"), 2);
            if (archiving) {
                arc.setNum("arc-batch", post.intv("batch"));
                arc.setNum("arc-post", post.intv("post-number"));
                arc.set("arc-code", post.str("post-code"));
                arc.set("arc-date", post.str("post-date"));
                arc.set("arc-legend", post.str("post-legend"));
                String side = post.str("post-vat-side");
                BigDecimal amt = post.num("post-amount"), vat = post.num("vat-amount");
                long dr = post.intv("post-dr"), cr = post.intv("post-cr"); int drPc = post.intv("dr-pc"), crPc = post.intv("cr-pc");
                writeArc(dr, drPc, cr, crPc, side.equals("CR") ? amt.add(vat) : amt);
                writeArc(cr, crPc, dr, drPc, (side.equals("DR") ? amt.add(vat) : amt).negate());
                if (post.intv("vat-ac") != 0 && vat.signum() != 0)
                    writeArc(post.intv("vat-ac"), post.intv("vat-pc"), dr, drPc, side.equals("CR") ? vat.negate() : vat);
            }
            postingFile.delete(post);
        }
    }

    private void diskChange() {
        file2 = "archives" + osDelimiter(23) + file2.trim();
        display(12, 1, "GL115 Ensure Archive USB Memory Stick is in path"); eraseEol(12, 49);
        display(13, 1, "GL114 Enter <0> to signify change made or <9> to abort this run :- [ ]"); eraseEol(13, 71);
        while (true) {
            a = (int) acceptNum(13, 69, 2);
            if (a == 9) return;
            if (a != 0) continue;
            display(14, 1, "Current path/name is :"); eraseEol(14, 23);
            show(15, 1, pad(file2, 80), 2);
            file2 = acceptUpdate(15, 1, 80, pad(file2, 80));
            if (file2.isEmpty() || file2.charAt(0) == ' ') continue;
            return;
        }
    }

    /** compress-post: posting-file を作業ファイル経由で詰め直す（相対番号を 1 から振り直す）。 */
    private void compressPost() {
        display(8, 1, "Phase - 4.  Posting Contraction ");
        List<byte[]> recs = new ArrayList<>();
        if (postingFile.open(CobFile.Mode.INPUT).equals("00")) {
            while (postingFile.readNext(post).equals("00")) recs.add(post.bytes().clone());
        }
        postingFile.close();
        postingFile.open(CobFile.Mode.OUTPUT);
        for (byte[] r : recs) { postingFile.rrn = 0; postingFile.write(r); }
        postingFile.close();
    }
}
