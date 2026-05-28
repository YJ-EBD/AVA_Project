package com.ava.backend.push.dto;

import jakarta.validation.constraints.Size;

public record MobilePushDeviceHeartbeatRequest(
	@Size(max = 160)
	String deviceId,

	@Size(max = 40)
	String platform,

	@Size(max = 40)
	String appVersion
) {
}
