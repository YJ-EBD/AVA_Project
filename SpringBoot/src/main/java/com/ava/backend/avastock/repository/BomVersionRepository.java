package com.ava.backend.avastock.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.BomVersionEntity;
import com.ava.backend.avastock.entity.ProductModelEntity;

public interface BomVersionRepository extends JpaRepository<BomVersionEntity, Long> {
	Optional<BomVersionEntity> findFirstByModelAndCurrentVersionTrueAndActiveTrue(ProductModelEntity model);

	List<BomVersionEntity> findByModelOrderByVersionNoDesc(ProductModelEntity model);
}
