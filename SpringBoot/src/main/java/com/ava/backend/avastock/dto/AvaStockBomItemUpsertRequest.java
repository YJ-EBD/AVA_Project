package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

public record AvaStockBomItemUpsertRequest(
	@NotNull Long partId,
	String itemLabel,
	@Min(1) Integer defaultQty,
	@Min(1) Integer sortOrder,
	Boolean requiredFlag,
	Boolean active
) {
}
