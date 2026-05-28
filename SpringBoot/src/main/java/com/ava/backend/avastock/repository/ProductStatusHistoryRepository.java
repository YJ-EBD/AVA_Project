package com.ava.backend.avastock.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ProductStatusHistoryEntity;

public interface ProductStatusHistoryRepository extends JpaRepository<ProductStatusHistoryEntity, Long> {
}
