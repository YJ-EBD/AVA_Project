package com.ava.backend.azoom.dto;

public record AzoomNotivaEventResponse(
	String type,
	String roomName,
	AzoomMeetingTranscriptResponse transcript
) {
}
