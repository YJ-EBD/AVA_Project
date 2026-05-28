package com.ava.backend.azoom.controller;

import java.util.List;
import java.util.UUID;

import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.azoom.dto.AzoomChannelAccessRequest;
import com.ava.backend.azoom.dto.AzoomChannelMutationRequest;
import com.ava.backend.azoom.dto.AzoomChannelsResponse;
import com.ava.backend.azoom.dto.AzoomInviteCandidateResponse;
import com.ava.backend.azoom.dto.AzoomInviteMembersRequest;
import com.ava.backend.azoom.dto.AzoomLiveKitTokenResponse;
import com.ava.backend.azoom.dto.AzoomMeetingTranscriptResponse;
import com.ava.backend.azoom.dto.AzoomMeetingTranscriptSummaryResponse;
import com.ava.backend.azoom.dto.AzoomMemberMutationRequest;
import com.ava.backend.azoom.dto.AzoomNotivaAudioResponse;
import com.ava.backend.azoom.dto.AzoomNotivaEventResponse;
import com.ava.backend.azoom.dto.AzoomNotivaSessionResponse;
import com.ava.backend.azoom.dto.AzoomNotivaUtteranceRequest;
import com.ava.backend.azoom.dto.AzoomVoiceChannelResponse;
import com.ava.backend.azoom.dto.AzoomVoiceEffectResponse;
import com.ava.backend.azoom.dto.AzoomVoiceJoinResponse;
import com.ava.backend.azoom.dto.AzoomVoiceStatusRequest;
import com.ava.backend.azoom.dto.AzoomWorkspaceResponse;
import com.ava.backend.azoom.service.AzoomNotivaService;
import com.ava.backend.azoom.service.AzoomService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/azoom")
public class AzoomController {

	private final AzoomService azoomService;
	private final AzoomNotivaService notivaService;
	private final SimpMessagingTemplate messagingTemplate;

	public AzoomController(
		AzoomService azoomService,
		AzoomNotivaService notivaService,
		SimpMessagingTemplate messagingTemplate
	) {
		this.azoomService = azoomService;
		this.notivaService = notivaService;
		this.messagingTemplate = messagingTemplate;
	}

	@GetMapping("/channels")
	public AzoomChannelsResponse channels(@AuthenticationPrincipal AuthPrincipal principal) {
		return azoomService.channels(principal);
	}

	@GetMapping("/workspace")
	public AzoomWorkspaceResponse workspace(@AuthenticationPrincipal AuthPrincipal principal) {
		return azoomService.workspace(principal);
	}

	@PostMapping("/voice-channels")
	public AzoomVoiceChannelResponse createVoiceChannel(
		@Valid @RequestBody AzoomChannelMutationRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.createVoiceChannel(request, principal);
	}

	@PutMapping("/voice-channels/{channelId}")
	public AzoomVoiceChannelResponse updateVoiceChannel(
		@PathVariable String channelId,
		@Valid @RequestBody AzoomChannelMutationRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.updateVoiceChannel(channelId, request, principal);
	}

	@DeleteMapping("/channels/{channelId}")
	public AzoomChannelsResponse archiveChannel(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.archiveChannel(channelId, principal);
	}

	@PostMapping("/members")
	public AzoomWorkspaceResponse addMember(
		@Valid @RequestBody AzoomMemberMutationRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.addMember(request, principal);
	}

	@GetMapping("/invite-candidates")
	public List<AzoomInviteCandidateResponse> inviteCandidates(
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.inviteCandidates(principal);
	}

	@PostMapping("/invite-members")
	public AzoomWorkspaceResponse inviteMembers(
		@RequestBody AzoomInviteMembersRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.inviteMembers(request, principal);
	}

	@PutMapping("/voice-channels/{channelId}/access")
	public AzoomVoiceChannelResponse updateChannelAccess(
		@PathVariable String channelId,
		@RequestBody AzoomChannelAccessRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomVoiceChannelResponse response = azoomService.updateChannelAccess(channelId, request, principal);
		publishVoiceStates(azoomService.voiceStates(principal));
		return response;
	}

	@GetMapping("/voice-channels/{channelId}/state")
	public AzoomVoiceChannelResponse voiceState(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.voiceState(channelId, principal);
	}

	@PostMapping("/voice-channels/{channelId}/join")
	public AzoomVoiceJoinResponse joinVoice(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomVoiceJoinResponse response = azoomService.joinVoice(channelId, principal);
		publishVoiceStates(azoomService.voiceStates(principal));
		return response;
	}

	@PostMapping("/voice-channels/{channelId}/leave")
	public AzoomVoiceChannelResponse leaveVoice(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomVoiceChannelResponse response = azoomService.leaveVoice(channelId, principal);
		notivaService.finishIfVoiceChannelEnded(channelId, principal, response.participants().isEmpty());
		publishVoiceStates(azoomService.voiceStates(principal));
		return response;
	}

	@PutMapping("/voice-channels/{channelId}/status")
	public AzoomVoiceChannelResponse updateVoiceStatus(
		@PathVariable String channelId,
		@RequestBody AzoomVoiceStatusRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomVoiceChannelResponse response = azoomService.updateVoiceStatus(channelId, request, principal);
		publishVoiceStates(azoomService.voiceStates(principal));
		return response;
	}

	@GetMapping("/voice-channels/{channelId}/livekit-token")
	public AzoomLiveKitTokenResponse liveKitToken(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return azoomService.liveKitToken(channelId, principal);
	}

	@PostMapping("/voice-channels/{channelId}/effects/firework")
	public AzoomVoiceEffectResponse triggerFirework(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomVoiceEffectResponse response = azoomService.voiceEffect(channelId, "FIREWORK", principal);
		messagingTemplate.convertAndSend("/topic/azoom/voice-effects/" + response.roomName(), response);
		return response;
	}

	@GetMapping("/meeting-transcripts")
	public List<AzoomMeetingTranscriptSummaryResponse> meetingTranscripts(
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return notivaService.transcripts(principal);
	}

	@GetMapping("/meeting-transcripts/{transcriptId}")
	public AzoomMeetingTranscriptResponse meetingTranscript(
		@PathVariable UUID transcriptId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return notivaService.transcript(transcriptId, principal);
	}

	@PostMapping("/voice-channels/{channelId}/notiva/start")
	public AzoomNotivaSessionResponse startNotiva(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomNotivaSessionResponse response = notivaService.start(channelId, principal);
		messagingTemplate.convertAndSend(
			"/topic/azoom/notiva/" + response.roomName(),
			new AzoomNotivaEventResponse("STARTED", response.roomName(), response.realtimeTranscript())
		);
		return response;
	}

	@PostMapping("/voice-channels/{channelId}/notiva/realtime-utterances")
	public AzoomMeetingTranscriptResponse appendNotivaRealtimeUtterance(
		@PathVariable String channelId,
		@Valid @RequestBody AzoomNotivaUtteranceRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomMeetingTranscriptResponse response = notivaService.appendRealtimeUtterance(channelId, request, principal);
		publishNotivaTranscript("REALTIME_UTTERANCE", response);
		return response;
	}

	@PostMapping("/voice-channels/{channelId}/notiva/finish")
	public AzoomMeetingTranscriptResponse finishNotiva(
		@PathVariable String channelId,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomMeetingTranscriptResponse response = notivaService.finishRealtime(channelId, principal);
		if (response != null) {
			publishNotivaTranscript("FINISHED", response);
		}
		return response;
	}

	@PostMapping("/voice-channels/{channelId}/notiva/realtime-audio")
	public AzoomNotivaAudioResponse transcribeNotivaRealtimeAudio(
		@PathVariable String channelId,
		@RequestParam("file") MultipartFile file,
		@RequestParam(value = "speakerUserId", required = false) String speakerUserId,
		@RequestParam(value = "speakerName", required = false) String speakerName,
		@RequestParam(value = "speakerEmail", required = false) String speakerEmail,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomNotivaAudioResponse response = notivaService.transcribeRealtimeAudio(
			channelId,
			file,
			speakerUserId,
			speakerName,
			speakerEmail,
			principal
		);
		publishNotivaTranscript("REALTIME_AUDIO", response.transcript());
		return response;
	}

	@PostMapping("/voice-channels/{channelId}/notiva/batch-audio")
	public AzoomNotivaAudioResponse transcribeNotivaBatchAudio(
		@PathVariable String channelId,
		@RequestParam("file") MultipartFile file,
		@RequestParam(value = "speakerUserId", required = false) String speakerUserId,
		@RequestParam(value = "speakerName", required = false) String speakerName,
		@RequestParam(value = "speakerEmail", required = false) String speakerEmail,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AzoomNotivaAudioResponse response = notivaService.transcribeBatchAudio(
			channelId,
			file,
			speakerUserId,
			speakerName,
			speakerEmail,
			principal
		);
		publishNotivaTranscript("BATCH_AUDIO", response.transcript());
		return response;
	}

	private void publishVoiceState(AzoomVoiceChannelResponse response) {
		messagingTemplate.convertAndSend("/topic/azoom/voice/" + response.roomName(), response);
	}

	private void publishVoiceStates(List<AzoomVoiceChannelResponse> responses) {
		for (AzoomVoiceChannelResponse response : responses) {
			publishVoiceState(response);
		}
	}

	private void publishNotivaTranscript(String type, AzoomMeetingTranscriptResponse response) {
		messagingTemplate.convertAndSend(
			"/topic/azoom/notiva/" + response.roomName(),
			new AzoomNotivaEventResponse(type, response.roomName(), response)
		);
	}
}
