package jp.co.acas.sl;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Rec;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** sl165.cbl: 顧客を名称順に整列し、顧客コードの一覧 custsort.tmp を作る。 */
public class Sl165 extends SlProgram {
    static final String PROG_NAME = "SL165 (3.01.01)";
    static final String F_CUSTSORT = "custsort.tmp";

    @Override
    public void run(Object... args) {
        Rec sales = salesRec();
        CobFile salesFile = salesFile(sales), sort = CobFile.sequential(ctx.store, ctx.path(F_CUSTSORT));
        salesFile.open(CobFile.Mode.INPUT);
        sort.open(CobFile.Mode.OUTPUT);
        List<String[]> items = new ArrayList<>();
        while (salesFile.readNext(sales).equals("00")) items.add(new String[] {pad(sales.str("sales-key"), 7), pad(sales.str("sales-name"), 30)});
        items.sort(Comparator.comparing(a -> a[1]));
        for (String[] i : items) sort.write(i[0].getBytes(StandardCharsets.ISO_8859_1));
        salesFile.close(); sort.close();
    }
}
