package com.ava.backend.chat.dao;

import java.util.List;

import org.springframework.stereotype.Repository;

import com.ava.backend.chat.entity.ChatRoomEntity;
import com.ava.backend.chat.repository.ChatRoomMemberRepository;
import com.ava.backend.chat.repository.ChatRoomRepository;

@Repository
public class ChatRoomDao {

	private final ChatRoomRepository roomRepository;
	private final ChatRoomMemberRepository memberRepository;

	public ChatRoomDao(ChatRoomRepository roomRepository, ChatRoomMemberRepository memberRepository) {
		this.roomRepository = roomRepository;
		this.memberRepository = memberRepository;
	}

	public List<ChatRoomEntity> findAllRooms() {
		return roomRepository.findAll();
	}

	public ChatRoomEntity findByCode(String roomCode) {
		return roomRepository.findByCode(roomCode)
			.orElseThrow(() -> new IllegalArgumentException("채팅방을 찾을 수 없습니다."));
	}

	public long countMembers(String roomCode) {
		return memberRepository.countByRoomCode(roomCode);
	}
}
