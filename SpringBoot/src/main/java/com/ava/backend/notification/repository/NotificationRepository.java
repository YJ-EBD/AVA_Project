package com.ava.backend.notification.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.notification.entity.NotificationEntity;

public interface NotificationRepository extends JpaRepository<NotificationEntity, UUID> {
	List<NotificationEntity> findTop50ByAccountIdOrderByCreatedAtDesc(UUID accountId);

	long countByAccountIdAndReadAtIsNull(UUID accountId);
}
