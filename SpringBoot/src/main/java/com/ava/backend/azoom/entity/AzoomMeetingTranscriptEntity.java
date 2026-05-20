package com.ava.backend.azoom.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "azoom_voice_meeting_transcripts",
	indexes = {
		@Index(
			name = "idx_azoom_meeting_transcripts_workspace_channel",
			columnList = "workspace_id,voice_channel_id,started_at"
		),
		@Index(
			name = "idx_azoom_meeting_transcripts_kind",
			columnList = "workspace_id,transcript_kind,title_timestamp"
		)
	}
)
public class AzoomMeetingTranscriptEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "workspace_id", nullable = false)
	private AzoomWorkspaceEntity workspace;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "voice_channel_pk", nullable = false)
	private AzoomChannelEntity voiceChannel;

	@Column(name = "company_name", nullable = false, length = 120)
	private String companyName;

	@Column(name = "company_slug", nullable = false, length = 80)
	private String companySlug;

	@Column(name = "voice_channel_id", nullable = false, length = 60)
	private String voiceChannelId;

	@Column(name = "voice_channel_name", nullable = false, length = 120)
	private String voiceChannelName;

	@Column(name = "room_name", nullable = false, length = 160)
	private String roomName;

	@Enumerated(EnumType.STRING)
	@Column(name = "transcript_kind", nullable = false, length = 30)
	private AzoomMeetingTranscriptKind kind;

	@Enumerated(EnumType.STRING)
	@Column(name = "transcription_status", length = 30)
	private AzoomMeetingTranscriptStatus status;

	@Column(name = "title_timestamp", nullable = false, length = 40)
	private String titleTimestamp;

	@Column(name = "audio_file_path", length = 500)
	private String audioFilePath;

	@Column(name = "started_at", nullable = false)
	private Instant startedAt;

	@Column(name = "ended_at")
	private Instant endedAt;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	@Column(name = "updated_at", nullable = false)
	private Instant updatedAt;

	protected AzoomMeetingTranscriptEntity() {
	}

	public AzoomMeetingTranscriptEntity(
		AzoomWorkspaceEntity workspace,
		AzoomChannelEntity voiceChannel,
		String roomName,
		AzoomMeetingTranscriptKind kind,
		String titleTimestamp,
		Instant startedAt
	) {
		this.id = UUID.randomUUID();
		this.workspace = workspace;
		this.voiceChannel = voiceChannel;
		this.companyName = workspace.getCompanyName();
		this.companySlug = workspace.getCompanySlug();
		this.voiceChannelId = voiceChannel.getChannelId();
		this.voiceChannelName = voiceChannel.getName();
		this.roomName = roomName;
		this.kind = kind;
		this.titleTimestamp = titleTimestamp;
		this.startedAt = startedAt;
	}

	@PrePersist
	void prePersist() {
		Instant now = Instant.now();
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (createdAt == null) {
			createdAt = now;
		}
		if (status == null) {
			status = AzoomMeetingTranscriptStatus.READY;
		}
		if (updatedAt == null) {
			updatedAt = now;
		}
	}

	@PreUpdate
	void preUpdate() {
		updatedAt = Instant.now();
	}

	public UUID getId() {
		return id;
	}

	public AzoomWorkspaceEntity getWorkspace() {
		return workspace;
	}

	public AzoomChannelEntity getVoiceChannel() {
		return voiceChannel;
	}

	public String getCompanyName() {
		return companyName;
	}

	public String getCompanySlug() {
		return companySlug;
	}

	public String getVoiceChannelId() {
		return voiceChannelId;
	}

	public String getVoiceChannelName() {
		return voiceChannelName;
	}

	public String getRoomName() {
		return roomName;
	}

	public AzoomMeetingTranscriptKind getKind() {
		return kind;
	}

	public AzoomMeetingTranscriptStatus getStatus() {
		return status == null ? AzoomMeetingTranscriptStatus.READY : status;
	}

	public String getTitleTimestamp() {
		return titleTimestamp;
	}

	public String getAudioFilePath() {
		return audioFilePath;
	}

	public Instant getStartedAt() {
		return startedAt;
	}

	public Instant getEndedAt() {
		return endedAt;
	}

	public void setAudioFilePath(String audioFilePath) {
		this.audioFilePath = audioFilePath;
	}

	public void markProcessing() {
		status = AzoomMeetingTranscriptStatus.PROCESSING;
	}

	public void markReady(Instant endedAt) {
		status = AzoomMeetingTranscriptStatus.READY;
		finish(endedAt);
	}

	public void markFailed(Instant endedAt) {
		status = AzoomMeetingTranscriptStatus.FAILED;
		finish(endedAt);
	}

	public void finish(Instant endedAt) {
		if (this.endedAt == null) {
			this.endedAt = endedAt;
		}
	}
}
