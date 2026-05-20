package com.ava.backend.azoom.dto;

public record AzoomVoiceJoinResponse(
	AzoomVoiceChannelResponse channel,
	AzoomLiveKitTokenResponse liveKit
) {
}
