package com.ava.backend.ai.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ai.entity.AvaAiAgentTaskEntity;

public interface AvaAiAgentTaskRepository extends JpaRepository<AvaAiAgentTaskEntity, UUID> {

	Optional<AvaAiAgentTaskEntity> findTopByConversationIdOrderByUpdatedAtDesc(UUID conversationId);

	List<AvaAiAgentTaskEntity> findTop8ByConversationIdOrderByUpdatedAtDesc(UUID conversationId);

	List<AvaAiAgentTaskEntity> findByConversationId(UUID conversationId);

	void deleteByConversationId(UUID conversationId);
}
