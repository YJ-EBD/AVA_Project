package com.ava.backend.avastock.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.ava.backend.avastock.entity.OperationCheckItemEntity;
import com.ava.backend.avastock.entity.PartEntity;
import com.ava.backend.avastock.entity.PartStockMovementEntity;

public interface PartStockMovementRepository extends JpaRepository<PartStockMovementEntity, Long> {
	List<PartStockMovementEntity> findByPartOrderByCreatedAtDesc(PartEntity part);

	@Query("select coalesce(sum(m.qtyDelta), 0) from PartStockMovementEntity m where m.part = :part")
	Integer currentQty(@Param("part") PartEntity part);

	@Query("select coalesce(sum(m.qtyDelta), 0) from PartStockMovementEntity m where m.checkItem = :checkItem")
	Integer postedDelta(@Param("checkItem") OperationCheckItemEntity checkItem);
}
