package com.ava.backend.update.repository;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.update.entity.AppUpdateReleaseEntity;

public interface AppUpdateReleaseRepository extends JpaRepository<AppUpdateReleaseEntity, UUID> {

	Optional<AppUpdateReleaseEntity> findByPlatformAndVersion(String platform, String version);
}
