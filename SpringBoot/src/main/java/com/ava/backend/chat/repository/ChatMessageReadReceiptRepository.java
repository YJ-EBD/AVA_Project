package com.ava.backend.chat.repository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.chat.entity.ChatMessageReadReceiptEntity;

public interface ChatMessageReadReceiptRepository extends JpaRepository<ChatMessageReadReceiptEntity, UUID> {

	List<ChatMessageReadReceiptEntity> findByMessage_IdInAndAccountId(Collection<UUID> messageIds, UUID accountId);

	List<ChatMessageReadReceiptEntity> findByMessage_IdInAndAccountIdIn(
		Collection<UUID> messageIds,
		Collection<UUID> accountIds
	);

	List<ChatMessageReadReceiptEntity> findByRoomCode(String roomCode);

	long countByMessage_Id(UUID messageId);

	long countByMessage_IdAndAccountIdIn(UUID messageId, Collection<UUID> accountIds);

	boolean existsByMessage_IdAndAccountId(UUID messageId, UUID accountId);

	long deleteByRoomCode(String roomCode);
}
