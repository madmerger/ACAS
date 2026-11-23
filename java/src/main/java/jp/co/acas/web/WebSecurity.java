package jp.co.acas.web;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
class WebSecurity {
    @Bean
    SecurityFilterChain access(HttpSecurity http,
            @Value("${acas.test-api:false}") boolean testing,
            @Value("${server.address}") String address) throws Exception {
        if (testing) {
            if (!address.equals("127.0.0.1") && !address.equals("::1")) {
                throw new IllegalStateException("同一性検証用 API はループバックでのみ利用できます");
            }
            http.authorizeHttpRequests(auth -> auth.anyRequest().permitAll()).csrf(AbstractHttpConfigurer::disable);
        } else {
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
