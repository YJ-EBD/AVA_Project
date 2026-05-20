package com.ava.backend.ops.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.ops.entity.AppSettingEntity;

public interface AppSettingRepository extends JpaRepository<AppSettingEntity, String> {
}
