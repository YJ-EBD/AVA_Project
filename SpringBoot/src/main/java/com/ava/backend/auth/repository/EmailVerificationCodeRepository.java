package com.ava.backend.auth.repository;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.auth.entity.EmailVerificationCodeEntity;

public interface EmailVerificationCodeRepository extends JpaRepository<EmailVerificationCodeEntity, UUID> {

	Optional<EmailVerificationCodeEntity> findFirstByEmailIgnoreCaseAndConsumedAtIsNullOrderByCreatedAtDesc(
		String email
	);

	void deleteByExpiresAtBefore(Instant cutoff);
}
