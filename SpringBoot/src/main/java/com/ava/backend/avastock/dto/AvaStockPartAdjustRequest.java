package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.NotBlank;

public record AvaStockPartAdjustRequest(
	int quantity,
	@NotBlank String reason
) {
}
