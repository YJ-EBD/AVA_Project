package com.ava.backend.avastock.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ProductOperationEntity;
import com.ava.backend.avastock.entity.ProductUnitEntity;
import com.ava.backend.avastock.entity.ServiceCaseEntity;

public interface ProductOperationRepository extends JpaRepository<ProductOperationEntity, Long> {
	Optional<ProductOperationEntity> findFirstByProductUnitAndOperationTypeAndOperationStatusNot(ProductUnitEntity productUnit, String operationType, String operationStatus);
	Optional<ProductOperationEntity> findFirstByServiceCaseAndOperationTypeAndOperationStatusNot(ServiceCaseEntity serviceCase, String operationType, String operationStatus);
	List<ProductOperationEntity> findByProductUnitAndOperationStatusIn(ProductUnitEntity productUnit, Iterable<String> statuses);
}
