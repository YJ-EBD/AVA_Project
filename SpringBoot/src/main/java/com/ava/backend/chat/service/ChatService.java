package com.ava.backend.chat.service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.chat.dao.ChatRoomDao;
import com.ava.backend.chat.dto.ChatMessageReadState;
import com.ava.backend.chat.dto.ChatMessageRequest;
import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.dto.ChatMentionRequest;
import com.ava.backend.chat.dto.ChatMentionResponse;
import com.ava.backend.chat.dto.ChatMentionNotificationResponse;
import com.ava.backend.chat.dto.ChatNoticeRequest;
import com.ava.backend.chat.dto.ChatPinRequest;
import com.ava.backend.chat.dto.ChatReadStateResponse;
import com.ava.backend.chat.dto.ChatRoomLeaveResponse;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.chat.dto.ChatTalkDrawerItemResponse;
import com.ava.backend.chat.dto.DirectChatRoomRequest;
import com.ava.backend.chat.dto.GroupChatRoomRequest;
import com.ava.backend.chat.entity.ChatMessageEntity;
import com.ava.backend.chat.entity.ChatMessageDocument;
import com.ava.backend.chat.entity.ChatMentionNotificationEntity;
import com.ava.backend.chat.entity.ChatMessageReadReceiptEntity;
import com.ava.backend.chat.entity.ChatRoomEntity;
import com.ava.backend.chat.entity.ChatRoomMemberEntity;
import com.ava.backend.chat.entity.ChatRoomType;
import com.ava.backend.chat.entity.ChatTalkDrawerItemEntity;
import com.ava.backend.chat.entity.ChatTalkDrawerMediaType;
import com.ava.backend.chat.mapper.ChatMapper;
import com.ava.backend.chat.repository.ChatMessageJpaRepository;
import com.ava.backend.chat.repository.ChatMentionNotificationRepository;
import com.ava.backend.chat.repository.ChatMessageReadReceiptRepository;
import com.ava.backend.chat.repository.ChatMessageRepository;
import com.ava.backend.chat.repository.ChatRoomMemberRepository;
import com.ava.backend.chat.repository.ChatRoomRepository;
import com.ava.backend.chat.repository.ChatTalkDrawerItemRepository;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.mapper.UserMapper;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;
import com.ava.backend.user.service.ChatFolderSettingsService;

@Service
public class ChatService {

	private final ChatRoomDao chatRoomDao;
	private final ChatRoomRepository roomRepository;
	private final ChatRoomMemberRepository memberRepository;
	private final ChatMessageJpaRepository messageJpaRepository;
	private final ChatMentionNotificationRepository mentionNotificationRepository;
	private final ChatMessageReadReceiptRepository readReceiptRepository;
	private final ChatMessageRepository messageRepository;
	private final ChatTalkDrawerItemRepository talkDrawerItemRepository;
	private final UserAccountRepository accountRepository;
	private final UserProfileRepository profileRepository;
	private final UserMapper userMapper;
	private final ChatMapper chatMapper;
	private final ChatFolderSettingsService chatFolderSettingsService;
	private final CompanyScopeService companyScopeService;
	private final CompanyAllStaffChatService allStaffChatService;
	private final Path backupDirectory;
	private final Path attachmentDirectory;
	private final boolean mongoEnabled;

	public ChatService(
		ChatRoomDao chatRoomDao,
		ChatRoomRepository roomRepository,
		ChatRoomMemberRepository memberRepository,
		ChatMessageJpaRepository messageJpaRepository,
		ChatMentionNotificationRepository mentionNotificationRepository,
		ChatMessageReadReceiptRepository readReceiptRepository,
		ChatMessageRepository messageRepository,
		ChatTalkDrawerItemRepository talkDrawerItemRepository,
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		UserMapper userMapper,
		ChatMapper chatMapper,
		ChatFolderSettingsService chatFolderSettingsService,
		CompanyScopeService companyScopeService,
		CompanyAllStaffChatService allStaffChatService,
		@Value("${ava.chat.backup-directory:ChatBackUp}") String backupDirectory,
		@Value("${ava.chat.attachment-directory:ChatUploads}") String attachmentDirectory,
		@Value("${ava.chat.mongo-enabled:true}") boolean mongoEnabled
	) {
		this.chatRoomDao = chatRoomDao;
		this.roomRepository = roomRepository;
		this.memberRepository = memberRepository;
		this.messageJpaRepository = messageJpaRepository;
		this.mentionNotificationRepository = mentionNotificationRepository;
		this.readReceiptRepository = readReceiptRepository;
		this.messageRepository = messageRepository;
		this.talkDrawerItemRepository = talkDrawerItemRepository;
		this.accountRepository = accountRepository;
		this.profileRepository = profileRepository;
		this.userMapper = userMapper;
		this.chatMapper = chatMapper;
		this.chatFolderSettingsService = chatFolderSettingsService;
		this.companyScopeService = companyScopeService;
		this.allStaffChatService = allStaffChatService;
		this.backupDirectory = Path.of(backupDirectory);
		this.attachmentDirectory = Path.of(attachmentDirectory);
		this.mongoEnabled = mongoEnabled;
	}

	@Transactional(readOnly = true)
	public List<ChatRoomResponse> rooms(AuthPrincipal principal) {
		Map<String, Instant> pinnedRoomOrder = chatFolderSettingsService.pinnedRoomOrder(principal);
		String companyName = companyScopeService.effectiveCompany(principal);
		return chatRoomDao.findAllRooms().stream()
			.filter(room -> companyName.equalsIgnoreCase(roomCompanyName(room)))
			.filter(room -> roomVisibleToPrincipal(room, principal))
			.filter(room -> shouldDisplayInRoomList(room, principal))
			.sorted(Comparator
				.comparing((ChatRoomEntity room) -> !pinnedRoomOrder.containsKey(room.getCode()))
				.thenComparing(
					room -> pinnedRoomOrder.get(room.getCode()),
					Comparator.nullsLast(Comparator.reverseOrder())
				)
				.thenComparing(ChatRoomEntity::getLastMessageAt, Comparator.reverseOrder()))
			.map(room -> toRoomResponse(
				room,
				pinnedRoomOrder.containsKey(room.getCode()),
				pinnedRoomOrder.get(room.getCode()),
				principal
			))
			.toList();
	}

	private boolean roomVisibleToPrincipal(ChatRoomEntity room, AuthPrincipal principal) {
		if (memberRepository.existsByRoomCodeAndAccountId(room.getCode(), principal.userId())) {
			return true;
		}
		if (principal.role() != UserRole.SUPERUSER) {
			return false;
		}
		return room.getType() == ChatRoomType.GROUP;
	}

	private boolean shouldDisplayInRoomList(ChatRoomEntity room, AuthPrincipal principal) {
		if (isAzoomRoom(room)) {
			return false;
		}
		if (room.getType() != ChatRoomType.SELF) {
			if (allStaffChatService.isAllStaffRoom(room)) {
				return true;
			}
			if (hasLastMessage(room)) {
				return true;
			}
			return room.getCreatedByAccountId() != null
				&& room.getCreatedByAccountId().equals(principal.userId());
		}
		return hasLastMessage(room);
	}

	private boolean isAzoomRoom(ChatRoomEntity room) {
		return isAzoomRoomCode(room.getCode());
	}

	public boolean isAzoomRoomCode(String roomCode) {
		return roomCode != null && (
			roomCode.startsWith("azoom-")
				|| roomCode.startsWith("azoom:")
				|| roomCode.startsWith("azoom_")
		);
	}

	private boolean hasLastMessage(ChatRoomEntity room) {
		return room.getLastMessage() != null && !room.getLastMessage().isBlank();
	}

	@Transactional(readOnly = true)
	public ChatRoomResponse room(String roomCode) {
		return toRoomResponse(chatRoomDao.findByCode(roomCode));
	}

	@Transactional(readOnly = true)
	public ChatRoomResponse roomForMember(String roomCode, UUID accountId) {
		ChatRoomEntity room = chatRoomDao.findByCode(roomCode);
		UserAccount account = accountRepository.findById(accountId)
			.orElseThrow(() -> new IllegalArgumentException("Account not found."));
		return toRoomResponse(room, new AuthPrincipal(
			account.getId(),
			account.getEmail(),
			account.getDisplayName(),
			account.getRole(),
			""
		));
	}

	@Transactional
	public ChatRoomResponse startDirectRoom(DirectChatRoomRequest request, AuthPrincipal principal) {
		UserAccount currentUser = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("Account not found."));
		UserAccount targetUser = findDirectTarget(request);
		String companyName = companyScopeService.effectiveCompany(principal);
		assertTargetInCompany(targetUser, companyName);
		if (currentUser.getId().equals(targetUser.getId())) {
			throw new IllegalArgumentException("Cannot start a direct room with yourself.");
		}

		ChatRoomEntity room = findExistingDirectRoom(currentUser.getId(), targetUser.getId(), companyName)
			.orElseGet(() -> createDirectRoom(currentUser, targetUser, companyName));
		return toRoomResponse(room, principal);
	}

	@Transactional
	public ChatRoomResponse startGroupRoom(GroupChatRoomRequest request, AuthPrincipal principal) {
		UserAccount currentUser = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("Account not found."));
		LinkedHashSet<UUID> targetIds = new LinkedHashSet<>(request.targetUserIds());
		targetIds.remove(currentUser.getId());
		if (targetIds.isEmpty()) {
			throw new IllegalArgumentException("Group chat needs at least one participant.");
		}

		List<UserAccount> targetUsers = new ArrayList<>();
		String companyName = companyScopeService.effectiveCompany(principal);
		for (UUID targetId : targetIds) {
			UserAccount targetUser = accountRepository.findById(targetId)
				.orElseThrow(() -> new IllegalArgumentException("Group chat target not found."));
			assertTargetInCompany(targetUser, companyName);
			targetUsers.add(targetUser);
		}

		String title = trimToNull(request.title());
		if (title == null) {
			title = targetUsers.stream()
				.map(UserAccount::getDisplayName)
				.filter(name -> name != null && !name.isBlank())
				.limit(8)
				.reduce((first, second) -> first + ", " + second)
				.orElse("\uADF8\uB8F9\uCC44\uD305");
		}
		if (title.length() > 120) {
			title = title.substring(0, 120);
		}

		ChatRoomEntity room = new ChatRoomEntity(
			"group-" + UUID.randomUUID(),
			title,
			ChatRoomType.GROUP,
			false,
			""
		);
		room.setCompanyName(companyName);
		room.setCreatedByAccountId(currentUser.getId());
		room.setAvatarImageUrl(normalizeAvatarImageUrl(request.avatarImageUrl()));
		room = roomRepository.save(room);
		ensureMember(room, currentUser);
		for (UserAccount targetUser : targetUsers) {
			ensureMember(room, targetUser);
		}
		return toRoomResponse(room, principal);
	}

	@Transactional
	public ChatRoomResponse startSelfRoom(AuthPrincipal principal) {
		UserAccount currentUser = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("Account not found."));
		String roomCode = selfRoomCode(currentUser.getId());
		ChatRoomEntity room = roomRepository.findByCode(roomCode)
			.filter(item -> item.getType() == ChatRoomType.SELF)
			.orElseGet(() -> roomRepository.save(new ChatRoomEntity(
				roomCode,
				"\uB098\uC640\uC758 \uCC44\uD305",
				ChatRoomType.SELF,
				false,
				""
			)));
		room.setCompanyName(companyScopeService.effectiveCompany(principal));
		ensureMember(room, currentUser);
		roomRepository.save(room);
		return toRoomResponse(room, principal);
	}

	@Transactional
	public ChatRoomResponse inviteMembers(String roomCode, GroupChatRoomRequest request, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		ChatRoomEntity room = chatRoomDao.findByCode(roomCode);
		if (room.getType() == ChatRoomType.SELF) {
			throw new IllegalArgumentException("Cannot invite members to this room.");
		}
		LinkedHashSet<UUID> targetIds = new LinkedHashSet<>(request.targetUserIds());
		targetIds.remove(principal.userId());
		if (targetIds.isEmpty()) {
			throw new IllegalArgumentException("Invite target is empty.");
		}
		if (room.getType() == ChatRoomType.DIRECT) {
			for (ChatRoomMemberEntity member : memberRepository.findByRoomCode(roomCode)) {
				UUID accountId = member.getAccount().getId();
				if (!accountId.equals(principal.userId())) {
					targetIds.add(accountId);
				}
			}
			return startGroupRoom(
				new GroupChatRoomRequest(
					new ArrayList<>(targetIds),
					request.title(),
					request.avatarImageUrl()
				),
				principal
			);
		}

		String companyName = companyScopeService.effectiveCompany(principal);
		List<String> addedNames = new ArrayList<>();
		for (UUID targetId : targetIds) {
			UserAccount targetUser = accountRepository.findById(targetId)
				.orElseThrow(() -> new IllegalArgumentException("Invite target not found."));
			assertTargetInCompany(targetUser, companyName);
			if (!memberRepository.existsByRoomCodeAndAccountId(roomCode, targetUser.getId())) {
				ensureMember(room, targetUser);
				addedNames.add(targetUser.getDisplayName());
			}
		}
		if (!addedNames.isEmpty()) {
			String content = principal.displayName() + "\uB2D8\uC774 " + String.join(", ", addedNames)
				+ "\uB2D8\uC744 \uCD08\uB300\uD588\uC2B5\uB2C8\uB2E4.";
			messageJpaRepository.save(ChatMessageEntity.system(
				roomCode,
				principal.userId(),
				principal.displayName(),
				content
			));
			room.updateLastMessage(content);
			roomRepository.save(room);
		}
		return toRoomResponse(room, principal);
	}

	@Transactional(readOnly = true)
	public List<ChatMessageResponse> recentMessages(String roomCode, AuthPrincipal principal, int limit) {
		ChatRoomMemberEntity membership = assertMember(roomCode, principal);
		Instant visibleSince = membership == null ? null : membership.getJoinedAt();
		Pageable page = PageRequest.of(0, normalizeMessageLimit(limit));
		List<ChatMessageEntity> visibleMessages = visibleSince == null
			? messageJpaRepository.findByRoomCodeOrderBySentAtDesc(roomCode, page)
			: messageJpaRepository.findByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtDesc(roomCode, visibleSince, page);
		List<ChatMessageEntity> sortedMessages = visibleMessages.stream()
			.sorted(Comparator.comparing(ChatMessageEntity::getSentAt))
			.toList();
		List<ChatMessageResponse> savedMessages = toMessageResponses(roomCode, sortedMessages);
		if (!savedMessages.isEmpty() || !mongoEnabled || visibleSince != null) {
			return savedMessages;
		}
		try {
			return messageRepository.findTop50ByRoomCodeOrderBySentAtDesc(roomCode).stream()
				.sorted(Comparator.comparing(ChatMessageDocument::getSentAt))
				.map(chatMapper::toMessageResponse)
				.map(this::withSenderProfile)
				.toList();
		} catch (RuntimeException ignored) {
			return List.of();
		}
	}

	@Transactional(readOnly = true)
	public List<ChatMessageResponse> recentMessages(String roomCode, AuthPrincipal principal) {
		return recentMessages(roomCode, principal, 80);
	}

	@Transactional(readOnly = true)
	public List<ChatMessageResponse> messagesAround(
		String roomCode,
		UUID messageId,
		AuthPrincipal principal,
		int before,
		int after
	) {
		ChatRoomMemberEntity membership = assertMember(roomCode, principal);
		ChatMessageEntity target = messageJpaRepository.findById(messageId)
			.filter(message -> roomCode.equals(message.getRoomCode()))
			.orElseThrow(() -> new IllegalArgumentException("Chat message not found."));
		if (membership != null && membership.getJoinedAt() != null && target.getSentAt().isBefore(membership.getJoinedAt())) {
			throw new IllegalArgumentException("Chat message is not visible.");
		}
		int beforeLimit = Math.max(0, Math.min(before, 80));
		int afterLimit = Math.max(0, Math.min(after, 80));
		List<ChatMessageEntity> messages = new ArrayList<>();
		List<ChatMessageEntity> previous = messageJpaRepository
			.findByRoomCodeAndSentAtLessThanOrderBySentAtDesc(
				roomCode,
				target.getSentAt(),
				PageRequest.of(0, beforeLimit)
			)
			.stream()
			.sorted(Comparator.comparing(ChatMessageEntity::getSentAt))
			.toList();
		messages.addAll(previous);
		messages.add(target);
		messages.addAll(messageJpaRepository.findByRoomCodeAndSentAtGreaterThanOrderBySentAtAsc(
			roomCode,
			target.getSentAt(),
			PageRequest.of(0, afterLimit)
		));
		return toMessageResponses(roomCode, messages);
	}

	@Transactional(readOnly = true)
	public List<ChatMessageResponse> messagesBefore(
		String roomCode,
		UUID messageId,
		AuthPrincipal principal,
		int limit
	) {
		ChatRoomMemberEntity membership = assertMember(roomCode, principal);
		ChatMessageEntity boundary = messageJpaRepository.findById(messageId)
			.filter(message -> roomCode.equals(message.getRoomCode()))
			.orElseThrow(() -> new IllegalArgumentException("Chat message not found."));
		Instant visibleSince = membership == null ? null : membership.getJoinedAt();
		if (visibleSince != null && boundary.getSentAt().isBefore(visibleSince)) {
			throw new IllegalArgumentException("Chat message is not visible.");
		}
		Pageable page = PageRequest.of(0, normalizeMessageLimit(limit));
		List<ChatMessageEntity> olderMessages = visibleSince == null
			? messageJpaRepository.findByRoomCodeAndSentAtLessThanOrderBySentAtDesc(
				roomCode,
				boundary.getSentAt(),
				page
			)
			: messageJpaRepository.findByRoomCodeAndSentAtGreaterThanEqualAndSentAtLessThanOrderBySentAtDesc(
				roomCode,
				visibleSince,
				boundary.getSentAt(),
				page
			);
		List<ChatMessageEntity> sortedMessages = olderMessages.stream()
			.sorted(Comparator.comparing(ChatMessageEntity::getSentAt))
			.toList();
		return toMessageResponses(roomCode, sortedMessages);
	}

	@Transactional(readOnly = true)
	public List<ChatMessageResponse> recentMessagesIgnoringJoin(String roomCode, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		List<ChatMessageEntity> sortedMessages = messageJpaRepository.findTop50ByRoomCodeOrderBySentAtDesc(roomCode)
			.stream()
			.sorted(Comparator.comparing(ChatMessageEntity::getSentAt))
			.toList();
		List<ChatMessageResponse> savedMessages = toMessageResponses(roomCode, sortedMessages);
		if (!savedMessages.isEmpty() || !mongoEnabled) {
			return savedMessages;
		}
		try {
			return messageRepository.findTop50ByRoomCodeOrderBySentAtDesc(roomCode).stream()
				.sorted(Comparator.comparing(ChatMessageDocument::getSentAt))
				.map(chatMapper::toMessageResponse)
				.map(this::withSenderProfile)
				.toList();
		} catch (RuntimeException ignored) {
			return List.of();
		}
	}

	@Transactional
	public ChatMessageResponse send(String roomCode, ChatMessageRequest request, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		var room = chatRoomDao.findByCode(roomCode);
		String content = request.content().trim();
		boolean silent = request.isSilent();
		boolean spoiler = request.isSpoiler();
		String senderName = displayNameFor(principal.userId(), principal.displayName());
		List<ChatMentionResponse> mentions = resolveMentions(roomCode, content, request.normalizedMentions());
		var savedMessage = messageJpaRepository.save(new ChatMessageEntity(
			roomCode,
			principal.userId(),
			senderName,
			content,
			silent,
			spoiler,
			mentions.stream().map(ChatMentionResponse::userId).toList(),
			mentions.stream().map(ChatMentionResponse::displayName).toList()
		));
		readReceiptRepository.save(new ChatMessageReadReceiptEntity(savedMessage, principal.userId()));
		createMentionNotifications(savedMessage, mentions, principal.userId());
		if (mongoEnabled) {
			archiveToMongo(roomCode, principal, senderName, content, silent, spoiler, mentions);
		}
		room.updateLastMessage(content, spoiler);
		roomRepository.save(room);
		return toMessageResponse(savedMessage);
	}

	@Transactional
	public ChatMessageResponse sendAttachment(
		String roomCode,
		MultipartFile file,
		String groupId,
		AuthPrincipal principal
	) {
		assertMember(roomCode, principal);
		if (file == null || file.isEmpty()) {
			throw new IllegalArgumentException("Attachment file is required.");
		}
		var room = chatRoomDao.findByCode(roomCode);
		String originalName = sanitizeFileName(file.getOriginalFilename());
		String contentType = normalizeContentType(file.getContentType());
		long size = file.getSize();
		String normalizedGroupId = normalizeAttachmentGroupId(groupId);
		String storedName = UUID.randomUUID() + "-" + originalName;
		Path roomDirectory = attachmentDirectory.resolve(roomCode);
		Path storedPath = roomDirectory.resolve(storedName).normalize();
		if (!storedPath.startsWith(roomDirectory.normalize())) {
			throw new IllegalArgumentException("Invalid attachment path.");
		}
		String checksumSha256;
		try {
			Files.createDirectories(roomDirectory);
			MessageDigest digest = MessageDigest.getInstance("SHA-256");
			try (InputStream inputStream = new DigestInputStream(file.getInputStream(), digest)) {
				Files.copy(inputStream, storedPath, StandardCopyOption.REPLACE_EXISTING);
			}
			checksumSha256 = HexFormat.of().formatHex(digest.digest());
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to store attachment.", exception);
		} catch (NoSuchAlgorithmException exception) {
			throw new IllegalStateException("SHA-256 digest is not available.", exception);
		}

		ChatMessageEntity savedMessage = messageJpaRepository.save(ChatMessageEntity.attachment(
			roomCode,
			principal.userId(),
			displayNameFor(principal.userId(), principal.displayName()),
			originalName,
			contentType,
			size,
			storedPath.toString(),
			normalizedGroupId
		));
		readReceiptRepository.save(new ChatMessageReadReceiptEntity(savedMessage, principal.userId()));
		talkDrawerItemRepository.save(new ChatTalkDrawerItemEntity(
			companyScopeService.effectiveCompany(principal),
			roomCode,
			savedMessage.getId(),
			savedMessage.getAttachmentId(),
			normalizedGroupId,
			originalName,
			contentType,
			size,
			mediaTypeFor(originalName, contentType),
			storedPath.toString(),
			checksumSha256,
			principal.userId(),
			displayNameFor(principal.userId(), principal.displayName())
		));
		room.updateLastMessage(attachmentPreview(originalName, contentType), false);
		roomRepository.save(room);
		return toMessageResponse(savedMessage);
	}

	@Transactional
	public ChatMessageResponse sendAttachmentFromPath(
		String roomCode,
		Path sourcePath,
		String groupId,
		AuthPrincipal principal
	) {
		assertMember(roomCode, principal);
		if (sourcePath == null || !Files.isRegularFile(sourcePath)) {
			throw new IllegalArgumentException("Attachment file is required.");
		}
		var room = chatRoomDao.findByCode(roomCode);
		String originalName = sanitizeFileName(sourcePath.getFileName().toString());
		String probedContentType;
		try {
			probedContentType = Files.probeContentType(sourcePath);
		} catch (IOException ignored) {
			probedContentType = null;
		}
		String contentType = normalizeContentType(probedContentType);
		String normalizedGroupId = normalizeAttachmentGroupId(groupId);
		String storedName = UUID.randomUUID() + "-" + originalName;
		Path roomDirectory = attachmentDirectory.resolve(roomCode);
		Path storedPath = roomDirectory.resolve(storedName).normalize();
		if (!storedPath.startsWith(roomDirectory.normalize())) {
			throw new IllegalArgumentException("Invalid attachment path.");
		}
		long size;
		String checksumSha256;
		try {
			Files.createDirectories(roomDirectory);
			size = Files.size(sourcePath);
			MessageDigest digest = MessageDigest.getInstance("SHA-256");
			try (InputStream inputStream = new DigestInputStream(Files.newInputStream(sourcePath), digest)) {
				Files.copy(inputStream, storedPath, StandardCopyOption.REPLACE_EXISTING);
			}
			checksumSha256 = HexFormat.of().formatHex(digest.digest());
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to store attachment.", exception);
		} catch (NoSuchAlgorithmException exception) {
			throw new IllegalStateException("SHA-256 digest is not available.", exception);
		}

		ChatMessageEntity savedMessage = messageJpaRepository.save(ChatMessageEntity.attachment(
			roomCode,
			principal.userId(),
			displayNameFor(principal.userId(), principal.displayName()),
			originalName,
			contentType,
			size,
			storedPath.toString(),
			normalizedGroupId
		));
		readReceiptRepository.save(new ChatMessageReadReceiptEntity(savedMessage, principal.userId()));
		talkDrawerItemRepository.save(new ChatTalkDrawerItemEntity(
			companyScopeService.effectiveCompany(principal),
			roomCode,
			savedMessage.getId(),
			savedMessage.getAttachmentId(),
			normalizedGroupId,
			originalName,
			contentType,
			size,
			mediaTypeFor(originalName, contentType),
			storedPath.toString(),
			checksumSha256,
			principal.userId(),
			displayNameFor(principal.userId(), principal.displayName())
		));
		room.updateLastMessage(attachmentPreview(originalName, contentType), false);
		roomRepository.save(room);
		return toMessageResponse(savedMessage);
	}

	@Transactional(readOnly = true)
	public List<ChatTalkDrawerItemResponse> talkDrawerItems(
		String roomCode,
		String mediaType,
		AuthPrincipal principal
	) {
		assertMember(roomCode, principal);
		String companyName = companyScopeService.effectiveCompany(principal);
		ChatTalkDrawerMediaType type = parseMediaType(mediaType);
		List<ChatTalkDrawerItemEntity> items = type == null
			? talkDrawerItemRepository.findTop200ByCompanyNameIgnoreCaseAndRoomCodeAndDeletedFalseOrderByUploadedAtDesc(
				companyName,
				roomCode
			)
			: talkDrawerItemRepository.findTop200ByCompanyNameIgnoreCaseAndRoomCodeAndMediaTypeAndDeletedFalseOrderByUploadedAtDesc(
				companyName,
				roomCode,
				type
			);
		return items.stream()
			.map(chatMapper::toTalkDrawerItemResponse)
			.toList();
	}

	@Transactional(readOnly = true)
	public AttachmentDownload attachment(String roomCode, String attachmentId, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		ChatMessageEntity message = messageJpaRepository
			.findByRoomCodeAndAttachmentId(roomCode, attachmentId)
			.orElseThrow(() -> new IllegalArgumentException("Attachment not found."));
		if (!message.hasAttachment()) {
			throw new IllegalArgumentException("Attachment not found.");
		}
		try {
			Path path = Path.of(message.getAttachmentStoredPath()).normalize();
			Resource resource = new UrlResource(path.toUri());
			if (!resource.exists() || !resource.isReadable()) {
				throw new IllegalArgumentException("Attachment file is not available.");
			}
			return new AttachmentDownload(
				resource,
				message.getAttachmentFileName(),
				message.getAttachmentContentType(),
				message.getAttachmentSize()
			);
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to read attachment.", exception);
		}
	}

	@Transactional
	public ChatMessageResponse deleteMessageForEveryone(String roomCode, UUID messageId, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		ChatMessageEntity message = messageJpaRepository.findById(messageId)
			.filter(item -> roomCode.equals(item.getRoomCode()))
			.orElseThrow(() -> new IllegalArgumentException("Message not found."));
		if (!message.getSenderId().equals(principal.userId()) &&
			principal.role() != UserRole.ADMIN &&
			principal.role() != UserRole.SUPERUSER) {
			throw new AccessDeniedException("Only the sender can delete this message for everyone.");
		}

		message.markDeletedForEveryone();
		ChatMessageEntity savedMessage = messageJpaRepository.save(message);
		for (ChatTalkDrawerItemEntity item : talkDrawerItemRepository.findByRoomCodeAndMessageId(roomCode, messageId)) {
			item.markDeleted();
			talkDrawerItemRepository.save(item);
		}
		ChatRoomEntity room = chatRoomDao.findByCode(roomCode);
		if (room.getLastMessageAt() == null ||
			!savedMessage.getSentAt().isBefore(room.getLastMessageAt().minusSeconds(2))) {
			room.updateLastMessage("\uC0AD\uC81C\uB41C \uBA54\uC2DC\uC9C0\uC785\uB2C8\uB2E4", false);
			roomRepository.save(room);
		}
		return toMessageResponse(savedMessage);
	}

	@Transactional
	public ChatRoomLeaveResponse leaveRoom(String roomCode, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		ChatRoomEntity room = chatRoomDao.findByCode(roomCode);
		if (allStaffChatService.isAllStaffRoom(room)) {
			throw new IllegalArgumentException("\uC804\uC9C1\uC6D0 \uCC44\uD305\uBC29\uC740 \uB098\uAC08 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.");
		}
		if (room.getType() == ChatRoomType.DIRECT) {
			return leaveDirectRoom(room, principal);
		}
		if (!hasLastMessage(room) &&
			room.getCreatedByAccountId() != null &&
			room.getCreatedByAccountId().equals(principal.userId())) {
			ChatRoomResponse snapshot = toRoomResponse(room);
			backupAndDeleteRoom(room, "unstarted-group-room-discarded", principal);
			return new ChatRoomLeaveResponse(
				snapshot,
				null,
				principal.email(),
				true
			);
		}

		String content = principal.displayName() + "님이 채팅방을 나갔습니다.";
		content = principal.displayName() + "\uB2D8\uC774 \uCC44\uD305\uBC29\uC744 \uB098\uAC14\uC2B5\uB2C8\uB2E4.";
		ChatMessageEntity savedMessage = messageJpaRepository.save(ChatMessageEntity.system(
			roomCode,
			principal.userId(),
			principal.displayName(),
			content
		));
		long remainingCount = Math.max(0, memberRepository.countByRoomCode(roomCode) - 1);
		if (remainingCount == 0) {
			ChatRoomResponse snapshot = toRoomResponse(room);
			backupAndDeleteRoom(room, "group-room-empty", principal);
			return new ChatRoomLeaveResponse(
				snapshot,
				chatMapper.toMessageResponse(savedMessage, 0),
				principal.email(),
				true
			);
		}

		memberRepository.deleteByRoomCodeAndAccountId(roomCode, principal.userId());
		room.updateLastMessage(content);
		roomRepository.save(room);
		ChatRoomResponse updatedRoom = toRoomResponse(room);
		return new ChatRoomLeaveResponse(
			updatedRoom,
			chatMapper.toMessageResponse(savedMessage, 0),
			principal.email(),
			false
		);
	}

	private ChatRoomLeaveResponse leaveDirectRoom(ChatRoomEntity room, AuthPrincipal principal) {
		String roomCode = room.getCode();
		String content = principal.displayName() + "\uB2D8\uC774 \uCC44\uD305\uBC29\uC744 \uB098\uAC14\uC2B5\uB2C8\uB2E4.";
		ChatMessageEntity savedMessage = messageJpaRepository.save(ChatMessageEntity.system(
			roomCode,
			principal.userId(),
			principal.displayName(),
			content
		));
		long remainingCount = Math.max(0, memberRepository.countByRoomCode(roomCode) - 1);
		if (remainingCount == 0) {
			ChatRoomResponse snapshot = toRoomResponse(room);
			backupAndDeleteRoom(room, "direct-room-empty", principal);
			return new ChatRoomLeaveResponse(
				snapshot,
				chatMapper.toMessageResponse(savedMessage, 0),
				principal.email(),
				true
			);
		}

		memberRepository.deleteByRoomCodeAndAccountId(roomCode, principal.userId());
		room.updateLastMessage(content);
		roomRepository.save(room);
		ChatRoomResponse updatedRoom = toRoomResponse(room);
		return new ChatRoomLeaveResponse(
			updatedRoom,
			chatMapper.toMessageResponse(savedMessage, 0),
			principal.email(),
			false
		);
	}

	@Transactional
	public ChatReadStateResponse markRead(String roomCode, AuthPrincipal principal) {
		ChatRoomMemberEntity membership = assertMember(roomCode, principal);
		Instant visibleSince = membership == null ? null : membership.getJoinedAt();
		List<ChatMessageEntity> messages = visibleSince == null
			? messageJpaRepository.findByRoomCodeOrderBySentAtAsc(roomCode)
			: messageJpaRepository.findByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtAsc(roomCode, visibleSince);
		if (messages.isEmpty()) {
			return new ChatReadStateResponse(roomCode, List.of());
		}

		List<UUID> messageIds = messages.stream()
			.map(ChatMessageEntity::getId)
			.toList();
		Set<UUID> alreadyRead = new HashSet<>(readReceiptRepository
			.findByMessage_IdInAndAccountId(messageIds, principal.userId())
			.stream()
			.map(receipt -> receipt.getMessage().getId())
			.toList());
		List<ChatMessageReadReceiptEntity> newReceipts = messages.stream()
			.filter(message -> !alreadyRead.contains(message.getId()))
			.map(message -> new ChatMessageReadReceiptEntity(message, principal.userId()))
			.toList();
		if (!newReceipts.isEmpty()) {
			readReceiptRepository.saveAll(newReceipts);
		}

		return readStateFor(roomCode, messages);
	}

	@Transactional(readOnly = true)
	public void assertRoomMember(String roomCode, AuthPrincipal principal) {
		assertMember(roomCode, principal);
	}

	@Transactional
	public ChatRoomResponse setNotice(String roomCode, ChatNoticeRequest request, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		ChatRoomEntity room = chatRoomDao.findByCode(roomCode);
		ChatMessageEntity savedMessage = findSavedMessage(request.messageId()).orElse(null);
		if (savedMessage != null) {
			if (!roomCode.equals(savedMessage.getRoomCode())) {
				throw new IllegalArgumentException("Notice message belongs to another room.");
			}
			room.updateNotice(
				savedMessage.getId().toString(),
				savedMessage.getSenderId().toString(),
				savedMessage.getSenderName(),
				savedMessage.getContent(),
				savedMessage.getSentAt()
			);
		} else {
			room.updateNotice(
				trimToNull(request.messageId()),
				trimToNull(request.senderId()),
				request.senderName().trim(),
				request.content().trim(),
				request.sentAt()
			);
		}
		roomRepository.save(room);
		return toRoomResponse(room);
	}

	@Transactional
	public ChatRoomResponse setPinned(String roomCode, ChatPinRequest request, AuthPrincipal principal) {
		assertMember(roomCode, principal);
		ChatRoomEntity room = chatRoomDao.findByCode(roomCode);
		var pin = chatFolderSettingsService.setPinnedRoom(principal, roomCode, request.pinned());
		return toRoomResponse(room, pin.pinned(), pin.pinnedAt());
	}

	private Optional<ChatMessageEntity> findSavedMessage(String messageId) {
		if (messageId == null || messageId.isBlank()) {
			return Optional.empty();
		}
		try {
			return messageJpaRepository.findById(UUID.fromString(messageId));
		} catch (IllegalArgumentException ignored) {
			return Optional.empty();
		}
	}

	private String trimToNull(String value) {
		if (value == null || value.isBlank()) {
			return null;
		}
		return value.trim();
	}

	private String sanitizeFileName(String fileName) {
		String value = fileName == null || fileName.isBlank() ? "attachment" : fileName.trim();
		value = value.replace('\\', '/');
		int slash = value.lastIndexOf('/');
		if (slash >= 0) {
			value = value.substring(slash + 1);
		}
		value = value.replaceAll("[\\r\\n\\t]", "_").replaceAll("[<>:\"/\\\\|?*]", "_");
		if (value.isBlank()) {
			return "attachment";
		}
		return value.length() > 180 ? value.substring(value.length() - 180) : value;
	}

	private String normalizeContentType(String contentType) {
		if (contentType == null || contentType.isBlank()) {
			return "application/octet-stream";
		}
		return contentType.length() > 150 ? contentType.substring(0, 150) : contentType;
	}

	private String normalizeAttachmentGroupId(String groupId) {
		String trimmed = trimToNull(groupId);
		if (trimmed == null) {
			return null;
		}
		String normalized = trimmed.replaceAll("[^A-Za-z0-9_.:-]", "");
		if (normalized.isBlank()) {
			return null;
		}
		return normalized.length() > 120 ? normalized.substring(0, 120) : normalized;
	}

	private ChatTalkDrawerMediaType mediaTypeFor(String fileName, String contentType) {
		String type = contentType == null ? "" : contentType.toLowerCase();
		String lowerName = fileName == null ? "" : fileName.toLowerCase();
		if (type.startsWith("image/") || lowerName.matches(".*\\.(png|jpe?g|gif|bmp|webp|heic|heif)$")) {
			return ChatTalkDrawerMediaType.IMAGE;
		}
		if (type.startsWith("video/") || lowerName.matches(".*\\.(mp4|m4v|mov|avi|mkv|webm|wmv|mpg|mpeg|3gp|3gpp)$")) {
			return ChatTalkDrawerMediaType.VIDEO;
		}
		return ChatTalkDrawerMediaType.FILE;
	}

	private String attachmentPreview(String fileName, String contentType) {
		ChatTalkDrawerMediaType mediaType = mediaTypeFor(fileName, contentType);
		String safeName = fileName == null || fileName.isBlank() ? "attachment" : fileName.trim();
		return switch (mediaType) {
			case IMAGE -> "[이미지]";
			case VIDEO -> "[동영상]";
			case FILE -> "[파일] " + safeName;
		};
	}

	private ChatTalkDrawerMediaType parseMediaType(String mediaType) {
		String trimmed = trimToNull(mediaType);
		if (trimmed == null) {
			return null;
		}
		try {
			return ChatTalkDrawerMediaType.valueOf(trimmed.toUpperCase());
		} catch (IllegalArgumentException exception) {
			throw new IllegalArgumentException("Unsupported talk drawer media type.");
		}
	}

	private String normalizeAvatarImageUrl(String value) {
		String trimmed = trimToNull(value);
		if (trimmed == null) {
			return null;
		}
		if (trimmed.length() > 1_500_000) {
			throw new IllegalArgumentException("Chat room image is too large.");
		}
		if (trimmed.startsWith("data:image/") || trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
			return trimmed;
		}
		throw new IllegalArgumentException("Unsupported chat room image format.");
	}

	private UserAccount findDirectTarget(DirectChatRoomRequest request) {
		if (request.targetUserId() != null) {
			return accountRepository.findById(request.targetUserId())
				.orElseThrow(() -> new IllegalArgumentException("Direct chat target not found."));
		}

		String targetEmail = request.targetEmail() == null ? "" : request.targetEmail().trim();
		if (!targetEmail.isEmpty()) {
			return accountRepository.findByEmailIgnoreCase(targetEmail)
				.orElseThrow(() -> new IllegalArgumentException("Direct chat target not found."));
		}

		String targetName = request.targetName().trim();
		return accountRepository.findFirstByDisplayNameIgnoreCase(targetName)
			.orElseThrow(() -> new IllegalArgumentException("Direct chat target not found."));
	}

	private Optional<ChatRoomEntity> findExistingDirectRoom(UUID firstUserId, UUID secondUserId, String companyName) {
		return roomRepository.findAll().stream()
			.filter(room -> room.getType() == ChatRoomType.DIRECT)
			.filter(room -> companyName.equalsIgnoreCase(roomCompanyName(room)))
			.filter(room -> chatRoomDao.countMembers(room.getCode()) == 2)
			.filter(room -> memberRepository.existsByRoomCodeAndAccountId(room.getCode(), firstUserId))
			.filter(room -> memberRepository.existsByRoomCodeAndAccountId(room.getCode(), secondUserId))
			.findFirst();
	}

	private ChatRoomEntity createDirectRoom(UserAccount currentUser, UserAccount targetUser, String companyName) {
		String roomCode = directRoomCode(currentUser.getId(), targetUser.getId());
		Optional<ChatRoomEntity> existingRoom = roomRepository.findByCode(roomCode);
		if (existingRoom.isPresent()
			&& existingRoom.get().getType() == ChatRoomType.DIRECT
			&& chatRoomDao.countMembers(roomCode) < 2) {
			backupAndDeleteRoom(existingRoom.get(), "direct-room-recreated", null);
			existingRoom = Optional.empty();
		}
		ChatRoomEntity room = existingRoom
			.orElseGet(() -> roomRepository.save(new ChatRoomEntity(
				roomCode,
				targetUser.getDisplayName(),
				ChatRoomType.DIRECT,
				false,
				""
			)));
		if (room.getCreatedByAccountId() == null) {
			room.setCreatedByAccountId(currentUser.getId());
		}
		room.setCompanyName(companyName);
		room = roomRepository.save(room);
		ensureMember(room, currentUser);
		ensureMember(room, targetUser);
		return room;
	}

	private void ensureMember(ChatRoomEntity room, UserAccount account) {
		if (!memberRepository.existsByRoomCodeAndAccountId(room.getCode(), account.getId())) {
			memberRepository.save(new ChatRoomMemberEntity(room, account));
		}
	}

	private String directRoomCode(UUID firstUserId, UUID secondUserId) {
		String first = firstUserId.toString();
		String second = secondUserId.toString();
		return first.compareTo(second) < 0
			? "direct-" + first + "-" + second
			: "direct-" + second + "-" + first;
	}

	private String selfRoomCode(UUID userId) {
		return "self-" + userId;
	}

	private ChatRoomResponse toRoomResponse(ChatRoomEntity room) {
		return toRoomResponse(room, false, null);
	}

	private ChatRoomResponse toRoomResponse(ChatRoomEntity room, AuthPrincipal principal) {
		Map<String, Instant> pinnedRoomOrder = chatFolderSettingsService.pinnedRoomOrder(principal);
		return toRoomResponse(
			room,
			pinnedRoomOrder.containsKey(room.getCode()),
			pinnedRoomOrder.get(room.getCode()),
			principal
		);
	}

	private ChatRoomResponse toRoomResponse(ChatRoomEntity room, boolean pinned, Instant pinnedAt) {
		return chatMapper.toRoomResponse(
			room,
			chatRoomDao.countMembers(room.getCode()),
			membersOf(room.getCode()),
			pinned,
			pinnedAt,
			0
		);
	}

	private ChatRoomResponse toRoomResponse(
		ChatRoomEntity room,
		boolean pinned,
		Instant pinnedAt,
		AuthPrincipal principal
	) {
		return chatMapper.toRoomResponse(
			room,
			chatRoomDao.countMembers(room.getCode()),
			membersOf(room.getCode()),
			pinned,
			pinnedAt,
			unreadCountForRoom(room, principal.userId()),
			unreadMentionForRoom(room, principal.userId())
		);
	}

	private ChatReadStateResponse readStateFor(String roomCode, List<ChatMessageEntity> messages) {
		Map<UUID, Integer> unreadCounts = unreadCounts(roomCode, messages);
		return new ChatReadStateResponse(
			roomCode,
			messages.stream()
				.map(message -> new ChatMessageReadState(
					message.getId().toString(),
					unreadCounts.getOrDefault(message.getId(), 0)
				))
				.toList()
		);
	}

	private List<ChatMessageResponse> toMessageResponses(String roomCode, List<ChatMessageEntity> messages) {
		if (messages.isEmpty()) {
			return List.of();
		}
		Set<UUID> senderIds = new LinkedHashSet<>();
		for (ChatMessageEntity message : messages) {
			if (message.getSenderId() != null) {
				senderIds.add(message.getSenderId());
			}
		}
		Map<UUID, String> senderNames = new HashMap<>();
		Map<UUID, UserProfile> profiles = new HashMap<>();
		if (!senderIds.isEmpty()) {
			for (UserAccount account : accountRepository.findAllById(senderIds)) {
				senderNames.put(account.getId(), account.getDisplayName());
			}
			for (UserProfile profile : profileRepository.findByAccount_IdIn(senderIds)) {
				profiles.put(profile.getAccount().getId(), profile);
			}
		}
		Map<UUID, Integer> unreadCounts = unreadCounts(roomCode, messages);
		List<ChatMessageResponse> responses = new ArrayList<>(messages.size());
		for (ChatMessageEntity message : messages) {
			ChatMessageResponse response = chatMapper.toMessageResponse(
				message,
				unreadCounts.getOrDefault(message.getId(), 0)
			);
			responses.add(withSenderProfile(response, senderNames, profiles));
		}
		return responses;
	}

	private ChatMessageResponse toMessageResponse(ChatMessageEntity message) {
		return withSenderProfile(chatMapper.toMessageResponse(message, unreadCount(message)));
	}

	private ChatMessageResponse withSenderProfile(ChatMessageResponse message) {
		if (message.senderId() == null) {
			return message;
		}
		Map<UUID, String> senderNames = new HashMap<>();
		accountRepository.findById(message.senderId())
			.map(UserAccount::getDisplayName)
			.ifPresent(senderName -> senderNames.put(message.senderId(), senderName));
		Map<UUID, UserProfile> profiles = new HashMap<>();
		profileRepository.findByAccountId(message.senderId())
			.ifPresent(profile -> profiles.put(message.senderId(), profile));
		return withSenderProfile(message, senderNames, profiles);
	}

	private ChatMessageResponse withSenderProfile(
		ChatMessageResponse message,
		Map<UUID, String> senderNames,
		Map<UUID, UserProfile> profiles
	) {
		if (message.senderId() == null) {
			return message;
		}
		String senderName = Optional.ofNullable(senderNames.get(message.senderId()))
			.map(String::trim)
			.filter(value -> !value.isBlank())
			.orElse(message.senderName());
		UserProfile profile = profiles.get(message.senderId());
		String nickname = profile == null ? "" : blankToDefault(profile.getNickname(), "");
		String avatarColor = profile == null ? "#7AA06A" : blankToDefault(profile.getAvatarColor(), "#7AA06A");
		String avatarImageUrl = profile == null ? "" : blankToDefault(profile.getAvatarImageUrl(), "");
		return new ChatMessageResponse(
			message.id(),
			message.roomCode(),
			message.senderId(),
			senderName,
			nickname,
			avatarColor,
			avatarImageUrl,
			message.content(),
			message.sentAt(),
			message.unreadCount(),
			message.systemMessage(),
			message.silent(),
			message.spoiler(),
			message.deletedForEveryone(),
			message.attachment(),
			message.mentions()
		);
	}

	private Map<UUID, Integer> unreadCounts(String roomCode, List<ChatMessageEntity> messages) {
		if (messages.isEmpty()) {
			return Map.of();
		}
		List<ChatRoomMemberEntity> members = memberRepository.findByRoomCode(roomCode);
		if (members.isEmpty()) {
			return Map.of();
		}
		Set<UUID> messageIds = new LinkedHashSet<>();
		Set<UUID> memberIds = new LinkedHashSet<>();
		for (ChatMessageEntity message : messages) {
			messageIds.add(message.getId());
		}
		for (ChatRoomMemberEntity member : members) {
			memberIds.add(member.getAccount().getId());
		}
		Map<UUID, Set<UUID>> readAccountIdsByMessage = new HashMap<>();
		if (!messageIds.isEmpty() && !memberIds.isEmpty()) {
			for (ChatMessageReadReceiptEntity receipt : readReceiptRepository.findByMessage_IdInAndAccountIdIn(
				messageIds,
				memberIds
			)) {
				readAccountIdsByMessage
					.computeIfAbsent(receipt.getMessage().getId(), key -> new HashSet<>())
					.add(receipt.getAccountId());
			}
		}
		Map<UUID, Integer> result = new HashMap<>();
		for (ChatMessageEntity message : messages) {
			if (message.isSystemMessage()) {
				result.put(message.getId(), 0);
				continue;
			}
			Set<UUID> readableMemberIds = new HashSet<>();
			for (ChatRoomMemberEntity member : members) {
				if (member.getJoinedAt() == null || !member.getJoinedAt().isAfter(message.getSentAt())) {
					readableMemberIds.add(member.getAccount().getId());
				}
			}
			if (readableMemberIds.isEmpty()) {
				result.put(message.getId(), 0);
				continue;
			}
			Set<UUID> readAccountIds = readAccountIdsByMessage.getOrDefault(message.getId(), Set.of());
			int readCount = 0;
			for (UUID accountId : readAccountIds) {
				if (readableMemberIds.contains(accountId)) {
					readCount++;
				}
			}
			UUID senderId = message.getSenderId();
			if (senderId != null && readableMemberIds.contains(senderId) && !readAccountIds.contains(senderId)) {
				readCount++;
			}
			result.put(message.getId(), Math.max(0, readableMemberIds.size() - readCount));
		}
		return result;
	}

	private int unreadCount(ChatMessageEntity message) {
		if (message.isSystemMessage()) {
			return 0;
		}
		List<UUID> readableMemberIds = memberRepository.findByRoomCode(message.getRoomCode()).stream()
			.filter(member -> member.getJoinedAt() == null || !member.getJoinedAt().isAfter(message.getSentAt()))
			.map(member -> member.getAccount().getId())
			.toList();
		if (readableMemberIds.isEmpty()) {
			return 0;
		}
		long readCount = readReceiptRepository.countByMessage_IdAndAccountIdIn(message.getId(), readableMemberIds);
		if (readableMemberIds.contains(message.getSenderId())
			&& !readReceiptRepository.existsByMessage_IdAndAccountId(message.getId(), message.getSenderId())) {
			readCount++;
		}
		return Math.max(0, readableMemberIds.size() - (int) readCount);
	}

	private int unreadCountForRoom(ChatRoomEntity room, UUID accountId) {
		Optional<ChatRoomMemberEntity> membership = memberRepository.findByRoomCodeAndAccountId(room.getCode(), accountId);
		if (membership.isEmpty()) {
			return 0;
		}
		Instant visibleSince = membership.get().getJoinedAt();
		List<ChatMessageEntity> messages = visibleSince == null
			? messageJpaRepository.findByRoomCodeOrderBySentAtAsc(room.getCode())
			: messageJpaRepository.findByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtAsc(room.getCode(), visibleSince);
		List<UUID> unreadMessageIds = messages.stream()
			.filter(message -> !message.isSystemMessage())
			.filter(message -> !accountId.equals(message.getSenderId()))
			.map(ChatMessageEntity::getId)
			.toList();
		if (unreadMessageIds.isEmpty()) {
			return 0;
		}
		Set<UUID> readMessageIds = readReceiptRepository.findByMessage_IdInAndAccountId(unreadMessageIds, accountId)
			.stream()
			.map(receipt -> receipt.getMessage().getId())
			.collect(java.util.stream.Collectors.toSet());
		long unreadCount = unreadMessageIds.stream()
			.filter(messageId -> !readMessageIds.contains(messageId))
			.count();
		return unreadCount > Integer.MAX_VALUE ? Integer.MAX_VALUE : (int) unreadCount;
	}

	private boolean unreadMentionForRoom(ChatRoomEntity room, UUID accountId) {
		Optional<ChatRoomMemberEntity> membership = memberRepository.findByRoomCodeAndAccountId(room.getCode(), accountId);
		if (membership.isEmpty()) {
			return false;
		}
		Instant visibleSince = membership.get().getJoinedAt();
		List<ChatMessageEntity> messages = visibleSince == null
			? messageJpaRepository.findByRoomCodeOrderBySentAtAsc(room.getCode())
			: messageJpaRepository.findByRoomCodeAndSentAtGreaterThanEqualOrderBySentAtAsc(room.getCode(), visibleSince);
		List<UUID> mentionedUnreadMessageIds = messages.stream()
			.filter(message -> !message.isSystemMessage())
			.filter(message -> !accountId.equals(message.getSenderId()))
			.filter(message -> message.mentions(accountId))
			.map(ChatMessageEntity::getId)
			.toList();
		if (mentionedUnreadMessageIds.isEmpty()) {
			return false;
		}
		Set<UUID> readMessageIds = readReceiptRepository.findByMessage_IdInAndAccountId(
			mentionedUnreadMessageIds,
			accountId
		)
			.stream()
			.map(receipt -> receipt.getMessage().getId())
			.collect(java.util.stream.Collectors.toSet());
		return mentionedUnreadMessageIds.stream().anyMatch(messageId -> !readMessageIds.contains(messageId));
	}

	@Transactional
	public List<ChatMentionNotificationResponse> mentionNotifications(
		String status,
		AuthPrincipal principal,
		int limit
	) {
		backfillMentionNotifications(principal);
		Pageable page = PageRequest.of(0, normalizeNotificationLimit(limit));
		List<ChatMentionNotificationEntity> notifications = switch (normalizeMentionStatus(status)) {
			case "checked" -> mentionNotificationRepository
				.findByMentionedAccount_IdAndCheckedAtIsNotNullOrderByCreatedAtDesc(principal.userId(), page);
			case "requested" -> mentionNotificationRepository
				.findByMentionedAccount_IdAndCheckedAtIsNullOrderByCreatedAtDesc(principal.userId(), page);
			default -> mentionNotificationRepository.findByMentionedAccount_IdOrderByCreatedAtDesc(principal.userId(), page);
		};
		String companyName = companyScopeService.effectiveCompany(principal);
		return notifications.stream()
			.filter(notification -> roomRepository.findByCode(notification.getRoomCode())
				.map(room -> companyName.equalsIgnoreCase(roomCompanyName(room)))
				.orElse(false))
			.map(this::toMentionNotificationResponse)
			.toList();
	}

	@Transactional
	public ChatMentionNotificationResponse markMentionNotificationChecked(UUID notificationId, AuthPrincipal principal) {
		ChatMentionNotificationEntity notification = mentionNotificationRepository
			.findByIdAndMentionedAccount_Id(notificationId, principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("Mention notification not found."));
		notification.markChecked();
		ChatMessageEntity message = notification.getMessage();
		if (!readReceiptRepository.existsByMessage_IdAndAccountId(message.getId(), principal.userId())) {
			readReceiptRepository.save(new ChatMessageReadReceiptEntity(message, principal.userId()));
		}
		return toMentionNotificationResponse(notification);
	}

	@Transactional(readOnly = true)
	public long unreadMentionNotificationCount(AuthPrincipal principal) {
		return mentionNotificationRepository.countByMentionedAccount_IdAndCheckedAtIsNull(principal.userId());
	}

	private void createMentionNotifications(
		ChatMessageEntity message,
		List<ChatMentionResponse> mentions,
		UUID senderId
	) {
		for (ChatMentionResponse mention : mentions) {
			if (mention.userId() == null || mention.userId().equals(senderId)) {
				continue;
			}
			if (mentionNotificationRepository.existsByMessage_IdAndMentionedAccount_Id(message.getId(), mention.userId())) {
				continue;
			}
			accountRepository.findById(mention.userId()).ifPresent(account ->
				mentionNotificationRepository.save(new ChatMentionNotificationEntity(
					message,
					account,
					blankToDefault(mention.displayName(), account.getDisplayName())
				))
			);
		}
	}

	private void backfillMentionNotifications(AuthPrincipal principal) {
		for (ChatRoomResponse room : rooms(principal)) {
			for (ChatMessageEntity message : messageJpaRepository.findByRoomCodeOrderBySentAtAsc(room.code())) {
				if (message.isSystemMessage() || principal.userId().equals(message.getSenderId()) || !message.mentions(principal.userId())) {
					continue;
				}
				if (mentionNotificationRepository.existsByMessage_IdAndMentionedAccount_Id(message.getId(), principal.userId())) {
					continue;
				}
				String displayName = mentionDisplayNameFor(message, principal.userId(), principal.displayName());
				accountRepository.findById(principal.userId()).ifPresent(account ->
					mentionNotificationRepository.save(new ChatMentionNotificationEntity(message, account, displayName))
				);
			}
		}
	}

	private String mentionDisplayNameFor(ChatMessageEntity message, UUID accountId, String fallback) {
		List<UUID> ids = message.getMentionUserIds();
		List<String> names = message.getMentionDisplayNames();
		for (int index = 0; index < ids.size(); index++) {
			if (ids.get(index).equals(accountId) && index < names.size()) {
				return blankToDefault(names.get(index), fallback);
			}
		}
		return blankToDefault(fallback, "");
	}

	private ChatMentionNotificationResponse toMentionNotificationResponse(ChatMentionNotificationEntity notification) {
		ChatMessageEntity message = notification.getMessage();
		ChatRoomEntity room = chatRoomDao.findByCode(notification.getRoomCode());
		UserProfile profile = profileRepository.findByAccountId(message.getSenderId()).orElse(null);
		String nickname = profile == null ? "" : blankToDefault(profile.getNickname(), "");
		String avatarColor = profile == null ? "#7AA06A" : blankToDefault(profile.getAvatarColor(), "#7AA06A");
		String avatarImageUrl = profile == null ? "" : blankToDefault(profile.getAvatarImageUrl(), "");
		return new ChatMentionNotificationResponse(
			notification.getId(),
			notification.getRoomCode(),
			room.getTitle(),
			(int) Math.min(Integer.MAX_VALUE, chatRoomDao.countMembers(notification.getRoomCode())),
			membersOf(notification.getRoomCode()),
			message.getId(),
			message.getSenderId(),
			displayNameFor(message.getSenderId(), message.getSenderName()),
			nickname,
			avatarColor,
			avatarImageUrl,
			notification.getMentionDisplayName(),
			message.getContent(),
			message.getSentAt(),
			notification.getCheckedAt(),
			notification.isChecked()
		);
	}

	private String normalizeMentionStatus(String status) {
		if (status == null || status.isBlank()) {
			return "all";
		}
		String normalized = status.trim().toLowerCase(java.util.Locale.ROOT);
		if (normalized.equals("checked") || normalized.equals("requested")) {
			return normalized;
		}
		return "all";
	}

	private int normalizeNotificationLimit(int limit) {
		return Math.max(1, Math.min(limit <= 0 ? 80 : limit, 200));
	}

	private int normalizeMessageLimit(int limit) {
		return Math.max(1, Math.min(limit <= 0 ? 80 : limit, 200));
	}

	private List<ChatMentionResponse> resolveMentions(
		String roomCode,
		String content,
		List<ChatMentionRequest> requestedMentions
	) {
		Map<UUID, String> memberNames = memberRepository.findByRoomCode(roomCode).stream()
			.map(ChatRoomMemberEntity::getAccount)
			.collect(java.util.stream.Collectors.toMap(
				UserAccount::getId,
				account -> displayNameFor(account.getId(), account.getDisplayName()),
				(first, second) -> first
			));
		if (memberNames.isEmpty()) {
			return List.of();
		}

		Map<UUID, String> mentioned = new java.util.LinkedHashMap<>();
		for (ChatMentionRequest mention : requestedMentions) {
			if (mention != null && mention.userId() != null && memberNames.containsKey(mention.userId())) {
				String requestedName = blankToDefault(mention.displayName(), memberNames.get(mention.userId()));
				String displayName = content.contains("@" + requestedName)
					? requestedName
					: memberNames.get(mention.userId());
				mentioned.put(mention.userId(), displayName);
			}
		}

		for (String token : mentionTokens(content)) {
			for (Map.Entry<UUID, String> entry : memberNames.entrySet()) {
				if (entry.getValue().equals(token)) {
					mentioned.putIfAbsent(entry.getKey(), token);
					break;
				}
			}
		}

		return mentioned.entrySet().stream()
			.map(entry -> new ChatMentionResponse(entry.getKey(), blankToDefault(entry.getValue(), "")))
			.toList();
	}

	private List<String> mentionTokens(String content) {
		if (content == null || content.isBlank()) {
			return List.of();
		}
		List<String> tokens = new ArrayList<>();
		java.util.regex.Matcher matcher = java.util.regex.Pattern.compile("(?<!\\S)@([^\\s@]{1,80})")
			.matcher(content);
		while (matcher.find()) {
			String token = matcher.group(1).trim();
			if (!token.isBlank()) {
				tokens.add(token);
			}
		}
		return tokens;
	}

	private List<UserProfileResponse> membersOf(String roomCode) {
		return memberRepository.findByRoomCode(roomCode).stream()
			.map(ChatRoomMemberEntity::getAccount)
			.map(account -> profileRepository.findByAccountId(account.getId())
				.map(profile -> userMapper.toResponse(account, profile))
				.orElseGet(() -> userMapper.toResponse(account, new com.ava.backend.user.entity.UserProfile(
					account,
					"AVA",
					"온라인",
					"#7AA06A"
				))))
			.toList();
	}

	private void backupAndDeleteRoom(ChatRoomEntity room, String reason, AuthPrincipal triggeredBy) {
		String roomCode = room.getCode();
		List<ChatRoomMemberEntity> members = memberRepository.findByRoomCode(roomCode);
		List<ChatMessageEntity> messages = messageJpaRepository.findByRoomCodeOrderBySentAtAsc(roomCode);
		List<ChatMessageReadReceiptEntity> readReceipts = readReceiptRepository.findByRoomCode(roomCode);

		ChatRoomBackup backup = new ChatRoomBackup(
			UUID.randomUUID().toString(),
			reason,
			Instant.now(),
			triggeredBy == null ? null : new BackupActor(
				triggeredBy.userId(),
				triggeredBy.email(),
				triggeredBy.displayName()
			),
			new BackupRoom(
				room.getId(),
				room.getCode(),
				room.getTitle(),
				room.getType().name(),
				room.getCreatedAt(),
				room.getLastMessage(),
				room.getLastMessageAt()
			),
			members.stream()
				.map(member -> new BackupMember(
					member.getAccount().getId(),
					member.getAccount().getEmail(),
					member.getAccount().getDisplayName(),
					member.getJoinedAt()
				))
				.toList(),
			messages.stream()
				.map(message -> new BackupMessage(
					message.getId(),
					message.getSenderId(),
					message.getSenderName(),
					message.getContent(),
					message.getSentAt(),
					message.isSystemMessage(),
					message.isSilentMessage(),
					message.isSpoilerMessage()
				))
				.toList(),
			readReceipts.stream()
				.map(receipt -> new BackupReadReceipt(
					receipt.getMessage().getId(),
					receipt.getAccountId(),
					receipt.getReadAt()
				))
				.toList()
		);

		try {
			Files.createDirectories(backupDirectory);
			String timestamp = DateTimeFormatter.ISO_INSTANT.format(backup.backedUpAt())
				.replace(":", "-")
				.replace(".", "-");
			String safeRoomCode = roomCode.replaceAll("[^a-zA-Z0-9._-]", "_");
			Path backupPath = backupDirectory.resolve(timestamp + "-" + safeRoomCode + ".json");
			Files.writeString(backupPath, backupToJson(backup));
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to back up chat room before deleting it.", exception);
		}

		readReceiptRepository.deleteByRoomCode(roomCode);
		talkDrawerItemRepository.deleteByRoomCode(roomCode);
		messageJpaRepository.deleteByRoomCode(roomCode);
		memberRepository.deleteByRoomCode(roomCode);
		roomRepository.delete(room);
		roomRepository.flush();
	}

	private String backupToJson(ChatRoomBackup backup) {
		StringBuilder json = new StringBuilder(4096);
		json.append("{\n");
		appendField(json, 1, "backupId", backup.backupId(), true);
		appendField(json, 1, "reason", backup.reason(), true);
		appendField(json, 1, "backedUpAt", backup.backedUpAt(), true);
		appendActor(json, backup.triggeredBy());
		json.append(",\n");
		appendRoom(json, backup.room());
		json.append(",\n");
		appendMembers(json, backup.members());
		json.append(",\n");
		appendMessages(json, backup.messages());
		json.append(",\n");
		appendReadReceipts(json, backup.readReceipts());
		json.append("\n}\n");
		return json.toString();
	}

	private void appendActor(StringBuilder json, BackupActor actor) {
		indent(json, 1).append("\"triggeredBy\": ");
		if (actor == null) {
			json.append("null");
			return;
		}
		json.append("{\n");
		appendField(json, 2, "id", actor.id(), true);
		appendField(json, 2, "email", actor.email(), true);
		appendField(json, 2, "displayName", actor.displayName(), false);
		json.append('\n');
		indent(json, 1).append('}');
	}

	private void appendRoom(StringBuilder json, BackupRoom room) {
		indent(json, 1).append("\"room\": {\n");
		appendField(json, 2, "id", room.id(), true);
		appendField(json, 2, "code", room.code(), true);
		appendField(json, 2, "title", room.title(), true);
		appendField(json, 2, "type", room.type(), true);
		appendField(json, 2, "createdAt", room.createdAt(), true);
		appendField(json, 2, "lastMessage", room.lastMessage(), true);
		appendField(json, 2, "lastMessageAt", room.lastMessageAt(), false);
		json.append('\n');
		indent(json, 1).append('}');
	}

	private void appendMembers(StringBuilder json, List<BackupMember> members) {
		indent(json, 1).append("\"members\": [");
		for (int i = 0; i < members.size(); i++) {
			BackupMember member = members.get(i);
			json.append(i == 0 ? "\n" : ",\n");
			indent(json, 2).append("{\n");
			appendField(json, 3, "id", member.id(), true);
			appendField(json, 3, "email", member.email(), true);
			appendField(json, 3, "displayName", member.displayName(), true);
			appendField(json, 3, "joinedAt", member.joinedAt(), false);
			json.append('\n');
			indent(json, 2).append('}');
		}
		if (!members.isEmpty()) {
			json.append('\n');
			indent(json, 1);
		}
		json.append(']');
	}

	private void appendMessages(StringBuilder json, List<BackupMessage> messages) {
		indent(json, 1).append("\"messages\": [");
		for (int i = 0; i < messages.size(); i++) {
			BackupMessage message = messages.get(i);
			json.append(i == 0 ? "\n" : ",\n");
			indent(json, 2).append("{\n");
			appendField(json, 3, "id", message.id(), true);
			appendField(json, 3, "senderId", message.senderId(), true);
			appendField(json, 3, "senderName", message.senderName(), true);
			appendField(json, 3, "content", message.content(), true);
			appendField(json, 3, "sentAt", message.sentAt(), true);
			appendBooleanField(json, 3, "systemMessage", message.systemMessage(), true);
			appendBooleanField(json, 3, "silentMessage", message.silentMessage(), true);
			appendBooleanField(json, 3, "spoilerMessage", message.spoilerMessage(), false);
			json.append('\n');
			indent(json, 2).append('}');
		}
		if (!messages.isEmpty()) {
			json.append('\n');
			indent(json, 1);
		}
		json.append(']');
	}

	private void appendReadReceipts(StringBuilder json, List<BackupReadReceipt> readReceipts) {
		indent(json, 1).append("\"readReceipts\": [");
		for (int i = 0; i < readReceipts.size(); i++) {
			BackupReadReceipt receipt = readReceipts.get(i);
			json.append(i == 0 ? "\n" : ",\n");
			indent(json, 2).append("{\n");
			appendField(json, 3, "messageId", receipt.messageId(), true);
			appendField(json, 3, "accountId", receipt.accountId(), true);
			appendField(json, 3, "readAt", receipt.readAt(), false);
			json.append('\n');
			indent(json, 2).append('}');
		}
		if (!readReceipts.isEmpty()) {
			json.append('\n');
			indent(json, 1);
		}
		json.append(']');
	}

	private void appendField(StringBuilder json, int indent, String name, Object value, boolean comma) {
		indent(json, indent)
			.append('"')
			.append(name)
			.append("\": ")
			.append(jsonValue(value));
		if (comma) {
			json.append(',');
		}
		json.append('\n');
	}

	private void appendBooleanField(StringBuilder json, int indent, String name, boolean value, boolean comma) {
		indent(json, indent)
			.append('"')
			.append(name)
			.append("\": ")
			.append(value);
		if (comma) {
			json.append(',');
		}
		json.append('\n');
	}

	private StringBuilder indent(StringBuilder json, int indent) {
		return json.append("  ".repeat(indent));
	}

	private String jsonValue(Object value) {
		if (value == null) {
			return "null";
		}
		return "\"" + escapeJson(value.toString()) + "\"";
	}

	private String escapeJson(String value) {
		StringBuilder escaped = new StringBuilder(value.length() + 16);
		for (int i = 0; i < value.length(); i++) {
			char ch = value.charAt(i);
			switch (ch) {
				case '"' -> escaped.append("\\\"");
				case '\\' -> escaped.append("\\\\");
				case '\b' -> escaped.append("\\b");
				case '\f' -> escaped.append("\\f");
				case '\n' -> escaped.append("\\n");
				case '\r' -> escaped.append("\\r");
				case '\t' -> escaped.append("\\t");
				default -> {
					if (ch < 0x20) {
						escaped.append("\\u%04x".formatted((int) ch));
					} else {
						escaped.append(ch);
					}
				}
			}
		}
		return escaped.toString();
	}

	private void archiveToMongo(
		String roomCode,
		AuthPrincipal principal,
		String senderName,
		String content,
		boolean silent,
		boolean spoiler,
		List<ChatMentionResponse> mentions
	) {
		try {
			messageRepository.save(new ChatMessageDocument(
				roomCode,
				principal.userId(),
				senderName,
				content,
				silent,
				spoiler,
				mentions.stream().map(ChatMentionResponse::userId).toList(),
				mentions.stream().map(ChatMentionResponse::displayName).toList()
			));
		} catch (RuntimeException ignored) {
			// PostgreSQL/H2 remains the canonical local store, so messages are never local-only.
		}
	}

	private String displayNameFor(UUID accountId, String fallback) {
		return accountRepository.findById(accountId)
			.map(UserAccount::getDisplayName)
			.map(String::trim)
			.filter(value -> !value.isBlank())
			.orElse(blankToDefault(fallback, ""));
	}

	private String blankToDefault(String value, String fallback) {
		return value == null || value.isBlank() ? fallback : value;
	}

	private ChatRoomMemberEntity assertMember(String roomCode, AuthPrincipal principal) {
		Optional<ChatRoomMemberEntity> membership = memberRepository.findByRoomCodeAndAccountId(roomCode, principal.userId());
		if (membership.isPresent()) {
			return membership.get();
		}
		ChatRoomEntity room = chatRoomDao.findByCode(roomCode);
		if (principal.role() == com.ava.backend.user.entity.UserRole.SUPERUSER
			&& room.getType() == ChatRoomType.GROUP
			&& companyScopeService.effectiveCompany(principal).equalsIgnoreCase(roomCompanyName(room))) {
			return null;
		}
		if (membership.isEmpty()) {
			throw new IllegalArgumentException("채팅방 권한이 없습니다.");
		}
		return membership.orElseThrow(() -> new IllegalArgumentException("Chat room permission is required."));
	}

	private void assertTargetInCompany(UserAccount targetUser, String companyName) {
		String targetCompany = profileRepository.findByAccountId(targetUser.getId())
			.map(UserProfile::getCompanyName)
			.map(companyScopeService::normalizeCompany)
			.orElse(CompanyScopeService.DEFAULT_COMPANY);
		if (!companyName.equalsIgnoreCase(targetCompany)) {
			throw new IllegalArgumentException("선택한 회사의 사용자만 채팅에 추가할 수 있습니다.");
		}
	}

	private String roomCompanyName(ChatRoomEntity room) {
		return companyScopeService.normalizeCompany(room.getCompanyName());
	}

	public record ChatRoomBackup(
		String backupId,
		String reason,
		Instant backedUpAt,
		BackupActor triggeredBy,
		BackupRoom room,
		List<BackupMember> members,
		List<BackupMessage> messages,
		List<BackupReadReceipt> readReceipts
	) {
	}

	public record BackupActor(UUID id, String email, String displayName) {
	}

	public record BackupRoom(
		UUID id,
		String code,
		String title,
		String type,
		Instant createdAt,
		String lastMessage,
		Instant lastMessageAt
	) {
	}

	public record BackupMember(UUID id, String email, String displayName, Instant joinedAt) {
	}

	public record BackupMessage(
		UUID id,
		UUID senderId,
		String senderName,
		String content,
		Instant sentAt,
		boolean systemMessage,
		boolean silentMessage,
		boolean spoilerMessage
	) {
	}

	public record BackupReadReceipt(UUID messageId, UUID accountId, Instant readAt) {
	}

	public record AttachmentDownload(Resource resource, String fileName, String contentType, long size) {
	}
}
