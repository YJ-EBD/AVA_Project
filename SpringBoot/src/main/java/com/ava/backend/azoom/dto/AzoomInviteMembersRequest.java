package com.ava.backend.azoom.dto;

import java.util.List;
import java.util.UUID;

public record AzoomInviteMembersRequest(
	List<UUID> accountIds
) {
}
