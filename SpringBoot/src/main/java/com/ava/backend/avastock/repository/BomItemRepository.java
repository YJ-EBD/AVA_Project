package com.ava.backend.avastock.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.BomItemEntity;
import com.ava.backend.avastock.entity.BomVersionEntity;

public interface BomItemRepository extends JpaRepository<BomItemEntity, Long> {
	List<BomItemEntity> findByBomVersionAndActiveTrueOrderBySortOrderAsc(BomVersionEntity bomVersion);

	List<BomItemEntity> findByBomVersionOrderBySortOrderAsc(BomVersionEntity bomVersion);
}
