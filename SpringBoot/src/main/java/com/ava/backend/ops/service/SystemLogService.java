package com.ava.backend.ops.service;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.ops.dto.SystemLogResponse;
import com.ava.backend.ops.entity.SystemLogEntity;
import com.ava.backend.ops.repository.SystemLogRepository;

import jakarta.servlet.http.HttpServletRequest;

@Service
public class SystemLogService {

	private final SystemLogRepository systemLogRepository;

	public SystemLogService(SystemLogRepository systemLogRepository) {
		this.systemLogRepository = systemLogRepository;
	}

	@Transactional(propagation = Propagation.REQUIRES_NEW)
	public void recordRequest(
		String requestId,
		AuthPrincipal principal,
		HttpServletRequest request,
		int status,
		long durationMs,
		Throwable error
	) {
		systemLogRepository.save(new SystemLogEntity(
			limit(requestId, 80),
			principal == null ? null : principal.userId(),
			principal == null ? null : principal.email(),
			limit(request.getMethod(), 16),
			limit(request.getRequestURI(), 600),
			sanitizeQuery(request.getQueryString()),
			status,
			Math.max(0, durationMs),
			clientIp(request),
			limit(request.getHeader("User-Agent"), 400),
			error == null ? "" : limit(error.getClass().getSimpleName() + ": " + error.getMessage(), 800)
		));
	}

	@Transactional(readOnly = true)
	public List<SystemLogResponse> latest() {
		return systemLogRepository.findTop200ByOrderByCreatedAtDesc().stream()
			.map(this::toResponse)
			.toList();
	}

	private SystemLogResponse toResponse(SystemLogEntity log) {
		return new SystemLogResponse(
			log.getId(),
			log.getRequestId(),
			log.getAccountId(),
			log.getAccountEmail(),
			log.getMethod(),
			log.getPath(),
			log.getQueryString(),
			log.getStatus(),
			log.getDurationMs(),
			log.getIpAddress(),
			log.getUserAgent(),
			log.getErrorMessage(),
			log.getCreatedAt()
		);
	}

	private String clientIp(HttpServletRequest request) {
		String forwardedFor = request.getHeader("X-Forwarded-For");
		if (forwardedFor != null && !forwardedFor.isBlank()) {
			return limit(forwardedFor.split(",")[0].trim(), 80);
		}
		return limit(request.getRemoteAddr(), 80);
	}

	private String sanitizeQuery(String queryString) {
		if (queryString == null || queryString.isBlank()) {
			return "";
		}
		return limit(queryString.replaceAll("(?i)(password|token|secret|key)=([^&\\s]+)", "$1=<redacted>"), 1000);
	}

	private String limit(String value, int maxLength) {
		if (value == null) {
			return "";
		}
		String trimmed = value.trim();
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}
}
