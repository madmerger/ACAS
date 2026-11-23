package jp.co.acas.web;

import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class CalcControllerTest {
    private final MockMvc mvc = MockMvcBuilders.standaloneSetup(new CalcController()).build();

    @Test
    void invalidAmountReturnsJapaneseMessage() throws Exception {
        mvc.perform(get("/api/calc/vat").param("net", "abc").param("rate", "20"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("税抜金額の数値が不正です。"));
    }

    @Test
    void invalidDaysReturnJapaneseMessage() throws Exception {
        mvc.perform(get("/api/calc/age").param("days", "1.5"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("経過日数は整数で入力してください。"));
    }

    @Test
    void missingRateReturnsJapaneseMessage() throws Exception {
        mvc.perform(get("/api/calc/vat").param("net", "100"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("必要な項目を入力してください。"));
    }

    @Test
    void zeroQuantityRemainsACompletedCalculationWithNoCost() throws Exception {
        mvc.perform(get("/api/calc/average-cost").param("value", "100").param("qty", "0"))
                .andExpect(status().isOk())
                .andExpect(content().json("{\"cost\":null}", true));
    }
}
