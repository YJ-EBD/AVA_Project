package com.ava.backend.azoom.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.azoom.entity.AzoomMemberEntity;

public interface AzoomMemberRepository extends JpaRepository<AzoomMemberEntity, UUID> {
	List<AzoomMemberEntity> findByWorkspace_IdOrderByJoinedAtAsc(UUID workspaceId);

	Optional<AzoomMemberEntity> findByWorkspace_IdAndAccount_Id(UUID workspaceId, UUID accountId);

	boolean existsByWorkspace_IdAndAccount_Id(UUID workspaceId, UUID accountId);
}
