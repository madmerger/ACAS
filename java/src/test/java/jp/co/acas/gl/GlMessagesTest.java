package jp.co.acas.gl;

import static org.junit.jupiter.api.Assertions.*;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import jp.co.acas.core.Messages;
import org.junit.jupiter.api.Test;

class GlMessagesTest {
    @Test
    void 訳語の表示幅は原文以下でエラーコードを保持する() throws Exception {
        List<String> bad = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(
                getClass().getResourceAsStream("/i18n/gl.tsv"), StandardCharsets.UTF_8))) {
            for (String line; (line = r.readLine()) != null; ) {
                if (line.startsWith("#") || !line.contains("\t")) continue;
                String[] p = line.split("\t", 2);
                if (Messages.width(p[1]) > p[0].length()) bad.add("幅超過: " + line);
                if (p[0].matches("GL\\d{3} .*") && !p[1].startsWith(p[0].substring(0, 6))) bad.add("コード欠落: " + line);
                int b = p[0].indexOf('[');
                if (b >= 0 && (p[1].indexOf('[') < 0 || Messages.width(p[1].substring(0, p[1].indexOf('['))) != b))
                    bad.add("入力欄の桁ずれ: " + line);
            }
        }
        assertTrue(bad.isEmpty(), String.join("\n", bad));
    }

    @Test
    void メニュー文言が日本語化される() {
        assertEquals("GL009 日付不正", Messages.ja("GL009 Invalid Date").stripTrailing());
        assertTrue(Messages.ja("(1)  Detailed Trial Balance").contains("明細試算表"));
    }
}
