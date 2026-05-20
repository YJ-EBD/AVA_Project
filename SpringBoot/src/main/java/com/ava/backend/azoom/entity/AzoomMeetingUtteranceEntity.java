package com.ava.backend.azoom.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Lob;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

@Entity
@Table(
	name = "azoom_voice_meeting_utterances",
	indexes = @Index(
		name = "idx_azoom_meeting_utterances_transcript_sequence",
		columnList = "transcript_id,sequence_no"
	)
)
public class AzoomMeetingUtteranceEntity {

	@Id
	private UUID id;

	@ManyToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "transcript_id", nullable = false)
	private AzoomMeetingTranscriptEntity transcript;

	@Column(name = "sequence_no", nullable = false)
	private int sequenceNo;

	@Column(name = "speaker_user_id")
	private UUID speakerUserId;

	@Column(name = "speaker_name", nullable = false, length = 120)
	private String speakerName;

	@Column(name = "speaker_email", length = 190)
	private String speakerEmail;

	@Lob
	@Column(nullable = false)
	private String content;

	@Column(name = "started_at")
	private Instant startedAt;

	@Column(name = "ended_at")
	private Instant endedAt;

	@Column(name = "created_at", nullable = false)
	private Instant createdAt;

	protected AzoomMeetingUtteranceEntity() {
	}

	public AzoomMeetingUtteranceEntity(
		AzoomMeetingTranscriptEntity transcript,
		int sequenceNo,
		UUID speakerUserId,
		String speakerName,
		String speakerEmail,
		String content,
		Instant startedAt,
		Instant endedAt
	) {
		this.id = UUID.randomUUID();
		this.transcript = transcript;
		this.sequenceNo = sequenceNo;
		this.speakerUserId = speakerUserId;
		this.speakerName = speakerName;
		this.speakerEmail = speakerEmail;
		this.content = content;
		this.startedAt = startedAt;
		this.endedAt = endedAt;
	}

	@PrePersist
	void prePersist() {
		if (id == null) {
			id = UUID.randomUUID();
		}
		if (createdAt == null) {
			createdAt = Instant.now();
		}
	}

	public UUID getId() {
		return id;
	}

	public AzoomMeetingTranscriptEntity getTranscript() {
		return transcript;
	}

	public int getSequenceNo() {
		return sequenceNo;
	}

	public UUID getSpeakerUserId() {
		return speakerUserId;
	}

	public String getSpeakerName() {
		return speakerName;
	}

	public String getSpeakerEmail() {
		return speakerEmail;
	}

	public String getContent() {
		return content;
	}

	public Instant getStartedAt() {
		return startedAt;
	}

	public Instant getEndedAt() {
		return endedAt;
	}
}
