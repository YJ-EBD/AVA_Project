package com.ava.backend.calendar;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.auth.security.AuthPrincipal;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/calendar")
public class CalendarController {
	private final CalendarService calendarService;

	public CalendarController(CalendarService calendarService) {
		this.calendarService = calendarService;
	}

	@GetMapping("/events")
	public List<CalendarDtos.EventResponse> events(
		@RequestParam(value = "startAt", required = false) Instant startAt,
		@RequestParam(value = "endAt", required = false) Instant endAt,
		@RequestParam(value = "categoryId", required = false) UUID categoryId,
		@RequestParam(value = "status", required = false) CalendarEventStatus status,
		@RequestParam(value = "query", required = false) String query,
		@RequestParam(value = "page", required = false) Integer page,
		@RequestParam(value = "size", required = false) Integer size,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.events(startAt, endAt, categoryId, status, query, page, size, principal);
	}

	@GetMapping("/events/{id}")
	public CalendarDtos.EventResponse event(@PathVariable UUID id, @AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.event(id, principal);
	}

	@PostMapping("/events")
	public CalendarDtos.EventResponse createEvent(
		@Valid @RequestBody CalendarDtos.EventRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.create(request, principal);
	}

	@PatchMapping("/events/{id}")
	public CalendarDtos.EventResponse updateEvent(
		@PathVariable UUID id,
		@Valid @RequestBody CalendarDtos.EventPatchRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.update(id, request, principal);
	}

	@DeleteMapping("/events/{id}")
	public void deleteEvent(
		@PathVariable UUID id,
		@RequestParam(value = "recurrenceDeleteScope", required = false) String recurrenceDeleteScope,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		calendarService.delete(id, recurrenceDeleteScope, principal);
	}

	@GetMapping("/categories")
	public List<CalendarDtos.CategoryResponse> categories(@AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.categories(principal);
	}

	@PostMapping("/categories")
	public CalendarDtos.CategoryResponse createCategory(
		@Valid @RequestBody CalendarDtos.CategoryRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.createCategory(request, principal);
	}

	@PatchMapping("/categories/{id}")
	public CalendarDtos.CategoryResponse updateCategory(
		@PathVariable UUID id,
		@Valid @RequestBody CalendarDtos.CategoryRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.updateCategory(id, request, principal);
	}

	@DeleteMapping("/categories/{id}")
	public void deleteCategory(@PathVariable UUID id, @AuthenticationPrincipal AuthPrincipal principal) {
		calendarService.deleteCategory(id, principal);
	}

	@PostMapping("/events/{id}/attendees")
	public CalendarDtos.AttendeeResponse addAttendee(
		@PathVariable UUID id,
		@Valid @RequestBody CalendarDtos.AttendeeRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.addAttendee(id, request, principal);
	}

	@PatchMapping("/events/{id}/attendees/{attendeeId}")
	public CalendarDtos.AttendeeResponse updateAttendee(
		@PathVariable UUID id,
		@PathVariable UUID attendeeId,
		@Valid @RequestBody CalendarDtos.AttendeeRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.updateAttendee(id, attendeeId, request, principal);
	}

	@DeleteMapping("/events/{id}/attendees/{attendeeId}")
	public void deleteAttendee(@PathVariable UUID id, @PathVariable UUID attendeeId, @AuthenticationPrincipal AuthPrincipal principal) {
		calendarService.deleteAttendee(id, attendeeId, principal);
	}

	@PostMapping("/events/{id}/reminders")
	public CalendarDtos.ReminderResponse addReminder(
		@PathVariable UUID id,
		@Valid @RequestBody CalendarDtos.ReminderRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.addReminder(id, request, principal);
	}

	@DeleteMapping("/events/{id}/reminders/{reminderId}")
	public void deleteReminder(@PathVariable UUID id, @PathVariable UUID reminderId, @AuthenticationPrincipal AuthPrincipal principal) {
		calendarService.deleteReminder(id, reminderId, principal);
	}

	@PostMapping("/events/{id}/files")
	public CalendarDtos.FileLinkResponse addFile(@PathVariable UUID id, @Valid @RequestBody CalendarDtos.FileLinkRequest request, @AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.addFile(id, request, principal);
	}

	@DeleteMapping("/events/{id}/files/{fileLinkId}")
	public void deleteFile(@PathVariable UUID id, @PathVariable UUID fileLinkId, @AuthenticationPrincipal AuthPrincipal principal) {
		calendarService.deleteFile(id, fileLinkId, principal);
	}

	@PostMapping("/events/{id}/notion-links")
	public CalendarDtos.NotionLinkResponse addNotion(@PathVariable UUID id, @Valid @RequestBody CalendarDtos.NotionLinkRequest request, @AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.addNotion(id, request, principal);
	}

	@DeleteMapping("/events/{id}/notion-links/{linkId}")
	public void deleteNotion(@PathVariable UUID id, @PathVariable UUID linkId, @AuthenticationPrincipal AuthPrincipal principal) {
		calendarService.deleteNotion(id, linkId, principal);
	}

	@PostMapping("/events/{id}/chat-links")
	public CalendarDtos.ChatLinkResponse addChat(@PathVariable UUID id, @Valid @RequestBody CalendarDtos.ChatLinkRequest request, @AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.addChat(id, request, principal);
	}

	@DeleteMapping("/events/{id}/chat-links/{linkId}")
	public void deleteChat(@PathVariable UUID id, @PathVariable UUID linkId, @AuthenticationPrincipal AuthPrincipal principal) {
		calendarService.deleteChat(id, linkId, principal);
	}

	@PostMapping("/events/{id}/azoom-links")
	public CalendarDtos.AzoomLinkResponse addAzoom(@PathVariable UUID id, @Valid @RequestBody CalendarDtos.AzoomLinkRequest request, @AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.addAzoom(id, request, principal);
	}

	@DeleteMapping("/events/{id}/azoom-links/{linkId}")
	public void deleteAzoom(@PathVariable UUID id, @PathVariable UUID linkId, @AuthenticationPrincipal AuthPrincipal principal) {
		calendarService.deleteAzoom(id, linkId, principal);
	}

	@PostMapping("/conflicts/check")
	public CalendarDtos.ConflictCheckResponse checkConflicts(
		@Valid @RequestBody CalendarDtos.ConflictCheckRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.checkConflicts(request, principal);
	}

	@PostMapping("/availability/suggest")
	public List<CalendarDtos.AvailabilitySuggestion> suggestAvailability(
		@Valid @RequestBody CalendarDtos.AvailabilityRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.suggestAvailability(request, principal);
	}

	@GetMapping("/summary/today")
	public CalendarDtos.CalendarSummaryResponse today(@AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.today(principal);
	}

	@GetMapping("/summary/week")
	public CalendarDtos.CalendarSummaryResponse week(@AuthenticationPrincipal AuthPrincipal principal) {
		return calendarService.week(principal);
	}

	@GetMapping("/search")
	public List<CalendarDtos.EventResponse> search(
		@RequestParam("query") String query,
		@RequestParam(value = "startAt", required = false) Instant startAt,
		@RequestParam(value = "endAt", required = false) Instant endAt,
		@RequestParam(value = "page", required = false) Integer page,
		@RequestParam(value = "size", required = false) Integer size,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarService.events(startAt, endAt, null, null, query, page, size, principal);
	}

	@GetMapping("/tools")
	public List<Map<String, Object>> tools() {
		return calendarService.toolSpecs();
	}
}
