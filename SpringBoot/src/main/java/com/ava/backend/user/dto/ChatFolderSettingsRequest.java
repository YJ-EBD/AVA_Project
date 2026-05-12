package com.ava.backend.user.dto;

import java.util.List;

public record ChatFolderSettingsRequest(
	List<ChatFolderRequest> folders
) {
}
