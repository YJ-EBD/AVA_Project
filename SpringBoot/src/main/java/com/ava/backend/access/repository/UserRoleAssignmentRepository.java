package com.ava.backend.access.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.access.entity.UserRoleAssignmentEntity;

public interface UserRoleAssignmentRepository extends JpaRepository<UserRoleAssignmentEntity, UUID> {
	List<UserRoleAssignmentEntity> findByAccount_Id(UUID accountId);

	void deleteByAccount_Id(UUID accountId);
}
