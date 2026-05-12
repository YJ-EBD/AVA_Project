package com.ava.backend.chat.entity;

import java.time.Instant;
import java.util.UUID;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document("chat_messages")
public class ChatMessageDocument {

	@Id
	private String id;

	@Indexed
	private String roomCode;

	private UUID senderId;
	private String senderName;
	private String content;
	private Instant sentAt;
	private Boolean systemMessage = false;
	private Boolean silentMessage = false;
	private Boolean spoilerMessage = false;
	private String attachmentId;
	private String attachmentGroupId;
	private String attachmentFileName;
	private String attachmentContentType;
	private Long attachmentSize;

	protected ChatMessageDocument() {
	}

	public ChatMessageDocument(String roomCode, UUID senderId, String senderName, String content) {
		this(roomCode, senderId, senderName, content, false, false);
	}

	public ChatMessageDocument(
		String roomCode,
		UUID senderId,
		String senderName,
		String content,
		boolean silentMessage,
		boolean spoilerMessage
	) {
		this.roomCode = roomCode;
		this.senderId = senderId;
		this.senderName = senderName;
		this.content = content;
		this.sentAt = Instant.now();
		this.systemMessage = false;
		this.silentMessage = silentMessage;
		this.spoilerMessage = spoilerMessage;
	}

	public String getId() {
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

	public boolean hasAttachment() {
		return attachmentId != null && !attachmentId.isBlank();
	}
}
