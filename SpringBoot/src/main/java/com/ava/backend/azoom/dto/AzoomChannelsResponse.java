package com.ava.backend.azoom.dto;

import java.util.List;

public record AzoomChannelsResponse(
	String companyName,
	boolean liveKitEnabled,
	String liveKitUrl,
	List<AzoomVoiceChannelResponse> voiceChannels
) {
}
