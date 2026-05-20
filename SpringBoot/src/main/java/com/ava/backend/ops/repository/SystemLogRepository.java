package com.ava.backend.ops.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ops.entity.SystemLogEntity;

public interface SystemLogRepository extends JpaRepository<SystemLogEntity, UUID> {
	List<SystemLogEntity> findTop200ByOrderByCreatedAtDesc();
}
