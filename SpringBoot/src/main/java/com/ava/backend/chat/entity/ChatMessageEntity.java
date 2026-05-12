package com.ava.backend.chat.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "chat_message_records",
	indexes = @Index(name = "idx_chat_message_records_room_sent_at", columnList = "room_code,sent_at")
)
public class ChatMessageEntity {

	@Id
	private UUID id;

	@Column(name = "room_code", nullable = false, length = 80)
	private String roomCode;

	@Column(name = "sender_id", nullable = false)
	private UUID senderId;

	@Column(name = "sender_name", nullable = false, length = 120)
	private String senderName;

	@Column(nullable = false, length = 2000)
	private String content;

	@Column(name = "sent_at", nullable = false)
	private Instant sentAt;

	@Column(name = "system_message")
	private Boolean systemMessage = false;

	@Column(name = "silent_message")
	private Boolean silentMessage = false;

	@Column(name = "spoiler_message")
	private Boolean spoilerMessage = false;

	@Column(name = "attachment_id", length = 80)
	private String attachmentId;

	@Column(name = "attachment_group_id", length = 120)
	private String attachmentGroupId;

	@Column(name = "attachment_file_name", length = 512)
	private String attachmentFileName;

	@Column(name = "attachment_content_type", length = 160)
	private String attachmentContentType;

	@Column(name = "attachment_size")
	private Long attachmentSize;

	@Column(name = "attachment_stored_path", length = 1200)
	private String attachmentStoredPath;

	protected ChatMessageEntity() {
	}

	public ChatMessageEntity(String roomCode, UUID senderId, String senderName, String content) {
		this(roomCode, senderId, senderName, content, false, false);
	}

	public ChatMessageEntity(
		String roomCode,
		UUID senderId,
		String senderName,
		String content,
		boolean silentMessage,
		boolean spoilerMessage
	) {
		this.id = UUID.randomUUID();
		this.roomCode = roomCode;
		this.senderId = senderId;
		this.senderName = senderName;
		this.content = content;
		this.sentAt = Instant.now();
		this.systemMessage = false;
		this.silentMessage = silentMessage;
		this.spoilerMessage = spoilerMessage;
	}

	public static ChatMessageEntity system(String roomCode, UUID senderId, String senderName, String content) {
		ChatMessageEntity message = new ChatMessageEntity(roomCode, senderId, senderName, content);
		message.systemMessage = true;
		return message;
	}

	public static ChatMessageEntity attachment(
		String roomCode,
		UUID senderId,
		String senderName,
		String fileName,
		String contentType,
		long size,
		String storedPath,
		String groupId
	) {
		ChatMessageEntity message = new ChatMessageEntity(roomCode, senderId, senderName, fileName);
		message.attachmentId = UUID.randomUUID().toString();
		message.attachmentGroupId = groupId;
		message.attachmentFileName = fileName;
		message.attachmentContentType = contentType;
		message.attachmentSize = size;
		message.attachmentStoredPath = storedPath;
		return message;
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (sentAt == null) {
			sentAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public String getRoomCode() {
		return roomCode;
	}

	public UUID getSenderId() {
		return senderId;
	}

	public String getSenderName() {
		return senderName;
	}

	public String getContent() {
		return content;
	}

	public Instant getSentAt() {
		return sentAt;
	}

	public boolean isSystemMessage() {
		return Boolean.TRUE.equals(systemMessage);
	}

	public boolean isSilentMessage() {
		return Boolean.TRUE.equals(silentMessage);
	}

	public boolean isSpoilerMessage() {
		return Boolean.TRUE.equals(spoilerMessage);
	}

	public String getAttachmentId() {
		return attachmentId;
	}

	public String getAttachmentGroupId() {
		return attachmentGroupId;
	}

	public String getAttachmentFileName() {
		return attachmentFileName;
	}

	public String getAttachmentContentType() {
		return attachmentContentType;
	}

	public long getAttachmentSize() {
		return attachmentSize == null ? 0 : attachmentSize;
	}

	public String getAttachmentStoredPath() {
		return attachmentStoredPath;
	}

	public boolean hasAttachment() {
		return attachmentId != null && !attachmentId.isBlank();
	}
}
