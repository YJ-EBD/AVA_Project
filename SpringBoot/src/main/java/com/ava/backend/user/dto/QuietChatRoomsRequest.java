package com.ava.backend.user.dto;

import java.util.List;

public record QuietChatRoomsRequest(
	List<String> roomIds
) {
}
