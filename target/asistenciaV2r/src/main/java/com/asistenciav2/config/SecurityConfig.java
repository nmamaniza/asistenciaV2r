package com.asistenciav2.config;

import com.asistenciav2.security.CustomUserDetailsService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.security.web.authentication.rememberme.JdbcTokenRepositoryImpl;
import org.springframework.security.web.authentication.rememberme.PersistentTokenRepository;
import org.springframework.http.HttpMethod;

import javax.sql.DataSource;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Autowired
    private DataSource dataSource;

    @Bean
    public UserDetailsService userDetailsService() {
        return new CustomUserDetailsService();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public AuthenticationSuccessHandler successHandler() {
        return new CustomAuthenticationSuccessHandler();
    }

    @Bean
    public PersistentTokenRepository persistentTokenRepository() {
        JdbcTokenRepositoryImpl tokenRepository = new JdbcTokenRepositoryImpl();
        tokenRepository.setDataSource(dataSource);
        // Descomentar para crear la tabla automáticamente la primera vez
        // tokenRepository.setCreateTableOnStartup(true);
        return tokenRepository;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(authz -> authz
                        .requestMatchers("/", "/login.html", "/index.html", "/css/**", "/js/**", "/resources/**",
                                "/searchAttendance", "/api/userInfo")
                        .permitAll()
                        .requestMatchers("/dashboard_admin.html", "/admin/**").hasRole("ADMIN")
                        .requestMatchers("/dashboard.html", "/user/**").hasAnyRole("USER", "ADMIN")
                        .requestMatchers("/perfiles.html").hasRole("ADMIN")
                        .requestMatchers("/api/users", "/api/users/**").hasRole("ADMIN")
                        .requestMatchers("/api/workschedules", "/api/jobassignments", "/api/jobassignments/**")
                        .hasRole("ADMIN")
                        .requestMatchers("/api/permissions", "/api/permission-types", "/api/lactation-schedules")
                        .hasRole("ADMIN")
                        .requestMatchers("/api/consolidated-data", "/api/consolidated-export", "/api/consolidated-time",
                                "/api/consolidated-time-export")
                        .hasRole("ADMIN")
                        .anyRequest().authenticated())
                .formLogin(form -> form
                        .loginPage("/login.html")
                        .loginProcessingUrl("/login")
                        .usernameParameter("identifier")
                        .passwordParameter("password")
                        .successHandler(successHandler())
                        .failureUrl("/login.html?error=true")
                        .permitAll())
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint((request, response, authException) -> {
                            response.sendRedirect("/login.html");
                        }))
                .rememberMe(remember -> remember
                        .tokenRepository(persistentTokenRepository())
                        .tokenValiditySeconds(2592000) // 30 días
                        .userDetailsService(userDetailsService())
                        .key("asistenciaV2rSecretKey")
                        .rememberMeParameter("remember-me")
                        .useSecureCookie(true))
                .sessionManagement(session -> session
                        .invalidSessionUrl("/login.html")
                        .maximumSessions(1)
                        .expiredUrl("/login.html?expired")
                        .and()
                        .sessionFixation().migrateSession())
                .logout(logout -> logout
                        .logoutUrl("/logout")
                        .logoutSuccessUrl("/login.html")
                        .invalidateHttpSession(true)
                        .deleteCookies("JSESSIONID")
                        .permitAll())
                .csrf(csrf -> csrf.disable());

        return http.build();
    }

}
