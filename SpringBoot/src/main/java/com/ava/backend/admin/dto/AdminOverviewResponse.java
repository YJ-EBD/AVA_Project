package com.ava.backend.admin.dto;

public record AdminOverviewResponse(
	long totalUsers,
	long enabledUsers,
	long disabledUsers,
	long chatRooms,
	long chatMessages,
	long unreadNotifications
) {
}
