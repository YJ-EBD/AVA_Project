package com.ava.backend.ai.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ai.entity.AvaAiMessageEntity;

public interface AvaAiMessageRepository extends JpaRepository<AvaAiMessageEntity, UUID> {

	boolean existsByConversationId(UUID conversationId);

	List<AvaAiMessageEntity> findTop200ByConversationIdOrderByCreatedAtDesc(UUID conversationId);

	List<AvaAiMessageEntity> findTop24ByConversationIdOrderByCreatedAtDesc(UUID conversationId);
}
