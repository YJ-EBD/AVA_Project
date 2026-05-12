package com.ava.backend.user.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(name = "user_chat_folder_settings")
public class UserChatFolderSetting {

	@Id
	@Column(name = "account_id")
	private UUID accountId;

	@Column(nullable = false, columnDefinition = "text")
	private String foldersJson = "[]";

	@Column(columnDefinition = "text")
	private String filterOrderJson = "[]";

	@Column(columnDefinition = "text")
	private String quietRoomIdsJson = "[]";

	@Column(columnDefinition = "text")
	private String pinnedRoomIdsJson = "[]";

	@Column(nullable = false)
	private Instant updatedAt;

	protected UserChatFolderSetting() {
	}

	public UserChatFolderSetting(UserAccount account) {
		this.accountId = account.getId();
	}

	@PrePersist
	@PreUpdate
	void touch() {
		this.updatedAt = Instant.now();
	}

	public UUID getAccountId() {
		return accountId;
	}

	public String getFoldersJson() {
		return foldersJson;
	}

	public void setFoldersJson(String foldersJson) {
		this.foldersJson = foldersJson == null || foldersJson.isBlank() ? "[]" : foldersJson;
	}

	public String getFilterOrderJson() {
		return filterOrderJson;
	}

	public void setFilterOrderJson(String filterOrderJson) {
		this.filterOrderJson = filterOrderJson == null || filterOrderJson.isBlank() ? "[]" : filterOrderJson;
	}

	public String getQuietRoomIdsJson() {
		return quietRoomIdsJson;
	}

	public void setQuietRoomIdsJson(String quietRoomIdsJson) {
		this.quietRoomIdsJson = quietRoomIdsJson == null || quietRoomIdsJson.isBlank() ? "[]" : quietRoomIdsJson;
	}

	public String getPinnedRoomIdsJson() {
		return pinnedRoomIdsJson;
	}

	public void setPinnedRoomIdsJson(String pinnedRoomIdsJson) {
		this.pinnedRoomIdsJson = pinnedRoomIdsJson == null || pinnedRoomIdsJson.isBlank() ? "[]" : pinnedRoomIdsJson;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}
}
