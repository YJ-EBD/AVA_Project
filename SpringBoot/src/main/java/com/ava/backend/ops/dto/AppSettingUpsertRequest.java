package com.ava.backend.ops.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record AppSettingUpsertRequest(
	@NotBlank @Size(max = 120) String key,
	@NotBlank @Size(max = 2000) String value,
	@Size(max = 400) String description
) {
}
