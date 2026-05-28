package com.ava.backend.azoom.dto;

import java.util.List;

public record AzoomChannelAccessRequest(
	String accessMode,
	List<String> allowedDepartments
) {
}
