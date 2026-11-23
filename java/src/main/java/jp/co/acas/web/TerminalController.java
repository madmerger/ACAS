package jp.co.acas.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jp.co.acas.core.Ctx;
import jp.co.acas.core.Messages;
import jp.co.acas.core.Store;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.*;

@RestController
@RequestMapping("/api")
public class TerminalController {
    // 2000 件のキーをすべて JSON の Unicode エスケープで表しても収まる。
    private static final int MAX_KEYS_BODY_BYTES = 3 * 1024 * 1024;
    private final SessionManager sessions; private final Store store;
    private final ObjectMapper json;
    public TerminalController(SessionManager sessions, Store store, ObjectMapper json) {
        this.sessions = sessions;
        this.store = store;
        this.json = json;
    }

    public record Keys(List<String> keys) { }
    private static final Set<String> COMMANDS = Set.of("ENTER", "ESC", "TAB", "BACKTAB", "UP", "DOWN", "LEFT", "RIGHT",
            "HOME", "END", "PGUP", "PGDN", "BACKSPACE", "DELETE", "F1", "F2", "F3", "F4", "F5", "F6", "F7",
            "F8", "F9", "F10", "F11", "F12");

    @PostMapping("/sessions")
    public Map<String, Object> start(@RequestParam(defaultValue = "acas") String app, HttpServletRequest request) {
        String owner = request.getSession().getId();
        String id;
        try { id = sessions.start(app, owner); } catch (IllegalArgumentException e) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()); }
        Map<String, Object> m = sessions.get(id, owner).term.webSnapshot();
        m.put("id", id);
        return m;
    }
    @GetMapping("/sessions/{id}")
    public Map<String, Object> screen(@PathVariable String id, HttpServletRequest request) {
        return ctx(id, sessionOwner(request)).term.webSnapshot();
    }

    /** キー入力。keys の各要素は 1 文字、または ENTER/ESC/TAB/BACKTAB/UP/DOWN/LEFT/RIGHT/HOME/END/PGUP/PGDN/BACKSPACE/DELETE/F1..F12。 */
    @PostMapping(value = "/sessions/{id}/keys", consumes = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, Object> keys(@PathVariable String id, HttpServletRequest request, InputStream requestBody)
            throws IOException {
        Ctx c = ctx(id, sessionOwner(request));
        byte[] data = requestBody.readNBytes(MAX_KEYS_BODY_BYTES + 1);
        if (data.length > MAX_KEYS_BODY_BYTES) {
            throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "入力本文が大きすぎます");
        }
        Keys body;
        try {
            body = json.readValue(data, Keys.class);
        } catch (JsonProcessingException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "入力形式が正しくありません");
        }
        if (body == null || body.keys() == null || body.keys().isEmpty() || body.keys().size() > 2000
                || !body.keys().stream().allMatch(TerminalController::validKey)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "入力形式が正しくありません");
        }
        c.term.feed(body.keys(), 15000);
        return c.term.webSnapshot();
    }
    private static boolean validKey(String key) {
        return key != null && (COMMANDS.contains(key) || key.matches("REPLACE:[0-9]{1,4}:[0-9]{1,4}:[ -~]{0,200}")
                || key.length() == 1 && key.charAt(0) >= ' ' && key.charAt(0) <= '~');
    }
    @DeleteMapping("/sessions/{id}")
    public void close(@PathVariable String id, HttpServletRequest request) {
        sessions.close(id, sessionOwner(request));
    }

    @GetMapping("/csrf")
    public Map<String, String> csrf(HttpServletRequest request) {
        var token = (org.springframework.security.web.csrf.CsrfToken)
            request.getAttribute(org.springframework.security.web.csrf.CsrfToken.class.getName());
        return token == null ? Map.of() : Map.of(token.getHeaderName(), token.getToken());
    }

    private static String sessionOwner(HttpServletRequest request) {
        var session = request.getSession(false);
        return session == null ? null : session.getId();
    }

    private Ctx ctx(String id, String owner) {
        try { return sessions.get(id, owner); } catch (IllegalArgumentException e) { throw new ResponseStatusException(HttpStatus.NOT_FOUND, e.getMessage()); }
    }

    // ---------- 帳票 ----------
    @GetMapping("/reports")
    public List<Map<String, Object>> reports() {
        List<Map<String, Object>> out = new ArrayList<>();
        for (String f : store.fileNames()) {
            String base = f.substring(f.lastIndexOf('/') + 1);
            if (!isReport(f)) continue;
            out.add(Map.of("name", f, "lines", store.count(f)));
        }
        return out;
    }
    @GetMapping("/reports/content")
    public Map<String, Object> report(@RequestParam String name, @RequestParam(defaultValue = "ja") String lang) {
        if (!isReport(name) || !store.exists(name)) throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        List<String> lines = new ArrayList<>();
        for (var e : store.all(name)) {
            lines.add(new String(e.getValue(), StandardCharsets.ISO_8859_1));
        }
        if ("ja".equals(lang)) {
            boolean systemParameters = !lines.isEmpty() && lines.getFirst().startsWith("SYS002 (");
            for (int i = 0; i < lines.size(); i++) {
                String line = lines.get(i);
                // 設定帳票の冒頭では桁 28〜70 が会社名・住所のデータ領域です。
                lines.set(i, systemParameters && i >= 5 && i <= 9 && line.length() >= 70
                        ? Messages.jaReport(line.substring(0, 27)) + line.substring(27, 70)
                                + Messages.jaReport(line.substring(70))
                        : Messages.jaReport(line));
            }
        }
        return Map.of("name", name, "lines", lines);
    }
    private static boolean isReport(String name) {
        String base = name.substring(name.lastIndexOf('/') + 1);
        return base.startsWith("prt-") || name.startsWith("spool/") && !base.equals("command.txt");
    }
    /** 英語（レガシー原文）→日本語 文言対応表。 */
    @GetMapping("/messages")
    public Map<String, String> messages() { return Messages.catalog(); }
}
