package com.ava.backend.azoom.dto;

public record AzoomVoiceStatusRequest(
	Boolean muted,
	Boolean deafened,
	Boolean cameraEnabled,
	Boolean screenSharing
) {
}
