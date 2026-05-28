package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.Min;

public record AvaStockBomVersionUpsertRequest(
	@Min(1) int versionNo,
	String versionName,
	Boolean currentVersion,
	Boolean active
) {
}
