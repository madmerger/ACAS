package jp.co.acas.web;

import jp.co.acas.core.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** 利用者セッションごとにレガシー相当の対話プログラムを仮想スレッドで実行する。 */
@Component
public class SessionManager {
    private static final Logger log = LoggerFactory.getLogger(SessionManager.class);
    private final Store store;
    private final Map<String, Ctx> sessions = new ConcurrentHashMap<>();
    @Value("${acas.fixed-date:}") private String fixedDate;

    public SessionManager(Store store) { this.store = store; }

    public String start(String app) {
        String program = switch (app) { case "acas" -> "acas"; case "irs" -> "irs"; default -> throw new IllegalArgumentException("不明なアプリ: " + app); };
        if (sessions.size() > 200) sessions.entrySet().removeIf(e -> e.getValue().term.isEnded());
        String id = UUID.randomUUID().toString();
        Ctx ctx = new Ctx(store, fixedDate == null || fixedDate.isBlank() ? null : LocalDate.parse(fixedDate));
        sessions.put(id, ctx);
        Thread.ofVirtual().name("acas-" + id).start(() -> {
            String msg = "";
            try {
                if (!ctx.call(program)) msg = "プログラム " + program + " は未実装です";
            } catch (StopRun e) {
                msg = e.getMessage();
            } catch (Throwable t) {
                log.error("プログラム異常終了", t);
                msg = "異常終了: " + t;
            } finally {
                // irs 単体起動のレガシー実測では終了時表示が出ず、最終画面がそのまま残る
                if ((msg == null || msg.isEmpty()) && !program.equals("irs")) {
                    // GnuCOBOL ランタイムの画面終了時表示（キー入力で終了）
                    try {
                        ctx.term.clear();
                        ctx.term.display(2, 1, "end of program, please press a key to exit", 7);
                        ctx.term.accept(2, 79, 1, null, Terminal.AUTO, 7);
                    } catch (RuntimeException ignored) { }
                }
                ctx.term.end(msg);
            }
        });
        ctx.term.awaitIdle(10000);
        return id;
    }
    public Ctx get(String id) {
        Ctx c = sessions.get(id);
        if (c == null) throw new IllegalArgumentException("セッションがありません");
        return c;
    }
    public void close(String id) { Ctx c = sessions.remove(id); if (c != null) c.term.end(""); }
    public void closeAll() { sessions.values().forEach(c -> c.term.end("")); sessions.clear(); }
}
