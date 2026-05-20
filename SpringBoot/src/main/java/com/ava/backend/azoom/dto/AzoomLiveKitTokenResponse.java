package com.ava.backend.azoom.dto;

public record AzoomLiveKitTokenResponse(
	boolean enabled,
	String url,
	String token,
	String roomName,
	String reason
) {
	public static AzoomLiveKitTokenResponse disabled(String roomName, String reason) {
		return new AzoomLiveKitTokenResponse(false, "", "", roomName, reason);
	}
}
