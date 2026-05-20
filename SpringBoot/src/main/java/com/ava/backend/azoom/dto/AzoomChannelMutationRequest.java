package com.ava.backend.azoom.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record AzoomChannelMutationRequest(
	@Pattern(regexp = "TEXT|VOICE") String type,
	@NotBlank @Size(max = 120) String name,
	@Size(max = 60) String channelId,
	Integer sortOrder
) {
}
