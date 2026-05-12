package com.ava.backend.chat.repository;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.chat.entity.ChatRoomEntity;

public interface ChatRoomRepository extends JpaRepository<ChatRoomEntity, UUID> {

	Optional<ChatRoomEntity> findByCode(String code);

	boolean existsByCode(String code);
}
