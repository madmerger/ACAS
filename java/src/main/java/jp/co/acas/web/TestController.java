package jp.co.acas.web;

import jp.co.acas.core.Messages;
import jp.co.acas.core.Store;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.Set;

/** 同一性検証専用 API。acas.test-api=true のときだけ有効（既定は無効）。 */
@RestController
@RequestMapping("/api/test")
@ConditionalOnProperty(name = "acas.test-api", havingValue = "true")
public class TestController {
    private final Store store; private final SessionManager sessions;
    public TestController(Store store, SessionManager sessions) { this.store = store; this.sessions = sessions; }

    /** ベースラインデータへ初期化（全セッション終了）。 */
    @PostMapping("/reset")
    public Map<String, Object> reset(@RequestParam String baseline) {
        sessions.closeAll();
        if ("empty".equals(baseline)) store.clearAll(); else store.loadBaseline(baseline);
        return Map.of("baseline", baseline, "files", store.fileNames());
    }
    /** 全レコードの 16 進スナップショット。 */
    @GetMapping("/snapshot")
    public Map<String, Map<String, String>> snapshot() { return store.snapshot(); }
    /** レガシー原文（英語）面の画面テキスト。 */
    @GetMapping("/sessions/{id}/screen")
    public Map<String, Object> screen(@PathVariable String id, @RequestParam(defaultValue = "en") String lang) {
        var t = sessions.get(id).term;
        return Map.of("text", t.text("ja".equals(lang)), "ended", t.isEnded(), "history", t.history());
    }
    /** 対応表に無かった固定文言（日本語化漏れの検出用）。 */
    @GetMapping("/untranslated")
    public Set<String> untranslated() { return Messages.untranslated(); }
}
