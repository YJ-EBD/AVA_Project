package com.ava.backend.chat.entity;

import java.time.Instant;
import java.util.UUID;

import com.ava.backend.user.entity.UserAccount;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "chat_room_members",
	uniqueConstraints = @UniqueConstraint(columnNames = {"room_id", "account_id"})
)
public class ChatRoomMemberEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "room_id", nullable = false)
	private ChatRoomEntity room;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "account_id", nullable = false)
	private UserAccount account;

	private Instant joinedAt;

	protected ChatRoomMemberEntity() {
	}

	public ChatRoomMemberEntity(ChatRoomEntity room, UserAccount account) {
		this.id = UUID.randomUUID();
		this.room = room;
		this.account = account;
		this.joinedAt = Instant.now();
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (joinedAt == null) {
			joinedAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public ChatRoomEntity getRoom() {
		return room;
	}

	public UserAccount getAccount() {
		return account;
	}

	public Instant getJoinedAt() {
		return joinedAt;
	}
}
