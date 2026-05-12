package com.ava.backend.user.dto;

import java.util.List;

public record ChatFolderRequest(
	String id,
	String name,
	String icon,
	List<String> roomIds,
	Boolean favorite
) {
}
