package com.ava.backend.avastock.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.PartEntity;

public interface PartRepository extends JpaRepository<PartEntity, Long> {
	Optional<PartEntity> findByPartCodeIgnoreCase(String partCode);
}
