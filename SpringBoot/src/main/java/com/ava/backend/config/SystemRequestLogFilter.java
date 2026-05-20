package com.ava.backend.config;

import java.io.IOException;
import java.util.UUID;

import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.ops.service.SystemLogService;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component
public class SystemRequestLogFilter extends OncePerRequestFilter {

	private final SystemLogService systemLogService;

	public SystemRequestLogFilter(SystemLogService systemLogService) {
		this.systemLogService = systemLogService;
	}

	@Override
	protected boolean shouldNotFilter(HttpServletRequest request) {
		String path = request.getRequestURI();
		return path == null
			|| path.equals("/api/health")
			|| path.equals("/api/readiness")
			|| path.startsWith("/actuator")
			|| path.startsWith("/api/app-updates")
			|| path.startsWith("/ws")
			|| path.startsWith("/rtc");
	}

	@Override
	protected void doFilterInternal(
		HttpServletRequest request,
		HttpServletResponse response,
		FilterChain filterChain
	) throws ServletException, IOException {
		long startedAt = System.nanoTime();
		String requestId = requestId(request);
		response.setHeader("X-Request-ID", requestId);
		Throwable error = null;
		try {
			filterChain.doFilter(request, response);
		} catch (ServletException | IOException | RuntimeException throwable) {
			error = throwable;
			throw throwable;
		} finally {
			record(requestId, request, response, startedAt, error);
		}
	}

	private void record(
		String requestId,
		HttpServletRequest request,
		HttpServletResponse response,
		long startedAt,
		Throwable error
	) {
		try {
			long durationMs = (System.nanoTime() - startedAt) / 1_000_000;
			AuthPrincipal principal = principal();
			systemLogService.recordRequest(requestId, principal, request, response.getStatus(), durationMs, error);
		} catch (RuntimeException ignored) {
			// Request logging must never break the user-facing request path.
		}
	}

	private AuthPrincipal principal() {
		var authentication = SecurityContextHolder.getContext().getAuthentication();
		if (authentication == null || !(authentication.getPrincipal() instanceof AuthPrincipal principal)) {
			return null;
		}
		return principal;
	}

	private String requestId(HttpServletRequest request) {
		String provided = request.getHeader("X-Request-ID");
		if (provided == null || provided.isBlank()) {
			return UUID.randomUUID().toString();
		}
		String trimmed = provided.trim();
		return trimmed.length() <= 80 ? trimmed : trimmed.substring(0, 80);
	}
}
