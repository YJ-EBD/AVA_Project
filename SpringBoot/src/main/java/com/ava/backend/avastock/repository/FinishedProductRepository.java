package com.ava.backend.avastock.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.FinishedProductEntity;
import com.ava.backend.avastock.entity.ProductUnitEntity;

public interface FinishedProductRepository extends JpaRepository<FinishedProductEntity, Long> {
	Optional<FinishedProductEntity> findByProductUnit(ProductUnitEntity productUnit);
}
