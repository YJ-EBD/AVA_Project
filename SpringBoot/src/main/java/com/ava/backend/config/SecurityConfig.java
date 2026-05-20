package com.ava.backend.config;

import java.util.Arrays;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import com.ava.backend.auth.security.JwtAuthenticationFilter;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

	private final List<String> allowedOrigins;

	public SecurityConfig(@Value("${ava.web.allowed-origins:*}") String allowedOrigins) {
		this.allowedOrigins = parseAllowedOrigins(allowedOrigins);
	}

	@Bean
	SecurityFilterChain securityFilterChain(
		HttpSecurity http,
		JwtAuthenticationFilter jwtAuthenticationFilter,
		AuthRateLimitFilter authRateLimitFilter,
		SystemRequestLogFilter systemRequestLogFilter
	) throws Exception {
		return http
			.csrf(AbstractHttpConfigurer::disable)
			.cors(cors -> cors.configurationSource(corsConfigurationSource()))
			.sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
			.authorizeHttpRequests(authorize -> authorize
				.requestMatchers(
					"/api/health",
					"/api/readiness",
					"/actuator/health",
					"/api/auth/signup",
					"/api/auth/email-verifications",
					"/api/auth/email-verifications/confirm",
					"/api/auth/login",
					"/api/auth/refresh",
					"/api/auth/find-account",
					"/api/app-updates/**",
					"/ws/**",
					"/rtc/**"
				).permitAll()
				.anyRequest().authenticated()
			)
			.addFilterBefore(systemRequestLogFilter, UsernamePasswordAuthenticationFilter.class)
			.addFilterBefore(authRateLimitFilter, UsernamePasswordAuthenticationFilter.class)
			.addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)
			.build();
	}

	@Bean
	FilterRegistrationBean<SystemRequestLogFilter> systemRequestLogFilterRegistration(SystemRequestLogFilter filter) {
		var registration = new FilterRegistrationBean<SystemRequestLogFilter>(filter);
		registration.setEnabled(false);
		return registration;
	}

	@Bean
	PasswordEncoder passwordEncoder() {
		return new BCryptPasswordEncoder();
	}

	@Bean
	CorsConfigurationSource corsConfigurationSource() {
		var configuration = new CorsConfiguration();
		allowedOrigins.forEach(configuration::addAllowedOriginPattern);
		configuration.addAllowedHeader("*");
		configuration.addAllowedMethod("*");
		var source = new UrlBasedCorsConfigurationSource();
		source.registerCorsConfiguration("/**", configuration);
		return source;
	}

	private static List<String> parseAllowedOrigins(String value) {
		List<String> origins = Arrays.stream(value.split(","))
			.map(String::trim)
			.filter(origin -> !origin.isBlank())
			.toList();
		return origins.isEmpty() ? List.of("*") : origins;
	}
}
