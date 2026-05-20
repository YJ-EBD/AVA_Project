package com.ava.backend.user.repository;

import java.util.Optional;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.user.entity.UserProfile;

public interface UserProfileRepository extends JpaRepository<UserProfile, UUID> {

	Optional<UserProfile> findByAccountId(UUID accountId);

	List<UserProfile> findByCompanyNameIgnoreCase(String companyName);
}
