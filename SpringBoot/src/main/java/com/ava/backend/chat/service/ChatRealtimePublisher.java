package com.ava.backend.chat.service;

import java.util.concurrent.Executor;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.dto.ChatReadStateResponse;
import com.ava.backend.chat.dto.ChatRealtimeEvent;
import com.ava.backend.chat.dto.ChatRoomLeaveResponse;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.push.service.MobilePushService;

@Service
public class ChatRealtimePublisher {

	private static final Logger log = LoggerFactory.getLogger(ChatRealtimePublisher.class);

	private final ChatService chatService;
	private final SimpMessagingTemplate messagingTemplate;
	private final MobilePushService mobilePushService;
	private final Executor chatRealtimeEventExecutor;

	public ChatRealtimePublisher(
		ChatService chatService,
		SimpMessagingTemplate messagingTemplate,
		MobilePushService mobilePushService,
		@Qualifier("chatRealtimeEventExecutor") Executor chatRealtimeEventExecutor
	) {
		this.chatService = chatService;
		this.messagingTemplate = messagingTemplate;
		this.mobilePushService = mobilePushService;
		this.chatRealtimeEventExecutor = chatRealtimeEventExecutor;
	}

	public void publishMessage(String roomCode, ChatMessageResponse message, boolean notifyMobile) {
		ChatRoomResponse room = chatService.room(roomCode);
		publishMessage(room, message, notifyMobile);
	}

	public void publishMessage(ChatRoomResponse room, ChatMessageResponse message, boolean notifyMobile) {
		ChatRealtimeEvent immediateEvent = new ChatRealtimeEvent("message", room, message);
		for (var member : room.members()) {
			messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", immediateEvent);
		}
		if (notifyMobile) {
			mobilePushService.sendChatMessage(room.code(), message);
		}
		chatRealtimeEventExecutor.execute(() -> publishRecipientRoomStateEvents(room));
	}

	public void publishRoomState(ChatRoomResponse room) {
		for (var member : room.members()) {
			ChatRoomResponse recipientRoom = member.id() == null
				? room
				: chatService.roomForMember(room.code(), member.id());
			ChatRealtimeEvent event = new ChatRealtimeEvent("room", recipientRoom, null);
			messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", event);
		}
	}

	public void publishRoomDeleted(ChatRoomLeaveResponse response) {
		ChatRealtimeEvent event = new ChatRealtimeEvent("room-deleted", response.room(), response.message());
		for (var member : response.room().members()) {
			if (!member.email().equalsIgnoreCase(response.leaverEmail())) {
				messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", event);
			}
		}
	}

	public void publishReadState(String roomCode, ChatReadStateResponse readState) {
		messagingTemplate.convertAndSend("/topic/rooms/" + roomCode + "/read-state", readState);
	}

	private void publishRecipientRoomStateEvents(ChatRoomResponse room) {
		try {
			for (var member : room.members()) {
				if (member.id() == null) {
					continue;
				}
				ChatRoomResponse recipientRoom = chatService.roomForMember(room.code(), member.id());
				ChatRealtimeEvent stateEvent = new ChatRealtimeEvent("room", recipientRoom, null);
				messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", stateEvent);
			}
		} catch (Exception exception) {
			log.warn("Failed to publish chat room state event for room {}: {}", room.code(), exception.getMessage());
		}
	}
}
