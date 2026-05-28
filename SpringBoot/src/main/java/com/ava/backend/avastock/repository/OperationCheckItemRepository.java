package com.ava.backend.avastock.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.BomItemEntity;
import com.ava.backend.avastock.entity.OperationCheckItemEntity;
import com.ava.backend.avastock.entity.ProductOperationEntity;

public interface OperationCheckItemRepository extends JpaRepository<OperationCheckItemEntity, Long> {
	List<OperationCheckItemEntity> findByOperationOrderByBomItemSortOrderAsc(ProductOperationEntity operation);
	Optional<OperationCheckItemEntity> findByOperationAndBomItem(ProductOperationEntity operation, BomItemEntity bomItem);
}
