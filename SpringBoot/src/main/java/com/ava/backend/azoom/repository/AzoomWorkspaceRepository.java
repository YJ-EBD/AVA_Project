package com.ava.backend.azoom.repository;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.azoom.entity.AzoomWorkspaceEntity;

public interface AzoomWorkspaceRepository extends JpaRepository<AzoomWorkspaceEntity, UUID> {
	Optional<AzoomWorkspaceEntity> findByCompanySlug(String companySlug);
}
