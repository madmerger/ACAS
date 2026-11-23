package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Num;
import jp.co.acas.core.Rec;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.TreeMap;

/** irs090.cbl: 月次分析表（Monthly Analysis Report、132 桁帳票）。irs085 の workpost.tmp を勘定・月別に集計する。 */
public class Irs090 extends IrsBase {
    static final String PROG_NAME = "irs090 (3.01.10)";
    private static final String[] MLITS = {" JAN ", " FEB ", "MARCH", "APRIL", " MAY ", " JUNE", "JULY ", " AUG ", "SEPT ", " OCT ", " NOV ", " DEC "};
    private Rec sys, nl, work;
    private CobFile prt, nlFile;
    private int srReply, pageNo, lineCnt;
    private long savedAccount, years;
    private final BigDecimal[] mths = new BigDecimal[13];
    private final TreeMap<Long, String> work2 = new TreeMap<>();
    private static final class Abort extends RuntimeException { }

    @Override
    public void run(Object... args) {
        sys = (Rec) args[0];
        nl = newNlRecord(); work = Irs085.newOutputRecord();
        FileAccess fa = fa();
        fa.fileNames = sys.str("system-files");
        for (int b = 1; b <= 12; b++) mths[b] = BigDecimal.ZERO;
        clearScreen();
        show(1, 1, PROG_NAME, 2);
        display(1, 30, "Monthly Analysis Report", 7);
        show(1, 73, sys.str("run-date"), 2);
        display(6, 23, "You will need 132 column wide paper", 3);
        display(12, 1, "Which Month does your Tax Year start (01-12)  [  ]");
        do { srReply = (int) Num.parse(acceptUpdate(12, 48, 2, "00")).longValue(); } while (srReply < 1 || srReply > 12);
        CobFile wf = CobFile.sequential(ctx.store, ctx.irsPath("workpost.tmp"));
        boolean wfOpen = wf.open(CobFile.Mode.INPUT).equals("00");
        nlFile = CobFile.indexed(ctx.store, ctx.irsPath(fa.file(1)), 0, 10);
        nlFile.open(CobFile.Mode.INPUT);
        prt = openPrint();
        headings();
        // lc-process
        try {
            while (true) {
                if (!wfOpen || !wf.read(work).equals("00")) {
                    if (!printLine()) break;
                    getNominal();   // レガシーの perform lze-print-line thru lzf-exit は勘定読込みまで実行する
                    break;
                }
                long account = work.longv("output-account");
                if (savedAccount == 0) { getNominal(); savedAccount = account; }
                if (savedAccount != account) {
                    if (!printLine()) break;
                    getNominal();
                    savedAccount = account;
                }
                int mm = work.intv("output-date");
                if (mm < 1 || mm > 12) mm = 1;
                mths[mm] = mths[mm].add(work.num("output-amount"));
            }
        } catch (Abort a) {
            prt.close();
            stopRun();
        }
        // ld-output-final
        nlFile.close();
        nlFile.open(CobFile.Mode.INPUT);
        while (nlFile.readNext(nl).equals("00")) {
            if (nl.str("nl-type").equals("S")) continue;
            long no = nl.longv("nl-sub-nominal") != 0 ? nl.longv("nl-sub-nominal") : nl.longv("nl-owning");
            String group = work2.get(no);
            if (group == null) continue;
            if (lineCnt > 60) headings();
            writeAfter(prt, Num.edit(BigDecimal.valueOf(no), "z(4)9") + " " + group, 1);
            lineCnt = (lineCnt + 1) % 100;
        }
        // le-close
        writeAfter(prt, "Note that above values are subject to rounding", 3);
        if (wfOpen) wf.close();
        nlFile.close();
        printReport(sys, prt, "orientation-requested=4 page-left=18 page-top=48 page-right=10");
        for (String n : new String[] {"work2.tmp", "workpost.tmp"}) {
            CobFile f = CobFile.sequential(ctx.store, ctx.irsPath(n));
            f.open(CobFile.Mode.OUTPUT);
            f.close();
        }
    }

    private void headings() {
        pageNo = (pageNo + 1) % 100;
        writeAfter(prt, pad(sys.str("client"), 32) + " ".repeat(23) + pad("Monthly Analysis Report", 25) + " ".repeat(28) + pad(sys.str("run-date"), 8)
                + " ".repeat(8) + "Page " + Num.edit(BigDecimal.valueOf(pageNo), "zz9"), 1);
        writeAfter(prt, pad("<----------Account--------->", 29) + "<" + "-".repeat(46) + "Year" + "-".repeat(43) + ">", 2);
        StringBuilder l3 = new StringBuilder(pad("  No Typ      Name", 28));
        for (int a = 1, b = srReply; a <= 12; a++, b = b == 12 ? 1 : b + 1) l3.append("   ").append(MLITS[b - 1]);
        writeAfter(prt, l3 + pad("  Total", 9), 1);
        writeAfter(prt, "", 1);
        lineCnt = 5;
    }

    /** lze-print-line: 月別集計を work2 へ書く。キー重複（FF）の場合は false（lc-process を抜ける）。 */
    private boolean printLine() {
        StringBuilder months = new StringBuilder();
        for (int a = 1, b = srReply; a <= 12; a++, b = b == 12 ? 1 : b + 1) {
            long z = mths[b].setScale(0, RoundingMode.DOWN).longValue();
            years += z;
            months.append(Num.edit(BigDecimal.valueOf(z), "-(7)9"));
        }
        long no; String type;
        if (nl.longv("nl-sub-nominal") == 0) { no = nl.longv("nl-owning"); type = "M"; } else { no = nl.longv("nl-sub-nominal"); type = "S"; }
        String group = type + " " + pad(nl.str("nl-name"), 20) + months + Num.edit(BigDecimal.valueOf(years), "-(7)9");
        years = 0;
        for (int b = 1; b <= 12; b++) mths[b] = BigDecimal.ZERO;
        if (work2.containsKey(no)) {
            display(16, 1, "090-01 Reply - ");
            show(16, 16, "FF");
            display(16, 25, "NOTE ERROR & Hit Return");
            accept(17, 40, 2);
            return false;
        }
        work2.put(no, group);
        return true;
    }

    /** lzf-get-nominal: 勘定を索引読み（補助勘定ポインタは辿る）。無ければ中断。 */
    private void getNominal() {
        nl.setNum("nl-owning", work.longv("output-account"));
        nl.setNum("nl-sub-nominal", 0);
        while (true) {
            if (!nlFile.read(nl).equals("00")) {
                show(14, 1, Num.z9(nl.longv("nl-owning"), 5));
                display(14, 7, "Does not exist..Aborting");
                display(14, 34, "Note error & Hit return to continue");
                accept(14, 71, 2);
                throw new Abort();
            }
            if (!nl.str("nl-type").equals("S")) return;
            long owning = nl.longv("nl-owning");
            nl.setNum("nl-sub-nominal", owning);
            nl.setNum("nl-owning", nl.longv("nl-pointer"));
        }
    }
}
