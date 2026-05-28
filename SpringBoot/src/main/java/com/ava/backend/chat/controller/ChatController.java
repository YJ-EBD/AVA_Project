package com.ava.backend.chat.controller;

import java.util.List;
import java.util.UUID;

import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.chat.dto.ChatMessageRequest;
import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.dto.ChatMentionNotificationResponse;
import com.ava.backend.chat.dto.ChatLinkPreviewResponse;
import com.ava.backend.chat.dto.ChatNoticeRequest;
import com.ava.backend.chat.dto.ChatPinRequest;
import com.ava.backend.chat.dto.ChatReadStateResponse;
import com.ava.backend.chat.dto.ChatRealtimeEvent;
import com.ava.backend.chat.dto.ChatRoomLeaveResponse;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.chat.dto.ChatTalkDrawerItemResponse;
import com.ava.backend.chat.dto.DirectChatRoomRequest;
import com.ava.backend.chat.dto.GroupChatRoomRequest;
import com.ava.backend.chat.service.ChatService;
import com.ava.backend.chat.service.ChatLinkPreviewService;
import com.ava.backend.push.service.MobilePushService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/chat")
public class ChatController {

	private final ChatService chatService;
	private final ChatLinkPreviewService linkPreviewService;
	private final SimpMessagingTemplate messagingTemplate;
	private final MobilePushService mobilePushService;

	public ChatController(
		ChatService chatService,
		ChatLinkPreviewService linkPreviewService,
		SimpMessagingTemplate messagingTemplate,
		MobilePushService mobilePushService
	) {
		this.chatService = chatService;
		this.linkPreviewService = linkPreviewService;
		this.messagingTemplate = messagingTemplate;
		this.mobilePushService = mobilePushService;
	}

	@GetMapping("/rooms")
	public List<ChatRoomResponse> rooms(@AuthenticationPrincipal AuthPrincipal principal) {
		return chatService.rooms(principal);
	}

	@GetMapping("/link-preview")
	public ChatLinkPreviewResponse linkPreview(
		@RequestParam("url") String url,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return linkPreviewService.preview(url);
	}

	@PostMapping("/direct-rooms")
	public ChatRoomResponse directRoom(
		@Valid @RequestBody DirectChatRoomRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		ChatRoomResponse response = chatService.startDirectRoom(request, principal);
		publishRoomState(response);
		return response;
	}

	@PostMapping("/group-rooms")
	public ChatRoomResponse groupRoom(
		@Valid @RequestBody GroupChatRoomRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		ChatRoomResponse response = chatService.startGroupRoom(request, principal);
		publishRoomState(response);
		return response;
	}

	@PostMapping("/self-room")
	public ChatRoomResponse selfRoom(@AuthenticationPrincipal AuthPrincipal principal) {
		ChatRoomResponse response = chatService.startSelfRoom(principal);
		publishRoomState(response);
		return response;
	}

	@PostMapping("/rooms/{roomCode}/members")
	public ChatRoomResponse inviteMembers(
		@PathVariable String roomCode,
		@Valid @RequestBody GroupChatRoomRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		ChatRoomResponse response = chatService.inviteMembers(roomCode, request, principal);
		publishRoomState(response);
		return response;
	}

	@GetMapping("/rooms/{roomCode}/messages")
	public List<ChatMessageResponse> messages(
		@PathVariable String roomCode,
		@RequestParam(value = "limit", required = false, defaultValue = "80") int limit,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		return chatService.recentMessages(roomCode, principal, limit);
	}

	@GetMapping("/rooms/{roomCode}/messages/around/{messageId}")
	public List<ChatMessageResponse> messagesAround(
		@PathVariable String roomCode,
		@PathVariable UUID messageId,
		@RequestParam(value = "before", required = false, defaultValue = "40") int before,
		@RequestParam(value = "after", required = false, defaultValue = "40") int after,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		return chatService.messagesAround(roomCode, messageId, principal, before, after);
	}

	@GetMapping("/rooms/{roomCode}/messages/before/{messageId}")
	public List<ChatMessageResponse> messagesBefore(
		@PathVariable String roomCode,
		@PathVariable UUID messageId,
		@RequestParam(value = "limit", required = false, defaultValue = "80") int limit,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		return chatService.messagesBefore(roomCode, messageId, principal, limit);
	}

	@PostMapping("/rooms/{roomCode}/messages")
	public ChatMessageResponse send(
		@PathVariable String roomCode,
		@Valid @RequestBody ChatMessageRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		ChatMessageResponse response = chatService.send(roomCode, request, principal);
		messagingTemplate.convertAndSend("/topic/rooms/" + roomCode, response);
		publishRoomEvent(roomCode, response);
		mobilePushService.sendChatMessage(roomCode, response);
		return response;
	}

	@PostMapping(
		value = "/rooms/{roomCode}/attachments",
		consumes = MediaType.MULTIPART_FORM_DATA_VALUE
	)
	public ChatMessageResponse sendAttachment(
		@PathVariable String roomCode,
		@RequestParam("file") MultipartFile file,
		@RequestParam(value = "groupId", required = false) String groupId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		ChatMessageResponse response = chatService.sendAttachment(roomCode, file, groupId, principal);
		messagingTemplate.convertAndSend("/topic/rooms/" + roomCode, response);
		publishRoomEvent(roomCode, response);
		mobilePushService.sendChatMessage(roomCode, response);
		return response;
	}

	@GetMapping("/rooms/{roomCode}/attachments/{attachmentId}")
	public ResponseEntity<Resource> downloadAttachment(
		@PathVariable String roomCode,
		@PathVariable String attachmentId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		ChatService.AttachmentDownload download = chatService.attachment(roomCode, attachmentId, principal);
		return ResponseEntity.ok()
			.header(
				HttpHeaders.CONTENT_DISPOSITION,
				ContentDisposition.attachment()
					.filename(download.fileName(), java.nio.charset.StandardCharsets.UTF_8)
					.build()
					.toString()
			)
			.contentType(MediaType.parseMediaType(download.contentType()))
			.contentLength(download.size())
			.body(download.resource());
	}

	@PostMapping("/rooms/{roomCode}/messages/{messageId}/delete-for-everyone")
	public ChatMessageResponse deleteMessageForEveryone(
		@PathVariable String roomCode,
		@PathVariable UUID messageId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		ChatMessageResponse response = chatService.deleteMessageForEveryone(roomCode, messageId, principal);
		messagingTemplate.convertAndSend("/topic/rooms/" + roomCode, response);
		publishRoomEvent(roomCode, response);
		return response;
	}

	@GetMapping("/rooms/{roomCode}/talk-drawer")
	public List<ChatTalkDrawerItemResponse> talkDrawer(
		@PathVariable String roomCode,
		@RequestParam(value = "type", required = false) String type,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		return chatService.talkDrawerItems(roomCode, type, principal);
	}

	@PostMapping("/rooms/{roomCode}/read")
	public ChatReadStateResponse markRead(
		@PathVariable String roomCode,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		ChatReadStateResponse response = chatService.markRead(roomCode, principal);
		publishReadState(roomCode, response);
		return response;
	}

	@GetMapping("/mention-notifications")
	public List<ChatMentionNotificationResponse> mentionNotifications(
		@RequestParam(value = "status", required = false, defaultValue = "all") String status,
		@RequestParam(value = "limit", required = false, defaultValue = "80") int limit,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return chatService.mentionNotifications(status, principal, limit);
	}

	@PostMapping("/mention-notifications/{notificationId}/checked")
	public ChatMentionNotificationResponse markMentionNotificationChecked(
		@PathVariable UUID notificationId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return chatService.markMentionNotificationChecked(notificationId, principal);
	}

	@PostMapping("/rooms/{roomCode}/leave")
	public ChatRoomLeaveResponse leave(
		@PathVariable String roomCode,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		ChatRoomLeaveResponse response = chatService.leaveRoom(roomCode, principal);
		if (response.deleted()) {
			publishRoomDeleted(response);
			return response;
		}

		messagingTemplate.convertAndSend("/topic/rooms/" + roomCode, response.message());
		publishRoomEvent(response.room(), response.message());
		return response;
	}

	private void publishRoomEvent(String roomCode, ChatMessageResponse message) {
		ChatRoomResponse room = chatService.room(roomCode);
		publishRoomEvent(room, message);
	}

	private void publishRoomEvent(ChatRoomResponse room, ChatMessageResponse message) {
		for (var member : room.members()) {
			ChatRoomResponse recipientRoom = member.id() == null
				? room
				: chatService.roomForMember(room.code(), member.id());
			ChatRealtimeEvent event = new ChatRealtimeEvent("message", recipientRoom, message);
			messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", event);
		}
	}

	private void publishRoomState(ChatRoomResponse room) {
		for (var member : room.members()) {
			ChatRoomResponse recipientRoom = member.id() == null
				? room
				: chatService.roomForMember(room.code(), member.id());
			ChatRealtimeEvent event = new ChatRealtimeEvent("room", recipientRoom, null);
			messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", event);
		}
	}

	private void publishRoomDeleted(ChatRoomLeaveResponse response) {
		ChatRealtimeEvent event = new ChatRealtimeEvent("room-deleted", response.room(), response.message());
		for (var member : response.room().members()) {
			if (!member.email().equalsIgnoreCase(response.leaverEmail())) {
				messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", event);
			}
		}
	}

	private void publishReadState(String roomCode, ChatReadStateResponse readState) {
		messagingTemplate.convertAndSend("/topic/rooms/" + roomCode + "/read-state", readState);
	}

	@PutMapping("/rooms/{roomCode}/notice")
	public ChatRoomResponse setNotice(
		@PathVariable String roomCode,
		@Valid @RequestBody ChatNoticeRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		return chatService.setNotice(roomCode, request, principal);
	}

	@PutMapping("/rooms/{roomCode}/pin")
	public ChatRoomResponse setPinned(
		@PathVariable String roomCode,
		@RequestBody ChatPinRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		assertRegularChatRoomCode(roomCode);
		return chatService.setPinned(roomCode, request, principal);
	}

	private void assertRegularChatRoomCode(String roomCode) {
		if (chatService.isAzoomRoomCode(roomCode)) {
			throw new IllegalArgumentException("AZOOM text chat rooms are no longer supported.");
		}
	}
}
