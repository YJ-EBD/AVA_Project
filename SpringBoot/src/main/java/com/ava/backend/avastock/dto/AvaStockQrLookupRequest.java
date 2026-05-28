package com.ava.backend.avastock.dto;

import jakarta.validation.constraints.NotBlank;

public record AvaStockQrLookupRequest(@NotBlank String qrValue) {
}
