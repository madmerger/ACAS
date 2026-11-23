package jp.co.acas.core;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * COBOL SCREEN SECTION の実行時解釈。レガシーソースの画面定義（resources/screens/*.scr）をそのまま読み、
 * DISPLAY screen-name / ACCEPT screen-name を再現する。固定文言（VALUE）は対応表で日本語化される。
 */
public final class ScreenDef {
    /** 画面項目とプログラム変数の対応付け。 */
    public interface Binder {
        /** 項目値。数値は BigDecimal、文字は String。 */
        Object get(String name);
        /** 入力結果（画面上の文字列）を変数へ格納する。 */
        void set(String name, String text);
    }

    public static final class Item {
        public String name, value, from, using, pic;
        public int line, col, size;
        boolean input() { return using != null; }
        String source() { return using != null ? using : from != null ? from : name; }
    }

    public final String name;
    public final List<Item> items = new ArrayList<>();
    private ScreenDef(String name) { this.name = name; }

    private static final Map<String, Map<String, ScreenDef>> CACHE = new ConcurrentHashMap<>();

    /** resource: resources/screens からの相対パス。screen: 01 レベル名。 */
    public static ScreenDef of(String resource, String screen) {
        ScreenDef d = CACHE.computeIfAbsent(resource, ScreenDef::load).get(screen.toLowerCase(Locale.ROOT));
        if (d == null) throw new IllegalArgumentException("画面 " + screen + " が " + resource + " にありません");
        return d;
    }

    private static final Pattern TOKEN = Pattern.compile("\"([^\"]*)\"|(\\S+)");

    private static Map<String, ScreenDef> load(String resource) {
        String src;
        try (InputStream in = ScreenDef.class.getResourceAsStream("/screens/" + resource)) {
            if (in == null) throw new IllegalArgumentException("画面定義 " + resource + " がありません");
            src = new String(in.readAllBytes(), StandardCharsets.ISO_8859_1);
        } catch (IOException e) { throw new UncheckedIOException(e); }
        StringBuilder sb = new StringBuilder();
        for (String l : src.split("\n")) {
            String t = l.stripLeading();
            if (t.startsWith("*>")) continue;
            int c = commentStart(l);
            sb.append(c >= 0 ? l.substring(0, c) : l).append('\n');
        }
        Map<String, ScreenDef> out = new LinkedHashMap<>();
        ScreenDef cur = null;
        int line = 1, col = 1;
        for (String stmt : splitStatements(sb.toString())) {
            List<String[]> toks = new ArrayList<>();
            Matcher m = TOKEN.matcher(stmt);
            while (m.find()) toks.add(m.group(1) != null ? new String[]{"S", m.group(1)} : new String[]{"W", m.group(2)});
            if (toks.isEmpty() || !toks.get(0)[1].matches("\\d+")) continue;
            int level = Integer.parseInt(toks.get(0)[1]);
            int i = 1;
            if (level == 1) {
                cur = new ScreenDef(toks.get(1)[1].toLowerCase(Locale.ROOT));
                out.put(cur.name, cur); line = 1; col = 1;
                continue;
            }
            if (cur == null) continue;
            Item it = new Item();
            boolean hasLine = false, hasCol = false;
            if (i < toks.size() && toks.get(i)[0].equals("W") && !isKeyword(toks.get(i)[1])) it.name = toks.get(i++)[1].toLowerCase(Locale.ROOT);
            while (i < toks.size()) {
                String w = toks.get(i)[1].toLowerCase(Locale.ROOT);
                boolean str = toks.get(i)[0].equals("S");
                i++;
                if (str) continue;
                switch (w) {
                    case "value" -> {
                        StringBuilder v = new StringBuilder(toks.get(i++)[1]);
                        while (i + 1 < toks.size() && toks.get(i)[1].equals("&")) { v.append(toks.get(i + 1)[1]); i += 2; }
                        it.value = v.toString();
                    }
                    case "from" -> it.from = toks.get(i++)[1].toLowerCase(Locale.ROOT);
                    case "using", "to" -> it.using = toks.get(i++)[1].toLowerCase(Locale.ROOT);
                    case "pic", "picture" -> it.pic = expand(toks.get(i++)[1]);
                    case "line" -> { it.line = Integer.parseInt(toks.get(i++)[1]); hasLine = true; }
                    case "col", "column" -> { it.col = Integer.parseInt(toks.get(i++)[1]); hasCol = true; }
                    case "foreground-color", "background-color" -> i++;
                    default -> { }
                }
            }
            if (!hasLine) it.line = line;
            if (!hasCol) it.col = hasLine ? 1 : col;
            it.size = it.pic != null ? it.pic.length() : it.value != null ? it.value.length() : 0;
            if (it.value != null && it.pic != null && it.value.length() < it.size) it.value = Terminal.Field.fit(it.value, it.size);
            line = it.line; col = it.col + it.size;
            cur.items.add(it);
        }
        return out;
    }

    private static boolean isKeyword(String w) {
        return switch (w.toLowerCase(Locale.ROOT)) {
            case "value", "from", "using", "to", "pic", "picture", "line", "col", "column", "foreground-color", "background-color",
                 "blank", "erase", "highlight", "lowlight", "blink", "reverse-video", "underline", "secure", "auto", "full", "required", "bell" -> true;
            default -> false;
        };
    }
    private static int commentStart(String l) {
        boolean q = false;
        for (int i = 0; i < l.length() - 1; i++) {
            char c = l.charAt(i);
            if (c == '"') q = !q;
            else if (!q && c == '*' && l.charAt(i + 1) == '>') return i;
        }
        return -1;
    }
    /** 文字列外のピリオド＋空白で文を区切る。 */
    private static List<String> splitStatements(String s) {
        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        boolean q = false;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"') q = !q;
            if (!q && c == '.' && (i + 1 >= s.length() || Character.isWhitespace(s.charAt(i + 1)))) { out.add(cur.toString()); cur.setLength(0); }
            else cur.append(c);
        }
        return out;
    }
    /** x(24) → xxx…、9(5) → 99999。 */
    static String expand(String pic) {
        Matcher m = Pattern.compile("(.)\\((\\d+)\\)").matcher(pic);
        StringBuilder sb = new StringBuilder();
        while (m.find()) m.appendReplacement(sb, Matcher.quoteReplacement(m.group(1).repeat(Integer.parseInt(m.group(2)))));
        m.appendTail(sb);
        return sb.toString();
    }

    private String text(Item it, Binder b) {
        Object v = b.get(it.source());
        int size = it.size;
        if (v instanceof BigDecimal d) {
            if (it.pic != null && !it.pic.toLowerCase(Locale.ROOT).startsWith("x")) return Num.edit(d, it.pic);
            String s = d.toPlainString();
            return size > 0 ? Terminal.Field.fit(s, size) : s;
        }
        String s = v == null ? "" : v.toString();
        return size > 0 ? Terminal.Field.fit(s, size) : s;
    }

    /** DISPLAY screen-name。 */
    public void display(Terminal term, Binder b, int fg) {
        for (Item it : items) {
            if (it.value != null && it.name == null && it.from == null && it.using == null) term.display(it.line, it.col, it.value, fg);
            else term.displayData(it.line, it.col, it.value != null && it.from == null && it.using == null && b.get(it.name) == null ? it.value : text(it, b), fg);
        }
    }

    /** ACCEPT screen-name（WITH UPDATE 相当: 現在値を初期表示）。戻り値は CRT STATUS。 */
    public int accept(Terminal term, Binder b, int fg) {
        List<Terminal.Field> fields = new ArrayList<>();
        List<Item> inputs = new ArrayList<>();
        for (Item it : items) {
            if (!it.input()) continue;
            String t = text(it, b);
            inputs.add(it);
            fields.add(new Terminal.Field(it.line, it.col, t.length(), t));
        }
        int st = term.acceptScreen(fields, fg);
        for (int i = 0; i < inputs.size(); i++) b.set(inputs.get(i).using, fields.get(i).value);
        return st;
    }
}
