package com.ava.backend.chat.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(
	name = "chat_talk_drawer_items",
	uniqueConstraints = @UniqueConstraint(columnNames = "attachment_id"),
	indexes = {
		@Index(
			name = "idx_talk_drawer_company_room_uploaded",
			columnList = "company_name,room_code,uploaded_at"
		),
		@Index(
			name = "idx_talk_drawer_room_type_uploaded",
			columnList = "room_code,media_type,uploaded_at"
		),
		@Index(name = "idx_talk_drawer_message", columnList = "message_id")
	}
)
public class ChatTalkDrawerItemEntity {

	@Id
	private UUID id;

	@Column(name = "company_name", nullable = false, length = 80)
	private String companyName;

	@Column(name = "room_code", nullable = false, length = 80)
	private String roomCode;

	@Column(name = "message_id", nullable = false)
	private UUID messageId;

	@Column(name = "attachment_id", nullable = false, length = 80)
	private String attachmentId;

	@Column(name = "attachment_group_id", length = 120)
	private String attachmentGroupId;

	@Column(name = "file_name", nullable = false, length = 512)
	private String fileName;

	@Column(name = "content_type", nullable = false, length = 160)
	private String contentType;

	@Column(name = "file_size", nullable = false)
	private long fileSize;

	@Enumerated(EnumType.STRING)
	@Column(name = "media_type", nullable = false, length = 20)
	private ChatTalkDrawerMediaType mediaType;

	@Column(name = "storage_path", nullable = false, length = 1200)
	private String storagePath;

	@Column(name = "checksum_sha256", length = 64)
	private String checksumSha256;

	@Column(name = "uploaded_by_account_id", nullable = false)
	private UUID uploadedByAccountId;

	@Column(name = "uploaded_by_name", nullable = false, length = 120)
	private String uploadedByName;

	@Column(name = "uploaded_at", nullable = false)
	private Instant uploadedAt;

	@Column(nullable = false, columnDefinition = "boolean default false")
	private boolean deleted = false;

	private Instant deletedAt;

	protected ChatTalkDrawerItemEntity() {
	}

	public ChatTalkDrawerItemEntity(
		String companyName,
		String roomCode,
		UUID messageId,
		String attachmentId,
		String attachmentGroupId,
		String fileName,
		String contentType,
		long fileSize,
		ChatTalkDrawerMediaType mediaType,
		String storagePath,
		String checksumSha256,
		UUID uploadedByAccountId,
		String uploadedByName
	) {
		this.id = UUID.randomUUID();
		this.companyName = companyName;
		this.roomCode = roomCode;
		this.messageId = messageId;
		this.attachmentId = attachmentId;
		this.attachmentGroupId = attachmentGroupId;
		this.fileName = fileName;
		this.contentType = contentType;
		this.fileSize = fileSize;
		this.mediaType = mediaType;
		this.storagePath = storagePath;
		this.checksumSha256 = checksumSha256;
		this.uploadedByAccountId = uploadedByAccountId;
		this.uploadedByName = uploadedByName;
		this.uploadedAt = Instant.now();
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (uploadedAt == null) {
			uploadedAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public String getCompanyName() {
		return companyName;
	}

	public String getRoomCode() {
		return roomCode;
	}

	public UUID getMessageId() {
		return messageId;
	}

	public String getAttachmentId() {
		return attachmentId;
	}

	public String getAttachmentGroupId() {
		return attachmentGroupId;
	}

	public String getFileName() {
		return fileName;
	}

	public String getContentType() {
		return contentType;
	}

	public long getFileSize() {
		return fileSize;
	}

	public ChatTalkDrawerMediaType getMediaType() {
		return mediaType;
	}

	public String getStoragePath() {
		return storagePath;
	}

	public String getChecksumSha256() {
		return checksumSha256;
	}

	public UUID getUploadedByAccountId() {
		return uploadedByAccountId;
	}

	public String getUploadedByName() {
		return uploadedByName;
	}

	public Instant getUploadedAt() {
		return uploadedAt;
	}

	public boolean isDeleted() {
		return deleted;
	}

	public Instant getDeletedAt() {
		return deletedAt;
	}

	public void markDeleted() {
		this.deleted = true;
		this.deletedAt = Instant.now();
	}
}
