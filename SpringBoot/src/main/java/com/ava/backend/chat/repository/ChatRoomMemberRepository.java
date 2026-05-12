package com.ava.backend.chat.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.chat.entity.ChatRoomMemberEntity;

public interface ChatRoomMemberRepository extends JpaRepository<ChatRoomMemberEntity, UUID> {

	List<ChatRoomMemberEntity> findByRoomCode(String roomCode);

	Optional<ChatRoomMemberEntity> findByRoomCodeAndAccountId(String roomCode, UUID accountId);

	long countByRoomCode(String roomCode);

	boolean existsByRoomCodeAndAccountId(String roomCode, UUID accountId);

	long deleteByRoomCodeAndAccountId(String roomCode, UUID accountId);

	long deleteByRoomCode(String roomCode);
}
