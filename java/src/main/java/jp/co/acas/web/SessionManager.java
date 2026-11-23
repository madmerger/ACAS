package jp.co.acas.web;

import jp.co.acas.core.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** 利用者セッションごとにレガシー相当の対話プログラムを仮想スレッドで実行する。 */
@Component
public class SessionManager {
    private static final Logger log = LoggerFactory.getLogger(SessionManager.class);
    private final Store store;
    private record Entry(String owner, Ctx ctx) { }
    private final Map<String, Entry> sessions = new ConcurrentHashMap<>();
    @Value("${acas.fixed-date:}") private String fixedDate;

    public SessionManager(Store store) { this.store = store; }

    public String start(String app, String owner) {
        String program = switch (app) { case "acas" -> "acas"; case "irs" -> "irs"; default -> throw new IllegalArgumentException("不明なアプリ: " + app); };
        String id = UUID.randomUUID().toString();
        Ctx ctx = new Ctx(store, fixedDate == null || fixedDate.isBlank() ? null : LocalDate.parse(fixedDate));
        synchronized (sessions) {
            if (sessions.size() >= 200) sessions.entrySet().removeIf(e -> e.getValue().ctx().term.isEnded());
            if (sessions.size() >= 200) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "セッション数が上限に達しました");
            sessions.put(id, new Entry(owner, ctx));
        }
        Thread.ofVirtual().name("acas-" + id).start(() -> {
            String msg = "";
            try {
                if (!ctx.call(program)) msg = "この業務は利用できません";
            } catch (StopRun e) {
                msg = e.getMessage();
            } catch (RuntimeException t) {
                log.error("プログラム異常終了", t);
                msg = "業務処理が異常終了しました";
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
    Ctx get(String id, String owner) {
        Entry entry = sessions.get(id);
        if (entry == null || !entry.owner().equals(owner)) {
            throw new IllegalArgumentException("セッションがありません");
        }
        return entry.ctx();
    }

    /** トークン認証済みの同一性検証用 API が画面証跡を取得する。 */
    Ctx get(String id) {
        Entry entry = sessions.get(id);
        if (entry == null) throw new IllegalArgumentException("セッションがありません");
        return entry.ctx();
    }

    void close(String id, String owner) {
        Entry entry = sessions.get(id);
        if (entry != null && entry.owner().equals(owner) && sessions.remove(id, entry)) {
            entry.ctx().term.end("");
        }
    }
    public void closeAll() {
        sessions.values().forEach(entry -> entry.ctx().term.end(""));
        sessions.clear();
    }
}
