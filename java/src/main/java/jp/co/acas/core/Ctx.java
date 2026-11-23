package jp.co.acas.core;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/** 1 利用者セッション（= レガシーの 1 実行単位）の実行コンテキスト。 */
public final class Ctx {
    public final Terminal term = new Terminal();
    public final Store store;
    private final LocalDate fixedDate;
    /** 実行単位内で共有する領域（レガシーの LINKAGE で引き回す system-record 等）。 */
    public final Map<String, Object> shared = new HashMap<>();
    /** ACAS_LEDGERS / ACAS_IRS に相当する論理ディレクトリ。 */
    public String ledgersDir = "acas", irsDir = "irs";
    private static final String[] PACKAGES = {"sys", "gl", "sl", "pl", "st", "irs", "calc"};
    private int spoolSeq;

    public Ctx(Store store, LocalDate fixedDate) { this.store = store; this.fixedDate = fixedDate; }

    public LocalDate today() { return fixedDate != null ? fixedDate : LocalDate.now(); }
    public LocalDateTime now() { return LocalDateTime.of(today(), LocalTime.now()); }

    /** ACAS データファイルの論理名（例 "ledger.dat" → "acas/ledger.dat"）。 */
    public String path(String file) { return ledgersDir + "/" + file; }
    public String irsPath(String file) { return irsDir + "/" + file; }

    /** CALL "name" 相当。クラス jp.co.acas.<pkg>.<Name> を探して実行する。未実装なら false。 */
    public boolean call(String name, Object... args) {
        Program p = find(name);
        if (p == null) return false;
        p.ctx = this;
        p.run(args);
        return true;
    }
    public static Program find(String name) {
        String n = name.trim().toLowerCase(Locale.ROOT).replace("-", "");
        if (n.isEmpty()) return null;
        String cls = Character.toUpperCase(n.charAt(0)) + n.substring(1);
        for (String pkg : PACKAGES) {
            try {
                Class<?> c = Class.forName("jp.co.acas." + pkg + "." + cls);
                if (Program.class.isAssignableFrom(c)) return (Program) c.getDeclaredConstructor().newInstance();
            } catch (ClassNotFoundException ignored) {
            } catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
        }
        return null;
    }

    /**
     * 帳票の印刷指示（レガシーの print-spool-command = lpr 呼出し）相当。
     * 印刷ファイルの内容を spool/<連番>/<file> として保存する（帳票画面で閲覧可能）。
     */
    public void spool(String file, String command) {
        String src = path(file);
        if (!store.exists(src)) return;
        String dir = "spool/" + String.format("%04d", nextSpool());
        store.create(dir + "/" + file);
        for (var e : store.all(src)) store.put(dir + "/" + file, e.getKey(), e.getValue());
        store.create(dir + "/command.txt");
        store.put(dir + "/command.txt", new byte[8], command.getBytes(StandardCharsets.ISO_8859_1));
    }
    private int nextSpool() {
        int max = spoolSeq;
        for (String f : store.fileNames())
            if (f.startsWith("spool/")) try { max = Math.max(max, Integer.parseInt(f.split("/")[1])); } catch (NumberFormatException ignored) { }
        return spoolSeq = max + 1;
    }
}
