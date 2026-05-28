package com.ava.backend.avastock.dto;

import java.time.LocalDate;
import java.util.List;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

public record AvaStockShipmentCreateRequest(
	@NotBlank String destinationName,
	String imei,
	@NotBlank String shippingMethod,
	LocalDate shippingDate,
	String shipmentStatus,
	@NotEmpty List<Long> productUnitIds
) {
}
