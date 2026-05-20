package com.ava.backend.azoom.service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.Normalizer;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.azoom.dto.AzoomMeetingTranscriptResponse;
import com.ava.backend.azoom.dto.AzoomMeetingTranscriptSummaryResponse;
import com.ava.backend.azoom.dto.AzoomMeetingUtteranceResponse;
import com.ava.backend.azoom.dto.AzoomNotivaAudioResponse;
import com.ava.backend.azoom.dto.AzoomNotivaEventResponse;
import com.ava.backend.azoom.dto.AzoomNotivaSessionResponse;
import com.ava.backend.azoom.dto.AzoomNotivaUtteranceRequest;
import com.ava.backend.azoom.entity.AzoomChannelEntity;
import com.ava.backend.azoom.entity.AzoomMeetingTranscriptEntity;
import com.ava.backend.azoom.entity.AzoomMeetingTranscriptKind;
import com.ava.backend.azoom.entity.AzoomMeetingUtteranceEntity;
import com.ava.backend.azoom.entity.AzoomWorkspaceEntity;
import com.ava.backend.azoom.repository.AzoomMeetingTranscriptRepository;
import com.ava.backend.azoom.repository.AzoomMeetingUtteranceRepository;
import com.ava.backend.azoom.service.AzoomNotivaWhisperClient.NotivaWhisperMode;
import com.ava.backend.user.dto.UserProfileResponse;

@Service
public class AzoomNotivaService {

	private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
	private static final DateTimeFormatter TITLE_TIMESTAMP =
		DateTimeFormatter.ofPattern("yyyy:MM:dd (E) - HH:mm:ss", Locale.KOREAN).withZone(SEOUL);

	private final AzoomService azoomService;
	private final AzoomMeetingTranscriptRepository transcriptRepository;
	private final AzoomMeetingUtteranceRepository utteranceRepository;
	private final AzoomNotivaWhisperClient whisperClient;
	private final SimpMessagingTemplate messagingTemplate;
	private final TransactionTemplate transactionTemplate;
	private final Path audioDirectory;

	public AzoomNotivaService(
		AzoomService azoomService,
		AzoomMeetingTranscriptRepository transcriptRepository,
		AzoomMeetingUtteranceRepository utteranceRepository,
		AzoomNotivaWhisperClient whisperClient,
		SimpMessagingTemplate messagingTemplate,
		PlatformTransactionManager transactionManager,
		@Value("${ava.azoom.notiva.audio-directory:NotivaAudio}") String audioDirectory
	) {
		this.azoomService = azoomService;
		this.transcriptRepository = transcriptRepository;
		this.utteranceRepository = utteranceRepository;
		this.whisperClient = whisperClient;
		this.messagingTemplate = messagingTemplate;
		this.transactionTemplate = new TransactionTemplate(transactionManager);
		this.audioDirectory = Path.of(audioDirectory);
	}

	@Transactional(readOnly = true)
	public List<AzoomMeetingTranscriptSummaryResponse> transcripts(AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = azoomService.workspaceForNotiva(principal);
		return transcriptRepository.findByWorkspace_IdOrderByCreatedAtDesc(workspace.getId())
			.stream()
			.map(this::summaryResponse)
			.toList();
	}

	@Transactional(readOnly = true)
	public AzoomMeetingTranscriptResponse transcript(UUID transcriptId, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = azoomService.workspaceForNotiva(principal);
		AzoomMeetingTranscriptEntity transcript = transcriptRepository
			.findByIdAndWorkspace_Id(transcriptId, workspace.getId())
			.orElseThrow(() -> new IllegalArgumentException("AZOOM meeting transcript not found."));
		return transcriptResponse(transcript);
	}

	@Transactional
	public AzoomNotivaSessionResponse start(String channelId, AuthPrincipal principal) {
		AzoomContext context = context(channelId, principal);
		AzoomMeetingTranscriptEntity transcript = activeTranscript(
			context,
			AzoomMeetingTranscriptKind.REALTIME,
			context.startedAt()
		);
		return new AzoomNotivaSessionResponse(context.roomName(), transcriptResponse(transcript));
	}

	@Transactional
	public AzoomMeetingTranscriptResponse appendRealtimeUtterance(
		String channelId,
		AzoomNotivaUtteranceRequest request,
		AuthPrincipal principal
	) {
		AzoomContext context = context(channelId, principal);
		AzoomMeetingTranscriptEntity transcript = activeTranscript(
			context,
			AzoomMeetingTranscriptKind.REALTIME,
			context.startedAt()
		);
		appendUtterance(transcript, request, principal);
		return transcriptResponse(transcript);
	}

	@Transactional
	public AzoomMeetingTranscriptResponse finishRealtime(String channelId, AuthPrincipal principal) {
		AzoomContext context = context(channelId, principal);
		return transcriptRepository
			.findFirstByWorkspace_IdAndVoiceChannelIdAndKindAndEndedAtIsNullOrderByStartedAtDesc(
				context.workspace().getId(),
				context.channel().getChannelId(),
				AzoomMeetingTranscriptKind.REALTIME
			)
			.map(transcript -> {
				transcript.finish(Instant.now());
				return transcriptResponse(transcript);
			})
			.orElse(null);
	}

	@Transactional
	public void finishIfVoiceChannelEnded(String channelId, AuthPrincipal principal, boolean channelEmpty) {
		if (channelEmpty) {
			finishRealtime(channelId, principal);
		}
	}

	@Transactional
	public AzoomNotivaAudioResponse transcribeRealtimeAudio(
		String channelId,
		MultipartFile file,
		String speakerUserId,
		String speakerName,
		String speakerEmail,
		AuthPrincipal principal
	) {
		AzoomContext context = context(channelId, principal);
		Path savedAudio = storeAudioFile(context, file, "realtime");
		AzoomNotivaWhisperClient.NotivaWhisperResponse whisper = transcribe(savedAudio, NotivaWhisperMode.REALTIME);
		AzoomMeetingTranscriptEntity transcript = realtimeTranscriptForAudio(context);
		appendWhisperSegments(transcript, whisper, speakerUserId, speakerName, speakerEmail, transcript.getStartedAt());
		return new AzoomNotivaAudioResponse(file.getOriginalFilename(), transcriptResponse(transcript));
	}

	@Transactional
	public AzoomNotivaAudioResponse transcribeBatchAudio(
		String channelId,
		MultipartFile file,
		String speakerUserId,
		String speakerName,
		String speakerEmail,
		AuthPrincipal principal
	) {
		AzoomContext context = context(channelId, principal);
		AzoomMeetingTranscriptEntity realtimeTranscript = latestRealtimeTranscript(context);
		Instant startedAt = realtimeTranscript == null ? context.startedAt() : realtimeTranscript.getStartedAt();
		String titleTimestamp = realtimeTranscript == null
			? TITLE_TIMESTAMP.format(startedAt)
			: realtimeTranscript.getTitleTimestamp();
		Path savedAudio = storeAudioFile(context, file, "batch");
		AzoomMeetingTranscriptEntity transcript = new AzoomMeetingTranscriptEntity(
			context.workspace(),
			context.channel(),
			context.roomName(),
			AzoomMeetingTranscriptKind.BATCH_AUDIO,
			titleTimestamp,
			startedAt
		);
		transcript.setAudioFilePath(savedAudio.toString());
		transcript.markProcessing();
		transcriptRepository.save(transcript);
		UUID transcriptId = transcript.getId();
		startBatchTranscriptionAfterCommit(transcriptId, savedAudio, speakerUserId, speakerName, speakerEmail);
		return new AzoomNotivaAudioResponse(file.getOriginalFilename(), transcriptResponse(transcript));
	}

	private AzoomMeetingTranscriptEntity latestRealtimeTranscript(AzoomContext context) {
		return transcriptRepository
			.findFirstByWorkspace_IdAndVoiceChannelIdAndKindOrderByStartedAtDesc(
				context.workspace().getId(),
				context.channel().getChannelId(),
				AzoomMeetingTranscriptKind.REALTIME
			)
			.orElse(null);
	}

	private AzoomMeetingTranscriptEntity realtimeTranscriptForAudio(AzoomContext context) {
		return transcriptRepository
			.findFirstByWorkspace_IdAndVoiceChannelIdAndKindAndEndedAtIsNullOrderByStartedAtDesc(
				context.workspace().getId(),
				context.channel().getChannelId(),
				AzoomMeetingTranscriptKind.REALTIME
			)
			.orElseGet(() -> {
				AzoomMeetingTranscriptEntity latest = latestRealtimeTranscript(context);
				if (latest != null) {
					return latest;
				}
				return transcriptRepository.save(new AzoomMeetingTranscriptEntity(
					context.workspace(),
					context.channel(),
					context.roomName(),
					AzoomMeetingTranscriptKind.REALTIME,
					TITLE_TIMESTAMP.format(context.startedAt()),
					context.startedAt()
				));
			});
	}

	private void startBatchTranscriptionAfterCommit(
		UUID transcriptId,
		Path savedAudio,
		String speakerUserId,
		String speakerName,
		String speakerEmail
	) {
		if (TransactionSynchronizationManager.isSynchronizationActive()) {
			TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
				@Override
				public void afterCommit() {
					startBatchTranscription(transcriptId, savedAudio, speakerUserId, speakerName, speakerEmail);
				}
			});
			return;
		}
		startBatchTranscription(transcriptId, savedAudio, speakerUserId, speakerName, speakerEmail);
	}

	private void startBatchTranscription(
		UUID transcriptId,
		Path savedAudio,
		String speakerUserId,
		String speakerName,
		String speakerEmail
	) {
		CompletableFuture.runAsync(() -> completeBatchTranscription(
			transcriptId,
			savedAudio,
			speakerUserId,
			speakerName,
			speakerEmail
		));
	}

	private void completeBatchTranscription(
		UUID transcriptId,
		Path savedAudio,
		String speakerUserId,
		String speakerName,
		String speakerEmail
	) {
		try {
			AzoomNotivaWhisperClient.NotivaWhisperResponse whisper = transcribe(savedAudio, NotivaWhisperMode.BATCH);
			transactionTemplate.executeWithoutResult(status -> {
				AzoomMeetingTranscriptEntity transcript = transcriptRepository.findById(transcriptId)
					.orElseThrow(() -> new IllegalArgumentException("AZOOM meeting transcript not found."));
				appendWhisperSegments(transcript, whisper, speakerUserId, speakerName, speakerEmail, transcript.getStartedAt());
				transcript.markReady(Instant.now());
				publishNotivaTranscript("BATCH_AUDIO", transcriptResponse(transcript));
			});
		} catch (RuntimeException error) {
			transactionTemplate.executeWithoutResult(status -> transcriptRepository.findById(transcriptId).ifPresent(transcript -> {
				transcript.markFailed(Instant.now());
				publishNotivaTranscript("BATCH_AUDIO_FAILED", transcriptResponse(transcript));
			}));
		}
	}

	private AzoomContext context(String channelId, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = azoomService.workspaceForNotiva(principal);
		AzoomChannelEntity channel = azoomService.voiceChannelForNotiva(workspace, channelId);
		String roomName = azoomService.voiceRoomNameForNotiva(channel, workspace.getCompanySlug());
		Instant startedAt = azoomService.voiceStartedAtForNotiva(roomName);
		if (startedAt == null) {
			startedAt = Instant.now();
		}
		return new AzoomContext(workspace, channel, roomName, startedAt);
	}

	private AzoomMeetingTranscriptEntity activeTranscript(
		AzoomContext context,
		AzoomMeetingTranscriptKind kind,
		Instant startedAt
	) {
		return transcriptRepository
			.findFirstByWorkspace_IdAndVoiceChannelIdAndKindAndEndedAtIsNullOrderByStartedAtDesc(
				context.workspace().getId(),
				context.channel().getChannelId(),
				kind
			)
			.orElseGet(() -> transcriptRepository.save(new AzoomMeetingTranscriptEntity(
				context.workspace(),
				context.channel(),
				context.roomName(),
				kind,
				TITLE_TIMESTAMP.format(startedAt),
				startedAt
			)));
	}

	private void appendUtterance(
		AzoomMeetingTranscriptEntity transcript,
		AzoomNotivaUtteranceRequest request,
		AuthPrincipal principal
	) {
		String content = request.content() == null ? "" : request.content().trim();
		if (content.isBlank()) {
			return;
		}
		UserProfileResponse profile = azoomService.currentProfileForNotiva(principal);
		UUID speakerUserId = request.speakerUserId() == null ? principal.userId() : request.speakerUserId();
		String speakerName = blankToDefault(request.speakerName(), blankToDefault(profile.name(), principal.displayName()));
		String speakerEmail = blankToDefault(request.speakerEmail(), principal.email());
		int sequenceNo = (int) utteranceRepository.countByTranscript_Id(transcript.getId()) + 1;
		utteranceRepository.save(new AzoomMeetingUtteranceEntity(
			transcript,
			sequenceNo,
			speakerUserId,
			speakerName,
			speakerEmail,
			content,
			request.startedAt(),
			request.endedAt()
		));
	}

	private void appendWhisperSegments(
		AzoomMeetingTranscriptEntity transcript,
		AzoomNotivaWhisperClient.NotivaWhisperResponse whisper,
		String speakerUserId,
		String speakerName,
		String speakerEmail,
		Instant baseTime
	) {
		UUID parsedSpeakerId = parseUuid(speakerUserId);
		String resolvedSpeakerName = blankToDefault(speakerName, "Unknown");
		String resolvedSpeakerEmail = blankToDefault(speakerEmail, "");
		List<AzoomNotivaWhisperClient.NotivaWhisperSegment> segments = whisper.segments();
		if (segments.isEmpty()) {
			String text = whisper.text() == null ? "" : whisper.text().trim();
			if (!text.isBlank()) {
				appendSegment(transcript, parsedSpeakerId, resolvedSpeakerName, resolvedSpeakerEmail, text, baseTime, baseTime);
			}
			return;
		}
		for (AzoomNotivaWhisperClient.NotivaWhisperSegment segment : segments) {
			String text = segment.text() == null ? "" : segment.text().trim();
			if (text.isBlank()) {
				continue;
			}
			Instant start = baseTime.plusMillis(Math.round(segment.start() * 1000));
			Instant end = baseTime.plusMillis(Math.round(segment.end() * 1000));
			appendSegment(transcript, parsedSpeakerId, resolvedSpeakerName, resolvedSpeakerEmail, text, start, end);
		}
	}

	private void appendSegment(
		AzoomMeetingTranscriptEntity transcript,
		UUID speakerUserId,
		String speakerName,
		String speakerEmail,
		String content,
		Instant startedAt,
		Instant endedAt
	) {
		int sequenceNo = (int) utteranceRepository.countByTranscript_Id(transcript.getId()) + 1;
		utteranceRepository.save(new AzoomMeetingUtteranceEntity(
			transcript,
			sequenceNo,
			speakerUserId,
			speakerName,
			speakerEmail,
			content,
			startedAt,
			endedAt
		));
	}

	private Path storeAudioFile(AzoomContext context, MultipartFile file, String mode) {
		if (file == null || file.isEmpty()) {
			throw new IllegalArgumentException("Notiva AI audio file is required.");
		}
		String fileName = sanitizeFileName(blankToDefault(file.getOriginalFilename(), "audio.webm"));
		Path directory = audioDirectory
			.resolve(context.workspace().getCompanySlug())
			.resolve(context.channel().getChannelId())
			.resolve(mode);
		try {
			Files.createDirectories(directory);
			Path target = directory.resolve(Instant.now().toEpochMilli() + "-" + fileName);
			file.transferTo(target);
			return target;
		} catch (IOException error) {
			throw new IllegalStateException("Failed to store Notiva AI audio file.", error);
		}
	}

	private AzoomNotivaWhisperClient.NotivaWhisperResponse transcribe(Path audioFile, NotivaWhisperMode mode) {
		try {
			return whisperClient.transcribe(audioFile, "ko", mode);
		} catch (IOException error) {
			throw new IllegalStateException("Notiva AI transcription failed: " + error.getMessage(), error);
		}
	}

	private AzoomMeetingTranscriptSummaryResponse summaryResponse(AzoomMeetingTranscriptEntity transcript) {
		return new AzoomMeetingTranscriptSummaryResponse(
			transcript.getId(),
			transcript.getVoiceChannelId(),
			transcript.getVoiceChannelName(),
			transcript.getRoomName(),
			transcript.getKind().name(),
			transcript.getStatus().name(),
			transcript.getTitleTimestamp(),
			transcript.getStartedAt(),
			transcript.getEndedAt(),
			utteranceRepository.countByTranscript_Id(transcript.getId())
		);
	}

	private AzoomMeetingTranscriptResponse transcriptResponse(AzoomMeetingTranscriptEntity transcript) {
		return new AzoomMeetingTranscriptResponse(
			transcript.getId(),
			transcript.getCompanyName(),
			transcript.getCompanySlug(),
			transcript.getVoiceChannelId(),
			transcript.getVoiceChannelName(),
			transcript.getRoomName(),
			transcript.getKind().name(),
			transcript.getStatus().name(),
			transcript.getTitleTimestamp(),
			transcript.getAudioFilePath(),
			transcript.getStartedAt(),
			transcript.getEndedAt(),
			utteranceRepository.findByTranscript_IdOrderBySequenceNoAsc(transcript.getId())
				.stream()
				.map(this::utteranceResponse)
				.toList()
		);
	}

	private AzoomMeetingUtteranceResponse utteranceResponse(AzoomMeetingUtteranceEntity utterance) {
		return new AzoomMeetingUtteranceResponse(
			utterance.getId(),
			utterance.getSequenceNo(),
			utterance.getSpeakerUserId(),
			utterance.getSpeakerName(),
			utterance.getSpeakerEmail(),
			utterance.getContent(),
			utterance.getStartedAt(),
			utterance.getEndedAt()
		);
	}

	private void publishNotivaTranscript(String type, AzoomMeetingTranscriptResponse response) {
		messagingTemplate.convertAndSend(
			"/topic/azoom/notiva/" + response.roomName(),
			new AzoomNotivaEventResponse(type, response.roomName(), response)
		);
	}

	private UUID parseUuid(String value) {
		if (value == null || value.isBlank()) {
			return null;
		}
		try {
			return UUID.fromString(value.trim());
		} catch (IllegalArgumentException ignored) {
			return null;
		}
	}

	private String sanitizeFileName(String value) {
		String normalized = Normalizer.normalize(value, Normalizer.Form.NFKC);
		String cleaned = normalized.replaceAll("[\\\\/:*?\"<>|]+", "-").replaceAll("\\s+", " ").trim();
		return cleaned.isBlank() ? "audio.webm" : cleaned;
	}

	private String blankToDefault(String value, String fallback) {
		return value == null || value.isBlank() ? fallback : value.trim();
	}

	private record AzoomContext(
		AzoomWorkspaceEntity workspace,
		AzoomChannelEntity channel,
		String roomName,
		Instant startedAt
	) {
	}
}
