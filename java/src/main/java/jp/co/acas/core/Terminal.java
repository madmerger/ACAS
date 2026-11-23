package jp.co.acas.core;

import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

/**
 * レガシーの 80x24 文字端末（GnuCOBOL DISPLAY/ACCEPT AT）と同じ意味論を持つ仮想画面。
 * 英語（レガシー原文）と日本語の 2 面を同時に保持する。ブラウザには日本語面を返す。
 */
public final class Terminal {
    public static final int ROWS = 24, COLS = 80;
    public static final int AUTO = 1, SECURE = 2, UPPER = 4, NUMERIC = 8;

    private final char[][] en = new char[ROWS][COLS];
    private final char[][] ja = new char[ROWS][COLS];   // '\0' = 全角文字の右半分
    private final byte[][] color = new byte[ROWS][COLS];
    private final ReentrantLock lock = new ReentrantLock();
    private final Condition changed = lock.newCondition();
    private final Deque<String> keys = new ArrayDeque<>();
    private boolean waiting, ended; private int curRow = -1, curCol = -1;
    private String endMessage = "";
    /** 直近 ACCEPT の終了キー（COB-CRT-STATUS 相当: 0=Enter, 1001-=F1-, 2001=PgUp, 2002=PgDn, 2003=↑, 2004=↓, 2005=Esc, 2007=Tab, 2008=BackTab）。 */
    public int crtStatus;
    /** COB_SCREEN_ESC / COB_SCREEN_EXCEPTIONS 相当。false の間は Esc / ファンクションキーを無視する。 */
    public boolean escEnabled = false, exceptionsEnabled = false;
    private final List<String> history = new ArrayList<>();

    public Terminal() { clear(); }

    public void clear() { lock.lock(); try { for (int r = 0; r < ROWS; r++) blank(r, 0, COLS); } finally { lock.unlock(); } }
    private void blank(int r, int from, int to) {
        if (from > 0 && ja[r][from] == 0) ja[r][from - 1] = ' ';
        for (int c = from; c < to; c++) { en[r][c] = ' '; ja[r][c] = ' '; color[r][c] = 7; }
        if (to < COLS && ja[r][to] == 0) ja[r][to] = ' ';
    }
    /** ERASE EOS: (line,col) から画面末尾まで消去。 */
    public void eraseEos(int line, int col) {
        lock.lock(); try { blank(line - 1, col - 1, COLS); for (int r = line; r < ROWS; r++) blank(r, 0, COLS); } finally { lock.unlock(); }
    }
    /** ERASE EOL。 */
    public void eraseEol(int line, int col) { lock.lock(); try { blank(line - 1, col - 1, COLS); } finally { lock.unlock(); } }

    /** 固定文言の表示（日本語面は対応表で変換）。 */
    public void display(int line, int col, String text, int fg) { put(line, col, text, Messages.ja(text), fg); }
    /** データ値の表示（変換しない）。 */
    public void displayData(int line, int col, String text, int fg) { put(line, col, text, text, fg); }

    private void put(int line, int col, String e, String j, int fg) {
        lock.lock();
        try {
            int r = line - 1, c = col - 1;
            if (r < 0 || r >= ROWS || c < 0) return;
            for (int i = 0; i < e.length() && c + i < COLS; i++) {
                char ch = e.charAt(i);
                en[r][c + i] = ch < ' ' ? ' ' : ch; color[r][c + i] = (byte) fg;
            }
            int end = Math.min(COLS, c + Math.max(e.length(), Messages.width(j)));
            if (c > 0 && ja[r][c] == 0) ja[r][c - 1] = ' ';
            if (end < COLS && ja[r][end] == 0) ja[r][end] = ' ';
            int p = c;
            for (int i = 0; i < j.length() && p < COLS; i++) {
                char ch = j.charAt(i);
                if (Messages.wide(ch)) {
                    if (p + 1 >= COLS) { ja[r][p++] = ' '; break; }
                    ja[r][p] = ch; ja[r][p + 1] = 0; color[r][p] = color[r][p + 1] = (byte) fg; p += 2;
                } else { ja[r][p] = ch < ' ' ? ' ' : ch; color[r][p] = (byte) fg; p++; }
            }
            for (; p < end; p++) { ja[r][p] = ' '; }
        } finally { lock.unlock(); }
    }

    /**
     * ACCEPT ... AT line/col。initial が null なら UPDATE なし（空白から入力）。
     * 戻り値は size 桁の入力域内容。終了キーは crtStatus。
     */
    public String accept(int line, int col, int size, String initial, int flags, int fg) {
        char[] buf = new char[size];
        Arrays.fill(buf, ' ');
        if (initial != null) for (int i = 0; i < Math.min(size, initial.length()); i++) buf[i] = initial.charAt(i);
        int idx = 0;
        boolean secure = (flags & SECURE) != 0;
        while (true) {
            String shown = secure ? "*".repeat(size) : new String(buf);
            if (!secure || initial != null) displayData(line, col, secure ? (new String(buf).isBlank() ? " ".repeat(size) : shown) : shown, fg);
            String k = take(line - 1, col - 1 + idx);
            if (k == null) throw new StopRun("セッションが終了しました");
            if (k.length() == 1) {
                char ch = k.charAt(0);
                if (ch < ' ' || ch > '~') continue;
                if ((flags & NUMERIC) != 0 && !(ch >= '0' && ch <= '9' || ch == '.' || ch == '-' || ch == '+' || ch == ',')) continue;
                if ((flags & UPPER) != 0) ch = Character.toUpperCase(ch);
                buf[idx] = ch;
                if (idx < size - 1) idx++;
                else if ((flags & AUTO) != 0) { crtStatus = 0; break; }
                continue;
            }
            Integer st = switch (k) {
                case "ENTER" -> 0; case "TAB" -> 2007; case "BACKTAB" -> 2008;
                case "UP" -> 2003; case "DOWN" -> 2004; case "PGUP" -> 2001; case "PGDN" -> 2002;
                case "ESC" -> escEnabled ? 2005 : null;
                default -> k.matches("F\\d{1,2}") && exceptionsEnabled ? 1000 + Integer.parseInt(k.substring(1)) : null;
            };
            if (st != null) { crtStatus = st; break; }
            switch (k) {
                case "LEFT" -> { if (idx > 0) idx--; }
                case "RIGHT" -> { if (idx < size - 1) idx++; }
                case "HOME" -> idx = 0;
                case "END" -> idx = size - 1;
                case "BACKSPACE" -> { if (idx > 0) { idx--; System.arraycopy(buf, idx + 1, buf, idx, size - idx - 1); buf[size - 1] = ' '; } }
                case "DELETE" -> { System.arraycopy(buf, idx + 1, buf, idx, size - idx - 1); buf[size - 1] = ' '; }
                default -> { }
            }
        }
        String res = new String(buf);
        if (!secure) displayData(line, col, res, fg);
        return res;
    }

    /** SCREEN SECTION の入力項目（USING / TO）。value は size 桁の表示内容で、acceptScreen が更新する。 */
    public static final class Field {
        public final int line, col, size, flags;
        public String value;
        public Field(int line, int col, int size, String value, int flags) {
            this.line = line; this.col = col; this.size = size; this.flags = flags;
            this.value = fit(value == null ? "" : value, size);
        }
        public Field(int line, int col, int size, String value) { this(line, col, size, value, 0); }
        static String fit(String v, int size) { return v.length() >= size ? v.substring(0, size) : v + " ".repeat(size - v.length()); }
    }

    /**
     * ACCEPT screen-name（SCREEN SECTION の複数項目入力）。GnuCOBOL と同じく TAB / 下矢印で次項目、
     * BACKTAB / 上矢印で前項目、項目末尾まで入力すると次項目へ進み、ENTER で確定する。終了キーは crtStatus。
     */
    public int acceptScreen(List<Field> fields, int fg) {
        if (fields.isEmpty()) { crtStatus = 0; return 0; }
        int f = 0, idx = 0;
        for (Field x : fields) if ((x.flags & SECURE) == 0) displayData(x.line, x.col, x.value, fg);
        while (true) {
            Field cur = fields.get(f);
            String k = take(cur.line - 1, cur.col - 1 + idx);
            if (k == null) throw new StopRun("セッションが終了しました");
            char[] buf = cur.value.toCharArray();
            if (k.length() == 1) {
                char ch = k.charAt(0);
                if (ch < ' ' || ch > '~') continue;
                if ((cur.flags & UPPER) != 0) ch = Character.toUpperCase(ch);
                buf[idx] = ch;
                cur.value = new String(buf);
                if ((cur.flags & SECURE) == 0) displayData(cur.line, cur.col, cur.value, fg);
                if (idx < cur.size - 1) idx++;
                else if (f < fields.size() - 1) { f++; idx = 0; }
                continue;
            }
            Integer st = switch (k) {
                case "ENTER" -> 0; case "PGUP" -> 2001; case "PGDN" -> 2002;
                case "ESC" -> escEnabled ? 2005 : null;
                default -> k.matches("F\\d{1,2}") && exceptionsEnabled ? 1000 + Integer.parseInt(k.substring(1)) : null;
            };
            if (st != null) { crtStatus = st; return st; }
            switch (k) {
                case "TAB", "DOWN" -> { f = (f + 1) % fields.size(); idx = 0; }
                case "BACKTAB", "UP" -> { f = (f + fields.size() - 1) % fields.size(); idx = 0; }
                case "HOME" -> { f = 0; idx = 0; }
                case "END" -> { f = fields.size() - 1; idx = 0; }
                case "LEFT" -> { if (idx > 0) idx--; else if (f > 0) { f--; idx = fields.get(f).size - 1; } }
                case "RIGHT" -> { if (idx < cur.size - 1) idx++; else if (f < fields.size() - 1) { f++; idx = 0; } }
                case "BACKSPACE" -> {
                    if (idx > 0) {
                        idx--; System.arraycopy(buf, idx + 1, buf, idx, cur.size - idx - 1); buf[cur.size - 1] = ' ';
                        cur.value = new String(buf);
                        if ((cur.flags & SECURE) == 0) displayData(cur.line, cur.col, cur.value, fg);
                    }
                }
                case "DELETE" -> {
                    System.arraycopy(buf, idx + 1, buf, idx, cur.size - idx - 1); buf[cur.size - 1] = ' ';
                    cur.value = new String(buf);
                    if ((cur.flags & SECURE) == 0) displayData(cur.line, cur.col, cur.value, fg);
                }
                default -> { }
            }
        }
    }

    /** 入力キーを 1 つ取り出す（無ければ入力待ち状態を通知して待機）。 */
    private String take(int r, int c) {
        lock.lock();
        try {
            curRow = r; curCol = c;
            while (keys.isEmpty()) {
                if (ended) return null;
                waiting = true; changed.signalAll();
                try { if (!changed.await(30, TimeUnit.MINUTES)) { ended = true; return null; } }
                catch (InterruptedException e) { ended = true; return null; }
            }
            waiting = false;
            return keys.poll();
        } finally { lock.unlock(); }
    }

    /** ブラウザ／検証ハーネスからのキー投入。プログラムが次の入力待ちになる（または終了する）まで待つ。 */
    public void feed(List<String> ks, long timeoutMs) {
        lock.lock();
        try {
            if (ended) return;
            keys.addAll(ks); waiting = false; changed.signalAll();
            long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs);
            while (!(ended || (waiting && keys.isEmpty()))) {
                long left = deadline - System.nanoTime();
                if (left <= 0) break;
                try { changed.awaitNanos(left); } catch (InterruptedException e) { Thread.currentThread().interrupt(); break; }
            }
            history.add(text(false));
        } finally { lock.unlock(); }
    }
    public void awaitIdle(long timeoutMs) { feed(List.of(), timeoutMs); }

    public void end(String message) {
        lock.lock();
        try { ended = true; endMessage = message == null ? "" : message; curRow = curCol = -1; changed.signalAll(); } finally { lock.unlock(); }
    }
    public boolean isEnded() { return ended; }
    public boolean isWaiting() { lock.lock(); try { return waiting && keys.isEmpty(); } finally { lock.unlock(); } }

    /** 画面テキスト（24 行）。japanese=false はレガシー原文面。 */
    public String text(boolean japanese) {
        lock.lock();
        try {
            StringBuilder sb = new StringBuilder();
            for (int r = 0; r < ROWS; r++) {
                for (int c = 0; c < COLS; c++) { char ch = (japanese ? ja : en)[r][c]; if (ch != 0) sb.append(ch); }
                sb.append('\n');
            }
            return sb.toString();
        } finally { lock.unlock(); }
    }
    public List<String> history() { lock.lock(); try { return new ArrayList<>(history); } finally { lock.unlock(); } }

    public Map<String, Object> snapshot() {
        lock.lock();
        try {
            List<String> rows = new ArrayList<>(), colors = new ArrayList<>();
            for (int r = 0; r < ROWS; r++) {
                StringBuilder sb = new StringBuilder(), cb = new StringBuilder();
                for (int c = 0; c < COLS; c++) { if (ja[r][c] != 0) { sb.append(ja[r][c]); cb.append((char) ('0' + color[r][c])); } }
                rows.add(sb.toString()); colors.add(cb.toString());
            }
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("rows", rows); m.put("colors", colors);
            m.put("cursorRow", curRow); m.put("cursorCol", curCol);
            m.put("ended", ended); m.put("endMessage", endMessage); m.put("waiting", waiting);
            return m;
        } finally { lock.unlock(); }
    }
}
