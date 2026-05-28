package com.ava.backend.push.dto;

public record MobilePushDeviceHeartbeatResponse(
	boolean enabled,
	String transport
) {
}
