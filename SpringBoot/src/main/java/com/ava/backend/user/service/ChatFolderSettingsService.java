package com.ava.backend.user.service;

import java.util.ArrayList;
import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.dto.ChatFolderOrderRequest;
import com.ava.backend.user.dto.ChatFolderRequest;
import com.ava.backend.user.dto.ChatFolderResponse;
import com.ava.backend.user.dto.ChatFolderSettingsRequest;
import com.ava.backend.user.dto.QuietChatRoomsRequest;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserChatFolderSetting;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserChatFolderSettingRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class ChatFolderSettingsService {

	private static final String FAVORITE_FOLDER_ID = "favorite";
	private static final String DEFAULT_ICON = "\u2298";

	private final UserChatFolderSettingRepository settingRepository;
	private final UserAccountRepository accountRepository;
	private final ObjectMapper objectMapper;

	public ChatFolderSettingsService(
		UserChatFolderSettingRepository settingRepository,
		UserAccountRepository accountRepository,
		ObjectMapper objectMapper
	) {
		this.settingRepository = settingRepository;
		this.accountRepository = accountRepository;
		this.objectMapper = objectMapper;
	}

	@Transactional(readOnly = true)
	public List<ChatFolderResponse> folders(AuthPrincipal principal) {
		return settingRepository.findById(principal.userId())
			.map(setting -> readFolders(setting.getFoldersJson()))
			.orElseGet(List::of);
	}

	@Transactional
	public List<ChatFolderResponse> saveFolders(AuthPrincipal principal, ChatFolderSettingsRequest request) {
		List<ChatFolderResponse> folders = normalize(request == null ? null : request.folders());
		UserChatFolderSetting setting = settingFor(principal);
		setting.setFoldersJson(writeFolders(folders));
		settingRepository.save(setting);
		return folders;
	}

	@Transactional(readOnly = true)
	public List<String> filterOrder(AuthPrincipal principal) {
		return settingRepository.findById(principal.userId())
			.map(setting -> readStringList(setting.getFilterOrderJson()))
			.orElseGet(List::of);
	}

	@Transactional
	public List<String> saveFilterOrder(AuthPrincipal principal, ChatFolderOrderRequest request) {
		List<String> filterIds = normalizeIds(request == null ? null : request.filterIds());
		UserChatFolderSetting setting = settingFor(principal);
		setting.setFilterOrderJson(writeStringList(filterIds));
		settingRepository.save(setting);
		return filterIds;
	}

	@Transactional(readOnly = true)
	public List<String> quietRoomIds(AuthPrincipal principal) {
		return settingRepository.findById(principal.userId())
			.map(setting -> readStringList(setting.getQuietRoomIdsJson()))
			.orElseGet(List::of);
	}

	@Transactional
	public List<String> saveQuietRoomIds(AuthPrincipal principal, QuietChatRoomsRequest request) {
		List<String> roomIds = normalizeIds(request == null ? null : request.roomIds());
		UserChatFolderSetting setting = settingFor(principal);
		setting.setQuietRoomIdsJson(writeStringList(roomIds));
		settingRepository.save(setting);
		return roomIds;
	}

	@Transactional(readOnly = true)
	public List<String> pinnedRoomIds(AuthPrincipal principal) {
		return settingRepository.findById(principal.userId())
			.map(setting -> readStringList(setting.getPinnedRoomIdsJson()))
			.orElseGet(List::of);
	}

	@Transactional(readOnly = true)
	public Map<String, Instant> pinnedRoomOrder(AuthPrincipal principal) {
		return pinnedRoomOrder(pinnedRoomIds(principal));
	}

	@Transactional
	public PinnedRoomSetting setPinnedRoom(AuthPrincipal principal, String roomId, boolean pinned) {
		String normalizedRoomId = trim(roomId);
		if (normalizedRoomId.isBlank()) {
			throw new IllegalArgumentException("Room id is required.");
		}
		List<String> roomIds = new ArrayList<>(pinnedRoomIds(principal));
		roomIds.remove(normalizedRoomId);
		Instant pinnedAt = null;
		if (pinned) {
			roomIds.add(0, normalizedRoomId);
			pinnedAt = Instant.now();
		}
		UserChatFolderSetting setting = settingFor(principal);
		setting.setPinnedRoomIdsJson(writeStringList(roomIds));
		settingRepository.save(setting);
		return new PinnedRoomSetting(normalizedRoomId, pinned, pinnedAt);
	}

	public Map<String, Instant> pinnedRoomOrder(List<String> pinnedRoomIds) {
		Map<String, Instant> order = new LinkedHashMap<>();
		Instant base = Instant.now();
		int index = 0;
		for (String roomId : normalizeIds(pinnedRoomIds)) {
			order.put(roomId, base.minusMillis(index++));
		}
		return order;
	}

	public record PinnedRoomSetting(
		String roomId,
		boolean pinned,
		Instant pinnedAt
	) {
	}

	private List<ChatFolderResponse> normalize(List<ChatFolderRequest> folders) {
		if (folders == null || folders.isEmpty()) {
			return List.of();
		}

		List<ChatFolderResponse> normalized = new ArrayList<>();
		Set<String> usedIds = new LinkedHashSet<>();
		for (ChatFolderRequest folder : folders) {
			if (folder == null) {
				continue;
			}

			boolean favorite = Boolean.TRUE.equals(folder.favorite());
			String id = favorite ? FAVORITE_FOLDER_ID : trim(folder.id());
			if (id.isBlank()) {
				id = "folder-" + UUID.randomUUID();
			}
			if (!usedIds.add(id)) {
				if (favorite) {
					continue;
				}
				id = "folder-" + UUID.randomUUID();
				usedIds.add(id);
			}

			String name = trimToLimit(folder.name(), 10);
			if (name.isBlank()) {
				name = favorite ? "Favorites" : "Folder";
			}
			String icon = trimToLimit(folder.icon(), 8);
			if (icon.isBlank()) {
				icon = DEFAULT_ICON;
			}

			normalized.add(new ChatFolderResponse(
				id,
				name,
				icon,
				normalizeRoomIds(folder.roomIds()),
				favorite
			));
		}
		return List.copyOf(normalized);
	}

	private List<String> normalizeRoomIds(List<String> roomIds) {
		return normalizeIds(roomIds);
	}

	private List<String> normalizeIds(List<String> roomIds) {
		if (roomIds == null || roomIds.isEmpty()) {
			return List.of();
		}
		Set<String> normalized = new LinkedHashSet<>();
		for (String roomId : roomIds) {
			String value = trim(roomId);
			if (!value.isBlank()) {
				normalized.add(value);
			}
		}
		return List.copyOf(normalized);
	}

	private UserChatFolderSetting settingFor(AuthPrincipal principal) {
		UserAccount account = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("Account not found."));
		return settingRepository.findById(account.getId())
			.orElseGet(() -> new UserChatFolderSetting(account));
	}

	private List<ChatFolderResponse> readFolders(String json) {
		if (json == null || json.isBlank()) {
			return List.of();
		}
		try {
			return objectMapper.readValue(json, new TypeReference<List<ChatFolderResponse>>() {
			});
		} catch (JsonProcessingException error) {
			return List.of();
		}
	}

	private String writeFolders(List<ChatFolderResponse> folders) {
		try {
			return objectMapper.writeValueAsString(folders);
		} catch (JsonProcessingException error) {
			throw new IllegalStateException("Could not save chat folder settings.", error);
		}
	}

	private List<String> readStringList(String json) {
		if (json == null || json.isBlank()) {
			return List.of();
		}
		try {
			return normalizeIds(objectMapper.readValue(json, new TypeReference<List<String>>() {
			}));
		} catch (JsonProcessingException error) {
			return List.of();
		}
	}

	private String writeStringList(List<String> values) {
		try {
			return objectMapper.writeValueAsString(normalizeIds(values));
		} catch (JsonProcessingException error) {
			throw new IllegalStateException("Could not save chat folder settings.", error);
		}
	}

	private String trim(String value) {
		return value == null ? "" : value.trim();
	}

	private String trimToLimit(String value, int maxLength) {
		String trimmed = trim(value);
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}
}
