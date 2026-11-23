package jp.co.acas.irs;

import jp.co.acas.core.CobFile;
import jp.co.acas.core.Layout;
import jp.co.acas.core.Program;
import jp.co.acas.core.Rec;

import java.util.Locale;

/** IRS 各プログラム共通の作業領域定義と補助処理（COPY 句・共通段落相当）。 */
public abstract class IrsBase extends Program {
    static final String CB = "incomplete_records_system/";

    /** copy "wsfnctn.cob" (file-access)。 */
    public static final class FileAccess {
        public int fileFunction, accessType, weError;
        public String fileNames = "";
        public String file(int n) {
            int[] off = {0, 9, 19, 27, 35, 47}; int[] len = {9, 10, 8, 8, 12, 1};
            String s = (fileNames + " ".repeat(49)).substring(0, 49);
            return s.substring(off[n - 1], off[n - 1] + len[n - 1]).trim();
        }
    }

    public static Rec newSystemRecord() { return Layout.of(CB + "wssystem.cob", "system-record").newRec(); }
    public static Rec newNlRecord() { return Layout.of(CB + "wsnl.cob", "nl-record").newRec(); }
    public static Rec newDefaultRecord() { return Layout.of(CB + "wsdflt.cob", "default-record").newRec(); }
    public static Rec newPostingRecord() { return Layout.of(CB + "wspost.cob", "posting-record").newRec(); }
    public static Rec newFinalRecord() { return Layout.of(CB + "wsfinal.cob", "final-record").newRec(); }

    protected FileAccess fa() {
        return (FileAccess) ctx.shared.computeIfAbsent("irs.file-access", k -> new FileAccess());
    }
    protected CobFile sharedFile(String key) { return (CobFile) ctx.shared.get(key); }

    protected static String pad(String s, int n) { return s.length() >= n ? s.substring(0, n) : s + " ".repeat(n - s.length()); }
    protected static String up(String s) { return s.toUpperCase(Locale.ROOT); }
    protected static boolean numeric(String s) { return !s.isEmpty() && s.chars().allMatch(c -> c >= '0' && c <= '9'); }

    /** fsdispfe.cob: display-file-error。 */
    protected void displayFileError(String fsReply) {
        if (!fsReply.equals("00")) {
            display(24, 30, "error code = ", 4);
            show(24, 43, fsReply, 4);
            display(24, 48, "Hit return to continue");
            accept(24, 72, 2);
        }
    }

    /**
     * date-validate section（各プログラム共通）: dd/mm/yy の検査。区切り . , - は / に置換する。
     * 戻り値 [0]=置換後の日付、[1]=u-bin（0 は不正）。
     */
    public static Object[] dateValidate(String date) {
        final int[] days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
        String u = pad(date, 8).replace('.', '/').replace(',', '/').replace('-', '/');
        Object[] bad = {u, 0};
        long q = u.chars().filter(c -> c == '/').count();
        String dd = u.substring(0, 2), mm = u.substring(3, 5), yy = u.substring(6, 8);
        if (q != 2 || !numeric(dd) || !numeric(mm) || !numeric(yy)) return bad;
        int d = Integer.parseInt(dd), m = Integer.parseInt(mm), y = Integer.parseInt(yy);
        if (d < 1 || d > 31 || m < 1 || m > 12) return bad;
        if (d > 29 && m == 2) return bad;
        if (d > days[m - 1] && m != 2) return bad;
        if (m == 2 && d > 28 && y != (y / 4) * 4) return bad;
        int w1 = 1, w2 = 0, bin = y * 365;
        while (y > w2) { bin++; w2 += 4; }
        if (y == w2 && m > 2) bin++;
        while (m > w1) { bin += days[w1 - 1]; w1++; }
        if (d <= days[w1 - 1]) bin += d;
        else if (d == 29 && m == 2 && y == w2) bin += d;
        else bin = 0;
        return new Object[]{u, bin};
    }

    /**
     * 印刷ファイル prt-1（行順、IRS ディレクトリ）。GnuCOBOL の WRITE AFTER n は「改行 n 個 + 行」なので
     * ファイル先頭に空行が 1 行入り、以後 AFTER n は空行 n-1 行 + 行となる（レガシー実測）。
     */
    protected CobFile openPrint() {
        CobFile f = CobFile.lineSequential(ctx.store, ctx.irsPath("prt-1"));
        f.open(CobFile.Mode.OUTPUT);
        pendingLine = "";
        return f;
    }
    /** 直前に書いた行（改行前）。AFTER PAGE は改行せず FF + 行を同じ物理行へ続けるため、1 行分だけ保留する。 */
    private String pendingLine;
    protected void writeAfter(CobFile f, String line, int after) {
        f.writeLine(pendingLine);
        for (int i = 1; i < after; i++) f.writeLine("");
        pendingLine = line;
    }
    protected void writeAfterPage(CobFile f, String line) { pendingLine = pendingLine.stripTrailing() + "\f" + line; }
    protected void closePrint(CobFile f) {
        if (pendingLine != null) f.writeLine(pendingLine);
        pendingLine = null;
        f.close();
    }
    /** call "SYSTEM" using Print-Report（lpr による印刷指示）。IRS の prt-1 は IRS ディレクトリにあるため spool へ自前で複写する。 */
    protected void printReport(Rec sys, CobFile f) {
        printReport(sys, f, "orientation-requested=3 page-left=48 page-top=24 page-right=24");
    }
    /** print-spool-command.cob（横向き）/ print-spool-command-p.cob（縦向き）の lpr オプション違いを opts で渡す。 */
    protected void printReport(Rec sys, CobFile f, String opts) {
        closePrint(f);
        String src = ctx.irsPath("prt-1");
        if (!ctx.store.exists(src)) return;
        int max = 0;
        for (String n : ctx.store.fileNames())
            if (n.startsWith("spool/")) try { max = Math.max(max, Integer.parseInt(n.split("/")[1])); } catch (NumberFormatException ignored) { }
        String dir = "spool/" + String.format("%04d", max + 1);
        ctx.store.create(dir + "/prt-1");
        for (var e : ctx.store.all(src)) ctx.store.put(dir + "/prt-1", e.getKey(), e.getValue());
        String command = "lpr -r -o '" + opts + " sides=two-sided-long-edge cpi=12 lpi=8' -P "
                + sys.str("print-spool-name").trim() + " prt-1";
        ctx.store.create(dir + "/command.txt");
        ctx.store.put(dir + "/command.txt", new byte[8], command.getBytes(java.nio.charset.StandardCharsets.ISO_8859_1));
    }
    protected static final String[] NL_AMOUNTS = {"nl-dr", "nl-cr"};
    /** nl-dr / nl-cr / nl-dr-last(1-4) / nl-cr-last(1-4) をゼロにする。 */
    protected static void zeroAmounts(Rec nl) {
        nl.setNum("nl-dr", 0); nl.setNum("nl-cr", 0);
        for (int i = 1; i <= 4; i++) { nl.setNum("nl-dr-last", 0, i); nl.setNum("nl-cr-last", 0, i); }
    }
}
