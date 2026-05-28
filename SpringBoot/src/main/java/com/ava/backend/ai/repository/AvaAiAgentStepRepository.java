package com.ava.backend.ai.repository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ai.entity.AvaAiAgentStepEntity;

public interface AvaAiAgentStepRepository extends JpaRepository<AvaAiAgentStepEntity, UUID> {

	List<AvaAiAgentStepEntity> findByTaskIdOrderByStepIndexAsc(UUID taskId);

	void deleteByTaskIdIn(Collection<UUID> taskIds);
}
