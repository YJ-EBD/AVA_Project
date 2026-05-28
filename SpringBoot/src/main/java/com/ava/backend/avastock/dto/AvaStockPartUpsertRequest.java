package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.NotBlank;

public record AvaStockPartUpsertRequest(
	@NotBlank String partCode,
	@NotBlank String partName,
	String unit,
	String imageUrl,
	String description,
	Boolean active
) {
}
