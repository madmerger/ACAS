package jp.co.acas.pl;

import jp.co.acas.core.Messages;
import org.junit.jupiter.api.Test;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertTrue;

/** i18n/pl.tsv: 訳語の表示幅と、買掛プログラムの画面文言が全て日本語化されること。 */
class PlMessagesTest {
    @Test
    void 訳語の表示幅は原文の桁数以下() throws Exception {
        List<String> bad = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(
                PlMessagesTest.class.getResourceAsStream("/i18n/pl.tsv"), StandardCharsets.UTF_8))) {
            for (String line; (line = r.readLine()) != null; ) {
                if (line.startsWith("#") || !line.contains("\t")) continue;
                String[] p = line.split("\t", 2);
                if (Messages.width(p[1]) > p[0].length()) bad.add(p[0]);
            }
        }
        assertTrue(bad.isEmpty(), "原文より幅が広い訳語: " + bad);
    }

    @Test
    void 画面文言は全て対応表で日本語化される() throws Exception {
        Pattern call = Pattern.compile("\\b(?:display|err)\\([^\"\\n]*?\"((?:[^\"\\\\]|\\\\.)*)\"");
        Path dir = Path.of("src/main/java/jp/co/acas/pl");
        try (Stream<Path> files = Files.list(dir)) {
            for (Path f : (Iterable<Path>) files::iterator) {
                for (String line : Files.readAllLines(f)) {
                    Matcher m = call.matcher(line);
                    while (m.find()) Messages.ja(m.group(1).replace("\\\"", "\""));
                }
            }
        }
        List<String> left = new ArrayList<>(Messages.untranslated());
        assertTrue(left.isEmpty(), "未翻訳の文言: " + left);
    }
}
