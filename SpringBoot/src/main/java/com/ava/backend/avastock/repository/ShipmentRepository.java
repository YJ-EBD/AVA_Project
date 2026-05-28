package com.ava.backend.avastock.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ShipmentEntity;

public interface ShipmentRepository extends JpaRepository<ShipmentEntity, Long> {
	List<ShipmentEntity> findTop20ByOrderByShippingDateDescCreatedAtDesc();
}
