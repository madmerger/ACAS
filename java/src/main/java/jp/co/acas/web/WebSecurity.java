package jp.co.acas.web;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.web.ServerProperties;
import org.springframework.boot.web.server.Ssl;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

@Configuration
class WebSecurity {
    @Bean
    SecurityFilterChain access(HttpSecurity http,
            ServerProperties server,
            @Value("${acas.test-api:false}") boolean testing,
            @Value("${spring.datasource.url}") String datasourceUrl,
            @Value("${ACAS_TEST_API_TOKEN:}") String testToken) throws Exception {
        boolean loopback = server.getAddress() != null && server.getAddress().isLoopbackAddress();
        if (testing) {
            if (!loopback) {
                throw new IllegalStateException("同一性検証用 API はループバックでのみ利用できます");
            }
            if (!datasourceUrl.startsWith("jdbc:h2:mem:")) {
                throw new IllegalStateException("同一性検証はインメモリの H2 データベースで実行してください");
            }
            if (testToken.length() < 32 || testToken.isBlank()) {
                throw new IllegalStateException("同一性検証には 32 文字以上の ACAS_TEST_API_TOKEN が必要です");
            }
            byte[] token = testToken.getBytes(StandardCharsets.UTF_8);
            http.authorizeHttpRequests(auth -> auth.anyRequest().access((authentication, context) -> {
                String supplied = context.getRequest().getHeader("X-ACAS-Test-Token");
                return new AuthorizationDecision(supplied != null
                        && MessageDigest.isEqual(token, supplied.getBytes(StandardCharsets.UTF_8)));
            })).csrf(AbstractHttpConfigurer::disable);
        } else {
            if (!loopback && !Ssl.isEnabled(server.getSsl())) {
                throw new IllegalStateException("ループバック以外で待ち受ける場合は TLS を設定してください");
            }
            http.authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
                .httpBasic(Customizer.withDefaults());
        }
        return http.build();
    }

    @Bean
    InMemoryUserDetailsManager account(@Value("${acas.web-password-hash:}") String hash) {
        InMemoryUserDetailsManager users = new InMemoryUserDetailsManager();
        if (!hash.isBlank()) {
            if (!hash.matches("\\$2[aby]\\$\\d{2}\\$[./A-Za-z0-9]{53}")) {
                throw new IllegalArgumentException("ACAS_WEB_PASSWORD_HASH には BCrypt ハッシュを指定してください");
            }
            users.createUser(User.withUsername("acas").password(hash).roles("ACAS").build());
        }
        return users;
    }

    @Bean
    BCryptPasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
