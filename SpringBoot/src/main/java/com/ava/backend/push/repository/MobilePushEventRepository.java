package com.ava.backend.push.repository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.push.entity.MobilePushEventEntity;

public interface MobilePushEventRepository extends JpaRepository<MobilePushEventEntity, UUID> {

	List<MobilePushEventEntity> findByAccountIdAndCreatedAtAfterOrderByCreatedAtAsc(
		UUID accountId,
		Instant createdAt,
		Pageable pageable
	);

	List<MobilePushEventEntity> findByAccountIdOrderByCreatedAtDesc(UUID accountId, Pageable pageable);
}
