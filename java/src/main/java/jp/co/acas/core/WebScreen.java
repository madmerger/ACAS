package jp.co.acas.core;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.NavigableMap;
import java.util.TreeMap;
import java.util.regex.Pattern;

/** 業務プログラムの表示項目と入力項目を、ブラウザー向けの項目に変換する。 */
final class WebScreen {
    private static final Pattern MENU = Pattern.compile("^\\s*\\(([A-Z0-9])\\)\\s*\\*?\\s*(.+)$");
    private static final Pattern RULE = Pattern.compile("^[\\s*=_+|\\[\\]{}<>─━│┌┐└┘-]+$");
    private static final Pattern PROGRAM = Pattern.compile("(?i)^[a-z]{2,7}\\s*\\([0-9.]+\\)$");
    private static final Pattern GRID_GAP = Pattern.compile(" {2,}");
    private static final Pattern OPTIONS = Pattern.compile("(?i)[Yy]/[Nn]|[Nn]/[Yy]");

    private record Output(String original, String label, int width, boolean data, int color) { }
    record Input(int row, int col, int size, String value, boolean secure, boolean numeric, boolean autoAdvance) { }
    record Field(int id, String label, int length, String value, boolean secure, boolean numeric) { }
    record Choice(String key, String label) { }
    record Line(List<String> cells, boolean error, boolean data) { }
    record View(String title, List<Field> fields, List<Choice> choices, List<Line> lines,
                int activeField, int caret, boolean confirm, boolean cancel, List<Choice> actions,
                boolean multiple, boolean yesNo, boolean autoAdvance) { }

    private final List<NavigableMap<Integer, Output>> rows = new ArrayList<>();

    WebScreen() {
        for (int i = 0; i < Terminal.ROWS; i++) rows.add(new TreeMap<>());
    }

    void clear(int row, int from, int to) {
        rows.get(row).entrySet().removeIf(e -> e.getKey() < to && e.getKey() + e.getValue().width() > from);
    }

    void display(int row, int col, String original, String label, boolean data, int color) {
        int width = original.length();
        if (row < 0 || row >= Terminal.ROWS || col < 0 || col >= Terminal.COLS || width == 0) return;
        var entries = rows.get(row);
        // 項目内のデータの重ね書きは、見出しや入力項目名を消さない。
        if (data && !entries.containsKey(col)) {
            var previous = entries.floorEntry(col);
            if (previous != null && previous.getValue().data() && previous.getKey() + previous.getValue().width() > col) {
                entries.remove(previous.getKey());
            }
        }
        entries.subMap(col, true, Math.min(Terminal.COLS, col + width), false).clear();
        if (!original.isBlank()) entries.put(col, new Output(original, label, width, data, color));
    }

    View view(List<Input> inputs, int active, int caret, boolean multiple, boolean cancel, boolean exceptions) {
        List<Field> fields = new ArrayList<>();
        List<Choice> choices = new ArrayList<>();
        List<Line> lines = new ArrayList<>();
        Map<String, String> actions = new java.util.LinkedHashMap<>();
        String title = "業務操作";
        boolean yesNo = false;
        for (int row = 0; row < rows.size(); row++) {
            List<String> cells = new ArrayList<>();
            boolean error = false;
            boolean data = false;
            for (var entry : rows.get(row).entrySet()) {
                int col = entry.getKey();
                Output output = entry.getValue();
                if (row == Terminal.ROWS - 1 && rows.get(row).values().stream()
                        .anyMatch(o -> o.original().startsWith("Copyright"))) break;
                if (hidden(output) || covered(inputs, row, col)) continue;
                String label = output.data() ? output.label().strip() : clean(output.label());
                if (label.isEmpty()) continue;
                var choice = MENU.matcher(output.original());
                if (choice.matches() && inputs.size() == 1 && inputs.getFirst().size() == 1) {
                    var translated = MENU.matcher(label);
                    choices.add(new Choice(choice.group(1), translated.matches() ? translated.group(2) : label));
                    continue;
                }
                if (!output.data()) {
                    if (output.original().startsWith("Select one of the following by letter")) continue;
                    yesNo |= OPTIONS.matcher(output.original()).find();
                    if (exceptions) addActions(output.original(), actions);
                    if (title.equals("業務操作") && row < 4 && label.matches(".*[ぁ-んァ-ヶ一-龯].*") && !label.endsWith("：")) {
                        title = label;
                        continue;
                    }
                }
                for (String cell : GRID_GAP.split(label)) if (!cell.isBlank()) cells.add(cell.strip());
                error |= output.color() == 4;
                data |= output.data();
            }
            if (!cells.isEmpty()) lines.add(new Line(cells, error, data));
        }
        for (int i = 0; i < inputs.size(); i++) {
            Input input = inputs.get(i);
            fields.add(new Field(i, fieldLabel(input, i + 1), input.size(), input.value(), input.secure(), input.numeric()));
        }
        choices.sort(java.util.Comparator.comparing(Choice::key));
        return new View(title, fields, choices, lines, active, caret, !fields.isEmpty(), cancel,
                actions.entrySet().stream().map(e -> new Choice(e.getKey(), e.getValue())).toList(),
                multiple, yesNo && inputs.size() == 1 && inputs.getFirst().size() == 1,
                inputs.size() == 1 && inputs.getFirst().autoAdvance());
    }

    private static boolean covered(List<Input> inputs, int row, int col) {
        for (Input i : inputs) {
            if (i.row() == row && col >= i.col() && col < i.col() + i.size()) return true;
        }
        return false;
    }

    private String fieldLabel(Input input, int number) {
        for (Output output : rows.get(input.row()).headMap(input.col(), false).descendingMap().values()) {
            String label = clean(output.label());
            if (!output.data() && !hidden(output) && !label.isEmpty()) return label;
        }
        if (input.secure()) return "パスワード";
        return "入力項目 " + number;
    }

    private static boolean hidden(Output output) {
        String s = output.original().strip();
        return s.isEmpty() || RULE.matcher(s).matches()
                || !output.data() && (s.startsWith("Copyright") || s.equals("Applewood Computers") || PROGRAM.matcher(s).matches());
    }

    private static String clean(String s) {
        if (s.strip().equals("OR")) return "または";
        return s.strip().replaceFirst("^\\*+\\s*", "").replaceAll("(?:\\s*:-)?[\\s\\[\\]{}:*]+$", "")
                .replace("Return", "確定").replace("RETURN", "確定").replace("Enter", "確定")
                .replace("Escape", "取消").replaceAll("\\bEsc\\b", "取消")
                .replaceAll("(?i)\\(?Y/N\\)?", "（はい／いいえ）").replace("dd/mm/yyyy", "日／月／西暦年")
                .replace("dd/mm/ccyy", "日／月／西暦年").replace("dd/mm/yy", "日／月／年")
                .replace("yyyy-mm-dd", "西暦年－月－日").replace("Linux", "リナックス")
                .replace("Windows", "ウィンドウズ").replace("Unix", "ユニックス").replace("POS", "店頭販売");
    }

    private static void addActions(String original, Map<String, String> actions) {
        var match = Pattern.compile("\\bF(1[0-2]|[1-9])\\b").matcher(original);
        while (match.find()) {
            String key = match.group();
            actions.putIfAbsent(key, key);
        }
        if (original.matches("(?i).*(Page ?Up|PgUp|Page ?Down|PgDn).*")) {
            actions.putIfAbsent("PGUP", "前のページ");
            actions.putIfAbsent("PGDN", "次のページ");
        }
    }
}
