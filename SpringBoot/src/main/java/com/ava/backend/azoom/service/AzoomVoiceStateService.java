package com.ava.backend.azoom.service;

import java.time.Instant;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.stereotype.Service;

import com.ava.backend.azoom.dto.AzoomVoiceParticipantResponse;
import com.ava.backend.azoom.dto.AzoomVoiceStatusRequest;
import com.ava.backend.user.dto.UserProfileResponse;

@Service
public class AzoomVoiceStateService {

	private static final Duration STALE_AFTER = Duration.ofSeconds(90);

	private final Map<String, Map<UUID, VoiceParticipantState>> channels = new ConcurrentHashMap<>();
	private final Map<String, Instant> channelStartedAt = new ConcurrentHashMap<>();

	public List<AzoomVoiceParticipantResponse> participants(String channelId) {
		pruneStaleParticipants();
		return snapshot(channelId);
	}

	public Instant startedAt(String channelId) {
		pruneStaleParticipants();
		return channelStartedAt.get(channelId);
	}

	public List<AzoomVoiceParticipantResponse> join(String channelId, UserProfileResponse profile) {
		removeFromOtherChannels(channelId, profile.id());
		channelStartedAt.computeIfAbsent(channelId, ignored -> Instant.now());
		channels.computeIfAbsent(channelId, ignored -> new ConcurrentHashMap<>())
			.compute(profile.id(), (id, previous) -> {
				if (previous == null) {
					return VoiceParticipantState.from(profile);
				}
				return previous.refreshProfile(profile);
			});
		return snapshot(channelId);
	}

	public List<AzoomVoiceParticipantResponse> leave(String channelId, UUID userId) {
		Map<UUID, VoiceParticipantState> participants = channels.get(channelId);
		if (participants != null) {
			participants.remove(userId);
			if (participants.isEmpty()) {
				channels.remove(channelId);
				channelStartedAt.remove(channelId);
			}
		}
		return snapshot(channelId);
	}

	public List<AzoomVoiceParticipantResponse> update(
		String channelId,
		UserProfileResponse profile,
		AzoomVoiceStatusRequest request
	) {
		pruneStaleParticipants();
		channelStartedAt.computeIfAbsent(channelId, ignored -> Instant.now());
		channels.computeIfAbsent(channelId, ignored -> new ConcurrentHashMap<>())
			.compute(profile.id(), (id, previous) -> {
				VoiceParticipantState next = previous == null
					? VoiceParticipantState.from(profile)
					: previous.refreshProfile(profile);
				if (request.muted() != null) {
					next = next.withMuted(request.muted());
				}
				if (request.deafened() != null) {
					next = next.withDeafened(request.deafened());
				}
				if (request.cameraEnabled() != null) {
					next = next.withCameraEnabled(request.cameraEnabled());
				}
				if (request.screenSharing() != null) {
					next = next.withScreenSharing(request.screenSharing());
				}
				return next;
			});
		return snapshot(channelId);
	}

	private List<AzoomVoiceParticipantResponse> snapshot(String channelId) {
		pruneStaleParticipants();
		Map<UUID, VoiceParticipantState> participants = channels.getOrDefault(channelId, Map.of());
		List<VoiceParticipantState> states = new ArrayList<>(participants.values());
		states.sort(Comparator.comparing(VoiceParticipantState::joinedAt));
		return states.stream()
			.map(VoiceParticipantState::toResponse)
			.toList();
	}

	private void removeFromOtherChannels(String activeChannelId, UUID userId) {
		for (Map.Entry<String, Map<UUID, VoiceParticipantState>> entry : channels.entrySet()) {
			if (entry.getKey().equals(activeChannelId)) {
				continue;
			}
			Map<UUID, VoiceParticipantState> participants = entry.getValue();
			participants.remove(userId);
			if (participants.isEmpty()) {
				channels.remove(entry.getKey(), participants);
				channelStartedAt.remove(entry.getKey());
			}
		}
	}

	private void pruneStaleParticipants() {
		Instant cutoff = Instant.now().minus(STALE_AFTER);
		for (Map.Entry<String, Map<UUID, VoiceParticipantState>> entry : channels.entrySet()) {
			Map<UUID, VoiceParticipantState> participants = entry.getValue();
			participants.entrySet().removeIf(item -> item.getValue().lastSeenAt().isBefore(cutoff));
			if (participants.isEmpty()) {
				channels.remove(entry.getKey(), participants);
				channelStartedAt.remove(entry.getKey());
			}
		}
	}

	private record VoiceParticipantState(
		UUID userId,
		String email,
		String displayName,
		String nickname,
		String status,
		String avatarColor,
		String avatarImageUrl,
		Instant joinedAt,
		Instant lastSeenAt,
		boolean muted,
		boolean deafened,
		boolean cameraEnabled,
		boolean screenSharing
	) {
		static VoiceParticipantState from(UserProfileResponse profile) {
			return new VoiceParticipantState(
				profile.id(),
				profile.email(),
				profile.name(),
				profile.nickname(),
				profile.status(),
				profile.avatarColor(),
				profile.avatarImageUrl(),
				Instant.now(),
				Instant.now(),
				false,
				false,
				false,
				false
			);
		}

		VoiceParticipantState refreshProfile(UserProfileResponse profile) {
			return new VoiceParticipantState(
				userId,
				profile.email(),
				profile.name(),
				profile.nickname(),
				profile.status(),
				profile.avatarColor(),
				profile.avatarImageUrl(),
				joinedAt,
				Instant.now(),
				muted,
				deafened,
				cameraEnabled,
				screenSharing
			);
		}

		VoiceParticipantState withMuted(boolean value) {
			return copy(value, deafened, cameraEnabled, screenSharing);
		}

		VoiceParticipantState withDeafened(boolean value) {
			return copy(muted, value, cameraEnabled, screenSharing);
		}

		VoiceParticipantState withCameraEnabled(boolean value) {
			return copy(muted, deafened, value, screenSharing);
		}

		VoiceParticipantState withScreenSharing(boolean value) {
			return copy(muted, deafened, cameraEnabled, value);
		}

		VoiceParticipantState copy(
			boolean nextMuted,
			boolean nextDeafened,
			boolean nextCameraEnabled,
			boolean nextScreenSharing
		) {
			return new VoiceParticipantState(
				userId,
				email,
				displayName,
				nickname,
				status,
				avatarColor,
				avatarImageUrl,
				joinedAt,
				Instant.now(),
				nextMuted,
				nextDeafened,
				nextCameraEnabled,
				nextScreenSharing
			);
		}

		AzoomVoiceParticipantResponse toResponse() {
			return new AzoomVoiceParticipantResponse(
				userId,
				email,
				displayName,
				nickname,
				status,
				avatarColor,
				avatarImageUrl,
				joinedAt,
				muted,
				deafened,
				cameraEnabled,
				screenSharing
			);
		}
	}
}
