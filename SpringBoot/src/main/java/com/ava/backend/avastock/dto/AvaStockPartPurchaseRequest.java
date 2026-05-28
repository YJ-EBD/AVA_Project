package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.Min;

public record AvaStockPartPurchaseRequest(
	String qrValue,
	@Min(1) int quantity,
	String memo
) {
}
