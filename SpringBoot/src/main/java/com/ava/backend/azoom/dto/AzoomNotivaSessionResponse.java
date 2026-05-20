package com.ava.backend.azoom.dto;

public record AzoomNotivaSessionResponse(
	String roomName,
	AzoomMeetingTranscriptResponse realtimeTranscript
) {
}
