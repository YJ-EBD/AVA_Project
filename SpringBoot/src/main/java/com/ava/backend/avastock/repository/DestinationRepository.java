package com.ava.backend.avastock.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.DestinationEntity;

public interface DestinationRepository extends JpaRepository<DestinationEntity, Long> {
	Optional<DestinationEntity> findByDestinationNameIgnoreCase(String destinationName);
}
