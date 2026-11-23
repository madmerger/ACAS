package jp.co.acas.web;

import jp.co.acas.core.Messages;
import jp.co.acas.core.Store;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** 同一性検証専用 API。acas.test-api=true のときだけ有効（既定は無効）。 */
@RestController
@RequestMapping("/api/test")
@ConditionalOnProperty(name = "acas.test-api", havingValue = "true")
public class TestController {
    private static final String TOKEN_HEADER = "X-ACAS-Test-Token";
    private final Store store; private final SessionManager sessions;
    private final byte[] token;

    public TestController(Store store, SessionManager sessions,
            @Value("${ACAS_TEST_API_TOKEN:}") String testToken,
            @Value("${spring.datasource.url}") String datasourceUrl) {
        if (testToken.length() < 32 || testToken.isBlank()) {
            throw new IllegalStateException("同一性検証には 32 文字以上の ACAS_TEST_API_TOKEN が必要です");
        }
        if (!datasourceUrl.startsWith("jdbc:h2:mem:")) {
            throw new IllegalStateException("同一性検証はインメモリの H2 データベースで実行してください");
        }
        this.store = store;
        this.sessions = sessions;
        this.token = testToken.getBytes(StandardCharsets.UTF_8);
    }

    private void authorize(String supplied) {
        if (supplied == null || !MessageDigest.isEqual(token, supplied.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
    }

    /** ベースラインデータへ初期化（全セッション終了）。 */
    @PostMapping("/reset")
    public Map<String, Object> reset(@RequestParam String baseline,
            @RequestHeader(value = TOKEN_HEADER, required = false) String supplied) {
        authorize(supplied);
        sessions.closeAll();
        if ("empty".equals(baseline)) store.clearAll(); else store.loadBaseline(baseline);
        return Map.of("baseline", baseline, "files", store.fileNames());
    }
    /** 全レコードの 16 進スナップショット。 */
    @GetMapping("/snapshot")
    public Map<String, Map<String, String>> snapshot(
            @RequestHeader(value = TOKEN_HEADER, required = false) String supplied) {
        authorize(supplied);
        return store.snapshot();
    }
    /** レガシー原文（英語）面の画面テキスト。 */
    @GetMapping("/sessions/{id}/screen")
    public Map<String, Object> screen(@PathVariable String id, @RequestParam(defaultValue = "en") String lang,
            @RequestHeader(value = TOKEN_HEADER, required = false) String supplied) {
        authorize(supplied);
        var t = sessions.get(id).term;
        return Map.of("text", t.text("ja".equals(lang)), "ended", t.isEnded(), "history", t.history());
    }
    /** 対応表に無かった固定文言（日本語化漏れの検出用）。 */
    @GetMapping("/untranslated")
    public Set<String> untranslated(@RequestHeader(value = TOKEN_HEADER, required = false) String supplied) {
        authorize(supplied);
        return Messages.untranslated();
    }
}
