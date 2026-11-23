package jp.co.acas.calc;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;

import java.io.InputStream;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** CALC ケース（レガシー実測値）との一致を確認する。レガシー未実施のケースは対象外。 */
class CalcTest {
    @TestFactory
    List<DynamicTest> legacyMeasuredCases() throws Exception {
        List<DynamicTest> tests = new ArrayList<>();
        try (InputStream in = getClass().getResourceAsStream("/calc-cases.json")) {
            for (JsonNode c : new ObjectMapper().readTree(in)) {
                if (c.get("driver").isNull() || c.get("legacy_actual").isNull()) continue;
                JsonNode i = c.get("input"), want = c.get("legacy_actual");
                tests.add(DynamicTest.dynamicTest(c.get("id").asText(), () -> {
                    switch (c.get("driver").asText()) {
                        case "drv09" -> {
                            var r = Calc.checkDigit(i.get("code").asText());
                            assertEquals(want.get("check").asInt(), r.get("check"));
                            assertEquals(want.get("valid").asBoolean(), r.get("valid"));
                        }
                        case "drv04" -> {
                            var r = Calc.date(i.get("date").asText());
                            assertEquals(want.get("valid").asBoolean(), r.get("valid"));
                            assertEquals(want.get("integer").asLong(), r.get("integer"));
                            assertEquals(want.get("normalized").isNull() ? null : want.get("normalized").asText(), r.get("normalized"));
                        }
                        case "drvvat" -> assertEquals(0, new BigDecimal(want.get("vat").asText())
                                .compareTo(Calc.vat(new BigDecimal(i.get("net").asText()), new BigDecimal(i.get("rate").asText()))));
                        case "drvage" -> assertEquals(want.get("bucket").asInt(), Calc.ageBucket(i.get("days").asInt()));
                        case "drvavg" -> assertEquals(0, new BigDecimal(want.get("cost").asText())
                                .compareTo(Calc.averageCost(new BigDecimal(i.get("value").asText()), i.get("qty").asLong())));
                        default -> throw new IllegalStateException(c.get("driver").asText());
                    }
                }));
            }
        }
        return tests;
    }
}
