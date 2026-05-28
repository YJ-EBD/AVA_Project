package com.ava.backend.avastock.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ProductModelEntity;

public interface ProductModelRepository extends JpaRepository<ProductModelEntity, Long> {
	Optional<ProductModelEntity> findByModelCodeIgnoreCase(String modelCode);
}
