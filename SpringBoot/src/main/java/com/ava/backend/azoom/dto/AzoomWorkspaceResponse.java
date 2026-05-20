package com.ava.backend.azoom.dto;

import java.util.List;
import java.util.UUID;

public record AzoomWorkspaceResponse(
	UUID id,
	String companyName,
	String companySlug,
	String name,
	List<AzoomMemberResponse> members
) {
}
