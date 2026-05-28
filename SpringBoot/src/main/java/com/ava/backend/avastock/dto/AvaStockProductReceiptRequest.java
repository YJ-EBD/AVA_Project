package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.NotBlank;

public record AvaStockProductReceiptRequest(
	@NotBlank String modelCode,
	@NotBlank String serialNo,
	@NotBlank String qrValue,
	String supplierName,
	String memo
) {
}
