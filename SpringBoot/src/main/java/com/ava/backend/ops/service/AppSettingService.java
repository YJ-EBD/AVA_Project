package com.ava.backend.ops.service;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.ops.dto.AppSettingResponse;
import com.ava.backend.ops.dto.AppSettingUpsertRequest;
import com.ava.backend.ops.entity.AppSettingEntity;
import com.ava.backend.ops.repository.AppSettingRepository;

@Service
public class AppSettingService {

	private final AppSettingRepository appSettingRepository;

	public AppSettingService(AppSettingRepository appSettingRepository) {
		this.appSettingRepository = appSettingRepository;
	}

	@Transactional(readOnly = true)
	public List<AppSettingResponse> all() {
		return appSettingRepository.findAll().stream()
			.sorted((a, b) -> a.getKey().compareToIgnoreCase(b.getKey()))
			.map(this::toResponse)
			.toList();
	}

	@Transactional
	public AppSettingResponse upsert(AppSettingUpsertRequest request, AuthPrincipal principal) {
		String key = normalizeKey(request.key());
		AppSettingEntity setting = appSettingRepository.findById(key)
			.orElseGet(() -> new AppSettingEntity(key, request.value().trim(), trim(request.description()), principal.userId()));
		setting.update(request.value().trim(), trim(request.description()), principal.userId());
		return toResponse(appSettingRepository.save(setting));
	}

	private AppSettingResponse toResponse(AppSettingEntity setting) {
		return new AppSettingResponse(
			setting.getKey(),
			setting.getValue(),
			setting.getDescription(),
			setting.getUpdatedByAccountId(),
			setting.getUpdatedAt()
		);
	}

	private String normalizeKey(String key) {
		String normalized = key.trim().toLowerCase().replaceAll("[^a-z0-9_.-]+", "-");
		if (normalized.isBlank()) {
			throw new IllegalArgumentException("Setting key is required.");
		}
		return normalized;
	}

	private String trim(String value) {
		return value == null ? "" : value.trim();
	}
}
