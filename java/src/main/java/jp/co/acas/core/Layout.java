package jp.co.acas.core;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * レガシー COBOL コピー句（resources/copybooks 配下）を実行時に解析し、
 * GnuCOBOL と同一のバイト配置（オフセット・長さ・USAGE）を持つレコードレイアウトを得る。
 * これにより移行後もレコードはレガシーとバイト互換になる。
 */
public final class Layout {
    public enum Kind { GROUP, ALPHA, DISPLAY_NUM, COMP, COMP3, NATIVE_BIN, EDITED }

    public static final class Field {
        public String name; public int level; public Kind kind = Kind.GROUP;
        public int offset, size, digits, scale; public boolean signed;
        public int occurs = 1; public String redefines; public String pic;
        public Field parent; public List<Field> children = new ArrayList<>();
        /** この項目を含む OCCURS の (刻み幅) を外側から順に保持。 */
        public int[] strides = new int[0];
        Kind groupUsage; boolean nativeUnsigned; int nativeSize;
    }

    public final String name; public final int size;
    private final Map<String, Field> byName = new HashMap<>();
    public final Field root;

    private Layout(Field root) {
        this.root = root; this.name = root.name; this.size = root.size * root.occurs;
        index(root);
    }
    private void index(Field f) {
        if (f.name != null && !f.name.equals("filler")) byName.putIfAbsent(f.name, f);
        for (Field c : f.children) index(c);
    }
    public Field field(String n) {
        Field f = byName.get(n.toLowerCase(Locale.ROOT));
        if (f == null) throw new IllegalArgumentException("項目が見つかりません: " + n + " in " + name);
        return f;
    }
    public boolean has(String n) { return byName.containsKey(n.toLowerCase(Locale.ROOT)); }
    public Collection<Field> fields() { return byName.values(); }
    public Rec newRec() { Rec r = new Rec(this, new byte[size]); r.initialize(); return r; }
    public Rec wrap(byte[] data) {
        byte[] d = data.length == size ? data : Arrays.copyOf(data, size);
        if (data.length < size) Arrays.fill(d, data.length, size, (byte) ' ');
        return new Rec(this, d);
    }

    // ---------- 解析 ----------
    private static final Map<String, Layout> CACHE = new ConcurrentHashMap<>();

    /** copybook: resources/copybooks からの相対パス。record: 01 レベル名（大文字小文字無視）。 */
    public static Layout of(String copybook, String record) {
        return CACHE.computeIfAbsent(copybook + "#" + record.toLowerCase(Locale.ROOT), k -> {
            List<Field> tops = parse(source(copybook, new HashSet<>()));
            for (Field f : tops) if (record.equalsIgnoreCase(f.name)) return new Layout(f);
            throw new IllegalArgumentException("01 レベル " + record + " が " + copybook + " にありません");
        });
    }
    /** 文字列で直接定義したレイアウト（作業領域用）。 */
    public static Layout ofSource(String cobol, String record) {
        for (Field f : parse(cobol)) if (record.equalsIgnoreCase(f.name)) return new Layout(f);
        throw new IllegalArgumentException(record);
    }

    private static String source(String copybook, Set<String> seen) {
        String text = load(copybook);
        StringBuilder out = new StringBuilder();
        Pattern copy = Pattern.compile("(?i)^\\s*copy\\s+\"?([\\w./-]+)\"?\\s*(replacing.*)?\\.\\s*$");
        for (String line : text.split("\n")) {
            int c = line.indexOf("*>");
            if (c >= 0) line = line.substring(0, c);
            if (line.length() > 6 && (line.charAt(6) == '*' || line.charAt(6) == '/') && line.substring(0, 6).isBlank()) continue;
            Matcher m = copy.matcher(line);
            if (m.matches()) {
                String inc = m.group(1);
                if (seen.add(inc)) out.append(source(resolve(copybook, inc), seen)).append('\n');
            } else out.append(line).append('\n');
        }
        return out.toString();
    }
    private static String resolve(String from, String inc) {
        String dir = from.contains("/") ? from.substring(0, from.lastIndexOf('/') + 1) : "";
        for (String cand : new String[]{dir + inc, "copybooks/" + inc, inc})
            if (Layout.class.getResource("/copybooks/" + cand) != null) return cand;
        throw new IllegalArgumentException("コピー句が見つかりません: " + inc);
    }
    private static String load(String path) {
        try (InputStream in = Layout.class.getResourceAsStream("/copybooks/" + path)) {
            if (in == null) throw new IllegalArgumentException("コピー句が見つかりません: " + path);
            return new String(in.readAllBytes(), StandardCharsets.ISO_8859_1);
        } catch (IOException e) { throw new IllegalStateException(e); }
    }

    private static List<String> tokens(String sentence) {
        List<String> t = new ArrayList<>();
        Matcher m = Pattern.compile("\"[^\"]*\"|'[^']*'|\\S+").matcher(sentence);
        while (m.find()) t.add(m.group());
        return t;
    }

    static List<Field> parse(String src) {
        List<Field> tops = new ArrayList<>();
        Deque<Field> stack = new ArrayDeque<>();
        // 文（ピリオド+空白 で終端）へ分割。文字列リテラル内のピリオドは保護。
        List<String> sentences = new ArrayList<>();
        StringBuilder cur = new StringBuilder(); char q = 0;
        for (int i = 0; i < src.length(); i++) {
            char ch = src.charAt(i);
            if (q != 0) { cur.append(ch); if (ch == q) q = 0; continue; }
            if (ch == '"' || ch == '\'') { q = ch; cur.append(ch); continue; }
            if (ch == '.' && (i + 1 >= src.length() || Character.isWhitespace(src.charAt(i + 1)))) {
                sentences.add(cur.toString()); cur.setLength(0); continue;
            }
            cur.append(ch);
        }
        for (String s : sentences) {
            List<String> t = tokens(s);
            if (t.isEmpty() || !t.get(0).matches("\\d{1,2}")) continue;
            int level = Integer.parseInt(t.get(0));
            if (level == 88 || level == 66 || level == 78) continue;
            Field f = new Field(); f.level = level;
            int i = 1;
            String n = i < t.size() ? t.get(i).toLowerCase(Locale.ROOT) : "filler";
            if (Set.of("pic", "picture", "redefines", "occurs", "value", "comp", "comp-3", "binary", "usage").contains(n) || n.startsWith("binary-")) n = "filler"; else i++;
            f.name = n;
            for (; i < t.size(); i++) {
                String w = t.get(i).toLowerCase(Locale.ROOT);
                switch (w) {
                    case "pic", "picture" -> { i++; if (t.get(i).equalsIgnoreCase("is")) i++; f.pic = t.get(i).toLowerCase(Locale.ROOT); }
                    case "redefines" -> f.redefines = t.get(++i).toLowerCase(Locale.ROOT);
                    case "occurs" -> f.occurs = Integer.parseInt(t.get(++i));
                    case "comp", "computational", "binary", "comp-4", "comp-5" -> f.groupUsage = Kind.COMP;
                    case "comp-3", "computational-3", "packed-decimal" -> f.groupUsage = Kind.COMP3;
                    case "binary-char" -> { f.groupUsage = Kind.NATIVE_BIN; f.nativeSize = 1; }
                    case "binary-short" -> { f.groupUsage = Kind.NATIVE_BIN; f.nativeSize = 2; }
                    case "binary-long" -> { f.groupUsage = Kind.NATIVE_BIN; f.nativeSize = 4; }
                    case "binary-double" -> { f.groupUsage = Kind.NATIVE_BIN; f.nativeSize = 8; }
                    case "unsigned" -> f.nativeUnsigned = true;
                    case "value", "values" -> i = t.size();
                    default -> { }
                }
            }
            while (!stack.isEmpty() && stack.peek().level >= level) stack.pop();
            if (level == 1 || level == 77 || stack.isEmpty()) { tops.add(f); stack.clear(); }
            else { f.parent = stack.peek(); f.parent.children.add(f); }
            stack.push(f);
        }
        for (Field top : tops) { resolveUsage(top, null); layout(top, 0, new int[0]); }
        return tops;
    }

    private static void resolveUsage(Field f, Kind inherited) {
        Kind usage = f.groupUsage != null ? f.groupUsage : inherited;
        if (f.groupUsage == Kind.NATIVE_BIN) {
            f.kind = Kind.NATIVE_BIN; f.size = f.nativeSize; f.signed = !f.nativeUnsigned;
            f.digits = switch (f.size) { case 1 -> 3; case 2 -> 5; case 4 -> 10; default -> 18; };
        } else if (f.pic != null) {
            String p = expand(f.pic);
            boolean numeric = p.matches("s?[9vp]+");
            if (!numeric) {
                f.kind = p.matches("[xa9]+") && p.contains("x") || p.matches("[xa]+") ? Kind.ALPHA : Kind.EDITED;
                f.size = p.length();
                if (f.kind == Kind.EDITED) {
                    int dot = p.indexOf('.');
                    f.scale = dot < 0 ? 0 : (int) p.substring(dot).chars().filter(c -> c == '9' || c == 'z').count();
                }
            } else {
                f.signed = p.startsWith("s");
                int v = p.indexOf('v');
                f.digits = (int) p.chars().filter(c -> c == '9').count();
                f.scale = v < 0 ? 0 : (int) p.substring(v).chars().filter(c -> c == '9').count();
                if (usage == Kind.COMP) { f.kind = Kind.COMP; f.size = f.digits <= 2 ? 1 : f.digits <= 4 ? 2 : f.digits <= 9 ? 4 : 8; }
                else if (usage == Kind.COMP3) { f.kind = Kind.COMP3; f.size = f.digits / 2 + 1; }
                else { f.kind = Kind.DISPLAY_NUM; f.size = f.digits; }
            }
        } else {
            f.kind = Kind.GROUP;
            for (Field c : f.children) resolveUsage(c, usage);
        }
    }
    private static String expand(String pic) {
        StringBuilder sb = new StringBuilder();
        Matcher m = Pattern.compile("(.)\\((\\d+)\\)|(.)").matcher(pic);
        while (m.find()) {
            if (m.group(1) != null) sb.append(m.group(1).repeat(Integer.parseInt(m.group(2))));
            else sb.append(m.group(3));
        }
        return sb.toString();
    }
    private static int layout(Field f, int offset, int[] strides) {
        f.offset = offset; f.strides = strides;
        if (f.kind == Kind.GROUP) {
            int[] inner = strides;
            if (f.occurs > 1) { inner = Arrays.copyOf(strides, strides.length + 1); }
            int pos = offset, max = offset;
            Map<String, Field> sib = new HashMap<>();
            for (Field c : f.children) {
                int start = pos;
                if (c.redefines != null && sib.containsKey(c.redefines)) start = sib.get(c.redefines).offset;
                int end = layout(c, start, inner);
                sib.put(c.name, c);
                if (c.redefines == null) pos = end;
                max = Math.max(max, Math.max(end, pos));
            }
            f.size = max - offset;
            if (f.occurs > 1) setStride(f, strides.length, f.size);
        } else if (f.occurs > 1) {
            int[] inner = Arrays.copyOf(strides, strides.length + 1);
            inner[strides.length] = f.size; f.strides = inner;
        }
        return offset + f.size * f.occurs;
    }
    private static void setStride(Field f, int idx, int stride) {
        for (Field c : f.children) {
            if (c.strides.length > idx) c.strides[idx] = stride;
            setStride(c, idx, stride);
        }
        if (f.occurs > 1 && f.strides.length == idx) { f.strides = Arrays.copyOf(f.strides, idx + 1); f.strides[idx] = stride; }
    }
}
