package com.ava.backend.azoom.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.azoom.entity.AzoomMeetingTranscriptEntity;
import com.ava.backend.azoom.entity.AzoomMeetingTranscriptKind;

public interface AzoomMeetingTranscriptRepository extends JpaRepository<AzoomMeetingTranscriptEntity, UUID> {
	List<AzoomMeetingTranscriptEntity> findByWorkspace_IdOrderByCreatedAtDesc(UUID workspaceId);

	Optional<AzoomMeetingTranscriptEntity> findByIdAndWorkspace_Id(UUID id, UUID workspaceId);

	Optional<AzoomMeetingTranscriptEntity>
		findFirstByWorkspace_IdAndVoiceChannelIdAndKindAndEndedAtIsNullOrderByStartedAtDesc(
			UUID workspaceId,
			String voiceChannelId,
			AzoomMeetingTranscriptKind kind
		);

	Optional<AzoomMeetingTranscriptEntity> findFirstByWorkspace_IdAndVoiceChannelIdAndKindOrderByStartedAtDesc(
		UUID workspaceId,
		String voiceChannelId,
		AzoomMeetingTranscriptKind kind
	);

	List<AzoomMeetingTranscriptEntity> findByWorkspace_IdAndVoiceChannelIdAndTitleTimestampOrderByKindAsc(
		UUID workspaceId,
		String voiceChannelId,
		String titleTimestamp
	);
}
