package com.ava.backend.chat.repository;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.domain.Pageable;

import com.ava.backend.chat.entity.ChatMessageEntity;

public interface ChatMessageJpaRepository extends JpaRepository<ChatMessageEntity, UUID> {

	List<ChatMessageEntity> findTop50ByRoomCodeOrderBySentAtDesc(String roomCode);

	List<ChatMessageEntity> findByRoomCodeOrderBySentAtDesc(String roomCode, Pageable pageable);

	List<ChatMessageEntity> findTop50ByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtDesc(
		String roomCode,
		Instant sentAt
	);

	List<ChatMessageEntity> findByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtDesc(
		String roomCode,
		Instant sentAt,
		Pageable pageable
	);

	List<ChatMessageEntity> findByRoomCodeAndSentAtLessThanOrderBySentAtDesc(
		String roomCode,
		Instant sentAt,
		Pageable pageable
	);

	List<ChatMessageEntity> findByRoomCodeAndSentAtGreaterThanEqualAndSentAtLessThanOrderBySentAtDesc(
		String roomCode,
		Instant visibleSince,
		Instant sentAt,
		Pageable pageable
	);

	List<ChatMessageEntity> findByRoomCodeAndSentAtGreaterThanOrderBySentAtAsc(
		String roomCode,
		Instant sentAt,
		Pageable pageable
	);

	List<ChatMessageEntity> findByRoomCodeOrderBySentAtAsc(String roomCode);

	List<ChatMessageEntity> findByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtAsc(String roomCode, Instant sentAt);

	Optional<ChatMessageEntity> findByRoomCodeAndAttachmentId(String roomCode, String attachmentId);

	long deleteByRoomCode(String roomCode);

	long countByRoomCodeIn(Collection<String> roomCodes);
}
