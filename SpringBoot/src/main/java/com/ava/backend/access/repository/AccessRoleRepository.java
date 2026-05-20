package com.ava.backend.access.repository;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.access.entity.AccessRoleEntity;

public interface AccessRoleRepository extends JpaRepository<AccessRoleEntity, UUID> {
	boolean existsByCode(String code);
}
