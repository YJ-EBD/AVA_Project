package com.ava.backend.chat.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.same;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.auth.service.LoginSessionService;
import com.ava.backend.auth.service.TokenService;
import com.ava.backend.chat.dto.ChatMessageRequest;
import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.dto.ChatRealtimeEvent;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.chat.entity.ChatRoomType;
import com.ava.backend.chat.service.ChatRealtimePublisher;
import com.ava.backend.chat.service.ChatService;
import com.ava.backend.push.service.MobilePushService;
import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.entity.UserRole;

class ChatWebSocketControllerTest {

	private final ChatService chatService = mock(ChatService.class);
	private final SimpMessagingTemplate messagingTemplate = mock(SimpMessagingTemplate.class);
	private final TokenService tokenService = mock(TokenService.class);
	private final LoginSessionService loginSessionService = mock(LoginSessionService.class);
	private final MobilePushService mobilePushService = mock(MobilePushService.class);
	private final ChatRealtimePublisher realtimePublisher = new ChatRealtimePublisher(
		chatService,
		messagingTemplate,
		mobilePushService,
		Runnable::run
	);

	private final ChatWebSocketController controller = new ChatWebSocketController(
		chatService,
		messagingTemplate,
		tokenService,
		loginSessionService,
		realtimePublisher
	);

	@Test
	void websocketSendCreatesMobilePushEvent() {
		String roomCode = "room-chat-push";
		AuthPrincipal principal = new AuthPrincipal(
			UUID.randomUUID(),
			"sender@example.test",
			"Sender",
			UserRole.USER,
			"session"
		);
		ChatMessageRequest request = new ChatMessageRequest("hello", false, false, List.of());
		ChatMessageResponse response = ChatMessageResponse.local(
			roomCode,
			principal.userId(),
			principal.displayName(),
			request.content()
		);
		when(chatService.send(eq(roomCode), same(request), same(principal))).thenReturn(response);
		when(chatService.room(roomCode)).thenReturn(room(roomCode));

		controller.send(roomCode, request, principal, null);

		verify(messagingTemplate).convertAndSend("/topic/rooms/" + roomCode, response);
		verify(mobilePushService).sendChatMessage(roomCode, response);
	}

	@Test
	void websocketSendPublishesRecipientSpecificUnreadRoomState() {
		String roomCode = "room-recipient-unread";
		UUID senderId = UUID.randomUUID();
		UUID receiverId = UUID.randomUUID();
		AuthPrincipal principal = new AuthPrincipal(
			senderId,
			"sender@example.test",
			"Sender",
			UserRole.USER,
			"session"
		);
		ChatMessageRequest request = new ChatMessageRequest("@Receiver hello", false, false, List.of());
		ChatMessageResponse response = ChatMessageResponse.local(
			roomCode,
			principal.userId(),
			principal.displayName(),
			request.content()
		);
		ChatRoomResponse baseRoom = room(
			roomCode,
			List.of(
				member(senderId, "sender@example.test", "Sender"),
				member(receiverId, "receiver@example.test", "Receiver")
			),
			0,
			false
		);
		ChatRoomResponse senderRoom = room(roomCode, baseRoom.members(), 0, false);
		ChatRoomResponse receiverRoom = room(roomCode, baseRoom.members(), 1, true);
		when(chatService.send(eq(roomCode), same(request), same(principal))).thenReturn(response);
		when(chatService.room(roomCode)).thenReturn(baseRoom);
		when(chatService.roomForMember(roomCode, senderId)).thenReturn(senderRoom);
		when(chatService.roomForMember(roomCode, receiverId)).thenReturn(receiverRoom);

		controller.send(roomCode, request, principal, null);

		InOrder order = inOrder(messagingTemplate, chatService, mobilePushService);
		order.verify(messagingTemplate).convertAndSend("/topic/rooms/" + roomCode, response);
		order.verify(chatService).room(roomCode);
		order.verify(messagingTemplate).convertAndSendToUser(
			eq("sender@example.test"),
			eq("/queue/chat-events"),
			any(ChatRealtimeEvent.class)
		);
		order.verify(messagingTemplate).convertAndSendToUser(
			eq("receiver@example.test"),
			eq("/queue/chat-events"),
			any(ChatRealtimeEvent.class)
		);
		order.verify(mobilePushService).sendChatMessage(roomCode, response);
		order.verify(chatService).roomForMember(roomCode, senderId);

		ArgumentCaptor<ChatRealtimeEvent> senderEvents = ArgumentCaptor.forClass(ChatRealtimeEvent.class);
		ArgumentCaptor<ChatRealtimeEvent> receiverEvents = ArgumentCaptor.forClass(ChatRealtimeEvent.class);
		verify(messagingTemplate, times(2)).convertAndSendToUser(
			eq("sender@example.test"),
			eq("/queue/chat-events"),
			senderEvents.capture()
		);
		verify(messagingTemplate, times(2)).convertAndSendToUser(
			eq("receiver@example.test"),
			eq("/queue/chat-events"),
			receiverEvents.capture()
		);
		assertThat(senderEvents.getAllValues()).extracting(ChatRealtimeEvent::type)
			.containsExactly("message", "room");
		assertThat(receiverEvents.getAllValues()).extracting(ChatRealtimeEvent::type)
			.containsExactly("message", "room");
		assertThat(senderEvents.getAllValues().get(1).room().unreadCount()).isZero();
		assertThat(senderEvents.getAllValues().get(1).room().mentioned()).isFalse();
		assertThat(receiverEvents.getAllValues().get(1).room().unreadCount()).isEqualTo(1);
		assertThat(receiverEvents.getAllValues().get(1).room().mentioned()).isTrue();
		assertThat(receiverEvents.getAllValues().get(0).message()).isSameAs(response);
		assertThat(receiverEvents.getAllValues().get(1).message()).isNull();
	}

	@Test
	void websocketSendPublishesTenThousandRealtimeEventsWithoutDroppingPushes() {
		String roomCode = "room-realtime-stress";
		UUID senderId = UUID.randomUUID();
		UUID receiverId = UUID.randomUUID();
		AuthPrincipal principal = new AuthPrincipal(
			senderId,
			"sender@example.test",
			"Sender",
			UserRole.USER,
			"session"
		);
		ChatMessageRequest request = new ChatMessageRequest("stress hello", false, false, List.of());
		ChatMessageResponse response = ChatMessageResponse.local(
			roomCode,
			principal.userId(),
			principal.displayName(),
			request.content()
		);
		ChatRoomResponse baseRoom = room(
			roomCode,
			List.of(
				member(senderId, "sender@example.test", "Sender"),
				member(receiverId, "receiver@example.test", "Receiver")
			),
			0,
			false
		);
		ChatRoomResponse senderRoom = room(roomCode, baseRoom.members(), 0, false);
		ChatRoomResponse receiverRoom = room(roomCode, baseRoom.members(), 1, false);
		when(chatService.send(eq(roomCode), same(request), same(principal))).thenReturn(response);
		when(chatService.room(roomCode)).thenReturn(baseRoom);
		when(chatService.roomForMember(roomCode, senderId)).thenReturn(senderRoom);
		when(chatService.roomForMember(roomCode, receiverId)).thenReturn(receiverRoom);

		for (int i = 0; i < 10_000; i++) {
			controller.send(roomCode, request, principal, null);
		}

		ArgumentCaptor<ChatRealtimeEvent> receiverEvents = ArgumentCaptor.forClass(ChatRealtimeEvent.class);
		verify(messagingTemplate, times(10_000)).convertAndSend(eq("/topic/rooms/" + roomCode), same(response));
		verify(messagingTemplate, times(20_000)).convertAndSendToUser(
			eq("receiver@example.test"),
			eq("/queue/chat-events"),
			receiverEvents.capture()
		);
		verify(chatService, times(10_000)).room(roomCode);
		verify(chatService, times(10_000)).roomForMember(roomCode, receiverId);
		verify(mobilePushService, times(10_000)).sendChatMessage(roomCode, response);

		assertThat(receiverEvents.getAllValues()).hasSize(20_000);
		assertThat(receiverEvents.getAllValues().stream().filter(event -> "message".equals(event.type())).count())
			.isEqualTo(10_000);
		assertThat(receiverEvents.getAllValues().stream().filter(event -> "room".equals(event.type())).count())
			.isEqualTo(10_000);
	}

	private ChatRoomResponse room(String roomCode) {
		return room(roomCode, List.of(), 0, false);
	}

	private ChatRoomResponse room(
		String roomCode,
		List<UserProfileResponse> members,
		int unreadCount,
		boolean mentioned
	) {
		return new ChatRoomResponse(
			roomCode,
			"Chat",
			ChatRoomType.GROUP,
			1,
			false,
			null,
			"hello",
			Instant.now(),
			false,
			"",
			null,
			members,
			unreadCount,
			mentioned
		);
	}

	private UserProfileResponse member(UUID id, String email, String name) {
		return new UserProfileResponse(
			id,
			email,
			name,
			name,
			"",
			"",
			email,
			"",
			UserRole.USER,
			"ABBA-S",
			"",
			"",
			null,
			"general",
			"#7AA06A",
			"",
			"",
			"#7AA06A",
			"",
			false
		);
	}
}
