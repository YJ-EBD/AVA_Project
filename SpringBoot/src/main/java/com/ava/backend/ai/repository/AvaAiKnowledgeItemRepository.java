package com.ava.backend.ai.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ai.entity.AvaAiKnowledgeItemEntity;

public interface AvaAiKnowledgeItemRepository extends JpaRepository<AvaAiKnowledgeItemEntity, UUID> {

	List<AvaAiKnowledgeItemEntity> findByCompanyNameIgnoreCaseAndEnabledTrue(
		String companyName
	);
}
