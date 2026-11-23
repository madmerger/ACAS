package jp.co.acas.web;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;

class TestAccessFilterTest {
    private static final String TOKEN = "synthetic-test-token-not-a-secret";

    @Test
    void onlyRegistersInVerificationMode() {
        var context = new ApplicationContextRunner().withUserConfiguration(TestAccessFilter.class);
        context.run(application -> assertThat(application).doesNotHaveBean(TestAccessFilter.class));
        context.withPropertyValues("acas.test-api=true", "ACAS_TEST_API_TOKEN=" + TOKEN)
            .run(application -> assertThat(application).hasSingleBean(TestAccessFilter.class));
    }

    @Test
    void sameTokenIsRequiredForPageAssetsAndApis() throws Exception {
        var filter = new TestAccessFilter(TOKEN);
        for (String path : new String[] {"/calc.html", "/app.css", "/api/calc/date", "/api/test/snapshot"}) {
            for (String header : new String[] {null, "wrong-token", TOKEN}) {
                var request = new MockHttpServletRequest("GET", path);
                if (header != null) request.addHeader("X-ACAS-Test-Token", header);
                var response = new MockHttpServletResponse();
                var chain = new MockFilterChain();
                filter.doFilter(request, response, chain);
                assertThat(response.getStatus()).as(path).isEqualTo(TOKEN.equals(header) ? 200 : 403);
                assertThat(chain.getRequest()).as(path).isEqualTo(TOKEN.equals(header) ? request : null);
            }
        }
    }
}
