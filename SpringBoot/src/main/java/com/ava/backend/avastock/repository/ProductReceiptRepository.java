package com.ava.backend.avastock.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.avastock.entity.ProductReceiptEntity;

public interface ProductReceiptRepository extends JpaRepository<ProductReceiptEntity, Long> {
}
