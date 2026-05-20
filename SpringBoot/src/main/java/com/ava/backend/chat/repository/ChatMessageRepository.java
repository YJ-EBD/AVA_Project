package com.ava.backend.chat.repository;

import java.util.List;

import org.springframework.data.mongodb.repository.MongoRepository;

import com.ava.backend.chat.entity.ChatMessageDocument;

public interface ChatMessageRepository extends MongoRepository<ChatMessageDocument, String> {

	List<ChatMessageDocument> findTop50ByRoomCodeOrderBySentAtDesc(String roomCode);

	long deleteByRoomCode(String roomCode);
}
