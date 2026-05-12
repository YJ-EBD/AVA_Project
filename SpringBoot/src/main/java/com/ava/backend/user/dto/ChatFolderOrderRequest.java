package com.ava.backend.user.dto;

import java.util.List;

public record ChatFolderOrderRequest(
	List<String> filterIds
) {
}
