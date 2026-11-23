package jp.co.acas.core;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * レガシー英語文言 → 日本語文言の対応表（resources/i18n/*.tsv、タブ区切り「英語⇥日本語」）。
 * 画面・帳票とも内部ではレガシーと同一の英語文字列を保持し（同一性検証用）、表示時に日本語へ変換する。
 */
public final class Messages {
    private static final Map<String, String> EXACT = new HashMap<>();
    private static final List<String[]> PHRASES = new ArrayList<>();
    private static final Set<String> UNTRANSLATED = ConcurrentHashMap.newKeySet();
    private static final Pattern CHUNK = Pattern.compile("\\s{2,}|\\s*:-\\s*|\\s*\\[[^\\]]*\\]?|\\]|\\s+-\\s+");
    private static final Pattern HAS_WORD = Pattern.compile("[A-Za-z]{2,}");

    static {
        for (String f : new String[]{"common", "sys", "gl", "sl", "pl", "st", "irs"}) {
            try (InputStream in = Messages.class.getResourceAsStream("/i18n/" + f + ".tsv")) {
                if (in == null) continue;
                BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8));
                for (String line; (line = r.readLine()) != null; ) {
                    if (line.startsWith("#") || !line.contains("\t")) continue;
                    String[] p = line.split("\t", 2);
                    EXACT.putIfAbsent(norm(p[0]), p[1]);
                }
            } catch (Exception e) { throw new IllegalStateException(e); }
        }
        EXACT.forEach((k, v) -> { if (k.length() >= 4) PHRASES.add(new String[]{k, v}); });
        PHRASES.sort((a, b) -> b[0].length() - a[0].length());
    }
    private Messages() { }
    private static String norm(String s) { return s.strip().replaceAll("\\s+", " "); }

    public static Map<String, String> catalog() { return new TreeMap<>(EXACT); }
    public static Set<String> untranslated() { return new TreeSet<>(UNTRANSLATED); }

    /** 表示幅（全角=2）。 */
    public static int width(String s) { int w = 0; for (int i = 0; i < s.length(); i++) w += wide(s.charAt(i)) ? 2 : 1; return w; }
    public static boolean wide(char c) { return c >= 0x1100 && !(c >= 0xff61 && c <= 0xff9f); }
    private static String pad(String s, int w) { int d = w - width(s); return d > 0 ? s + " ".repeat(d) : s; }

    /** 英語の画面／帳票文字列を日本語へ。桁位置を保つため、可能な限り元の幅に合わせて空白で埋める。 */
    public static String ja(String en) {
        if (en == null || en.isBlank()) return en;
        String lead = en.substring(0, en.length() - en.stripLeading().length());
        String hit = EXACT.get(norm(en));
        if (hit != null) return pad(lead + hit, en.length());
        StringBuilder out = new StringBuilder();
        Matcher m = CHUNK.matcher(en);
        int pos = 0; int debt = 0; // debt: 日本語が広かった分、後続の空白から差し引く
        while (true) {
            boolean found = m.find();
            String chunk = en.substring(pos, found ? m.start() : en.length());
            if (!chunk.isEmpty()) {
                String t = chunk(chunk);
                debt += width(t) - chunk.length();
                out.append(t);
            }
            if (!found) break;
            String sep = m.group();
            if (debt > 0) {
                int lead2 = sep.length() - sep.stripLeading().length();
                int cut = Math.min(debt, Math.max(0, lead2 - 1));
                if (sep.isBlank()) cut = Math.min(debt, sep.length() - 1);
                sep = sep.substring(cut); debt -= cut;
            } else if (debt < 0) { out.append(" ".repeat(-debt)); debt = 0; }
            out.append(sep);
            pos = m.end();
        }
        if (debt < 0) out.append(" ".repeat(-debt));
        return out.toString();
    }
    private static String chunk(String chunk) {
        String lead = chunk.substring(0, chunk.length() - chunk.stripLeading().length());
        String hit = EXACT.get(norm(chunk));
        if (hit != null) return lead + hit;
        String s = chunk; boolean any = false;
        for (String[] p : PHRASES) {
            int i = s.indexOf(p[0]);
            if (i < 0) continue;
            boolean lb = i == 0 || !Character.isLetterOrDigit(s.charAt(i - 1));
            int e = i + p[0].length();
            boolean rb = e >= s.length() || !Character.isLetterOrDigit(s.charAt(e));
            if (lb && rb) { s = s.substring(0, i) + p[1] + s.substring(e); any = true; }
        }
        if (!any && HAS_WORD.matcher(chunk).find()) UNTRANSLATED.add(norm(chunk));
        return s;
    }
}
