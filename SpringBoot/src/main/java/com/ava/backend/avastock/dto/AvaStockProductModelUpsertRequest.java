package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.NotBlank;

public record AvaStockProductModelUpsertRequest(
	@NotBlank String modelCode,
	@NotBlank String modelName,
	String description,
	String imageUrl,
	Boolean active
) {
}
