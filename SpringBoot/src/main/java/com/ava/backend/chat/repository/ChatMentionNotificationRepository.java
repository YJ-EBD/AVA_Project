package com.ava.backend.chat.repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.chat.entity.ChatMentionNotificationEntity;

public interface ChatMentionNotificationRepository extends JpaRepository<ChatMentionNotificationEntity, UUID> {

	List<ChatMentionNotificationEntity> findByMentionedAccount_IdOrderByCreatedAtDesc(
		UUID mentionedAccountId,
		Pageable pageable
	);

	List<ChatMentionNotificationEntity> findByMentionedAccount_IdAndCheckedAtIsNullOrderByCreatedAtDesc(
		UUID mentionedAccountId,
		Pageable pageable
	);

	List<ChatMentionNotificationEntity> findByMentionedAccount_IdAndCheckedAtIsNotNullOrderByCreatedAtDesc(
		UUID mentionedAccountId,
		Pageable pageable
	);

	long countByMentionedAccount_IdAndCheckedAtIsNull(UUID mentionedAccountId);

	boolean existsByMessage_IdAndMentionedAccount_Id(UUID messageId, UUID mentionedAccountId);

	Optional<ChatMentionNotificationEntity> findByIdAndMentionedAccount_Id(UUID id, UUID mentionedAccountId);

	List<ChatMentionNotificationEntity> findByMessage_IdInAndMentionedAccount_Id(
		Collection<UUID> messageIds,
		UUID mentionedAccountId
	);
}
