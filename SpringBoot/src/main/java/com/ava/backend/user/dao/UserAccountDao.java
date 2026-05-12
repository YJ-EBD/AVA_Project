package com.ava.backend.user.dao;

import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Repository;

import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.repository.UserAccountRepository;

@Repository
public class UserAccountDao {

	private final UserAccountRepository repository;

	public UserAccountDao(UserAccountRepository repository) {
		this.repository = repository;
	}

	public Optional<UserAccount> findByEmail(String email) {
		return repository.findByEmailIgnoreCase(email);
	}

	public Optional<UserAccount> findById(UUID id) {
		return repository.findById(id);
	}

	public boolean existsByEmail(String email) {
		return repository.existsByEmailIgnoreCase(email);
	}

	public UserAccount save(UserAccount account) {
		return repository.save(account);
	}
}
