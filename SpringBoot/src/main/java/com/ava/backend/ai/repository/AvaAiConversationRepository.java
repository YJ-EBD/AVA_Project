package com.ava.backend.ai.repository;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ai.entity.AvaAiConversationEntity;

public interface AvaAiConversationRepository extends JpaRepository<AvaAiConversationEntity, UUID> {

	Optional<AvaAiConversationEntity> findByAccountId(UUID accountId);

	Optional<AvaAiConversationEntity> findByAccountIdAndCompanyNameIgnoreCase(UUID accountId, String companyName);
}
