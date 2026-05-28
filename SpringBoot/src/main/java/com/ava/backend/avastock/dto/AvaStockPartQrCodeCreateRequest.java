package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.NotBlank;

public record AvaStockPartQrCodeCreateRequest(
	@NotBlank String qrValue,
	String label,
	String locationCode
) {
}
