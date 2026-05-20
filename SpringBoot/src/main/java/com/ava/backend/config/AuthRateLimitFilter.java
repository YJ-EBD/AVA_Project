package com.ava.backend.config;

import java.io.IOException;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.ava.backend.common.ApiErrorResponse;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component
public class AuthRateLimitFilter extends OncePerRequestFilter {

	private final ObjectMapper objectMapper;
	private final int limitPerMinute;
	private final Map<String, WindowCounter> counters = new ConcurrentHashMap<>();

	public AuthRateLimitFilter(
		ObjectMapper objectMapper,
		@Value("${ava.security.auth-rate-limit-per-minute:60}") int limitPerMinute
	) {
		this.objectMapper = objectMapper;
		this.limitPerMinute = Math.max(5, limitPerMinute);
	}

	@Override
	protected void doFilterInternal(
		HttpServletRequest request,
		HttpServletResponse response,
		FilterChain filterChain
	) throws ServletException, IOException {
		if (!shouldLimit(request)) {
			filterChain.doFilter(request, response);
			return;
		}
		String key = clientKey(request);
		WindowCounter counter = counters.compute(key, (ignored, previous) -> {
			long now = Instant.now().getEpochSecond();
			if (previous == null || now - previous.windowStartedAt() >= 60) {
				return new WindowCounter(now, new AtomicInteger(1));
			}
			previous.count().incrementAndGet();
			return previous;
		});
		if (counter.count().get() <= limitPerMinute) {
			filterChain.doFilter(request, response);
			return;
		}
		response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
		response.setContentType("application/json;charset=UTF-8");
		objectMapper.writeValue(response.getWriter(), ApiErrorResponse.of(
			HttpStatus.TOO_MANY_REQUESTS.value(),
			"RATE_LIMITED",
			"Too many authentication requests. Please try again later.",
			request.getRequestURI()
		));
	}

	private boolean shouldLimit(HttpServletRequest request) {
		if (!"POST".equalsIgnoreCase(request.getMethod())) {
			return false;
		}
		String uri = request.getRequestURI();
		return "/api/auth/login".equals(uri)
			|| "/api/auth/signup".equals(uri)
			|| "/api/auth/refresh".equals(uri);
	}

	private String clientKey(HttpServletRequest request) {
		String forwardedFor = request.getHeader("X-Forwarded-For");
		String ip = forwardedFor == null || forwardedFor.isBlank()
			? request.getRemoteAddr()
			: forwardedFor.split(",")[0].trim();
		return ip + ":" + request.getRequestURI();
	}

	private record WindowCounter(long windowStartedAt, AtomicInteger count) {
	}
}
