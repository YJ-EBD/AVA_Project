package com.ava.backend.user.repository;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.user.entity.UserAccount;

public interface UserAccountRepository extends JpaRepository<UserAccount, UUID> {

	Optional<UserAccount> findByEmailIgnoreCase(String email);

	Optional<UserAccount> findFirstByDisplayNameIgnoreCase(String displayName);

	boolean existsByEmailIgnoreCase(String email);
}
