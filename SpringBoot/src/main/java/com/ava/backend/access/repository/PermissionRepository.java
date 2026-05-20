package com.ava.backend.access.repository;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.access.entity.PermissionEntity;

public interface PermissionRepository extends JpaRepository<PermissionEntity, UUID> {
	boolean existsByCode(String code);
}
