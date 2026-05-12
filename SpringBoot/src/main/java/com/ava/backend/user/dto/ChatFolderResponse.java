package com.ava.backend.user.dto;

import java.util.List;

public record ChatFolderResponse(
	String id,
	String name,
	String icon,
	List<String> roomIds,
	boolean favorite
) {
}
