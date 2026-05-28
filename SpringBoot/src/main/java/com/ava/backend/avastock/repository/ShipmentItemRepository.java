package com.ava.backend.avastock.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ProductUnitEntity;
import com.ava.backend.avastock.entity.ShipmentEntity;
import com.ava.backend.avastock.entity.ShipmentItemEntity;

public interface ShipmentItemRepository extends JpaRepository<ShipmentItemEntity, Long> {
	List<ShipmentItemEntity> findByProductUnit(ProductUnitEntity productUnit);

	List<ShipmentItemEntity> findByShipment(ShipmentEntity shipment);
}
