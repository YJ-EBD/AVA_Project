package com.ava.backend.azoom.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.azoom.entity.AzoomChannelEntity;
import com.ava.backend.azoom.entity.AzoomChannelType;

public interface AzoomChannelRepository extends JpaRepository<AzoomChannelEntity, UUID> {
	List<AzoomChannelEntity> findByWorkspace_IdAndTypeAndArchivedFalseOrderBySortOrderAscNameAsc(
		UUID workspaceId,
		AzoomChannelType type
	);

	Optional<AzoomChannelEntity> findByWorkspace_IdAndChannelIdAndArchivedFalse(UUID workspaceId, String channelId);

	boolean existsByWorkspace_IdAndChannelId(UUID workspaceId, String channelId);
}
