package com.ava.backend.azoom.service;

import java.text.Normalizer;
import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.azoom.dto.AzoomChannelAccessRequest;
import com.ava.backend.azoom.dto.AzoomChannelMutationRequest;
import com.ava.backend.azoom.dto.AzoomChannelsResponse;
import com.ava.backend.azoom.dto.AzoomInviteCandidateResponse;
import com.ava.backend.azoom.dto.AzoomInviteMembersRequest;
import com.ava.backend.azoom.dto.AzoomLiveKitTokenResponse;
import com.ava.backend.azoom.dto.AzoomMemberMutationRequest;
import com.ava.backend.azoom.dto.AzoomMemberResponse;
import com.ava.backend.azoom.dto.AzoomVoiceChannelResponse;
import com.ava.backend.azoom.dto.AzoomVoiceEffectResponse;
import com.ava.backend.azoom.dto.AzoomVoiceJoinResponse;
import com.ava.backend.azoom.dto.AzoomVoiceStatusRequest;
import com.ava.backend.azoom.dto.AzoomWorkspaceResponse;
import com.ava.backend.azoom.entity.AzoomChannelAccessMode;
import com.ava.backend.azoom.entity.AzoomChannelEntity;
import com.ava.backend.azoom.entity.AzoomChannelType;
import com.ava.backend.azoom.entity.AzoomMemberEntity;
import com.ava.backend.azoom.entity.AzoomMemberRole;
import com.ava.backend.azoom.entity.AzoomWorkspaceEntity;
import com.ava.backend.azoom.repository.AzoomChannelRepository;
import com.ava.backend.azoom.repository.AzoomMemberRepository;
import com.ava.backend.azoom.repository.AzoomWorkspaceRepository;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.push.service.MobilePushService;
import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.mapper.UserMapper;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class AzoomService {

	private static final List<DefaultChannel> DEFAULT_VOICE_CHANNELS = List.of(
		new DefaultChannel("all-staff", "\uC804\uC9C1\uC6D0 \uD68C\uC758", 10),
		new DefaultChannel("ra", "RA \uD300", 20),
		new DefaultChannel("research", "\uC5F0\uAD6C\uC18C", 30)
	);

	private final AzoomWorkspaceRepository workspaceRepository;
	private final AzoomChannelRepository channelRepository;
	private final AzoomMemberRepository memberRepository;
	private final UserAccountRepository accountRepository;
	private final UserProfileRepository profileRepository;
	private final UserMapper userMapper;
	private final AzoomVoiceStateService voiceStateService;
	private final AzoomLiveKitTokenService liveKitTokenService;
	private final CompanyScopeService companyScopeService;
	private final MobilePushService mobilePushService;

	public AzoomService(
		AzoomWorkspaceRepository workspaceRepository,
		AzoomChannelRepository channelRepository,
		AzoomMemberRepository memberRepository,
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		UserMapper userMapper,
		AzoomVoiceStateService voiceStateService,
		AzoomLiveKitTokenService liveKitTokenService,
		CompanyScopeService companyScopeService,
		MobilePushService mobilePushService
	) {
		this.workspaceRepository = workspaceRepository;
		this.channelRepository = channelRepository;
		this.memberRepository = memberRepository;
		this.accountRepository = accountRepository;
		this.profileRepository = profileRepository;
		this.userMapper = userMapper;
		this.voiceStateService = voiceStateService;
		this.liveKitTokenService = liveKitTokenService;
		this.companyScopeService = companyScopeService;
		this.mobilePushService = mobilePushService;
	}

	@Transactional
	public AzoomChannelsResponse channels(AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		return new AzoomChannelsResponse(
			workspace.getCompanyName(),
			liveKitTokenService.enabled(),
			liveKitTokenService.liveKitUrl(),
			voiceChannels(workspace).stream()
				.map(channel -> voiceChannelResponse(channel, workspace.getCompanySlug(), principal))
				.toList()
		);
	}

	@Transactional
	public AzoomWorkspaceResponse workspace(AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		return workspaceResponse(workspace);
	}

	@Transactional
	public AzoomVoiceChannelResponse createVoiceChannel(
		AzoomChannelMutationRequest request,
		AuthPrincipal principal
	) {
		AzoomChannelEntity channel = createChannel(request, AzoomChannelType.VOICE, principal);
		return voiceChannelResponse(channel, channel.getWorkspace().getCompanySlug(), principal);
	}

	@Transactional
	public AzoomVoiceChannelResponse updateVoiceChannel(
		String channelId,
		AzoomChannelMutationRequest request,
		AuthPrincipal principal
	) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomManager(workspace, principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		channel.rename(trimToLimit(request.name(), 120));
		if (request.sortOrder() != null) {
			channel.setSortOrder(Math.max(0, request.sortOrder()));
		}
		return voiceChannelResponse(channel, workspace.getCompanySlug(), principal);
	}

	@Transactional
	public AzoomChannelsResponse archiveChannel(String channelId, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomManager(workspace, principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		channel.archive();
		return channels(principal);
	}

	@Transactional
	public AzoomWorkspaceResponse addMember(AzoomMemberMutationRequest request, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomManager(workspace, principal);
		UserAccount target = targetAccount(request.accountId(), request.email());
		AzoomMemberRole role = parseMemberRole(request.role());
		AzoomMemberEntity member = memberRepository
			.findByWorkspace_IdAndAccount_Id(workspace.getId(), target.getId())
			.orElseGet(() -> new AzoomMemberEntity(workspace, target, role));
		member.setRole(role);
		memberRepository.save(member);
		return workspaceResponse(workspace);
	}

	@Transactional
	public List<AzoomInviteCandidateResponse> inviteCandidates(AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomManager(workspace, principal);
		return profileRepository.findByCompanyNameIgnoreCase(workspace.getCompanyName()).stream()
			.filter(profile -> !memberRepository.existsByWorkspace_IdAndAccount_Id(
				workspace.getId(),
				profile.getAccount().getId()
			))
			.map(profile -> new AzoomInviteCandidateResponse(
				profile.getAccount().getId(),
				profile.getAccount().getEmail(),
				profile.getAccount().getDisplayName(),
				nullToEmpty(profile.getDepartment()),
				nullToEmpty(profile.getPosition()),
				profile.getAvatarColor(),
				nullToEmpty(profile.getAvatarImageUrl())
			))
			.toList();
	}

	@Transactional
	public AzoomWorkspaceResponse inviteMembers(AzoomInviteMembersRequest request, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomManager(workspace, principal);
		for (UUID accountId : request.accountIds() == null ? List.<UUID>of() : request.accountIds()) {
			UserAccount target = accountRepository.findById(accountId)
				.orElseThrow(() -> new IllegalArgumentException("AZOOM invite target account not found."));
			if (!memberRepository.existsByWorkspace_IdAndAccount_Id(workspace.getId(), target.getId())) {
				memberRepository.save(new AzoomMemberEntity(workspace, target, AzoomMemberRole.MEMBER));
			}
		}
		return workspaceResponse(workspace);
	}

	@Transactional
	public AzoomVoiceChannelResponse updateChannelAccess(
		String channelId,
		AzoomChannelAccessRequest request,
		AuthPrincipal principal
	) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomManager(workspace, principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		AzoomChannelAccessMode mode = parseChannelAccessMode(request.accessMode());
		String departments = normalizeDepartments(request.allowedDepartments());
		if (mode == AzoomChannelAccessMode.DEPARTMENTS && departments.isBlank()) {
			mode = AzoomChannelAccessMode.ALL;
		}
		channel.setAccess(mode, departments);
		return voiceChannelResponse(channel, workspace.getCompanySlug(), principal);
	}

	@Transactional
	public AzoomVoiceJoinResponse joinVoice(String channelId, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		assertChannelJoinAllowed(channel, principal);
		UserProfileResponse profile = currentProfile(principal);
		String roomName = voiceRoomName(channel, workspace.getCompanySlug());
		boolean wasEmpty = voiceStateService.participants(roomName).isEmpty();
		voiceStateService.join(roomName, profile);
		if (wasEmpty) {
			mobilePushService.sendAzoomVoiceStarted(
				azoomMobilePushRecipients(workspace),
				principal.userId(),
				channel.getChannelId(),
				channel.getName(),
				roomName
			);
		}
		return new AzoomVoiceJoinResponse(
			voiceChannelResponse(channel, workspace.getCompanySlug(), principal),
			liveKitTokenService.token(roomName, principal, profile)
		);
	}

	@Transactional
	public AzoomVoiceChannelResponse voiceState(String channelId, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		return voiceChannelResponse(channel(workspace, channelId, AzoomChannelType.VOICE), workspace.getCompanySlug(), principal);
	}

	@Transactional
	public List<AzoomVoiceChannelResponse> voiceStates(AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		return voiceChannels(workspace).stream()
			.map(channel -> voiceChannelResponse(channel, workspace.getCompanySlug(), principal))
			.toList();
	}

	@Transactional
	public AzoomVoiceChannelResponse updateVoiceStatus(
		String channelId,
		AzoomVoiceStatusRequest request,
		AuthPrincipal principal
	) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		assertChannelJoinAllowed(channel, principal);
		voiceStateService.update(voiceRoomName(channel, workspace.getCompanySlug()), currentProfile(principal), request);
		return voiceChannelResponse(channel, workspace.getCompanySlug(), principal);
	}

	@Transactional
	public AzoomLiveKitTokenResponse liveKitToken(String channelId, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		assertChannelJoinAllowed(channel, principal);
		String roomName = voiceRoomName(channel, workspace.getCompanySlug());
		return liveKitTokenService.token(roomName, principal, currentProfile(principal));
	}

	@Transactional
	public AzoomVoiceChannelResponse leaveVoice(String channelId, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		voiceStateService.leave(voiceRoomName(channel, workspace.getCompanySlug()), principal.userId());
		return voiceChannelResponse(channel, workspace.getCompanySlug(), principal);
	}

	@Transactional
	public List<AzoomVoiceChannelResponse> leaveDisconnectedVoice(AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		Set<String> changedRoomNames = voiceStateService.leaveAll(principal.userId());
		if (changedRoomNames.isEmpty()) {
			return List.of();
		}
		return voiceChannels(workspace).stream()
			.filter(channel -> changedRoomNames.contains(voiceRoomName(channel, workspace.getCompanySlug())))
			.map(channel -> voiceChannelResponse(channel, workspace.getCompanySlug(), principal))
			.toList();
	}

	@Transactional
	public AzoomVoiceEffectResponse voiceEffect(String channelId, String type, AuthPrincipal principal) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomAccess(workspace, principal);
		AzoomChannelEntity channel = channel(workspace, channelId, AzoomChannelType.VOICE);
		assertChannelJoinAllowed(channel, principal);
		return new AzoomVoiceEffectResponse(
			type,
			channel.getChannelId(),
			voiceRoomName(channel, workspace.getCompanySlug()),
			principal.userId(),
			Instant.now()
		);
	}

	public AzoomWorkspaceEntity workspaceForNotiva(AuthPrincipal principal) {
		return ensureWorkspace(principal);
	}

	public AzoomChannelEntity voiceChannelForNotiva(AzoomWorkspaceEntity workspace, String channelId) {
		return channel(workspace, channelId, AzoomChannelType.VOICE);
	}

	String voiceRoomNameForNotiva(AzoomChannelEntity channel, String companySlug) {
		return voiceRoomName(channel, companySlug);
	}

	Instant voiceStartedAtForNotiva(String roomName) {
		return voiceStateService.startedAt(roomName);
	}

	public UserProfileResponse currentProfileForNotiva(AuthPrincipal principal) {
		return currentProfile(principal);
	}

	private AzoomChannelEntity createChannel(
		AzoomChannelMutationRequest request,
		AzoomChannelType type,
		AuthPrincipal principal
	) {
		AzoomWorkspaceEntity workspace = ensureWorkspace(principal);
		assertAzoomManager(workspace, principal);
		String name = trimToLimit(request.name(), 120);
		String channelId = uniqueChannelId(workspace, request.channelId(), name);
		int sortOrder = request.sortOrder() == null ? nextSortOrder(workspace, type) : Math.max(0, request.sortOrder());
		return channelRepository.save(new AzoomChannelEntity(
			workspace,
			channelId,
			name,
			type,
			sortOrder,
			principal.userId()
		));
	}

	private AzoomWorkspaceEntity ensureWorkspace(AuthPrincipal principal) {
		String companyName = companyNameFor(principal);
		String companySlug = companySlug(companyName);
		ensureCompanyExists(companyName, principal);
		AzoomWorkspaceEntity workspace = workspaceRepository.findByCompanySlug(companySlug)
			.orElseGet(() -> workspaceRepository.save(new AzoomWorkspaceEntity(
				companyName,
				companySlug,
				companyName + " AZOOM",
				principal.userId()
			)));
		ensureDefaultChannels(workspace, principal);
		ensureDefaultMembers(workspace, principal);
		return workspace;
	}

	private void ensureDefaultChannels(AzoomWorkspaceEntity workspace, AuthPrincipal principal) {
		archiveObsoleteAllStaffChannels(workspace);
		for (DefaultChannel channel : DEFAULT_VOICE_CHANNELS) {
			channelRepository.findByWorkspace_IdAndChannelIdAndArchivedFalse(workspace.getId(), channel.id())
				.ifPresentOrElse(existing -> {
					if (!existing.getName().equals(channel.name())) {
						existing.rename(channel.name());
					}
					if (existing.getSortOrder() != channel.sortOrder()) {
						existing.setSortOrder(channel.sortOrder());
					}
				}, () -> {
				channelRepository.save(new AzoomChannelEntity(
					workspace,
					channel.id(),
					channel.name(),
					AzoomChannelType.VOICE,
					channel.sortOrder(),
					principal.userId()
				));
				});
		}
	}

	private void archiveObsoleteAllStaffChannels(AzoomWorkspaceEntity workspace) {
		for (AzoomChannelEntity channel : voiceChannels(workspace)) {
			String normalizedName = compactChannelName(channel.getName());
			if (!"all-staff".equals(channel.getChannelId()) &&
				("\uC804\uC9C1\uC6D0".equals(normalizedName) || "\uC804\uC9C1\uC6D0\uD68C\uC758".equals(normalizedName))) {
				channel.archive();
			}
		}
	}

	private String compactChannelName(String name) {
		return name == null ? "" : name.replaceAll("\\s+", "").trim();
	}

	private void ensureDefaultMembers(AzoomWorkspaceEntity workspace, AuthPrincipal principal) {
		accountRepository.findById(principal.userId()).ifPresent(account -> {
			if ((account.getRole() == UserRole.ADMIN || account.getRole() == UserRole.SUPERUSER) &&
				!memberRepository.existsByWorkspace_IdAndAccount_Id(workspace.getId(), account.getId())) {
				memberRepository.save(new AzoomMemberEntity(
					workspace,
					account,
					AzoomMemberRole.OWNER
				));
			}
		});
	}

	private AzoomWorkspaceResponse workspaceResponse(AzoomWorkspaceEntity workspace) {
		return new AzoomWorkspaceResponse(
			workspace.getId(),
			workspace.getCompanyName(),
			workspace.getCompanySlug(),
			workspace.getName(),
			memberRepository.findByWorkspace_IdOrderByJoinedAtAsc(workspace.getId()).stream()
				.map(member -> new AzoomMemberResponse(
					member.getAccount().getId(),
					member.getAccount().getEmail(),
					member.getAccount().getDisplayName(),
					member.getRole().name()
				))
				.toList()
		);
	}

	private void assertAzoomManager(AzoomWorkspaceEntity workspace, AuthPrincipal principal) {
		if (principal.role() == UserRole.ADMIN || principal.role() == UserRole.SUPERUSER) {
			return;
		}
		AzoomMemberRole role = memberRepository.findByWorkspace_IdAndAccount_Id(workspace.getId(), principal.userId())
			.map(AzoomMemberEntity::getRole)
			.orElse(AzoomMemberRole.MEMBER);
		if (role != AzoomMemberRole.OWNER && role != AzoomMemberRole.MANAGER) {
			throw new IllegalArgumentException("AZOOM manager permission is required.");
		}
	}

	private void assertAzoomAccess(AzoomWorkspaceEntity workspace, AuthPrincipal principal) {
		if (principal.role() == UserRole.ADMIN || principal.role() == UserRole.SUPERUSER) {
			return;
		}
		if (!memberRepository.existsByWorkspace_IdAndAccount_Id(workspace.getId(), principal.userId())) {
			throw new IllegalArgumentException("AZOOM permission is required.");
		}
	}

	private void assertChannelJoinAllowed(AzoomChannelEntity channel, AuthPrincipal principal) {
		if (principal.role() == UserRole.ADMIN || principal.role() == UserRole.SUPERUSER) {
			return;
		}
		if (canJoinChannel(channel, principal)) {
			return;
		}
		throw new IllegalArgumentException("AZOOM voice channel permission is required.");
	}

	private boolean canJoinChannel(AzoomChannelEntity channel, AuthPrincipal principal) {
		if (principal.role() == UserRole.ADMIN || principal.role() == UserRole.SUPERUSER) {
			return true;
		}
		if (channel.getAccessMode() == AzoomChannelAccessMode.ALL) {
			return true;
		}
		String department = profileRepository.findByAccountId(principal.userId())
			.map(UserProfile::getDepartment)
			.orElse("");
		if (department == null || department.isBlank()) {
			return false;
		}
		return allowedDepartments(channel).stream()
			.anyMatch(value -> value.equalsIgnoreCase(department.trim()));
	}

	private void ensureCompanyExists(String companyName, AuthPrincipal principal) {
		Set<UserAccount> accounts = new LinkedHashSet<>();
		for (UserProfile profile : profileRepository.findByCompanyNameIgnoreCase(companyName)) {
			accounts.add(profile.getAccount());
		}
		accountRepository.findById(principal.userId()).ifPresent(accounts::add);
		if (accounts.isEmpty()) {
			throw new IllegalArgumentException("AZOOM company scope is empty.");
		}
	}

	private List<UserAccount> azoomMobilePushRecipients(AzoomWorkspaceEntity workspace) {
		return memberRepository.findByWorkspace_IdOrderByJoinedAtAsc(workspace.getId()).stream()
			.map(AzoomMemberEntity::getAccount)
			.toList();
	}

	private List<AzoomChannelEntity> voiceChannels(AzoomWorkspaceEntity workspace) {
		return channelRepository.findByWorkspace_IdAndTypeAndArchivedFalseOrderBySortOrderAscNameAsc(
			workspace.getId(),
			AzoomChannelType.VOICE
		);
	}

	private AzoomChannelEntity channel(
		AzoomWorkspaceEntity workspace,
		String channelId,
		AzoomChannelType type
	) {
		AzoomChannelEntity channel = channelRepository
			.findByWorkspace_IdAndChannelIdAndArchivedFalse(workspace.getId(), channelId)
			.orElseThrow(() -> new IllegalArgumentException("AZOOM channel not found."));
		if (channel.getType() != type) {
			throw new IllegalArgumentException("AZOOM channel type mismatch.");
		}
		return channel;
	}

	private AzoomVoiceChannelResponse voiceChannelResponse(
		AzoomChannelEntity channel,
		String companySlug,
		AuthPrincipal principal
	) {
		String roomName = voiceRoomName(channel, companySlug);
		return new AzoomVoiceChannelResponse(
			channel.getChannelId(),
			channel.getName(),
			roomName,
			voiceStateService.startedAt(roomName),
			java.time.Instant.now(),
			channel.getAccessMode().name(),
			allowedDepartments(channel),
			canJoinChannel(channel, principal),
			voiceStateService.participants(roomName)
		);
	}

	private AzoomChannelAccessMode parseChannelAccessMode(String accessMode) {
		if (accessMode == null || accessMode.isBlank()) {
			return AzoomChannelAccessMode.ALL;
		}
		String normalized = accessMode.trim().toUpperCase(Locale.ROOT);
		if ("SELECTED_DEPARTMENTS".equals(normalized) || "DEPARTMENT".equals(normalized)) {
			return AzoomChannelAccessMode.DEPARTMENTS;
		}
		return AzoomChannelAccessMode.valueOf(normalized);
	}

	private List<String> allowedDepartments(AzoomChannelEntity channel) {
		String value = channel.getAllowedDepartments();
		if (value == null || value.isBlank()) {
			return List.of();
		}
		return List.of(value.split("\\R|,|;")).stream()
			.map(String::trim)
			.filter(item -> !item.isBlank())
			.distinct()
			.toList();
	}

	private String normalizeDepartments(List<String> departments) {
		if (departments == null || departments.isEmpty()) {
			return "";
		}
		return departments.stream()
			.map(item -> item == null ? "" : item.trim())
			.filter(item -> !item.isBlank())
			.distinct()
			.collect(Collectors.joining("\n"));
	}

	private String nullToEmpty(String value) {
		return value == null ? "" : value;
	}

	private UserProfileResponse currentProfile(AuthPrincipal principal) {
		UserAccount account = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("Account not found."));
		UserProfile profile = profileRepository.findByAccountId(account.getId())
			.orElseGet(() -> new UserProfile(account, "AVA", "\uC628\uB77C\uC778", "#7AA06A"));
		return userMapper.toResponse(account, profile);
	}

	private UserAccount targetAccount(UUID accountId, String email) {
		if (accountId != null) {
			return accountRepository.findById(accountId)
				.orElseThrow(() -> new IllegalArgumentException("AZOOM member account not found."));
		}
		if (email != null && !email.isBlank()) {
			return accountRepository.findByEmailIgnoreCase(email.trim())
				.orElseThrow(() -> new IllegalArgumentException("AZOOM member account not found."));
		}
		throw new IllegalArgumentException("AZOOM member account is required.");
	}

	private AzoomMemberRole parseMemberRole(String role) {
		if (role == null || role.isBlank()) {
			return AzoomMemberRole.MEMBER;
		}
		return AzoomMemberRole.valueOf(role.trim().toUpperCase(Locale.ROOT));
	}

	private int nextSortOrder(AzoomWorkspaceEntity workspace, AzoomChannelType type) {
		return channelRepository.findByWorkspace_IdAndTypeAndArchivedFalseOrderBySortOrderAscNameAsc(
			workspace.getId(),
			type
		).stream()
			.mapToInt(AzoomChannelEntity::getSortOrder)
			.max()
			.orElse(0) + 10;
	}

	private String uniqueChannelId(AzoomWorkspaceEntity workspace, String requestedId, String name) {
		String base = slug(requestedId == null || requestedId.isBlank() ? name : requestedId);
		for (int suffix = 0; suffix < 1000; suffix++) {
			String candidate = suffix == 0 ? base : base + "-" + suffix;
			if (!channelRepository.existsByWorkspace_IdAndChannelId(workspace.getId(), candidate)) {
				return candidate;
			}
		}
		throw new IllegalArgumentException("Could not allocate AZOOM channel id.");
	}

	private String slug(String value) {
		String source = Normalizer.normalize(value == null ? "" : value, Normalizer.Form.NFKD)
			.toLowerCase(Locale.ROOT);
		String sanitized = source.replaceAll("[^a-z0-9]+", "-")
			.replaceAll("^-+", "")
			.replaceAll("-+$", "");
		if (sanitized.isBlank()) {
			sanitized = "channel";
		}
		return sanitized.length() > 40 ? sanitized.substring(0, 40).replaceAll("-+$", "") : sanitized;
	}

	private String trimToLimit(String value, int maxLength) {
		String trimmed = value == null ? "" : value.trim();
		if (trimmed.isBlank()) {
			throw new IllegalArgumentException("AZOOM channel name is required.");
		}
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}

	private String companyNameFor(AuthPrincipal principal) {
		return companyScopeService.effectiveCompany(principal);
	}

	private String voiceRoomName(AzoomChannelEntity channel, String companySlug) {
		return "azoom-" + companySlug + "-voice-" + channel.getChannelId();
	}

	private String companySlug(String companyName) {
		String source = Normalizer.normalize(companyName, Normalizer.Form.NFKD)
			.toLowerCase(Locale.ROOT);
		String sanitized = source.replaceAll("[^a-z0-9]+", "-")
			.replaceAll("^-+", "")
			.replaceAll("-+$", "");
		if (sanitized.isBlank()) {
			sanitized = "company";
		}
		if (sanitized.length() > 28) {
			sanitized = sanitized.substring(0, 28).replaceAll("-+$", "");
		}
		String hash = Integer.toUnsignedString(companyName.toLowerCase(Locale.ROOT).hashCode(), 36);
		return sanitized + "-" + hash;
	}

	private record DefaultChannel(String id, String name, int sortOrder) {
	}
}
