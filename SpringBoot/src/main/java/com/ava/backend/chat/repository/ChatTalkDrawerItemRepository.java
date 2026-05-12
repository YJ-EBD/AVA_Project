package com.ava.backend.chat.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.chat.entity.ChatTalkDrawerItemEntity;
import com.ava.backend.chat.entity.ChatTalkDrawerMediaType;

public interface ChatTalkDrawerItemRepository extends JpaRepository<ChatTalkDrawerItemEntity, UUID> {

	List<ChatTalkDrawerItemEntity> findTop200ByCompanyNameIgnoreCaseAndRoomCodeAndDeletedFalseOrderByUploadedAtDesc(
		String companyName,
		String roomCode
	);

	List<ChatTalkDrawerItemEntity> findTop200ByCompanyNameIgnoreCaseAndRoomCodeAndMediaTypeAndDeletedFalseOrderByUploadedAtDesc(
		String companyName,
		String roomCode,
		ChatTalkDrawerMediaType mediaType
	);

	List<ChatTalkDrawerItemEntity> findByRoomCodeOrderByUploadedAtAsc(String roomCode);

	long deleteByRoomCode(String roomCode);
}
