package com.ava.backend.user.mapper;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;

@Component
public class UserMapper {

	private static final String ONLINE = "\uC628\uB77C\uC778";
	private static final String BACKGROUND = "\uBC31\uADF8\uB77C\uC6B4\uB4DC";
	private static final String OFFLINE = "\uC624\uD504\uB77C\uC778";
	private static final String AWAY = "\uC790\uB9AC\uBE44\uC6C0";
	private static final Duration ACTIVE_STALE_AFTER = Duration.ofSeconds(45);
	private static final Duration BACKGROUND_STALE_AFTER = Duration.ofMinutes(10);

	public UserProfileResponse toResponse(UserAccount account, UserProfile profile) {
		return toResponse(account, profile, false);
	}

	public UserProfileResponse toResponse(UserAccount account, UserProfile profile, boolean blocked) {
		return new UserProfileResponse(
			account.getId(),
			account.getEmail(),
			account.getDisplayName(),
			account.getDisplayName(),
			blankToDefault(profile.getNickname(), account.getDisplayName()),
			blankToNull(profile.getPhoneNumber()),
			blankToNull(profile.getContactEmail()),
			blankToNull(profile.getGender()),
			account.getRole(),
			blankToDefault(profile.getCompanyName(), "ABBA-S"),
			blankToDefault(profile.getPosition(), "\uC0AC\uC6D0"),
			blankToDefault(profile.getDepartment(), "\uBBF8\uC9C0\uC815"),
			profile.getBirthDate(),
			effectiveStatus(profile),
			profile.getAvatarColor(),
			blankToNull(profile.getStatusMessage()),
			blankToNull(profile.getAvatarImageUrl()),
			profileBackgroundColor(account.getId(), profile.getProfileBackgroundColor()),
			blankToNull(profile.getProfileBackgroundImageUrl()),
			blocked
		);
	}

	private String effectiveStatus(UserProfile profile) {
		String status = normalizeStatus(profile.getStatus());
		if (OFFLINE.equals(status)) {
			return OFFLINE;
		}
		if (!ONLINE.equals(status) && !BACKGROUND.equals(status)) {
			return OFFLINE;
		}

		Instant updatedAt = profile.getPresenceUpdatedAt();
		if (updatedAt == null) {
			return OFFLINE;
		}
		Duration staleAfter = BACKGROUND.equals(status) ? BACKGROUND_STALE_AFTER : ACTIVE_STALE_AFTER;
		return updatedAt.plus(staleAfter).isBefore(Instant.now()) ? OFFLINE : status;
	}

	private String normalizeStatus(String status) {
		if (status == null || status.isBlank()) {
			return OFFLINE;
		}
		String trimmed = status.trim();
		if (ONLINE.equals(trimmed) || BACKGROUND.equals(trimmed) || OFFLINE.equals(trimmed)) {
			return trimmed;
		}
		if (AWAY.equals(trimmed)) {
			return BACKGROUND;
		}
		return switch (trimmed.toLowerCase()) {
			case "online" -> ONLINE;
			case "background", "away", "idle" -> BACKGROUND;
			case "offline" -> OFFLINE;
			default -> OFFLINE;
		};
	}

	private String blankToDefault(String value, String defaultValue) {
		return value == null || value.isBlank() ? defaultValue : value;
	}

	private String blankToNull(String value) {
		return value == null || value.isBlank() ? null : value;
	}

	private String profileBackgroundColor(UUID accountId, String color) {
		if (color != null && color.matches("#[0-9a-fA-F]{6}")) {
			return color;
		}
		String[] colors = {
			"#7AA06A",
			"#8BA6C9",
			"#9C8E82",
			"#6D91A8",
			"#A88976",
			"#7986A8",
			"#7A9A90",
			"#A0A76F"
		};
		int index = Math.floorMod(accountId.hashCode(), colors.length);
		return colors[index];
	}
}
