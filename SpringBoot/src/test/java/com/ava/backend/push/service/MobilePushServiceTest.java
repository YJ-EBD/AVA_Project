package com.ava.backend.push.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.entity.ChatRoomEntity;
import com.ava.backend.chat.entity.ChatRoomMemberEntity;
import com.ava.backend.chat.entity.ChatRoomType;
import com.ava.backend.chat.repository.ChatRoomMemberRepository;
import com.ava.backend.chat.repository.ChatRoomRepository;
import com.ava.backend.push.dto.MobilePushEventResponse;
import com.ava.backend.push.repository.MobilePushEventRepository;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.repository.UserAccountRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

class MobilePushServiceTest {

	private final MobilePushEventRepository eventRepository = mock(MobilePushEventRepository.class);
	private final ChatRoomMemberRepository memberRepository = mock(ChatRoomMemberRepository.class);
	private final ChatRoomRepository roomRepository = mock(ChatRoomRepository.class);
	private final UserAccountRepository userAccountRepository = mock(UserAccountRepository.class);
	private final SimpMessagingTemplate messagingTemplate = mock(SimpMessagingTemplate.class);
	private final MobilePushService service = new MobilePushService(
		eventRepository,
		memberRepository,
		roomRepository,
		userAccountRepository,
		messagingTemplate,
		new ObjectMapper()
	);

	@Test
	void chatPushIsSentBeforeBacklogSave() {
		String roomCode = "room-realtime-push";
		ChatRoomEntity room = new ChatRoomEntity(roomCode, "Realtime Room", ChatRoomType.DIRECT, false, "");
		UserAccount sender = new UserAccount("sender@example.test", "hash", "Sender", UserRole.USER);
		UserAccount receiver = new UserAccount("receiver@example.test", "hash", "Receiver", UserRole.USER);
		ChatMessageResponse message = ChatMessageResponse.local(
			roomCode,
			sender.getId(),
			sender.getDisplayName(),
			"hello now"
		);
		when(memberRepository.findByRoomCode(roomCode)).thenReturn(List.of(
			new ChatRoomMemberEntity(room, sender),
			new ChatRoomMemberEntity(room, receiver)
		));
		when(roomRepository.findByCode(roomCode)).thenReturn(Optional.of(room));
		when(eventRepository.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));

		service.sendChatMessage(roomCode, message);

		InOrder order = inOrder(messagingTemplate, eventRepository);
		order.verify(messagingTemplate).convertAndSendToUser(
			eq(receiver.getEmail()),
			eq("/queue/mobile-push"),
			any(MobilePushEventResponse.class)
		);
		order.verify(eventRepository).saveAll(any());

		ArgumentCaptor<MobilePushEventResponse> eventCaptor =
			ArgumentCaptor.forClass(MobilePushEventResponse.class);
		org.mockito.Mockito.verify(messagingTemplate).convertAndSendToUser(
			eq(receiver.getEmail()),
			eq("/queue/mobile-push"),
			eventCaptor.capture()
		);
		assertThat(eventCaptor.getValue().id()).isNotNull();
		assertThat(eventCaptor.getValue().createdAt()).isNotNull();
		assertThat(eventCaptor.getValue().body()).isEqualTo("hello now");
	}
}
