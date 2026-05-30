package com.ava.backend.calendar;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public record CalendarAiWorkspaceResponse(
	boolean handled,
	boolean mutation,
	boolean requiresClarification,
	String mode,
	String status,
	String selectedEventId,
	Summary summary,
	List<EventCard> events,
	List<CalendarDtos.ConflictResponse> conflicts,
	List<CalendarDtos.AvailabilitySuggestion> availability,
	Map<String, Object> metadata
) {
	public static CalendarAiWorkspaceResponse empty() {
		return new CalendarAiWorkspaceResponse(
			false,
			false,
			false,
			"",
			"",
			"",
			null,
			List.of(),
			List.of(),
			List.of(),
			Map.of()
		);
	}

	public record Summary(
		String title,
		Instant rangeStart,
		Instant rangeEnd,
		long totalCount,
		Map<String, Long> countsByStatus
	) {
	}

	public record EventCard(
		UUID id,
		String title,
		String description,
		Instant startAt,
		Instant endAt,
		boolean allDay,
		String location,
		String status,
		String statusLabel,
		String categoryName,
		String teamId,
		String teamLabel,
		String importance,
		String importanceLabel,
		String color,
		boolean hasAzoom,
		boolean hasChat,
		boolean hasFiles,
		boolean hasNotion,
		String memo
	) {
	}
}
