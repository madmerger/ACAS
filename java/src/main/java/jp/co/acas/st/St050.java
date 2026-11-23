package jp.co.acas.st;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Rec;
import jp.co.acas.sys.SystemFile;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** st050.cbl: 在庫ファイル圧縮（削除済みレコードの整理と在庫金額の再計算）。 */
public class St050 extends StProgram {
    static final String PROG_NAME = "ST050 (3.01.06)";
    private static final int L23 = 23;
    private Rec stock;
    private CobFile stockFile, tempFile;

    @Override
    public void run(Object... args) {
        term().exceptionsEnabled = true; term().escEnabled = true;
        Rec sys = SystemFile.shared(ctx);
        if (sys.intv("date-form") == 0) sys.setNum("date-form", 1);
        String convDate = St.fromUk((String) ctx.shared.getOrDefault("to-day", ""), sys.intv("date-form"));
        // aa010-Questions
        eraseEos(1, 1);
        display(1, 1, PROG_NAME);
        display(1, 28, "Stock Compression Utility");
        show(1, 71, convDate, 2);
        display(4, 10, "This process will clean up the Stock File of deleted records");
        display(6, 10, "Is this a recovery from a previous run of this process - [ ] (N/Y)");
        String recovery;
        while (true) {
            recovery = upper(acceptUpdate(6, 68, 1, "N"));
            if (recovery.equals("N") || recovery.equals("Y")) break;
            display(L23, 1, "ST502 Y or N only", 4);
        }
        while (true) {
            display(8, 10, "Confirm you wish this to happen & that you have a backup [ ] (N/Y)");
            String reply = upper(acceptUpdate(8, 68, 1, "N"));
            if (reply.equals("N")) return;
            if (reply.equals("Y")) break;
            display(L23, 1, "ST502 Y or N only", 4);
        }
        eraseEol(L23, 1);
        stock = St.fdRec(Layout.of("copybooks/fdstock.cob", "Stock-Record"));
        stockFile = St.stockFile(ctx, stock);
        tempFile = CobFile.sequential(ctx.store, ctx.path("tmp-stock.dat"));
        if (recovery.equals("Y")) {
            eraseEol(12, 10);
            display(12, 10, "recreating Stock file from temp file as requested");
            build();
            return;
        }
        if (!stockFile.open(CobFile.Mode.INPUT).equals("00")) { fail("ST501 Stock File not found", stockFile.status, 28); return; }
        if (!tempFile.open(CobFile.Mode.OUTPUT).equals("00")) { fail("ST503 Error opening temp file", tempFile.status, 31); return; }
        eraseEol(12, 10);
        display(12, 10, "Updating your Stock file as requested");
        // ba000-Process-Stock-Comp
        while (stockFile.readNext(stock).equals("00")) {
            BigDecimal v = stock.num("stock-cost").multiply(BigDecimal.valueOf(stock.longv("stock-held")))
                    .setScale(2, RoundingMode.DOWN).remainder(BigDecimal.valueOf(1_000_000_000L));
            stock.setNum("stock-value", v);
            if (!tempFile.write(stock.copyBytes()).equals("00")) {
                fail("ST504 Error writing to temp file", tempFile.status, 34);
                stockFile.close(); tempFile.close();
                return;
            }
        }
        stockFile.close(); tempFile.close();
        build();
    }

    /** ba010-Build-Stock: 一時ファイルから在庫ファイルを再作成する。 */
    private void build() {
        if (!tempFile.open(CobFile.Mode.INPUT).equals("00")) { fail("ST503 Error opening temp file", tempFile.status, 31); return; }
        if (!stockFile.open(CobFile.Mode.OUTPUT).equals("00")) {
            fail("ST506 Error opening Stock File", stockFile.status, 32);
            tempFile.close();
            return;
        }
        Rec tmp = stock.layout.newRec();
        while (tempFile.readNext(tmp).equals("00")) {
            stock.load(tmp.copyBytes());
            if (!stockFile.write(stock).equals("00")) {
                fail("ST000 Error on Writing to Stock File", stockFile.status, 38);
                break;
            }
        }
        stockFile.close(); tempFile.close();
    }

    private void fail(String msg, String fs, int col) {
        display(L23, 1, msg, 4);
        show(L23, col, fs, 2);
        display(L23, col + 3, St.evalStatus(fs), 2);
        maps99(45);
    }
}
