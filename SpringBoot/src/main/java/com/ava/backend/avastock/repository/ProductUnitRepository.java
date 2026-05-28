package com.ava.backend.avastock.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ProductUnitEntity;

public interface ProductUnitRepository extends JpaRepository<ProductUnitEntity, Long> {
	Optional<ProductUnitEntity> findByQrValue(String qrValue);
	Optional<ProductUnitEntity> findBySerialNo(String serialNo);
	long countByCurrentStatusIn(Iterable<String> statuses);
}
