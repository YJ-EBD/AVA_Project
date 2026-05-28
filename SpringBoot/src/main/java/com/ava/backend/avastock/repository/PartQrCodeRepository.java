package com.ava.backend.avastock.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.PartQrCodeEntity;
import com.ava.backend.avastock.entity.PartEntity;

public interface PartQrCodeRepository extends JpaRepository<PartQrCodeEntity, Long> {
	Optional<PartQrCodeEntity> findByQrValueAndActiveTrue(String qrValue);

	List<PartQrCodeEntity> findByPartOrderByCreatedAtDesc(PartEntity part);
}
