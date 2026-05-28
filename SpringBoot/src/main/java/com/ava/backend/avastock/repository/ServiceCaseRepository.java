package com.ava.backend.avastock.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ProductUnitEntity;
import com.ava.backend.avastock.entity.ServiceCaseEntity;

public interface ServiceCaseRepository extends JpaRepository<ServiceCaseEntity, Long> {
	Optional<ServiceCaseEntity> findFirstByProductUnitAndServiceStatusIn(ProductUnitEntity productUnit, Iterable<String> statuses);
}
