package com.ava.backend.azoom.dto;

public record AzoomNotivaAudioResponse(
	String sourceFileName,
	AzoomMeetingTranscriptResponse transcript
) {
}
