package com.ava.backend.ops.service;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.ops.dto.AuditLogResponse;
import com.ava.backend.ops.entity.AuditLogEntity;
import com.ava.backend.ops.repository.AuditLogRepository;

import jakarta.servlet.http.HttpServletRequest;

@Service
public class AuditLogService {

	private final AuditLogRepository auditLogRepository;

	public AuditLogService(AuditLogRepository auditLogRepository) {
		this.auditLogRepository = auditLogRepository;
	}

	@Transactional
	public void record(
		AuthPrincipal actor,
		String action,
		String resourceType,
		String resourceId,
		String metadata,
		HttpServletRequest request
	) {
		auditLogRepository.save(new AuditLogEntity(
			actor == null ? null : actor.userId(),
			actor == null ? null : actor.email(),
			limit(action, 80),
			limit(resourceType, 80),
			limit(resourceId, 160),
			clientIp(request),
			limit(request == null ? null : request.getHeader("User-Agent"), 400),
			sanitizeMetadata(metadata)
		));
	}

	@Transactional(readOnly = true)
	public List<AuditLogResponse> latest() {
		return auditLogRepository.findTop100ByOrderByCreatedAtDesc().stream()
			.map(this::toResponse)
			.toList();
	}

	private AuditLogResponse toResponse(AuditLogEntity log) {
		return new AuditLogResponse(
			log.getId(),
			log.getActorAccountId(),
			log.getActorEmail(),
			log.getAction(),
			log.getResourceType(),
			log.getResourceId(),
			log.getIpAddress(),
			log.getUserAgent(),
			log.getMetadata(),
			log.getCreatedAt()
		);
	}

	private String clientIp(HttpServletRequest request) {
		if (request == null) {
			return "";
		}
		String forwardedFor = request.getHeader("X-Forwarded-For");
		if (forwardedFor != null && !forwardedFor.isBlank()) {
			return limit(forwardedFor.split(",")[0].trim(), 80);
		}
		return limit(request.getRemoteAddr(), 80);
	}

	private String sanitizeMetadata(String value) {
		String text = value == null ? "" : value;
		return limit(text.replaceAll("(?i)(password|token|secret)=[^,\\s]+", "$1=<redacted>"), 4000);
	}

	private String limit(String value, int maxLength) {
		if (value == null) {
			return "";
		}
		String trimmed = value.trim();
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}
}
