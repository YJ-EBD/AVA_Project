package com.ava.backend.chat.repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.chat.entity.ChatMessageEntity;

public interface ChatMessageJpaRepository extends JpaRepository<ChatMessageEntity, UUID> {

	List<ChatMessageEntity> findTop50ByRoomCodeOrderBySentAtDesc(String roomCode);

	List<ChatMessageEntity> findTop50ByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtDesc(
		String roomCode,
		Instant sentAt
	);

	List<ChatMessageEntity> findByRoomCodeOrderBySentAtAsc(String roomCode);

	List<ChatMessageEntity> findByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtAsc(String roomCode, Instant sentAt);

	Optional<ChatMessageEntity> findByRoomCodeAndAttachmentId(String roomCode, String attachmentId);

	long deleteByRoomCode(String roomCode);
}
