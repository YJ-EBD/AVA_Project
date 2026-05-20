package com.ava.backend.ops.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ops.entity.AuditLogEntity;

public interface AuditLogRepository extends JpaRepository<AuditLogEntity, UUID> {
	List<AuditLogEntity> findTop100ByOrderByCreatedAtDesc();
}
