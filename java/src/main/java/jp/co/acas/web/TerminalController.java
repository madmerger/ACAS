package jp.co.acas.web;

import jp.co.acas.core.Ctx;
import jp.co.acas.core.Messages;
import jp.co.acas.core.Store;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.util.*;

@RestController
@RequestMapping("/api")
public class TerminalController {
    private final SessionManager sessions; private final Store store;
    public TerminalController(SessionManager sessions, Store store) { this.sessions = sessions; this.store = store; }

    public record Keys(List<String> keys) { }

    @PostMapping("/sessions")
    public Map<String, Object> start(@RequestParam(defaultValue = "acas") String app) {
        String id;
        try { id = sessions.start(app); } catch (IllegalArgumentException e) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()); }
        Map<String, Object> m = sessions.get(id).term.snapshot();
        m.put("id", id);
        return m;
    }
    @GetMapping("/sessions/{id}")
    public Map<String, Object> screen(@PathVariable String id) { return ctx(id).term.snapshot(); }

    /** キー入力。keys の各要素は 1 文字、または ENTER/ESC/TAB/BACKTAB/UP/DOWN/LEFT/RIGHT/HOME/END/PGUP/PGDN/BACKSPACE/DELETE/F1..F12。 */
    @PostMapping("/sessions/{id}/keys")
    public Map<String, Object> keys(@PathVariable String id, @RequestBody Keys body) {
        Ctx c = ctx(id);
        if (body.keys() == null || body.keys().size() > 2000) throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        c.term.feed(body.keys(), 15000);
        return c.term.snapshot();
    }
    @DeleteMapping("/sessions/{id}")
    public void close(@PathVariable String id) { sessions.close(id); }

    private Ctx ctx(String id) {
        try { return sessions.get(id); } catch (IllegalArgumentException e) { throw new ResponseStatusException(HttpStatus.NOT_FOUND, e.getMessage()); }
    }

    // ---------- 帳票 ----------
    @GetMapping("/reports")
    public List<Map<String, Object>> reports() {
        List<Map<String, Object>> out = new ArrayList<>();
        for (String f : store.fileNames()) {
            String base = f.substring(f.lastIndexOf('/') + 1);
            if (!(base.startsWith("prt-") || f.startsWith("spool/") && !base.equals("command.txt"))) continue;
            out.add(Map.of("name", f, "lines", store.count(f)));
        }
        return out;
    }
    @GetMapping("/reports/content")
    public Map<String, Object> report(@RequestParam String name, @RequestParam(defaultValue = "ja") String lang) {
        String base = name.substring(name.lastIndexOf('/') + 1);
        if (!store.exists(name) || !(base.startsWith("prt-") || name.startsWith("spool/"))) throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        List<String> lines = new ArrayList<>();
        for (var e : store.all(name)) {
            String line = new String(e.getValue(), StandardCharsets.ISO_8859_1);
            lines.add("ja".equals(lang) ? Messages.ja(line) : line);
        }
        return Map.of("name", name, "lines", lines);
    }
    /** 英語（レガシー原文）→日本語 文言対応表。 */
    @GetMapping("/messages")
    public Map<String, String> messages() { return Messages.catalog(); }
}
